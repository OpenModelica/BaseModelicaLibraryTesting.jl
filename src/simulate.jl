# ── Phase 3: ODE simulation with DifferentialEquations / MTK ──────────────────

import DifferentialEquations
import LinearAlgebra
import OrdinaryDiffEqBDF
import Logging
import ModelingToolkit
import Printf: @sprintf

"""Module-level default simulation settings.  Modify via `configure_simulate!`."""
const _SIM_SETTINGS = SimulateSettings(solver = DifferentialEquations.Rodas5Pr())

"""
    configure_simulate!(; solver, saveat_n) → SimulateSettings

Update the module-level simulation settings in-place and return them.

# Keyword arguments
- `solver`   — any SciML ODE/DAE algorithm instance (e.g. `FBDF()`, `Rodas5Pr()`).
- `saveat_n` — number of uniform time points for purely algebraic systems.

# Example

```julia
using OrdinaryDiffEqBDF
configure_simulate!(solver = FBDF())
```
"""
function configure_simulate!(;
    solver   :: Union{Any,Nothing} = nothing,
    saveat_n :: Union{Int,Nothing} = nothing,
)
    isnothing(solver)   || (_SIM_SETTINGS.solver   = solver)
    isnothing(saveat_n) || (_SIM_SETTINGS.saveat_n = saveat_n)
    return _SIM_SETTINGS
end

"""
    simulate_settings() → SimulateSettings

Return the current module-level simulation settings.
"""
simulate_settings() = _SIM_SETTINGS

"""
    run_simulate(ode_prob, model_dir, model; settings, cmp_signals, csv_max_size_mb) → (success, time, error, sol)

Solve `ode_prob` using the algorithm in `settings.solver`.  On success, also writes the
solution as a CSV file `<Short>_sim.csv` in `model_dir`.
Writes a `<model>_sim.log` file in `model_dir`.
Returns `nothing` as the fourth element on failure.

When `cmp_signals` is non-empty, only observed variables whose names appear in
that list are written to the CSV, keeping file sizes small when only a subset
of signals will be compared.

CSV files larger than `csv_max_size_mb` MiB are replaced with a
`<Short>_sim.csv.toobig` marker so that the report can note the omission.
"""
function run_simulate(ode_prob,
                      model_dir::String,
                      model::String;
                      settings       ::SimulateSettings = _SIM_SETTINGS,
                      cmp_signals    ::Vector{String}   = String[],
                      csv_max_size_mb::Int              = CSV_MAX_SIZE_MB)::Tuple{Bool,Float64,String,Any}
    sim_success           = false
    sim_time              = 0.0
    sim_error             = ""
    sol                   = nothing
    solver_settings_string = ""

    log_file = open(joinpath(model_dir, "$(model)_sim.log"), "w")
    println(log_file, "Model:   $model")
    logger = Logging.SimpleLogger(log_file, Logging.Debug)
    t0 = time()

    solver = settings.solver
    try
        # Redirect all library log output (including Symbolics/MTK warnings)
        # to the log file so they don't clutter stdout.
        sol = Logging.with_logger(logger) do
            # Overwrite saveat, always use dense output.
            # For stateless models (no unknowns) the adaptive solver takes no
            # internal steps and sol.t would be empty with saveat=[].
            # Supply explicit time points so observed variables can be evaluated.
            sys        = ode_prob.f.sys
            M          = ode_prob.f.mass_matrix
            unknowns   = ModelingToolkit.unknowns(sys)
            n_unknowns = length(unknowns)
            n_diff     = if M isa LinearAlgebra.UniformScaling
                n_unknowns
            else
                count(!iszero, LinearAlgebra.diag(M))
            end

            kwargs = if n_unknowns == 0
                # No unknowns at all (e.g. BusUsage): the solver takes no
                # internal steps with saveat=[], leaving sol.t empty.
                # Use a fixed grid + adaptive=false so observed variables
                # can be evaluated.
                t0_s, t1_s = ode_prob.tspan
                saveat_s   = collect(range(t0_s, t1_s; length = settings.saveat_n))
                dt_s       = saveat_s[2] - saveat_s[1]
                (saveat = saveat_s, adaptive = false, dt = dt_s, dense = false)
            elseif n_diff == 0
                # Algebraic unknowns only (e.g. CharacteristicIdealDiodes):
                # the solver must take adaptive steps to track discontinuities.
                # Keep saveat=[] + dense=true so the solver drives its own
                # step selection; dense output is unreliable but the solution
                # values at each step are correct.
                (saveat = Float64[], dense = true)
            else
                (saveat = Float64[], dense = true)
            end

            # Log solver settings — init returns NullODEIntegrator (no .opts)
            # when the problem has no unknowns (u::Nothing), so only inspect
            # opts when a real integrator is returned.
            # Use our own `saveat` vector for the log: integ.opts.saveat is a
            # BinaryHeap which does not support iterate/minimum/maximum.
            integ = DifferentialEquations.init(ode_prob, solver; kwargs...)
            saveat = kwargs.saveat
            solver_settings_string = if hasproperty(integ, :opts)
                sv_str = isempty(saveat) ? "[]" : "$(length(saveat)) points in [$(first(saveat)), $(last(saveat))]"
                """
                Solver $(parentmodule(typeof(solver))).$(nameof(typeof(solver)))
                    saveat:   $sv_str
                    abstol:   $(@sprintf("%.2e", integ.opts.abstol))
                    reltol:   $(@sprintf("%.2e", integ.opts.reltol))
                    adaptive: $(integ.opts.adaptive)
                    dense:    $(integ.opts.dense)
                """
            else
                sv_str = isempty(saveat) ? "[]" : "$(length(saveat)) points in [$(first(saveat)), $(last(saveat))]"
                "Solver (NullODEIntegrator — no unknowns)
                    saveat: $sv_str
                    dense:  true"
            end

            # Solve
            DifferentialEquations.solve(ode_prob, OrdinaryDiffEqBDF.FBDF(); kwargs...)
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
    println(log_file, solver_settings_string)
    println(log_file, "Time: $(round(sim_time; digits=3)) s")
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
                for (ti, t) in enumerate(sol.t)
                    row = [@sprintf("%.10g", t)]
                    for vi in eachindex(vars)
                        push!(row, @sprintf("%.10g", sol[vi, ti]))
                    end
                    for sym in obs_syms
                        val = try Float64(sol(t; idxs = sym)) catch; NaN end
                        push!(row, @sprintf("%.10g", val))
                    end
                    println(f, join(row, ","))
                end
            end
            csv_bytes = filesize(sim_csv)
            if csv_bytes > csv_max_size_mb * 1024^2
                csv_mb = round(csv_bytes / 1024^2; digits=1)
                @warn "Simulation CSV for $model is $(csv_mb) MB (> $(csv_max_size_mb) MB limit); skipping."
                rm(sim_csv)
                write(sim_csv * ".toobig", string(csv_bytes))
            end
        catch e
            @warn "Failed to write simulation CSV for $model: $(sprint(showerror, e))"
        end
    end

    return sim_success, sim_time, sim_error, sol
end
