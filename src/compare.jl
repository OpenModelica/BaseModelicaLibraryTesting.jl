# ── Variable name utilities ────────────────────────────────────────────────────

import CSV
import DataFrames
import ModelingToolkit
import Printf: @sprintf

"""Strip Julia var"..." quoting and MTK time annotation from a variable name.

MTK unknowns may be printed as `var"C1.v"(t)` (Julia's non-standard identifier
syntax). This function removes the surrounding `var"…"` wrapper and the trailing
`(t)` so that the result is a plain, human-readable name like `C1.v`.
"""
function _clean_var_name(name::AbstractString)::String
    s = strip(string(name))
    # Remove Julia's var"..." identifier quoting: var"foo"(t) → foo(t)
    if startswith(s, "var\"") && endswith(s, "\"")
        s = s[5:end-1]
    elseif startswith(s, "var\"") && endswith(s, "\"(t)")
        s = s[5:end-4]
    end
    # Remove trailing (t) time annotation
    if endswith(s, "(t)")
        s = s[1:end-3]
    end
    return s
end

"""Normalize a variable name for fuzzy matching across naming conventions.

MTK uses '₊' as the hierarchy separator and appends '(t)' to time-dependent
symbols; the MAP-LIB CSVs use plain dots. This function maps both to a common
lowercase dot-separated form.
"""
function _normalize_var(name::AbstractString)::String
    s = _clean_var_name(name)        # strip var"..." quoting and trailing (t)
    s = replace(s, "₊" => ".")       # MTK hierarchy → dot
    return lowercase(strip(s))
end

# ── Reference CSV helpers ──────────────────────────────────────────────────────

"""
    _ref_csv_path(ref_root, model) → path or nothing

Return the path to the reference CSV for `model` inside the MAP-LIB checkout
at `ref_root`, or `nothing` if the file does not exist.

Example: model = "Modelica.Electrical.Analog.Examples.ChuaCircuit"
         → <ref_root>/Modelica/Electrical/Analog/Examples/ChuaCircuit/ChuaCircuit.csv
"""
function _ref_csv_path(ref_root::String, model::String)::Union{String,Nothing}
    parts    = split(model, ".")
    csv_path = joinpath(ref_root, parts..., parts[end] * ".csv")
    isfile(csv_path) ? csv_path : nothing
end

"""
    _read_ref_csv(path) → (times, data)

Read a MAP-LIB reference CSV and return the time vector and a
column-name → value-vector dictionary.
"""
function _read_ref_csv(path::String)::Tuple{Vector{Float64}, Dict{String,Vector{Float64}}}
    lines = filter(!isempty ∘ strip, readlines(path))
    isempty(lines) && return Float64[], Dict{String,Vector{Float64}}()

    # Header row may have quoted column names: "time","C1.v","C2.v","L.i"
    headers = [replace(strip(h), "\"" => "") for h in split(lines[1], ",")]

    data = Dict{String,Vector{Float64}}(h => Float64[] for h in headers)
    for line in lines[2:end]
        isempty(strip(line)) && continue
        for (h, tok) in zip(headers, split(strip(line), ","))
            v = tryparse(Float64, strip(tok))
            push!(data[h], something(v, NaN))
        end
    end

    time_key = something(findfirst(h -> lowercase(h) == "time", headers), nothing)
    times = time_key === nothing ? Float64[] : data[headers[time_key]]
    return times, data
end

# ── Asset management ───────────────────────────────────────────────────────────

# Path to the package's bundled assets directory (../assets relative to src/)
const _ASSETS_DIR = joinpath(dirname(@__DIR__), "assets")

"""
    _install_assets(results_root)

Copy the bundled Dygraph JS/CSS and HTML template from the package `assets/`
directory into `<results_root>/assets/` so that generated HTML pages can
reference them with a relative path.  Files that already exist are skipped.
"""
function _install_assets(results_root::String)
    dst = joinpath(results_root, "assets")
    isdir(dst) || mkpath(dst)
    for fname in ("dygraph.min.js", "dygraph.min.css")
        src_file = joinpath(_ASSETS_DIR, fname)
        dst_file = joinpath(dst, fname)
        isfile(dst_file) || cp(src_file, dst_file)
    end
end

# ── Interactive diff HTML ──────────────────────────────────────────────────────

