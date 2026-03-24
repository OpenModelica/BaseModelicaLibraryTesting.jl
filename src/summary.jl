# ── Summary JSON serialization ─────────────────────────────────────────────────

function _esc_json(s::String)::String
    replace(s, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n")
end

"""
    write_summary(results, results_root, info)

Write a `summary.json` to `results_root` encoding run settings, tool versions,
machine info, and per-model pipeline pass/fail data.
Called automatically by `main()` at the end of each run.
"""
function write_summary(
    results      :: Vector{ModelResult},
    results_root :: String,
    info         :: RunInfo,
)
    path = joinpath(results_root, "summary.json")
    open(path, "w") do io
        print(io, "{\n")
        print(io, "  \"library\":      \"$(_esc_json(info.library))\",\n")
        print(io, "  \"lib_version\":  \"$(_esc_json(info.lib_version))\",\n")
        print(io, "  \"filter\":       \"$(_esc_json(info.filter))\",\n")
        print(io, "  \"omc_exe\":      \"$(_esc_json(info.omc_exe))\",\n")
        print(io, "  \"omc_options\":  \"$(_esc_json(info.omc_options))\",\n")
        print(io, "  \"results_root\": \"$(_esc_json(info.results_root))\",\n")
        print(io, "  \"ref_root\":     \"$(_esc_json(info.ref_root))\",\n")
        print(io, "  \"omc_version\":  \"$(_esc_json(info.omc_version))\",\n")
        print(io, "  \"bm_version\":   \"$(_esc_json(info.bm_version))\",\n")
        print(io, "  \"bm_sha\":       \"$(_esc_json(info.bm_sha))\",\n")
        print(io, "  \"cpu_model\":    \"$(_esc_json(info.cpu_model))\",\n")
        print(io, "  \"cpu_threads\":  $(info.cpu_threads),\n")
        print(io, "  \"ram_gb\":       $(@sprintf "%.2f" info.ram_gb),\n")
        print(io, "  \"total_time_s\": $(@sprintf "%.2f" info.total_time_s),\n")
        print(io, "  \"solver\":       \"$(_esc_json(info.solver))\",\n")
        print(io, "  \"models\": [\n")
        for (i, r) in enumerate(results)
            sep = i < length(results) ? "," : ""
            print(io,
                "    {\"name\":\"$(_esc_json(r.name))\"," *
                "\"export\":$(r.export_success)," *
                "\"export_time\":$(@sprintf "%.3f" r.export_time)," *
                "\"parse\":$(r.parse_success)," *
                "\"parse_time\":$(@sprintf "%.3f" r.parse_time)," *
                "\"sim\":$(r.sim_success)," *
                "\"sim_time\":$(@sprintf "%.3f" r.sim_time)," *
                "\"cmp_total\":$(r.cmp_total)," *
                "\"cmp_pass\":$(r.cmp_pass)}$sep\n")
        end
        print(io, "  ]\n}\n")
    end
    @info "summary.json written to $results_root"
end

# ── Summary type and JSON loading ──────────────────────────────────────────────

"""
    RunSummary

Parsed contents of a single `summary.json` file.

# Fields
- `library`      — Modelica library name (e.g. `"Modelica"`)
- `lib_version`  — library version (e.g. `"4.1.0"`)
- `filter`       — model name filter regex, or `""` when none was given
- `omc_exe`      — path / command used to launch OMC
- `omc_options`  — full options string passed to `setCommandLineOptions`
- `results_root` — absolute path where results were written
- `ref_root`     — absolute path to reference results, or `""` when unused
- `omc_version`  — OMC version string
- `bm_version`   — BaseModelica.jl version string (e.g. `"1.6.0"` or `"main"`)
- `bm_sha`       — git tree-SHA of the installed BaseModelica.jl, or `""`
- `cpu_model`    — CPU model name
- `cpu_threads`  — number of logical CPU threads
- `ram_gb`       — total system RAM in GiB
- `total_time_s` — wall-clock duration of the full test run in seconds
- `solver`       — fully-qualified solver name, e.g. `"DifferentialEquations.Rodas5P"`
- `models`       — vector of per-model dicts; each has keys
                   `"name"`, `"export"`, `"parse"`, `"sim"`, `"cmp_total"`, `"cmp_pass"`
"""
struct RunSummary
    library      :: String
    lib_version  :: String
    filter       :: String
    omc_exe      :: String
    omc_options  :: String
    results_root :: String
    ref_root     :: String
    omc_version  :: String
    bm_version   :: String
    bm_sha       :: String
    cpu_model    :: String
    cpu_threads  :: Int
    ram_gb       :: Float64
    total_time_s :: Float64
    solver       :: String
    models       :: Vector{Dict{String,Any}}
end

"""
    load_summary(results_root) → RunSummary or nothing

Read and parse the `summary.json` written by `write_summary` from `results_root`.
Returns `nothing` if the file does not exist or cannot be parsed.
"""
function load_summary(results_root::String)::Union{RunSummary,Nothing}
    path = joinpath(results_root, "summary.json")
    isfile(path) || return nothing
    txt = read(path, String)

    _str(key) = begin
        m = match(Regex("\"$(key)\"\\s*:\\s*\"([^\"]*)\""), txt)
        m === nothing ? "" : string(m.captures[1])
    end
    _int(key) = begin
        m = match(Regex("\"$(key)\"\\s*:\\s*(\\d+)"), txt)
        m === nothing ? 0 : parse(Int, m.captures[1])
    end
    _float(key) = begin
        m = match(Regex("\"$(key)\"\\s*:\\s*([\\d.]+)"), txt)
        m === nothing ? 0.0 : parse(Float64, m.captures[1])
    end

    models = Dict{String,Any}[]
    for m in eachmatch(
        r"\{\"name\":\"([^\"]*)\",\"export\":(true|false),\"export_time\":([\d.]+),\"parse\":(true|false),\"parse_time\":([\d.]+),\"sim\":(true|false),\"sim_time\":([\d.]+),\"cmp_total\":(\d+),\"cmp_pass\":(\d+)\}",
        txt)
        push!(models, Dict{String,Any}(
            "name"        => string(m.captures[1]),
            "export"      => m.captures[2] == "true",
            "export_time" => parse(Float64, m.captures[3]),
            "parse"       => m.captures[4] == "true",
            "parse_time"  => parse(Float64, m.captures[5]),
            "sim"         => m.captures[6] == "true",
            "sim_time"    => parse(Float64, m.captures[7]),
            "cmp_total"   => parse(Int, m.captures[8]),
            "cmp_pass"    => parse(Int, m.captures[9]),
        ))
    end
    return RunSummary(
        _str("library"),
        _str("lib_version"),
        _str("filter"),
        _str("omc_exe"),
        _str("omc_options"),
        _str("results_root"),
        _str("ref_root"),
        _str("omc_version"),
        _str("bm_version"),
        _str("bm_sha"),
        _str("cpu_model"),
        _int("cpu_threads"),
        _float("ram_gb"),
        _float("total_time_s"),
        _str("solver"),
        models,
    )
end
