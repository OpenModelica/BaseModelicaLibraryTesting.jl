"""
Tests for the BaseModelicaLibraryTesting package.

Files:
  unit_helpers.jl              — pure helper functions, no OMC or simulation needed
  chua_circuit.jl              — full pipeline for ChuaCircuit (requires OMC)
  bus_usage.jl                 — parse+simulate from fixture .bmo (no OMC)
  amplifier_with_op_amp.jl     — parse+simulate+verify from fixture .bmo (no OMC)

Run from the project directory:
  julia --project=. test/runtests.jl

Or via Pkg:
  julia --project=. -e 'import Pkg; Pkg.test()'

Environment variables:
  OMC_EXE   Path to the omc binary (default: system PATH)
"""

import Test: @test, @testset, @test_broken
import OMJulia
import BaseModelicaLibraryTesting: run_export, run_parse, run_simulate,
                                    compare_with_reference,
                                    _clean_var_name, _normalize_var,
                                    _ref_csv_path, _read_ref_csv

const FIXTURES  = joinpath(@__DIR__, "fixtures")
const TEST_OMC  = get(ENV, "OMC_EXE", "omc")
const TEST_MODEL_CHUA = "Modelica.Electrical.Analog.Examples.ChuaCircuit"

include("unit_helpers.jl")
include("chua_circuit.jl")
include("subtracter.jl")
