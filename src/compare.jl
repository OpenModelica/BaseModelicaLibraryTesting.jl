# ── Variable name utilities ────────────────────────────────────────────────────

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

# ── Comparison settings and error functions ────────────────────────────────────

"""Module-level default comparison settings.  Modify via `configure_comparison!`."""
const _CMP_SETTINGS = CompareSettings()

"""
    _check_relative(s, r, ref_scale, cfg) → Bool

Classic relative-error check.  Passes when

    |s − r| ≤ max(rel_tol · |r|, abs_tol)

This is the traditional approach used by many validation tools.  It works well
when the signal stays well away from zero, but may produce false failures at
zero crossings because the per-point tolerance shrinks to `abs_tol ≈ 0` when
`r ≈ 0`.
"""
function _check_relative(s::Real, r::Real, ::Real, cfg::CompareSettings)::Bool
    abs(s - r) <= max(cfg.rel_tol * abs(r), cfg.abs_tol)
end

"""
    _check_mixed(s, r, ref_scale, cfg) → Bool

Scale-aware relative-error check (default).  Passes when

    |s − r| ≤ max(rel_tol · |r|,  rel_tol · ref_scale,  abs_tol)

The middle term (`rel_tol · ref_scale`) provides an amplitude-proportional
absolute floor.  Near zero crossings the tolerance is set by the peak magnitude
of the reference signal rather than the near-zero instantaneous value, so
physically correct simulations are not falsely rejected.
"""
function _check_mixed(s::Real, r::Real, ref_scale::Real, cfg::CompareSettings)::Bool
    abs(s - r) <= max(cfg.rel_tol * abs(r), cfg.rel_tol * ref_scale, cfg.abs_tol)
end

"""
    _check_absolute(s, r, ref_scale, cfg) → Bool

Pure absolute check.  Passes when

    |s − r| ≤ abs_tol

Useful when all compared signals have known, small magnitudes or when a
signal-independent tolerance threshold is required.
"""
function _check_absolute(s::Real, r::Real, ::Real, cfg::CompareSettings)::Bool
    abs(s - r) <= cfg.abs_tol
end

"""
    _check_point(s, r, ref_scale, cfg) → Bool

Dispatch to the error function selected by `cfg.error_fn`.

| `error_fn`    | Description                                         |
|:--------------|:----------------------------------------------------|
| `:mixed`      | Scale-aware relative error (default, recommended)   |
| `:relative`   | Classic relative error (may fail at zero crossings) |
| `:absolute`   | Pure absolute error                                 |
"""
function _check_point(s::Real, r::Real, ref_scale::Real, cfg::CompareSettings)::Bool
    fn = cfg.error_fn
    fn === :mixed    && return _check_mixed(s, r, ref_scale, cfg)
    fn === :relative && return _check_relative(s, r, ref_scale, cfg)
    fn === :absolute && return _check_absolute(s, r, ref_scale, cfg)
    throw(ArgumentError(
        "Unknown error_fn $(repr(fn)); choose :mixed, :relative, or :absolute"))
end

"""
    configure_comparison!(; rel_tol, abs_tol, error_fn) → CompareSettings

Update the module-level comparison settings in-place and return them.

# Keyword arguments

- `rel_tol`  — maximum allowed relative error.  Default: `$(CMP_REL_TOL)` (2 %).
- `abs_tol`  — hard absolute-error floor applied when signals are near zero.
               Default: `$(CMP_ABS_TOL)`.
- `error_fn` — selects the point-wise check function.  One of:
  - `:mixed`    — scale-aware relative error (default, recommended);
  - `:relative` — classic relative error (may reject valid zero-crossing signals);
  - `:absolute` — pure absolute error.

# Example

```julia
configure_comparison!(rel_tol = 0.01, error_fn = :relative)
```
"""
function configure_comparison!(;
    rel_tol  :: Union{Float64,Nothing} = nothing,
    abs_tol  :: Union{Float64,Nothing} = nothing,
    error_fn :: Union{Symbol,Nothing}  = nothing,
)
    isnothing(rel_tol)  || (_CMP_SETTINGS.rel_tol  = rel_tol)
    isnothing(abs_tol)  || (_CMP_SETTINGS.abs_tol  = abs_tol)
    isnothing(error_fn) || (_CMP_SETTINGS.error_fn = error_fn)
    return _CMP_SETTINGS
end

