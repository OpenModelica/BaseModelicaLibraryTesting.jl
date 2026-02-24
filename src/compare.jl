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

    times = get(data, "time", Float64[])
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
    write_diff_html(diff_csv_path, model)

Generate an interactive HTML page for a `_diff.csv` file using the bundled
Dygraphs library.  One zoomable chart is created per failing signal, showing
the reference trace, the simulation trace, and the relative error on a second
y-axis.  The HTML file is written next to the CSV with a `.html` extension.

The page references `../../assets/dygraph.min.*` relative to its location
(`<results_root>/files/<model>/`).  `_install_assets` is called automatically
to copy the library files to `<results_root>/assets/` if not already present.
"""
function write_diff_html(diff_csv_path::String, model::String)
    lines = readlines(diff_csv_path)
    isempty(lines) && return

    headers = [replace(strip(h), "\"" => "") for h in split(lines[1], ",")]

    # Extract unique signal names from headers like "C1.v_ref", "C1.v_sim", …
    fail_sigs = String[]
    for h in headers
        if length(h) > 4 && h[end-3:end] == "_ref"
            push!(fail_sigs, h[1:end-4])
        end
    end
    isempty(fail_sigs) && return

    short_name = split(model, ".")[end]

    # Escape CSV content for embedding as a JS template literal.
    # The only characters that would break a template literal are \ and `.
    csv_text = read(diff_csv_path, String)
    csv_js   = replace(replace(csv_text, "\\" => "\\\\"), "`" => "\\`")

    # Derive results_root from diff_csv_path: <results_root>/files/<model>/<file>
    results_root = dirname(dirname(dirname(abspath(diff_csv_path))))
    _install_assets(results_root)

    # Fill template placeholders
    template = read(joinpath(_ASSETS_DIR, "diff_template.html"), String)
    html = replace(
        template,
        "{{TITLE}}"       => short_name,
        "{{MODEL}}"       => model,
        "{{N_FAIL}}"      => string(length(fail_sigs)),
        "{{REL_TOL_PCT}}" => string(round(Int, _CMP_SETTINGS.rel_tol * 100)),
        "{{ABS_TOL}}"     => string(_CMP_SETTINGS.abs_tol),
        "{{CSV_NAME}}"    => "$(short_name)_diff.csv",
        "{{CSV_DATA}}"    => csv_js,
    )

    html_path = replace(diff_csv_path, r"\.csv$" => ".html")
    write(html_path, html)
end

# ── Reference comparison ───────────────────────────────────────────────────────

"""
    compare_with_reference(sol, ref_csv_path, model_dir, model;
                           settings) → (total, pass, diff_csv)

Compare a DifferentialEquations solution against the MAP-LIB reference CSV.

Returns:
  total    — number of signals successfully compared
  pass     — number of signals within tolerance
  diff_csv — absolute path to the written diff CSV (empty string if all pass)

Signals that cannot be matched to an MTK state variable are skipped.

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
)::Tuple{Int,Int,String}

    times, ref_data = _read_ref_csv(ref_csv_path)
    isempty(times) && return 0, 0, ""

    # Determine which signals to compare: prefer comparisonSignals.txt
    sig_file = joinpath(dirname(ref_csv_path), "comparisonSignals.txt")
    signals  = if isfile(sig_file)
        filter(s -> s != "time" && !isempty(s), strip.(readlines(sig_file)))
    else
        filter(k -> k != "time", collect(keys(ref_data)))
    end

    # Build normalized-name → state-variable-index map from the MTK system
    sys      = sol.prob.f.sys
    vars     = ModelingToolkit.unknowns(sys)
    var_norm = Dict(_normalize_var(string(v)) => i for (i, v) in enumerate(vars))

    # Clip reference time points to the simulation interval
    t_start    = sol.t[1]
    t_end      = sol.t[end]
    valid_mask = (times .>= t_start) .& (times .<= t_end)
    t_ref      = times[valid_mask]
    isempty(t_ref) && return 0, 0, ""

    n_total    = 0
    n_pass     = 0
    fail_sigs  = String[]
    fail_scales = Dict{String,Float64}()   # peak |ref| per failing signal

    for sig in signals
        haskey(ref_data, sig)                 || continue
        haskey(var_norm, _normalize_var(sig)) || continue  # skip non-state signals

        ref_vals  = ref_data[sig][valid_mask]
        idx       = var_norm[_normalize_var(sig)]
        n_total  += 1

        # Peak magnitude of the reference signal — used as the absolute-error scale
        # near zero crossings so that relative error does not blow up.
        ref_scale = isempty(ref_vals) ? 0.0 : maximum(abs, ref_vals)

        # Interpolate simulation at reference time points
        sim_vals = [sol(t)[idx] for t in t_ref]

        pass = all(zip(sim_vals, ref_vals)) do (s, r)
            _check_point(s, r, ref_scale, settings)
        end

        if pass
            n_pass += 1
        else
            push!(fail_sigs, sig)
            fail_scales[sig] = ref_scale
        end
    end

    # Write diff CSV for failing signals (wide format: ref + sim + relerr per signal)
    diff_csv = ""
    if !isempty(fail_sigs)
        short_name = split(model, ".")[end]
        diff_csv   = joinpath(model_dir, "$(short_name)_diff.csv")

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
                    idx       = var_norm[_normalize_var(sig)]
                    s         = sol(t)[idx]
                    ref_scale = get(fail_scales, sig, 0.0)
                    relerr    = abs(s - r) / max(abs(r), ref_scale, settings.abs_tol)
                    push!(row, @sprintf("%.10g", r),
                               @sprintf("%.10g", s),
                               @sprintf("%.6g",  relerr))
                end
                println(f, join(row, ","))
            end
        end

        write_diff_html(diff_csv, model)
    end

    return n_total, n_pass, diff_csv
end
