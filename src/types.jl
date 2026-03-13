# ── Shared constants ───────────────────────────────────────────────────────────

const LIBRARY         = "Modelica"
const LIBRARY_VERSION = "4.1.0"

# Comparison tolerances (2 % relative, 1e-6 absolute — matches Modelica
# Association compliance tooling defaults).
const CMP_REL_TOL = 0.02
const CMP_ABS_TOL = 1e-6

# CSV files larger than this limit are not committed to gh-pages (GitHub
# enforces a 100 MB hard cap; we use a conservative 20 MB soft limit).
const CSV_MAX_SIZE_MB = 20

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

# ── Run metadata ───────────────────────────────────────────────────────────────

"""
    RunInfo

Metadata about a single test run, collected by `main()` and written into both
`index.html` and `summary.json`.

# Fields
- `library`      — Modelica library name (e.g. `"Modelica"`)
- `lib_version`  — library version (e.g. `"4.1.0"`)
- `filter`       — model name filter regex, or `""` when none was given
- `omc_exe`      — path / command used to launch OMC
- `omc_options`  — full options string passed to `setCommandLineOptions`
- `results_root` — absolute path where results are written
- `ref_root`     — absolute path to reference results, or `""` when unused
- `omc_version`  — version string returned by `getVersion()`, e.g. `"v1.23.0"`
- `bm_version`   — BaseModelica.jl version string, e.g. `"1.6.0"` or `"main"`
- `bm_sha`       — git tree-SHA of the installed BaseModelica.jl (first 7 chars), or `""`
- `cpu_model`    — CPU model name from `Sys.cpu_info()`
- `cpu_threads`  — number of logical CPU threads
- `ram_gb`       — total system RAM in GiB
- `total_time_s` — wall-clock duration of the full test run in seconds
"""
struct RunInfo
    library      :: String
    lib_version  :: String
    filter       :: String   # "" when no filter was given
    omc_exe      :: String
    omc_options  :: String
    results_root :: String
    ref_root     :: String   # "" when no reference root was given
    omc_version  :: String
    bm_version   :: String
    bm_sha       :: String   # git tree-SHA (short), "" for registry installs
    cpu_model    :: String
    cpu_threads  :: Int
    ram_gb       :: Float64
    total_time_s :: Float64
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
    cmp_total      :: Int     # signals actually compared (found in simulation)
    cmp_pass       :: Int
    cmp_skip       :: Int     # reference signals not found in simulation
    cmp_csv        :: String  # absolute path to diff CSV; "" if all pass or no comparison
end
