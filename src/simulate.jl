# ── Phase 3: ODE simulation with DifferentialEquations / MTK ──────────────────

import DifferentialEquations: solve, Rodas5P, ReturnCode
import ModelingToolkit
import Printf: @sprintf

"""
    run_simulate(ode_prob, model_dir, model) → (success, time, error, sol)

Solve `ode_prob` with Rodas5P (stiff solver).  On success, also writes the
full solution as a CSV file `<Short>_sim.csv` in `model_dir`.
Writes a `<model>_sim.log` file in `model_dir`.
Returns `nothing` as the fourth element on failure.
"""
function run_simulate(ode_prob, model_dir::String,
                      model::String)::Tuple{Bool,Float64,String,Any}
    sim_success = false
    sim_time    = 0.0
    sim_error   = ""
    sol         = nothing

    t0 = time()
    try
        # Rodas5P handles stiff DAE-like systems well.
        sol      = solve(ode_prob, Rodas5P())
        sim_time = time() - t0
        if sol.retcode == ReturnCode.Success
            sim_success = true
        else
            sim_error = "Solver returned: $(sol.retcode)"
        end
    catch e
        sim_time  = time() - t0
        sim_error = sprint(showerror, e, catch_backtrace())
    end

    open(joinpath(model_dir, "$(model)_sim.log"), "w") do f
        println(f, "Model:   $model")
        println(f, "Time:    $(round(sim_time; digits=3)) s")
        println(f, "Success: $sim_success")
        isempty(sim_error) || println(f, "\n--- Error ---\n$sim_error")
    end

    # Write simulation results CSV (time + all state variables)
    if sim_success && sol !== nothing
        short_name = split(model, ".")[end]
        sim_csv    = joinpath(model_dir, "$(short_name)_sim.csv")
        try
            sys       = sol.prob.f.sys
            vars      = ModelingToolkit.unknowns(sys)
            col_names = [_clean_var_name(string(v)) for v in vars]
            open(sim_csv, "w") do f
                println(f, join(["time"; col_names], ","))
                for (ti, t) in enumerate(sol.t)
                    row = [@sprintf("%.10g", t)]
                    for vi in eachindex(vars)
                        push!(row, @sprintf("%.10g", sol[vi, ti]))
                    end
                    println(f, join(row, ","))
                end
            end
        catch e
            @warn "Failed to write simulation CSV for $model: $(sprint(showerror, e))"
        end
    end

    return sim_success, sim_time, sim_error, sol
end
