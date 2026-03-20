# ── HTML report generation ─────────────────────────────────────────────────────

import Dates: now
import Printf: @sprintf

function _status_cell(ok::Bool, t::Float64, logFile::Union{String,Nothing})
    link = isnothing(logFile) ? "" : """ <a href="$(logFile)">(log)</a>"""
    time = t > 0 ? @sprintf("%.2f", t) * " s" : ""
    if ok
        return """<td class="ok">&#10003;$(time)$(link)</td>"""
    else
        return """<td class="fail">&#10007;$(time)$(link)</td>"""
    end
end

"""
    _cmp_cell(r, results_root, csv_max_size_mb) → HTML string

Build the "Ref Cmp" table cell for one model row.

Cell colour:
- green   (`ok`)      — all comparable signals pass, full coverage
- orange  (`partial`) — all comparable signals pass but some not found in simulation
- red     (`fail`)    — at least one signal outside tolerance
- grey    (`na`)      — no reference data at all

The sim CSV is always linked when the file exists (or shows "(CSV N/A)" when it
exceeded `csv_max_size_mb` MB and was replaced by a `.toobig` marker).  When there
are failures or skipped signals the detail page `<short>_diff.html` — which holds
zoomable charts and the variable-coverage table — is also linked.
"""
function _cmp_cell(r::ModelResult, results_root::String, csv_max_size_mb::Int)
    short = split(r.name, ".")[end]

    # ── Sim CSV link ────────────────────────────────────────────────────────────
    sim_csv     = joinpath("files", r.name, "$(short)_sim.csv")
    abs_sim_csv = joinpath(results_root, sim_csv)
    csv_link = if isfile(abs_sim_csv * ".toobig")
        """ <span title="Result file exceeds $(csv_max_size_mb) MB and was not uploaded">(CSV N/A)</span>"""
    elseif isfile(abs_sim_csv)
        """ <a href="$sim_csv">(CSV)</a>"""
    else
        ""
    end

    # ── Detail-page link (diff HTML with charts + coverage table) ───────────────
    diff_html_rel = joinpath("files", r.name, "$(short)_diff.html")
    has_details   = isfile(joinpath(results_root, diff_html_rel))

    # ── No comparison data at all ───────────────────────────────────────────────
    if r.cmp_total == 0 && r.cmp_skip == 0
        return isempty(csv_link) ? """<td class="na">—</td>""" :
                                   """<td class="na">$(csv_link)</td>"""
    end

    skip_note    = r.cmp_skip > 0 ? ", $(r.cmp_skip) not found" : ""
    details_link = has_details ? """ <a href="$diff_html_rel">(details)</a>""" : ""

    n, p = r.cmp_total, r.cmp_pass
    if p == n && r.cmp_skip == 0
        # Full coverage, all pass — green.
        return """<td class="ok">&#10003; $p/$n$(csv_link)</td>"""
    elseif p == n
        # Partial coverage, all comparable signals pass — orange.
        return """<td class="partial">&#10003; $p/$n$(skip_note)$(details_link)$(csv_link)</td>"""
    else
        # At least one failure — red; score links to the detail page.
        score = has_details ? """<a href="$diff_html_rel">$p/$n$(skip_note)</a>""" :
                              "$p/$n$(skip_note)"
        return """<td class="fail">$(score)$(csv_link)</td>"""
    end
end

function _cmp_status(r::ModelResult)::String
    r.cmp_total == 0 && r.cmp_skip == 0 && return "na"
    r.cmp_pass == r.cmp_total && return "pass"
    return "fail"
end

function rel_log_file_or_nothing(results_root::String, model::String,
                                  phase::String)::Union{String,Nothing}
    path = joinpath(results_root, "files", model, "$(model)_$(phase).log")
    isfile(path) ? joinpath("files", model, "$(model)_$(phase).log") : nothing
end

function _format_duration(t::Float64)::String
    t < 60 && return @sprintf("%.1f s", t)
    m = div(floor(Int, t), 60)
    s = floor(Int, t) % 60
    m < 60 && return @sprintf("%d min %d s", m, s)
    h = div(m, 60)
    return @sprintf("%d h %d min %d s", h, m % 60, s)
end

