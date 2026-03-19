@testset "AmplifierWithOpAmpDetailed verification" begin
    model    = "Modelica.Electrical.Analog.Examples.AmplifierWithOpAmpDetailed"
    bmo_path = joinpath(FIXTURES, "$model.bmo")
    ref_dir  = joinpath(FIXTURES, "AmplifierWithOpAmpDetailed")
    ref_csv  = joinpath(ref_dir, "AmplifierWithOpAmpDetailed.csv")
    sig_file = joinpath(ref_dir, "comparisonSignals.txt")
    signals  = String.(filter(s -> lowercase(s) != "time" && !isempty(s),
                              strip.(readlines(sig_file))))
    mktempdir() do tmpdir
        par_ok, _, par_err, ode_prob = run_parse(bmo_path, tmpdir, model)
        @test par_ok
        par_ok || @warn "Parse error: $par_err"

        if par_ok
            sim_ok, _, sim_err, sol = run_simulate(ode_prob, tmpdir, model;
                                                   cmp_signals = signals)
            @test sim_ok
            sim_ok || @warn "Simulation error: $sim_err"

            if sim_ok
                total, pass, skip, _ = compare_with_reference(
                    sol, ref_csv, tmpdir, model; signals)
                @test pass == total
                @info "AmplifierWithOpAmpDetailed: $pass/$total signals pass (skip=$skip)"
            end
        end
    end
end
