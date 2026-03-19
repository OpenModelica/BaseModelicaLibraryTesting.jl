@testset "ChuaCircuit pipeline" begin
    tmpdir    = mktempdir()
    model_dir = joinpath(tmpdir, "files", TEST_MODEL_CHUA)
    mkpath(model_dir)
    bm_path = replace(abspath(joinpath(model_dir, "$TEST_MODEL_CHUA.bmo")), "\\" => "/")

    omc = OMJulia.OMCSession(TEST_OMC)
    try
        OMJulia.sendExpression(omc, """setCommandLineOptions("--baseModelica --baseModelicaOptions=scalarize,moveBindings -d=evaluateAllParameters")""")
        ok = OMJulia.sendExpression(omc, """loadModel(Modelica, {"4.1.0"})""")
        @test ok == true

        exp_ok, _, exp_err = run_export(omc, TEST_MODEL_CHUA, model_dir, bm_path)
        @test exp_ok
        exp_ok || @warn "Export error: $exp_err"

        if exp_ok
            par_ok, _, par_err, ode_prob = run_parse(bm_path, model_dir, TEST_MODEL_CHUA)
            @test par_ok
            par_ok || @warn "Parse error: $par_err"

            if par_ok
                sim_ok, _, sim_err, _ = run_simulate(ode_prob, model_dir, TEST_MODEL_CHUA)
                @test sim_ok
                sim_ok || @warn "Simulation error: $sim_err"
            end
        end
    finally
        OMJulia.quit(omc)
    end
end
