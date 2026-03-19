# ── BaseModelica.jl version helpers ────────────────────────────────────────────

"""
    _bm_sha() → String

Return the first 7 characters of the git commit SHA for the installed
BaseModelica.jl package by resolving the package's tree SHA against the
cached git clone in the Julia depot. Falls back to the tree SHA when the
clone cannot be found, and returns `""` for registry installs (no git
metadata available) or when the SHA cannot be determined.
"""
function _bm_sha()::String
    try
        for (_, info) in Pkg.dependencies()
            info.name == "BaseModelica" || continue
            tree_sha = info.tree_hash
            tree_sha === nothing && return ""

            # Resolve the tree SHA to a commit SHA via the cached git clone.
            git_source = info.git_source
            if git_source !== nothing
                for depot in Base.DEPOT_PATH
                    clones_dir = joinpath(depot, "clones")
                    isdir(clones_dir) || continue
                    for clone in readdir(clones_dir; join=true)
                        isdir(clone) || continue
                        try
                            remote = strip(readchomp(`git -C $clone remote get-url origin`))
                            (remote == git_source || remote * ".git" == git_source ||
                             git_source * ".git" == remote) || continue
                            fmt = "%H %T"
                            log = readchomp(`git -C $clone log --all --format=$fmt`)
                            for line in split(log, '\n')
                                parts = split(strip(line))
                                length(parts) == 2 && parts[2] == tree_sha || continue
                                sha = parts[1]
                                return sha[1:min(7, length(sha))]
                            end
                        catch
                        end
                    end
                end
            end

            # Fall back to the tree SHA when no clone is found.
            return tree_sha[1:min(7, length(tree_sha))]
        end
    catch
    end
    return ""
end

# ── Per-model orchestrator ─────────────────────────────────────────────────────

"""
    test_model(omc, model, results_root, ref_root; csv_max_size_mb) → ModelResult

Run the four-phase pipeline for a single model and return its result.
"""
function test_model(omc::OMJulia.OMCSession, model::String, results_root::String,
                    ref_root::String;
                    sim_settings   ::SimulateSettings = _SIM_SETTINGS,
                    csv_max_size_mb::Int              = CSV_MAX_SIZE_MB)::ModelResult
    model_dir = joinpath(results_root, "files", model)
    mkpath(model_dir)

    # Use forward slashes so the path is valid as an OMC string literal on all
    # platforms (OMC accepts forward slashes on Windows too).
    bm_path = replace(abspath(joinpath(model_dir, "$(model).bmo")), "\\" => "/")

    # Phase 1 ──────────────────────────────────────────────────────────────────
    exp_ok, exp_t, exp_err = run_export(omc, model, model_dir, bm_path)
    exp_ok || return ModelResult(
        model, false, exp_t, exp_err, false, 0.0, "", false, 0.0, "", 0, 0, 0, "")

    # Phase 2 ──────────────────────────────────────────────────────────────────
    par_ok, par_t, par_err, ode_prob = run_parse(bm_path, model_dir, model)
    par_ok || return ModelResult(
        model, true, exp_t, exp_err, false, par_t, par_err, false, 0.0, "", 0, 0, 0, "")

    # Resolve reference CSV and comparison signals early so phase 3 can filter
    # the CSV output to only the signals that will actually be verified.
    ref_csv     = isempty(ref_root) ? nothing : _ref_csv_path(ref_root, model)
    cmp_signals = if ref_csv !== nothing
        sig_file = joinpath(dirname(ref_csv), "comparisonSignals.txt")
        if isfile(sig_file)
            String.(filter(s -> lowercase(s) != "time" && !isempty(s), strip.(readlines(sig_file))))
        else
            _, ref_data = _read_ref_csv(ref_csv)
            filter(k -> lowercase(k) != "time", collect(keys(ref_data)))
        end
    else
        String[]
    end

    # Phase 3 ──────────────────────────────────────────────────────────────────
    sim_ok, sim_t, sim_err, sol = run_simulate(ode_prob, model_dir, model;
                                               settings = sim_settings,
                                               csv_max_size_mb, cmp_signals)

    # Phase 4 (optional) ───────────────────────────────────────────────────────
    cmp_total, cmp_pass, cmp_skip, cmp_csv = 0, 0, 0, ""
    if sim_ok && ref_csv !== nothing
        try
            cmp_total, cmp_pass, cmp_skip, cmp_csv =
                compare_with_reference(sol, ref_csv, model_dir, model;
                                       signals = cmp_signals)
        catch e
            @warn "Reference comparison failed for $model: $(sprint(showerror, e))"
        end
    end

    return ModelResult(
        model,
        true,   exp_t, exp_err,
        true,   par_t, par_err,
        sim_ok, sim_t, sim_err,
        cmp_total, cmp_pass, cmp_skip, cmp_csv)
end

# ── Main ───────────────────────────────────────────────────────────────────────

