module BaseModelicaLibraryTesting

import Pkg
import OMJulia
import OMJulia: sendExpression
import BaseModelica
import DifferentialEquations: solve, Rodas5P, ReturnCode
import ModelingToolkit
import Dates: now
import Printf: @sprintf

include("types.jl")
include("compare.jl")    # defines _clean_var_name used by simulate.jl
include("export.jl")
include("parse_bm.jl")
include("simulate.jl")
include("report.jl")
include("summary.jl")
include("pipeline.jl")

# ── Public API ─────────────────────────────────────────────────────────────────

# Shared types and constants
export ModelResult, CompareSettings, RunInfo
export CMP_REL_TOL, CMP_ABS_TOL

# Pipeline phases
export run_export       # Phase 1: Base Modelica export via OMC
export run_parse        # Phase 2: BaseModelica.jl → ODEProblem
export run_simulate     # Phase 3: DifferentialEquations solve + CSV

# Reference comparison
export compare_with_reference, write_diff_html

# HTML report
export generate_report

# Summary JSON
export RunSummary, write_summary, load_summary

# Top-level orchestration
export test_model, main

end # module BaseModelicaLibraryTesting
