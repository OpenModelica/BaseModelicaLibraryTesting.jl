# ── Per-model orchestrator ─────────────────────────────────────────────────────

"""
    test_model(omc, model, results_root, ref_root) → ModelResult

Run the four-phase pipeline for a single model and return its result.
"""
function test_model(omc::OMJulia.OMCSession, model::String, results_root::String,
                    ref_root::String)::ModelResult
    model_dir = joinpath(results_root, "files", model)
    mkpath(model_dir)

    # Use forward slashes so the path is valid as an OMC string literal on all
    # platforms (OMC accepts forward slashes on Windows too).
    bm_path = replace(abspath(joinpath(model_dir, "$(model).bmo")), "\\" => "/")

    # Phase 1 ──────────────────────────────────────────────────────────────────
    exp_ok, exp_t, exp_err = run_export(omc, model, model_dir, bm_path)
    exp_ok || return ModelResult(
        model, false, exp_t, exp_err, false, 0.0, "", false, 0.0, "", 0, 0, "")

    # Phase 2 ──────────────────────────────────────────────────────────────────
    par_ok, par_t, par_err, ode_prob = run_parse(bm_path, model_dir, model)
    par_ok || return ModelResult(
        model, true, exp_t, exp_err, false, par_t, par_err, false, 0.0, "", 0, 0, "")

    # Phase 3 ──────────────────────────────────────────────────────────────────
    sim_ok, sim_t, sim_err, sol = run_simulate(ode_prob, model_dir, model)

    # Phase 4 (optional) ───────────────────────────────────────────────────────
    cmp_total, cmp_pass, cmp_csv = 0, 0, ""
    if sim_ok && !isempty(ref_root)
        ref_csv = _ref_csv_path(ref_root, model)
        if ref_csv !== nothing
            try
                cmp_total, cmp_pass, cmp_csv =
                    compare_with_reference(sol, ref_csv, model_dir, model)
            catch e
                @warn "Reference comparison failed for $model: $(sprint(showerror, e))"
            end
        end
    end

    return ModelResult(
        model,
        true,   exp_t, exp_err,
        true,   par_t, par_err,
        sim_ok, sim_t, sim_err,
        cmp_total, cmp_pass, cmp_csv)
end

# ── Main ───────────────────────────────────────────────────────────────────────

"""
    main(; library, version, filter, omc_exe, results_root, ref_root, bm_options) → results

Run the full pipeline over all experiment models in `library` `version`.
Discovers models via OMC, runs `test_model` for each, then writes the HTML
report.  Returns a `Vector{ModelResult}`.
"""
function main(;
    library      :: String                = LIBRARY,
    version      :: String                = LIBRARY_VERSION,
    filter       :: Union{String,Nothing} = nothing,
    omc_exe      :: String                = get(ENV, "OMC_EXE", "omc"),
    results_root :: String                = "",
    ref_root     :: String                = get(ENV, "MAPLIB_REF", ""),
    bm_options   :: String                = get(ENV, "BM_OPTIONS", "scalarize,moveBindings"),
)
    t0 = time()

    if isempty(results_root)
        results_root = joinpath(library, version)
    end
    results_root = abspath(results_root)
    mkpath(joinpath(results_root, "files"))
    @info "Writing results to: $results_root"

    @info "Starting OMC session ($(omc_exe))..."
    omc = OMJulia.OMCSession(omc_exe)

    omc_options = "--baseModelica --frontendInline --baseModelicaOptions=$(bm_options) -d=evaluateAllParameters"
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
            result = test_model(omc, model, results_root, ref_root)
            push!(results, result)

            phase = result.sim_success    ? "SIM OK"     :
                    result.parse_success  ? "SIM FAIL"   :
                    result.export_success ? "PARSE FAIL" : "EXPORT FAIL"
            cmp_info = result.cmp_total > 0 ?
                "  cmp=$(result.cmp_pass)/$(result.cmp_total)" : ""
            @info "  → $phase  export=$(round(result.export_time;digits=2))s" *
                  "  parse=$(round(result.parse_time;digits=2))s" *
                  "  sim=$(round(result.sim_time;digits=2))s$cmp_info"
        end

    finally
        OMJulia.quit(omc)
    end

    cpu_info = Sys.cpu_info()
    bm_ver_env = get(ENV, "BM_VERSION", "")
    bm_version = isempty(bm_ver_env) ? string(pkgversion(BaseModelica)) : bm_ver_env
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
        isempty(cpu_info) ? "unknown" : strip(cpu_info[1].model),
        length(cpu_info),
        Sys.total_memory() / 1024^3,
        time() - t0,
    )

    generate_report(results, results_root, info)
    write_summary(results, results_root, info)
    return results
end
