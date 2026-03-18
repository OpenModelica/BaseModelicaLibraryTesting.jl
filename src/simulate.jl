# ── Phase 3: ODE simulation with DifferentialEquations / MTK ──────────────────

import DifferentialEquations
import Logging
import ModelingToolkit
import Printf: @sprintf

"""
    run_simulate(ode_prob, model_dir, model; csv_max_size_mb) → (success, time, error, sol)

Solve `ode_prob` with Rodas5P (stiff solver).  On success, also writes the
solution as a CSV file `<Short>_sim.csv` in `model_dir`.
Writes a `<model>_sim.log` file in `model_dir`.
Returns `nothing` as the fourth element on failure.

CSV files larger than `csv_max_size_mb` MiB are deleted and replaced with a
`<Short>_sim.csv.toobig` marker so that the report can note the omission.
"""
function run_simulate(ode_prob, model_dir::String,
                      model::String;
                      cmp_signals    ::Vector{String} = String[],
                      csv_max_size_mb::Int            = CSV_MAX_SIZE_MB)::Tuple{Bool,Float64,String,Any}
    sim_success = false
    sim_time    = 0.0
    sim_error   = ""
    sol         = nothing

    log_file = open(joinpath(model_dir, "$(model)_sim.log"), "w")
    println(log_file, "Model:   $model")
    logger = Logging.SimpleLogger(log_file, Logging.Debug)
    t0 = time()

    # Read interval before overwriting it
    interval = something(get(ode_prob.kwargs, :saveat, nothing),
                         (ode_prob.tspan[end] - ode_prob.tspan[1]) / 500)

    try
        # Rodas5P handles stiff DAE-like systems well.
        # Redirect all library log output (including Symbolics/MTK warnings)
        # to the log file so they don't clutter stdout.
        sol = Logging.with_logger(logger) do
            DifferentialEquations.solve(ode_prob, DifferentialEquations.Rodas5P(); saveat = Float64[], dense = true)
        end
        sim_time = time() - t0
        if sol.retcode == DifferentialEquations.ReturnCode.Success
            sys    = sol.prob.f.sys
            n_vars = length(ModelingToolkit.unknowns(sys))
            n_obs  = length(ModelingToolkit.observed(sys))
            if isempty(sol.t)
                sim_error = "Simulation produced no time points"
            elseif n_vars == 0 && n_obs == 0
                sim_error = "Simulation produced no output variables (no states or observed)"
            else
                sim_success = true
            end
        else
            sim_error = "Solver returned: $(sol.retcode)"
        end
    catch e
        sim_time  = time() - t0
        sim_error = sprint(showerror, e, catch_backtrace())
    end
    println(log_file, "Time:    $(round(sim_time; digits=3)) s")
    println(log_file, "Success: $sim_success")
    isempty(sim_error) || println(log_file, "\n--- Error ---\n$sim_error")
    close(log_file)

    # Write simulation results CSV (time + state variables + observed variables)
    if sim_success && sol !== nothing
        short_name = split(model, ".")[end]
        sim_csv    = joinpath(model_dir, "$(short_name)_sim.csv")
        try
            sys      = sol.prob.f.sys
            vars     = ModelingToolkit.unknowns(sys)
            obs_eqs  = ModelingToolkit.observed(sys)
            # Only save observed variables that appear in cmp_signals.
            # This avoids writing thousands of algebraic variables to disk when
            # only a handful are actually verified during comparison.
            norm_cmp = Set(_normalize_var(s) for s in cmp_signals)
            obs_eqs_filtered = isempty(norm_cmp) ? obs_eqs :
                filter(eq -> _normalize_var(string(eq.lhs)) in norm_cmp, obs_eqs)
            obs_syms = [eq.lhs for eq in obs_eqs_filtered]
            col_names = vcat(
                [_clean_var_name(string(v)) for v in vars],
                [_clean_var_name(string(s)) for s in obs_syms],
            )
            open(sim_csv, "w") do f
                println(f, join(["time"; col_names], ","))
                t_csv = range(ode_prob.tspan[1], ode_prob.tspan[end]; step = interval)
                for t in t_csv
                    row = [@sprintf("%.10g", t)]
                    u   = sol(Float64(t))
                    for vi in eachindex(vars)
                        push!(row, @sprintf("%.10g", u[vi]))
                    end
                    for sym in obs_syms
                        val = try Float64(sol(Float64(t); idxs = sym)) catch; NaN end
                        push!(row, @sprintf("%.10g", val))
                    end
                    println(f, join(row, ","))
                end
            end
            csv_bytes = filesize(sim_csv)
            if csv_bytes > csv_max_size_mb * 1024^2
                csv_mb = round(csv_bytes / 1024^2; digits=1)
                @warn "Simulation CSV for $model is $(csv_mb) MB (> $(csv_max_size_mb) MB limit); skipping."
                write(sim_csv * ".toobig", string(csv_bytes))
            end
        catch e
            @warn "Failed to write simulation CSV for $model: $(sprint(showerror, e))"
        end
    end

    return sim_success, sim_time, sim_error, sol
end
