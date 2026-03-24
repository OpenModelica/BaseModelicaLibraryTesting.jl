# ── Phase 2: Base Modelica parsing with BaseModelica.jl ───────────────────────

import BaseModelica
import Logging
import ModelingToolkit
import ModelingToolkitBase

"""
    run_parse(bm_path, model_dir, model) → NamedTuple

Parse a Base Modelica `.bmo` file with BaseModelica.jl in three sub-steps and
create an `ODEProblem` from the `Experiment` annotation.

Sub-steps timed and reported separately, each with its own log file:
1. **ANTLR parser** — `<model>_antlr.log` — parses the `.bmo` file into an AST.
2. **BM → MTK** — `<model>_mtk.log` — converts the AST into a
   `ModelingToolkit.System`.
3. **ODEProblem** — `<model>_ode.log` — builds the `ODEProblem` using the
   `Experiment` annotation.

Returns a NamedTuple with fields:
- `success`, `time`, `error` — overall result
- `ode_prob` — the `ODEProblem` (or `nothing` on failure)
- `antlr_success`, `antlr_time`
- `mtk_success`,   `mtk_time`
- `ode_success`,   `ode_time`
"""
function run_parse(bm_path::String, model_dir::String,
                   model::String)
    antlr_success = false;  antlr_time = 0.0;  antlr_error = ""
    mtk_success   = false;  mtk_time   = 0.0;  mtk_error   = ""
    ode_success   = false;  ode_time   = 0.0;  ode_error   = ""
    ode_prob      = nothing
    package       = nothing
    sys           = nothing

    isdir(model_dir) || mkpath(model_dir)

    # ── Step 1: ANTLR parser ──────────────────────────────────────────────────
    log1   = open(joinpath(model_dir, "$(model)_antlr.log"), "w")
    pipe1  = Pipe()
    logger = Logging.SimpleLogger(log1, Logging.Debug)
    println(log1, "Model:  $model")
    t0 = time()
    try
        package = redirect_stdout(pipe1) do
            redirect_stderr(pipe1) do
                Logging.with_logger(logger) do
                    BaseModelica.parse_file_antlr(bm_path)
                end
            end
        end
        antlr_time    = time() - t0
        antlr_success = true
    catch e
        antlr_time  = time() - t0
        antlr_error = sprint(showerror, e, catch_backtrace())
    end
    close(pipe1.in)
    captured = read(pipe1.out, String)
    println(log1, "Time:    $(round(antlr_time; digits=3)) s")
    println(log1, "Success: $antlr_success")
    isempty(captured)    || print(log1, "\n--- Parser output ---\n", captured)
    isempty(antlr_error) || println(log1, "\n--- Error ---\n$antlr_error")
    close(log1)

    # ── Step 2: Base Modelica → ModelingToolkit ───────────────────────────────
    if antlr_success
        log2   = open(joinpath(model_dir, "$(model)_mtk.log"), "w")
        pipe2  = Pipe()
        logger = Logging.SimpleLogger(log2, Logging.Debug)
        println(log2, "Model:  $model")
        t0 = time()
        try
            sys = redirect_stdout(pipe2) do
                redirect_stderr(pipe2) do
                    Logging.with_logger(logger) do
                        BaseModelica.baseModelica_to_ModelingToolkit(package)
                    end
                end
            end
            mtk_time    = time() - t0
            mtk_success = true
        catch e
            mtk_time  = time() - t0
            mtk_error = sprint(showerror, e, catch_backtrace())
        end
        close(pipe2.in)
        captured = read(pipe2.out, String)
        println(log2, "Time:    $(round(mtk_time; digits=3)) s")
        println(log2, "Success: $mtk_success")
        isempty(captured)  || print(log2, "\n--- Parser output ---\n", captured)
        isempty(mtk_error) || println(log2, "\n--- Error ---\n$mtk_error")
        close(log2)
    end

    # ── Step 3: ODEProblem generation ─────────────────────────────────────────
    if mtk_success
        log3   = open(joinpath(model_dir, "$(model)_ode.log"), "w")
        pipe3  = Pipe()
        logger = Logging.SimpleLogger(log3, Logging.Debug)
        println(log3, "Model:  $model")
        t0 = time()
        try
            # Extract experiment annotation from the parsed package
            annotation = nothing
            try
                annotation = package.model.long_class_specifier.composition.annotation
            catch; end
            exp_params = BaseModelica.parse_experiment_annotation(annotation)

            ode_prob = redirect_stdout(pipe3) do
                redirect_stderr(pipe3) do
                    Logging.with_logger(logger) do
                        _mv = ModelingToolkitBase.MissingGuessValue.Constant(0.0)
                        if !isnothing(exp_params)
                            tspan    = (exp_params.StartTime, exp_params.StopTime)
                            extra_kw = isnothing(exp_params.Interval) ?
                                (reltol = exp_params.Tolerance,) :
                                (reltol = exp_params.Tolerance,
                                 saveat = exp_params.Interval)
                            ModelingToolkit.ODEProblem(sys, [], tspan;
                                missing_guess_value = _mv, extra_kw...)
                        else
                            ModelingToolkit.ODEProblem(sys, [], (0.0, 1.0);
                                missing_guess_value = _mv)
                        end
                    end
                end
            end
            ode_time    = time() - t0
            ode_success = true
        catch e
            ode_time  = time() - t0
            ode_error = sprint(showerror, e, catch_backtrace())
        end
        close(pipe3.in)
        captured = read(pipe3.out, String)
        println(log3, "Time:    $(round(ode_time; digits=3)) s")
        println(log3, "Success: $ode_success")
        isempty(captured)  || print(log3, "\n--- Parser output ---\n", captured)
        isempty(ode_error) || println(log3, "\n--- Error ---\n$ode_error")
        close(log3)
    end

    first_error = !isempty(antlr_error) ? antlr_error :
                  !isempty(mtk_error)   ? mtk_error   : ode_error
    return (
        success       = ode_success,
        time          = antlr_time + mtk_time + ode_time,
        error         = first_error,
        ode_prob      = ode_prob,
        antlr_success = antlr_success,
        antlr_time    = antlr_time,
        mtk_success   = mtk_success,
        mtk_time      = mtk_time,
        ode_success   = ode_success,
        ode_time      = ode_time,
    )
end
