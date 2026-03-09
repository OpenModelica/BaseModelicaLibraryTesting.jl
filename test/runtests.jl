"""
Tests for the BaseModelicaLibraryTesting package.

Sections:
  1. Unit tests  — pure helper functions, no OMC or simulation needed.
  2. Integration — full pipeline for Modelica.Electrical.Analog.Examples.ChuaCircuit.

Run from the julia/ directory:
  julia --project=. test/runtests.jl

Or via Pkg:
  julia --project=. -e 'import Pkg; Pkg.test()'

Environment variables:
  OMC_EXE   Path to the omc binary (default: system PATH)
"""

import Test: @test, @testset
import OMJulia
import BaseModelicaLibraryTesting: run_export, run_parse, run_simulate,
                                    _clean_var_name, _normalize_var,
                                    _ref_csv_path, _read_ref_csv

# ── 1. Unit tests ──────────────────────────────────────────────────────────────

@testset "Unit tests" begin

    @testset "_clean_var_name" begin
        # Standard MTK form: var"name"(t)
        @test _clean_var_name("var\"C1.v\"(t)") == "C1.v"
        # Without (t)
        @test _clean_var_name("var\"C1.v\"") == "C1.v"
        # Plain name with (t) suffix
        @test _clean_var_name("C1.v(t)") == "C1.v"
        # Plain name, no annotation
        @test _clean_var_name("x") == "x"
        # Leading/trailing whitespace is stripped
        @test _clean_var_name("  foo(t)  ") == "foo"
        # ₊ hierarchy separator is preserved (it is the job of _normalize_var)
        @test _clean_var_name("var\"C1₊v\"(t)") == "C1₊v"
    end

    @testset "_normalize_var" begin
        # Reference-CSV side: plain dot-separated name
        @test _normalize_var("C1.v")             == "c1.v"
        @test _normalize_var("L.i")              == "l.i"
        # MTK side with ₊ hierarchy separator and (t) annotation
        @test _normalize_var("C1₊v(t)")          == "c1.v"
        # MTK side with var"..." quoting
        @test _normalize_var("var\"C1₊v\"(t)")   == "c1.v"
        # Already normalized input
        @test _normalize_var("c1.v")             == "c1.v"
        # Multi-level hierarchy
        @test _normalize_var("a₊b₊c(t)")        == "a.b.c"
    end

    @testset "_ref_csv_path" begin
        mktempdir() do dir
            model   = "Modelica.Electrical.Analog.Examples.ChuaCircuit"
            csv_dir = joinpath(dir, "Modelica", "Electrical", "Analog",
                               "Examples", "ChuaCircuit")
            mkpath(csv_dir)
            csv_file = joinpath(csv_dir, "ChuaCircuit.csv")
            write(csv_file, "")
            @test _ref_csv_path(dir, model) == csv_file
            @test _ref_csv_path(dir, "Modelica.NotExisting") === nothing
        end
    end

    @testset "_read_ref_csv" begin
        mktempdir() do dir
            csv = joinpath(dir, "test.csv")

            # Quoted headers (MAP-LIB format)
            write(csv, "\"time\",\"C1.v\",\"L.i\"\n0,4,0\n0.5,3.5,0.1\n1,3.0,0.2\n")
            times, data = _read_ref_csv(csv)
            @test times        ≈ [0.0, 0.5, 1.0]
            @test data["C1.v"] ≈ [4.0, 3.5, 3.0]
            @test data["L.i"]  ≈ [0.0, 0.1, 0.2]
            @test !haskey(data, "\"time\"")   # quotes must be stripped from keys

            # Unquoted headers
            write(csv, "time,x,y\n0,1,2\n1,3,4\n")
            times2, data2 = _read_ref_csv(csv)
            @test times2     ≈ [0.0, 1.0]
            @test data2["x"] ≈ [1.0, 3.0]
            @test data2["y"] ≈ [2.0, 4.0]

            # Empty file → empty collections
            write(csv, "")
            t0, d0 = _read_ref_csv(csv)
            @test isempty(t0)
            @test isempty(d0)

            # Blank lines between data rows are ignored
            write(csv, "time,v\n0,1\n\n1,2\n\n")
            times3, data3 = _read_ref_csv(csv)
            @test times3     ≈ [0.0, 1.0]
            @test data3["v"] ≈ [1.0, 2.0]
        end
    end

end  # "Unit tests"

# ── 2. Integration test ────────────────────────────────────────────────────────

const TEST_MODEL = "Modelica.Electrical.Analog.Examples.ChuaCircuit"
const TEST_OMC   = get(ENV, "OMC_EXE", "omc")

@testset "ChuaCircuit pipeline" begin
    tmpdir    = mktempdir()
    model_dir = joinpath(tmpdir, "files", TEST_MODEL)
    mkpath(model_dir)
    bm_path = replace(abspath(joinpath(model_dir, "$TEST_MODEL.bmo")), "\\" => "/")

    omc = OMJulia.OMCSession(TEST_OMC)
    try
        OMJulia.sendExpression(omc, """setCommandLineOptions("--baseModelica --baseModelicaOptions=scalarize,moveBindings -d=evaluateAllParameters")""")
        ok = OMJulia.sendExpression(omc, """loadModel(Modelica, {"4.1.0"})""")
        @test ok == true

        exp_ok, _, exp_err = run_export(omc, TEST_MODEL, model_dir, bm_path)
        @test exp_ok
        exp_ok || @warn "Export error: $exp_err"

        if exp_ok
            par_ok, _, par_err, ode_prob = run_parse(bm_path, model_dir, TEST_MODEL)
            @test par_ok
            par_ok || @warn "Parse error: $par_err"

            if par_ok
                sim_ok, _, sim_err, _ = run_simulate(ode_prob, model_dir, TEST_MODEL)
                @test sim_ok
                sim_ok || @warn "Simulation error: $sim_err"
            end
        end
    finally
        OMJulia.quit(omc)
    end
end
