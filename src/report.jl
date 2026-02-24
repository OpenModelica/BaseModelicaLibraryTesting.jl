# ── HTML report generation ─────────────────────────────────────────────────────

import Dates: now
import Printf: @sprintf
import BaseModelica

function _status_cell(ok::Bool, t::Float64, logFile::Union{String,Nothing})
    link = isnothing(logFile) ? "" : """ <a href="$(logFile)">(log)</a>"""
    if ok
        return """<td class="ok">&#10003; $(@sprintf "%.2f" t) s$link</td>"""
    else
        return """<td class="fail">&#10007;$link</td>"""
    end
end

function _cmp_cell(r::ModelResult, results_root::String)
    if r.cmp_total == 0
        return """<td class="na">—</td>"""
    end
    n, p = r.cmp_total, r.cmp_pass
    if p == n
        return """<td class="ok">&#10003; $p/$n</td>"""
    else
        # Link to the interactive diff HTML (next to the CSV, same name, .html extension)
        diff_html = replace(r.cmp_csv, r"\.csv$" => ".html")
        rel = relpath(isfile(diff_html) ? diff_html : r.cmp_csv, results_root)
        return """<td class="fail"><a href="$rel">$p/$n</a></td>"""
    end
end

function rel_log_file_or_nothing(results_root::String, model::String,
                                  phase::String)::Union{String,Nothing}
    path = joinpath(results_root, "files", model, "$(model)_$(phase).log")
    isfile(path) ? joinpath("files", model, "$(model)_$(phase).log") : nothing
end

"""
    generate_report(results, results_root, library, version) → report_path

Write an `index.html` overview report to `results_root` and return its path.
"""
function generate_report(results::Vector{ModelResult}, results_root::String,
                         library::String, version::String)
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

    rows = join(["""    <tr>
      <td><a href="files/$(r.name)/$(r.name).bmo">$(r.name).bmo</a></td>
      $(_status_cell(r.export_success, r.export_time, rel_log_file_or_nothing(results_root, r.name, "export")))
      $(_status_cell(r.parse_success,  r.parse_time,  rel_log_file_or_nothing(results_root, r.name, "parsing")))
      $(_status_cell(r.sim_success,    r.sim_time,    rel_log_file_or_nothing(results_root, r.name, "sim")))
      $(_cmp_cell(r, results_root))
    </tr>""" for r in results], "\n")

    omc_ver = try sendExpression(OMJulia.OMCSession("omc"), "getVersion()") catch; "unknown" end
    bm_ver  = string(pkgversion(BaseModelica))

    html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <title>$library $version — Base Modelica / MTK Results</title>
  <style>
    body { font-family: sans-serif; margin: 2em; font-size: 14px; }
    h1   { font-size: 1.4em; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ccc; padding: 4px 10px; text-align: left; white-space: nowrap; }
    th { background: #eee; }
    td.ok   { background: #d4edda; color: #155724; }
    td.fail { background: #f8d7da; color: #721c24; }
    td.na   { color: #888; }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
<h1>$library $version — Base Modelica / MTK Pipeline Test Results</h1>
<p>Generated: $(now())<br>
OpenModelica: $omc_ver<br>
BaseModelica.jl: $bm_ver</p>

<table style="width:auto; margin-bottom:1.5em;">
  <tr><th>Stage</th><th>Passed</th><th>Total</th><th>Rate</th></tr>
  <tr><td>Base Modelica Export (OpenModelica)</td><td>$n_exp</td><td>$n</td>    <td>$(pct(n_exp,n))</td></tr>
  <tr><td>Parsing (BaseModelica.jl)</td>          <td>$n_par</td><td>$n_exp</td><td>$(pct(n_par,n_exp))</td></tr>
  <tr><td>Simulation (MTK.jl)</td>                <td>$n_sim</td><td>$n_par</td><td>$(pct(n_sim,n_par))</td></tr>$cmp_summary_row
</table>

<table>
  <tr>
    <th>Model</th>
    <th>BM Export</th>
    <th>BM Parse</th>
    <th>MTK Sim</th>
    <th>Ref Cmp</th>
  </tr>
$rows
</table>
</body>
</html>"""

    report_path = joinpath(results_root, "index.html")
    write(report_path, html)
    @info "Report written to $report_path"
    return report_path
end
