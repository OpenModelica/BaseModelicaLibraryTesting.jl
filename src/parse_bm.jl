# ── Phase 2: Base Modelica parsing with BaseModelica.jl ───────────────────────

import BaseModelica

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

    t0 = time()
    try
        # create_odeproblem returns an ODEProblem using the Experiment
        # annotation for StartTime/StopTime/Tolerance/Interval.
        ode_prob      = BaseModelica.create_odeproblem(bm_path)
        parse_time    = time() - t0
        parse_success = true
    catch e
        parse_time  = time() - t0
        parse_error = sprint(showerror, e, catch_backtrace())
    end

    open(joinpath(model_dir, "$(model)_parsing.log"), "w") do f
        println(f, "Model:   $model")
        println(f, "Time:    $(round(parse_time; digits=3)) s")
        println(f, "Success: $parse_success")
        isempty(parse_error) || println(f, "\n--- Error ---\n$parse_error")
    end

    return parse_success, parse_time, parse_error, ode_prob
end
