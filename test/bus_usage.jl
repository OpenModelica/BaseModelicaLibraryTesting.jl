@testset "BusUsage simulation (no states)" begin
    # Modelica.Blocks.Examples.BusUsage has no unknowns after structural_simplify.
    # The saveat-grid path in run_simulate must handle this without error.
    model    = "Modelica.Blocks.Examples.BusUsage"
    bmo_path = joinpath(FIXTURES, "$model.bmo")
    mktempdir() do tmpdir
        par_ok, _, par_err, ode_prob = run_parse(bmo_path, tmpdir, model)
        @test par_ok
        par_ok || @warn "Parse error: $par_err"

        if par_ok
            sim_ok, _, sim_err, _ = run_simulate(ode_prob, tmpdir, model)
            @test sim_ok
            sim_ok || @warn "Simulation error: $sim_err"
        end
    end
end
