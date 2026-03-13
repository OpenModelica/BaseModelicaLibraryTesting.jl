# ── Phase 2: Base Modelica parsing with BaseModelica.jl ───────────────────────

import BaseModelica
import Logging

"""
    run_parse(bm_path, model_dir, model) → (success, time, error, ode_prob)

Parse a Base Modelica `.bmo` file with BaseModelica.jl and create an
`ODEProblem` from the `Experiment` annotation.
Writes a `<model>_parsing.log` file in `model_dir`.
Returns `nothing` as the fourth element on failure.
"""
function run_parse(bm_path::String, model_dir::String,
                   model::String)::Tuple{Bool,Float64,String,Any}
    parse_success = false
    parse_time    = 0.0
    parse_error   = ""
    ode_prob      = nothing

    log_file = open(joinpath(model_dir, "$(model)_parsing.log"), "w")
    println(log_file, "Model:   $model")
    logger = Logging.SimpleLogger(log_file, Logging.Debug)
    t0 = time()
    try
        # create_odeproblem returns an ODEProblem using the Experiment
        # annotation for StartTime/StopTime/Tolerance/Interval.
        # Redirect all library log output (including Symbolics warnings)
        # to the log file so they don't clutter stdout.
        ode_prob      = Logging.with_logger(logger) do
            BaseModelica.create_odeproblem(bm_path)
        end
        parse_time    = time() - t0
        parse_success = true
    catch e
        parse_time  = time() - t0
        parse_error = sprint(showerror, e, catch_backtrace())
    end
    println(log_file, "Time:    $(round(parse_time; digits=3)) s")
    println(log_file, "Success: $parse_success")
    isempty(parse_error) || println(log_file, "\n--- Error ---\n$parse_error")
    close(log_file)

    return parse_success, parse_time, parse_error, ode_prob
end