"""
    write_diff_html(model_dir, model; diff_csv_path, pass_sigs, skip_sigs)

Generate an interactive HTML page for a comparison result using the bundled
Dygraphs library.  The page always includes a variable-coverage table listing
every reference signal and whether it was found in the simulation.  When there
are failing signals a zoomable chart is added per signal showing the reference
trace, the simulation trace, and the relative error on a second y-axis.

`model_dir` is `<results_root>/files/<model>`.  The HTML is written to
`<model_dir>/<short>_diff.html`.  `diff_csv_path` is the absolute path to the
diff CSV (empty string when all comparable signals pass).

The page references `../../assets/dygraph.min.*` relative to its location.
`_install_assets` is called automatically.
"""
function write_diff_html(model_dir::String, model::String;
                         diff_csv_path::String          = "",
                         pass_sigs::Vector{String}      = String[],
                         skip_sigs::Vector{String}      = String[],
                         pass_max_abs_error::Dict{String,Float64} = Dict{String,Float64}(),
                         pass_max_rel_error::Dict{String,Float64} = Dict{String,Float64}(),
                         settings::CompareSettings      = CompareSettings())
    short_name   = split(model, ".")[end]
    html_path    = joinpath(model_dir, "$(short_name)_diff.html")
    results_root = dirname(dirname(abspath(model_dir)))   # …/files/<model> → …
    _install_assets(results_root)

    # Read fail_sigs, per-signal max errors, and CSV content from the diff CSV.
    fail_sigs     = String[]
    max_abs_error = Dict{String,Float64}()
    max_rel_error = Dict{String,Float64}()
    csv_js        = ""
    if !isempty(diff_csv_path) && isfile(diff_csv_path)
        df = CSV.read(diff_csv_path, DataFrames.DataFrame)
        for col in names(df)
            endswith(col, "_ref") && push!(fail_sigs, col[1:end-4])
        end
        for sig in fail_sigs
            max_abs_error[sig] = maximum(df[!, "$(sig)_abserr"])
            max_rel_error[sig] = maximum(df[!, "$(sig)_relerr"])
        end
        csv_text = read(diff_csv_path, String)
        csv_js   = replace(replace(csv_text, "\\" => "\\\\"), "`" => "\\`")
    end

    # ── Meta block ──────────────────────────────────────────────────────────────
    tol_str  = if settings.abs_tol === nothing
        "(rel &#x2264; $(round(Int, settings.rel_tol * 100))%)"
    else
        "(rel &#x2264; $(round(Int, settings.rel_tol * 100))%," *
        " abs &#x2264; $(settings.abs_tol))"
    end
    csv_link = isempty(fail_sigs) ? "" :
        """ &nbsp;&middot;&nbsp; <a href="$(short_name)_diff.csv">Download diff CSV</a>"""
    skip_note = isempty(skip_sigs) ? "" :
        """ &nbsp;&middot;&nbsp; $(length(skip_sigs)) signal(s) not found in simulation"""
    meta_block = """<p class="meta">$(length(fail_sigs)) signal(s) outside tolerance """ *
                 """$tol_str$(skip_note)$(csv_link)</p>"""

    # ── Variable-coverage table ──────────────────────────────────────────────────
    all_sigs = vcat(pass_sigs, fail_sigs, skip_sigs)
    var_table = if isempty(all_sigs)
        ""
    else
        n_found = length(pass_sigs) + length(fail_sigs)
        n_total = n_found + length(skip_sigs)
        th = "border:1px solid #ccc;padding:3px 10px;background:#eee;text-align:left;"
        td = "border:1px solid #ccc;padding:3px 10px;"
        tdr = td * "text-align:right;"
        rows = String[]
        for sig in pass_sigs
            push!(rows, "<tr style=\"background:#d4edda\"><td style=\"$td\">$sig</td>" *
                        "<td style=\"$td\">&#10003; pass</td>" *
                        "<td style=\"$tdr\">$(@sprintf("%.4e", pass_max_abs_error[sig]))</td>" *
                        "<td style=\"$tdr\">$(@sprintf("%.2f%%", pass_max_rel_error[sig] * 100))</td></tr>")
        end
        for sig in fail_sigs
            push!(rows, "<tr style=\"background:#f8d7da\"><td style=\"$td\">$sig</td>" *
                        "<td style=\"$td\">&#10007; fail</td>" *
                        "<td style=\"$tdr\">$(@sprintf("%.4e", max_abs_error[sig]))</td>" *
                        "<td style=\"$tdr\">$(@sprintf("%.2f%%", max_rel_error[sig] * 100))</td></tr>")
        end
        for sig in skip_sigs
            push!(rows, "<tr style=\"background:#fff3cd\"><td style=\"$td\">$sig</td>" *
                        "<td style=\"$td\">not found in simulation</td>" *
                        "<td style=\"$tdr\">&#x2014;</td><td style=\"$tdr\">&#x2014;</td></tr>")
        end
        """<h2 style="font-size:1.1em;margin-top:2em;">Variable Coverage """ *
        """&#x2014; $n_found of $n_total reference signal(s) found</h2>""" *
        """<table style="border-collapse:collapse;font-size:13px;">""" *
        """<thead><tr><th style="$th">Signal</th><th style="$th">Status</th>""" *
        """<th style="$th">Max Abs Error</th><th style="$th">Max Rel Error</th></tr></thead>""" *
        """<tbody>$(join(rows))</tbody></table>"""
    end

    # ── Fill template ────────────────────────────────────────────────────────────
    template = read(joinpath(_ASSETS_DIR, "diff_template.html"), String)
    html = replace(
        template,
        "{{TITLE}}"       => short_name,
        "{{MODEL}}"       => model,
        "{{META_BLOCK}}"  => meta_block,
        "{{CSV_DATA}}"    => csv_js,
        "{{VAR_TABLE}}"   => var_table,
    )
    write(html_path, html)
