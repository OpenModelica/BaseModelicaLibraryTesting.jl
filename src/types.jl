# ── Shared constants ───────────────────────────────────────────────────────────

const LIBRARY         = "Modelica"
const LIBRARY_VERSION = "4.1.0"

# Comparison tolerances (2 % relative, 1e-6 absolute — matches Modelica
# Association compliance tooling defaults).
const CMP_REL_TOL = 0.02
const CMP_ABS_TOL = 1e-6

# ── Comparison settings ────────────────────────────────────────────────────────

"""
    CompareSettings

Mutable configuration struct for signal comparison.

# Fields
- `rel_tol`  — maximum allowed relative error (default: `$(CMP_REL_TOL)`, i.e. 2 %).
- `abs_tol`  — hard absolute-error floor used when signals are near zero
               (default: `$(CMP_ABS_TOL)`).
- `error_fn` — selects the point-wise pass/fail function.  One of:
  - `:mixed`    — scale-aware relative error (default, recommended);
  - `:relative` — classic relative error (may reject valid zero-crossing signals);
  - `:absolute` — pure absolute error.

Use `configure_comparison!` to update the module-level defaults, or construct a
local instance to pass to `compare_with_reference` for a single run.
"""
Base.@kwdef mutable struct CompareSettings
    rel_tol  :: Float64 = CMP_REL_TOL
    abs_tol  :: Float64 = CMP_ABS_TOL
    error_fn :: Symbol  = :mixed
end

# ── Result type ────────────────────────────────────────────────────────────────

struct ModelResult
    name           :: String
    export_success :: Bool
    export_time    :: Float64
    export_error   :: String
    parse_success  :: Bool
    parse_time     :: Float64
    parse_error    :: String
    sim_success    :: Bool
    sim_time       :: Float64
    sim_error      :: String
    cmp_total      :: Int     # 0 = no reference data available
    cmp_pass       :: Int
    cmp_csv        :: String  # absolute path to diff CSV; "" if all pass or no comparison
end