"""
    main(; library, version, filter, omc_exe, results_root, ref_root, bm_options) → results

Run the full pipeline over all experiment models in `library` `version`.
Discovers models via OMC, runs `test_model` for each, then writes the HTML
report.  Returns a `Vector{ModelResult}`.
"""
function main(;
    library          :: String                = LIBRARY,
    version          :: String                = LIBRARY_VERSION,
    filter           :: Union{String,Nothing} = nothing,
    omc_exe          :: String                = get(ENV, "OMC_EXE", "omc"),
    results_root     :: String                = "",
    ref_root         :: String                = get(ENV, "MAPLIB_REF", ""),
    bm_options       :: String                = get(ENV, "BM_OPTIONS", "scalarize,moveBindings,inlineFunctions"),
    sim_settings     :: SimulateSettings      = _SIM_SETTINGS,
    csv_max_size_mb  :: Int                   = CSV_MAX_SIZE_MB,
)
    t0 = time()

    # Set up working directory
    bm_version = get(ENV, "BM_VERSION", string(pkgversion(BaseModelica)))
    bm_sha     = _bm_sha()
    @info "Testing BaseModelica.jl version $(bm_version) ($(bm_sha))"

    if isempty(results_root)
        if bm_version == "main"
            results_root = joinpath("results", bm_sha, library, version)
        else
            results_root = joinpath("results", bm_version, library, version)
        end
    end
    results_root = abspath(results_root)
    mkpath(joinpath(results_root, "files"))
    @info "Writing results to: $results_root"

    @info "Starting OMC session ($(omc_exe))..."
    omc = OMJulia.OMCSession(omc_exe)

    omc_options = "--baseModelica --baseModelicaOptions=$(bm_options) -d=evaluateAllParameters"
    omc_version = "unknown"
    results = ModelResult[]
    try
        omc_version = sendExpression(omc, "getVersion()")
        @info "OMC version: $omc_version"

        ok = sendExpression(omc, """setCommandLineOptions("$(omc_options)")""")
        ok || @warn "Failed to set Base Modelica options: $(sendExpression(omc, "getErrorString()"))"

        ok = sendExpression(omc, """loadModel($library, {"$version"})""")
        ok || error("Failed to load $library $version: $(sendExpression(omc, "getErrorString()"))")
        @info "Loaded $library $version"

        @info "Discovering experiment models..."
        # OMC's ZMQ interactive mode does not support the {expr for var guard cond
        # in list} comprehension syntax. Instead we fetch all qualified class names
        # and a parallel boolean array of isExperiment flags, then zip-filter in Julia.
        all_names = sendExpression(omc,
            "{typeNameString(c) for c in getClassNames($library, recursive=true, qualified=true)}")
        is_exp    = sendExpression(omc,
            "{isExperiment(c) for c in getClassNames($library, recursive=true, qualified=true)}")
        all_names = all_names isa Vector ? all_names : [all_names]
        is_exp    = is_exp    isa Vector ? is_exp    : [is_exp]
        models    = String[string(n) for (n, e) in zip(all_names, is_exp) if e === true]

        if filter !== nothing
            pat    = Regex(filter)
            models = [m for m in models if occursin(pat, m)]
            @info "Filter '$(filter)': $(length(models)) model(s) remaining"
        end
        @info "Testing $(length(models)) model(s)"

        if !isempty(ref_root)
            ref_root = abspath(ref_root)
            if !isdir(ref_root)
                @warn "Reference results root '$ref_root' does not exist or is not a directory. Skipping reference comparison."
                ref_root = ""
            else
                @info "Reference results root: $ref_root"
            end
        end

        for (i, model) in enumerate(models)
            @info "[$i/$(length(models))] $model"
            result = test_model(omc, model, results_root, ref_root; sim_settings, csv_max_size_mb)
            push!(results, result)

            phase = if result.sim_success && result.cmp_total > 0
                result.cmp_pass == result.cmp_total ? "CMP OK" : "CMP FAIL"
            elseif result.sim_success
                "SIM OK"
            elseif result.parse_success
                "SIM FAIL"
            elseif result.export_success
                "PARSE FAIL"
            else
                "EXPORT FAIL"
            end
            cmp_info = if result.cmp_total > 0
                skip_note = result.cmp_skip > 0 ? " skip=$(result.cmp_skip)" : ""
                "  cmp=$(result.cmp_pass)/$(result.cmp_total)$skip_note"
            else
                ""
            end
            @info "  → $phase  export=$(round(result.export_time;digits=2))s" *
                  "  parse=$(round(result.parse_time;digits=2))s" *
                  "  sim=$(round(result.sim_time;digits=2))s$cmp_info"
        end

    finally
        OMJulia.quit(omc)
    end

    cpu_info = Sys.cpu_info()
    info = RunInfo(
        library,
        version,
        something(filter, ""),
        omc_exe,
        omc_options,
        results_root,
        ref_root,
        omc_version,
        bm_version,
        bm_sha,
        isempty(cpu_info) ? "unknown" : strip(cpu_info[1].model),
        length(cpu_info),
        Sys.total_memory() / 1024^3,
        time() - t0,
    )

    generate_report(results, results_root, info; csv_max_size_mb)
    write_summary(results, results_root, info)
    return results
end