end

# ── Reference comparison ───────────────────────────────────────────────────────

"""
    _absolute_error(actual, reference) -> Vector{Real}

Return the element-wise absolute error between `actual` and `reference`.
"""
function _absolute_error(actual::AbstractVector{<:Real}, reference::AbstractVector{<:Real})
    return abs.(actual .- reference)
end

"""
    _scaled_relative_error(actual, reference) -> Vector{Real}

Return the element-wise absolute error between `actual` and `reference`, scaled by the
maximum absolute value of `reference` (or `eps()` if that maximum is smaller, to avoid
division by zero).
"""
function _scaled_relative_error(actual::AbstractVector{<:Real}, reference::AbstractVector{<:Real})
    reference_scale = max( maximum(abs.(reference)), eps() )
    return abs.(actual .- reference) ./ reference_scale
end

"""
    _eval_sim(sol, accessor, t) → Float64

Evaluate the simulation solution at time `t` for a single signal.  `accessor`
is either an `Int` (index into the state vector, for unknowns) or an MTK
symbolic variable (for observed variables, evaluated via `sol(t; idxs=sym)`).
Returns `NaN` if the observed-variable evaluation fails.
"""
function _eval_sim(sol, accessor, t::Float64)::Float64
    if accessor isa Integer
        return Float64(sol(t)[accessor])
    else
        try
            return Float64(sol(t; idxs = accessor))
        catch
            return NaN
        end
    end
end

