@testset "OpAmps.Subtracter verification" begin
    model    = "Modelica.Electrical.Analog.Examples.OpAmps.Subtracter"
    bmo_path = joinpath(FIXTURES, "$model.bmo")
    ref_dir  = joinpath(FIXTURES, "Subtracter")
    ref_csv  = joinpath(ref_dir, "Subtracter.csv")
    sig_file = joinpath(ref_dir, "comparisonSignals.txt")
    signals  = String.(filter(s -> lowercase(s) != "time" && !isempty(s),
                              strip.(readlines(sig_file))))
    mktempdir() do tmpdir
        model_dir = joinpath(tmpdir, "files", model)
        par_ok, _, par_err, ode_prob = run_parse(bmo_path, model_dir, model)
        @test par_ok
        par_ok || @warn "Parse error: $par_err"

        if par_ok
            sim_ok, _, sim_err, sol = run_simulate(ode_prob, model_dir, model;
                                                   cmp_signals = signals)
            @test sim_ok
            sim_ok || @warn "Simulation error: $sim_err"

            if sim_ok
                total, pass, skip, _ = compare_with_reference(
                    sol, ref_csv, model_dir, model; signals)
                @test_broken pass == total
                @info "OpAmps.Subtracter: $pass/$total signals pass (skip=$skip)"
            end
        end
    end
end