"""
    generate_report(results, results_root, info; csv_max_size_mb) → report_path

Write an `index.html` overview report to `results_root` and return its path.
"""
function generate_report(results::Vector{ModelResult}, results_root::String,
                         info::RunInfo; csv_max_size_mb::Int = CSV_MAX_SIZE_MB)
    n     = length(results)
    n_exp = count(r -> r.export_success, results)
    n_par = count(r -> r.parse_success,  results)
    n_sim = count(r -> r.sim_success,    results)

    # Comparison summary (only models where cmp_total > 0)
    cmp_results  = filter(r -> r.cmp_total > 0, results)
    n_cmp_models = length(cmp_results)
    n_cmp_pass   = count(r -> r.cmp_pass == r.cmp_total, cmp_results)

    pct(num, den) = den > 0 ? @sprintf("%.1f%%", 100 * num / den) : "n/a"

    cmp_summary_row = n_cmp_models > 0 ? """
  <tr><td>Reference Comparison (MAP-LIB)</td><td>$n_cmp_pass</td><td>$n_cmp_models</td><td>$(pct(n_cmp_pass,n_cmp_models))</td></tr>""" : ""

    rows = join(["""    <tr data-exp="$(r.export_success ? "pass" : "fail")" data-par="$(r.parse_success ? "pass" : "fail")" data-sim="$(r.sim_success ? "pass" : "fail")" data-cmp="$(_cmp_status(r))">
      <td><a href="files/$(r.name)/$(r.name).bmo">$(r.name).bmo</a></td>
      $(_status_cell(r.export_success, r.export_time, rel_log_file_or_nothing(results_root, r.name, "export")))
      $(_status_cell(r.parse_success,  r.parse_time,  rel_log_file_or_nothing(results_root, r.name, "parsing")))
      $(_status_cell(r.sim_success,    r.sim_time,    rel_log_file_or_nothing(results_root, r.name, "sim")))
      $(_cmp_cell(r, results_root, csv_max_size_mb))
    </tr>""" for r in results], "\n")

    bm_sha_link = isempty(info.bm_sha) ? "" :
        """ (<a href="https://github.com/SciML/BaseModelica.jl/commit/$(info.bm_sha)">$(info.bm_sha)</a>)"""
    basemodelica_jl_version = info.bm_version * bm_sha_link
    var_filter              = isempty(info.filter)   ? "None" : "<code>$(info.filter)</code>"
    ref_results             = isempty(info.ref_root) ? "None" : "$(info.ref_root)"
    ram_str                 = @sprintf("%.1f", info.ram_gb)
    time_str                = _format_duration(info.total_time_s)

    html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <title>$(info.library) $(info.lib_version) — Base Modelica / MTK Results</title>
  <style>
    body { font-family: sans-serif; margin: 2em; font-size: 14px; }
    h1   { font-size: 1.4em; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ccc; padding: 4px 10px; text-align: left; white-space: nowrap; }
    th { background: #eee; }
    td.ok      { background: #d4edda; color: #155724; }
    td.partial { background: #fff3cd; color: #856404; }
    td.fail    { background: #f8d7da; color: #721c24; }
    td.na      { color: #888; }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .filter-row th { background: #f5f5f5; }
    .filter-row select { font-size: 12px; padding: 1px 4px; }
    .filter-row input { font-size: 12px; padding: 1px 4px; width: 16em; box-sizing: border-box; }
    .filter-row input.invalid { outline: 2px solid #c00; }
  </style>
</head>
<body>
<h1>$(info.library) $(info.lib_version) — Base Modelica / MTK Pipeline Test Results</h1>
<p>Generated: $(now())<br>
OpenModelica: $(info.omc_version)<br>
OMC options: <code>$(info.omc_options)</code><br>
BaseModelica.jl: $(basemodelica_jl_version)<br>
Filter: $(var_filter)<br>
Reference results: $(ref_results)</p>
<p>CPU: $(info.cpu_model) ($(info.cpu_threads) threads)<br>
RAM: $(ram_str) GiB<br>
Total run time: $(time_str)</p>

<table style="width:auto; margin-bottom:1.5em;">
  <tr><th>Stage</th><th>Passed</th><th>Total</th><th>Rate</th></tr>
  <tr><td>Base Modelica Export (OpenModelica)</td><td>$n_exp</td><td>$n</td>    <td>$(pct(n_exp,n))</td></tr>
  <tr><td>Parsing (BaseModelica.jl)</td>          <td>$n_par</td><td>$n_exp</td><td>$(pct(n_par,n_exp))</td></tr>
  <tr><td>Simulation (MTK.jl)</td>                <td>$n_sim</td><td>$n_par</td><td>$(pct(n_sim,n_par))</td></tr>$cmp_summary_row
</table>

<table id="model-table">
  <thead>
    <tr>
      <th>Model</th>
      <th>BM Export</th>
      <th>BM Parse</th>
      <th>MTK Sim</th>
      <th>Ref Cmp</th>
    </tr>
    <tr class="filter-row">
      <th><input id="f-name" type="text" placeholder="regex…" oninput="applyFilters()"/></th>
      <th><select id="f-exp" onchange="applyFilters()"><option value="all">All</option><option value="pass">Pass</option><option value="fail">Fail</option></select></th>
      <th><select id="f-par" onchange="applyFilters()"><option value="all">All</option><option value="pass">Pass</option><option value="fail">Fail</option></select></th>
      <th><select id="f-sim" onchange="applyFilters()"><option value="all">All</option><option value="pass">Pass</option><option value="fail">Fail</option></select></th>
      <th><select id="f-cmp" onchange="applyFilters()"><option value="all">All</option><option value="pass">Pass</option><option value="fail">Fail</option></select></th>
    </tr>
  </thead>
  <tbody id="model-rows">
$rows
  </tbody>
</table>
<script>
function applyFilters() {
  var nameInput = document.getElementById('f-name');
  var nameVal   = nameInput.value;
  var nameRe    = null;
  try {
    nameRe = nameVal ? new RegExp(nameVal, 'i') : null;
    nameInput.classList.remove('invalid');
  } catch(e) {
    nameInput.classList.add('invalid');
    return;
  }
  var exp = document.getElementById('f-exp').value;
  var par = document.getElementById('f-par').value;
  var sim = document.getElementById('f-sim').value;
  var cmp = document.getElementById('f-cmp').value;
  document.querySelectorAll('#model-rows tr').forEach(function(row) {
    var name = row.cells[0] ? row.cells[0].textContent : '';
    var show = (!nameRe || nameRe.test(name)) &&
               (exp === 'all' || row.dataset.exp === exp) &&
               (par === 'all' || row.dataset.par === par) &&
               (sim === 'all' || row.dataset.sim === sim) &&
               (cmp === 'all' || row.dataset.cmp === cmp);
    row.style.display = show ? '' : 'none';
  });
}
</script>
</body>
</html>"""

    report_path = joinpath(results_root, "index.html")
    write(report_path, html)
    @info "Report written to $report_path"
    return report_path
end