"""
    compare_with_reference(sol, ref_csv_path, model_dir, model;
                           settings) → (total, pass, skip, diff_csv)

Compare a DifferentialEquations / MTK solution against the MAP-LIB reference CSV.

Returns:
  total    — number of reference signals successfully compared
  pass     — number of compared signals within tolerance
  skip     — number of reference signals not found in the simulation
  diff_csv — absolute path to the written diff CSV (empty string if all pass)

The lookup covers both MTK state variables (`ModelingToolkit.unknowns`) and
observed (algebraically eliminated) variables (`ModelingToolkit.observed`),
so signals that MTK removed during structural simplification are still matched
and compared via continuous interpolation of the observed function.

A `_diff.html` detail page with zoomable charts and a variable-coverage table
is written whenever there are failures or skipped signals.

# Keyword arguments
- `settings` — a `CompareSettings` instance controlling tolerances and the
               error function.
"""
function compare_with_reference(
    sol,
    ref_csv_path::String,
    model_dir::String,
    model::String;
    settings::CompareSettings = CompareSettings(),
)::Tuple{Int,Int,Int,String}

    times, ref_data = _read_ref_csv(ref_csv_path)
    isempty(times) && return 0, 0, 0, ""

    # Determine which signals to compare: prefer comparisonSignals.txt
    sig_file           = joinpath(dirname(ref_csv_path), "comparisonSignals.txt")
    using_sig_file     = isfile(sig_file)
    signals = if using_sig_file
        sigs = filter(s -> lowercase(s) != "time" && !isempty(s), strip.(readlines(sig_file)))
        sigs_missing = filter(s -> !haskey(ref_data, s), sigs)
        isempty(sigs_missing) || error("Signal(s) listed in comparisonSignals.txt not present in reference CSV: $(join(sigs_missing, ", "))")
        sigs
    else
        filter(k -> lowercase(k) != "time", collect(keys(ref_data)))
    end
    n_total     = length(signals)

    # ── Build variable accessor map ──────────────────────────────────────────────
    # var_access: normalized name → Int (state index) or MTK symbolic (observed).
    # State variables come first so they take priority over any observed alias.
    sys = sol.prob.f.sys
    var_access = Dict{String,Any}()
    for (i, v) in enumerate(ModelingToolkit.unknowns(sys))
        var_access[_normalize_var(string(v))] = i
    end
    # Observed variables: algebraically eliminated by structural_simplify.
    # MTK solution objects support sol(t; idxs=sym) for these via SciML's
    # SymbolicIndexingInterface, so they can be interpolated like state vars.
    try
        for eq in ModelingToolkit.observed(sys)
            name = _normalize_var(string(eq.lhs))
            haskey(var_access, name) || (var_access[name] = eq.lhs)
        end
    catch e
        @warn "Could not enumerate observed variables: $(sprint(showerror, e))"
    end

    # Verify the simulation covers the expected reference time interval.
    # A large gap means the solver stopped early or started late.
    isempty(sol.t) && return n_total, 0, 0, ""
    t_start    = sol.t[1]
    t_end      = sol.t[end]
    ref_t_start = times[1]
    ref_t_end   = times[end]
    if t_start > ref_t_start || t_end < ref_t_end
        @error "Simulation interval [$(t_start), $(t_end)] does not cover " *
               "reference interval [$(ref_t_start), $(ref_t_end)]"
        return n_total, 0, 0, ""
    end

    # Clip reference time to the simulation interval
    valid_mask = (times .>= t_start) .& (times .<= t_end)
    t_ref      = times[valid_mask]
    isempty(t_ref) && return n_total, 0, 0, ""

    n_pass      = 0
    pass_sigs   = String[]
    fail_sigs   = String[]
    pass_max_abs_error    = Dict{String, Float64}()
    pass_max_rel_error    = Dict{String, Float64}()
    fail_ref_vals         = Dict{String, Vector{Float64}}()
    fail_sim_vals         = Dict{String, Vector{Float64}}()
    fail_abs_error        = Dict{String, Vector{Float64}}()
    fail_scaled_rel_error = Dict{String, Vector{Float64}}()

    for sig in signals
        signal_name = _normalize_var(sig)
        ref_vals    = ref_data[sig][valid_mask]

        nan_vec = fill(NaN, length(t_ref))

        if !haskey(var_access, signal_name)
            push!(fail_sigs, sig)
            fail_ref_vals[sig]         = ref_vals
            fail_sim_vals[sig]         = nan_vec
            fail_abs_error[sig]        = nan_vec
            fail_scaled_rel_error[sig] = nan_vec
            continue
        end

        accessor = var_access[signal_name]

        # Interpolate simulation at reference time points.
        sim_vals = [_eval_sim(sol, accessor, t) for t in t_ref]

        # If evaluation returned NaN (observed-var access failed), treat as fail.
        if any(isnan, sim_vals)
            push!(fail_sigs, sig)
            fail_ref_vals[sig]         = ref_vals
            fail_sim_vals[sig]         = sim_vals
            fail_abs_error[sig]        = nan_vec
            fail_scaled_rel_error[sig] = nan_vec
            continue
        end

        # Check absolute error and globally scaled relative error
        abs_error = _absolute_error(sim_vals, ref_vals)
        scaled_rel_error = _scaled_relative_error(sim_vals, ref_vals)

        pass = (settings.abs_tol === nothing || maximum(abs_error) < settings.abs_tol) &&
               maximum(scaled_rel_error) < settings.rel_tol

        if pass
            n_pass += 1
            push!(pass_sigs, sig)
            pass_max_abs_error[sig] = maximum(abs_error)
            pass_max_rel_error[sig] = maximum(scaled_rel_error)
        else
            push!(fail_sigs, sig)
            fail_ref_vals[sig]         = ref_vals
            fail_sim_vals[sig]         = sim_vals
            fail_abs_error[sig]        = abs_error
            fail_scaled_rel_error[sig] = scaled_rel_error
        end
    end

    # ── Write diff CSV for failing signals ──────────────────────────────────────
    # Wide format: time, <sig>_ref, <sig>_sim, <sig>_relerr per failing signal.
    short_name = split(model, ".")[end]
    diff_csv   = ""
    if !isempty(fail_sigs)
        diff_csv = joinpath(model_dir, "$(short_name)_diff.csv")
        df = DataFrames.DataFrame("time" => t_ref)
        for sig in fail_sigs
            df[!, "$(sig)_ref"]    = fail_ref_vals[sig]
            df[!, "$(sig)_sim"]    = fail_sim_vals[sig]
            df[!, "$(sig)_abserr"] = fail_abs_error[sig]
            df[!, "$(sig)_relerr"] = fail_scaled_rel_error[sig]
        end
        CSV.write(diff_csv, df)
    end

    # ── Write detail HTML whenever there is anything worth showing ───────────────
    if !isempty(fail_sigs)
        write_diff_html(model_dir, model;
                        diff_csv_path      = diff_csv,
                        pass_sigs          = pass_sigs,
                        pass_max_abs_error = pass_max_abs_error,
                        pass_max_rel_error = pass_max_rel_error,
                        settings           = settings)
    end

    return n_total, n_pass, 0, diff_csv
end