"""
    compare_settings() → CompareSettings

Return the current module-level comparison settings.

Pass the returned object (or a freshly constructed `CompareSettings(...)`) to
`compare_with_reference` via the `settings` keyword to override the defaults
for a single call without changing the global state.
"""
compare_settings() = _CMP_SETTINGS

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
                         diff_csv_path::String  = "",
                         pass_sigs::Vector{String} = String[],
                         skip_sigs::Vector{String} = String[])
    short_name   = split(model, ".")[end]
    html_path    = joinpath(model_dir, "$(short_name)_diff.html")
    results_root = dirname(dirname(abspath(model_dir)))   # …/files/<model> → …
    _install_assets(results_root)

    # Read fail_sigs and CSV content from the diff CSV (may not exist).
    fail_sigs = String[]
    csv_js    = ""
    if !isempty(diff_csv_path) && isfile(diff_csv_path)
        lines = readlines(diff_csv_path)
        if length(lines) >= 1
            headers = [replace(strip(h), "\"" => "") for h in split(lines[1], ",")]
            for h in headers
                length(h) > 4 && h[end-3:end] == "_ref" && push!(fail_sigs, h[1:end-4])
            end
            csv_text = read(diff_csv_path, String)
            csv_js   = replace(replace(csv_text, "\\" => "\\\\"), "`" => "\\`")
        end
    end

    # ── Meta block ──────────────────────────────────────────────────────────────
    tol_str  = "(rel &#x2264; $(round(Int, _CMP_SETTINGS.rel_tol * 100))%," *
               " abs &#x2264; $(_CMP_SETTINGS.abs_tol))"
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
        rows = String[]
        for sig in pass_sigs
            push!(rows, "<tr style=\"background:#d4edda\"><td style=\"$td\">$sig</td>" *
                        "<td style=\"$td\">&#10003; pass</td></tr>")
        end
        for sig in fail_sigs
            push!(rows, "<tr style=\"background:#f8d7da\"><td style=\"$td\">$sig</td>" *
                        "<td style=\"$td\">&#10007; fail</td></tr>")
        end
        for sig in skip_sigs
            push!(rows, "<tr style=\"background:#fff3cd\"><td style=\"$td\">$sig</td>" *
                        "<td style=\"$td\">not found in simulation</td></tr>")
        end
        """<h2 style="font-size:1.1em;margin-top:2em;">Variable Coverage """ *
        """&#x2014; $n_found of $n_total reference signal(s) found</h2>""" *
        """<table style="border-collapse:collapse;font-size:13px;">""" *
        """<thead><tr><th style="$th">Signal</th><th style="$th">Status</th></tr></thead>""" *
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
               error function.  Defaults to the module-level settings returned
               by `compare_settings()`.  Use `configure_comparison!` to change
               the defaults, or pass a local `CompareSettings(...)` here.
"""
function compare_with_reference(
    sol,
    ref_csv_path::String,
    model_dir::String,
    model::String;
    settings::CompareSettings = _CMP_SETTINGS,
)::Tuple{Int,Int,Int,String}

    times, ref_data = _read_ref_csv(ref_csv_path)
    isempty(times) && return 0, 0, 0, ""

    # Determine which signals to compare: prefer comparisonSignals.txt
    sig_file = joinpath(dirname(ref_csv_path), "comparisonSignals.txt")
    signals  = if isfile(sig_file)
        filter(s -> lowercase(s) != "time" && !isempty(s), strip.(readlines(sig_file)))
    else
        filter(k -> lowercase(k) != "time", collect(keys(ref_data)))
    end

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

    # Clip reference time to the simulation interval
    t_start    = sol.t[1]
    t_end      = sol.t[end]
    valid_mask = (times .>= t_start) .& (times .<= t_end)
    t_ref      = times[valid_mask]
    isempty(t_ref) && return 0, 0, 0, ""

    n_total     = 0
    n_pass      = 0
    pass_sigs   = String[]
    fail_sigs   = String[]
    skip_sigs   = String[]
    fail_scales = Dict{String,Float64}()

    for sig in signals
        haskey(ref_data, sig) || continue   # signal absent from ref CSV entirely

        norm = _normalize_var(sig)
        if !haskey(var_access, norm)
            push!(skip_sigs, sig)
            continue
        end

        accessor  = var_access[norm]
        ref_vals  = ref_data[sig][valid_mask]
        n_total  += 1

        # Peak |ref| — used as amplitude floor so relative error stays finite
        # near zero crossings.
        ref_scale = isempty(ref_vals) ? 0.0 : maximum(abs, ref_vals)

        # Interpolate simulation at reference time points.
        sim_vals = [_eval_sim(sol, accessor, t) for t in t_ref]

        # If evaluation returned NaN (observed-var access failed), treat as skip.
        if any(isnan, sim_vals)
            n_total -= 1
            push!(skip_sigs, sig)
            continue
        end

        pass = all(zip(sim_vals, ref_vals)) do (s, r)
            _check_point(s, r, ref_scale, settings)
        end

        if pass
            n_pass += 1
            push!(pass_sigs, sig)
        else
            push!(fail_sigs, sig)
            fail_scales[sig] = ref_scale
        end
    end

    # ── Write diff CSV for failing signals ──────────────────────────────────────
    # Wide format: time, <sig>_ref, <sig>_sim, <sig>_relerr per failing signal.
    short_name = split(model, ".")[end]
    diff_csv   = ""
    if !isempty(fail_sigs)
        diff_csv = joinpath(model_dir, "$(short_name)_diff.csv")
        open(diff_csv, "w") do f
            cols = ["time"]
            for sig in fail_sigs
                push!(cols, "$(sig)_ref", "$(sig)_sim", "$(sig)_relerr")
            end
            println(f, join(cols, ","))
            for (ti, t) in enumerate(t_ref)
                row = [@sprintf("%.10g", t)]
                for sig in fail_sigs
                    ref_vals  = ref_data[sig][valid_mask]
                    r         = ref_vals[ti]
                    s         = _eval_sim(sol, var_access[_normalize_var(sig)], t)
                    ref_scale = get(fail_scales, sig, 0.0)
                    relerr    = abs(s - r) / max(abs(r), ref_scale, settings.abs_tol)
                    push!(row, @sprintf("%.10g", r),
                               @sprintf("%.10g", s),
                               @sprintf("%.6g",  relerr))
                end
                println(f, join(row, ","))
            end
        end
    end

    # ── Write detail HTML whenever there is anything worth showing ───────────────
    if !isempty(fail_sigs) || !isempty(skip_sigs)
        write_diff_html(model_dir, model;
                        diff_csv_path = diff_csv,
                        pass_sigs     = pass_sigs,
                        skip_sigs     = skip_sigs)
    end

    return n_total, n_pass, length(skip_sigs), diff_csv
end
