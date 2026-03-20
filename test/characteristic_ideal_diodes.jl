@testset "CharacteristicIdealDiodes simulation (algebraic unknowns)" begin
    # This model has unknowns but all are algebraic (zero mass-matrix rows).
    # Regression test: Rodas5Pr returned Unstable when the saveat-grid fix
    # was only applied to models with no unknowns at all.
    model    = "Modelica.Electrical.Analog.Examples.CharacteristicIdealDiodes"
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
