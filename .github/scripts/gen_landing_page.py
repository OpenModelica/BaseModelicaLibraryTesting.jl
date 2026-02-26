#!/usr/bin/env python3
"""
Generate the root index.html landing page for the gh-pages site.

Scans  results/<bm_version>/<library>/<lib_version>/summary.json
and produces a table linking to each run's individual report.

Usage:
    python3 gen_landing_page.py <site_root>

<site_root> is the root of the gh-pages checkout (i.e. the directory that
contains the 'results/' sub-tree and will receive the generated index.html).
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


# ── Helpers ───────────────────────────────────────────────────────────────────

def pct_str(num: int, den: int) -> str:
    if den == 0:
        return "—"
    return f"{100 * num / den:.1f} %"


def format_duration(seconds: float) -> str:
    t = int(seconds)
    if t < 60:
        return f"{t} s"
    m, s = divmod(t, 60)
    if m < 60:
        return f"{m} min {s} s"
    h, m = divmod(m, 60)
    return f"{h} h {m} min"


def pct_class(num: int, den: int) -> str:
    """CSS class for a pass-rate cell."""
    if den == 0:
        return "na"
    r = num / den
    if r >= 0.90:
        return "ok"
    if r >= 0.70:
        return "warn"
    return "fail"


def git_date(summary_path: Path, site_root: Path) -> str:
    """Return the YYYY-MM-DD of the git commit that last touched summary_path."""
    try:
        rel = summary_path.relative_to(site_root)
        result = subprocess.run(
            ["git", "log", "-1", "--format=%as", "--", str(rel)],
            capture_output=True, text=True, cwd=site_root,
        )
        return result.stdout.strip()
    except Exception:
        return ""


# ── Data loading ──────────────────────────────────────────────────────────────

def load_runs(site_root: Path) -> list[dict]:
    runs = []
    results_dir = site_root / "results"
    if not results_dir.exists():
        return runs

    for summary_path in sorted(results_dir.glob("*/*/*/summary.json"), reverse=True):
        try:
            with open(summary_path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue

        models = data.get("models", [])
        n       = len(models)
        n_exp   = sum(1 for m in models if m.get("export", False))
        n_par   = sum(1 for m in models if m.get("parse",  False))
        n_sim   = sum(1 for m in models if m.get("sim",    False))

        cmp_models = [m for m in models if m.get("cmp_total", 0) > 0]
        n_cmp      = len(cmp_models)
        n_cmp_pass = sum(1 for m in cmp_models if m["cmp_pass"] == m["cmp_total"])

        run_dir   = summary_path.parent
        index_url = str((run_dir / "index.html").relative_to(site_root)).replace("\\", "/")

        runs.append({
            "bm_version":  data.get("bm_version",  "?"),
            "library":     data.get("library",      "?"),
            "lib_version": data.get("lib_version",  "?"),
            "omc_version": data.get("omc_version",  "?"),
            "total":       n,
            "n_exp":       n_exp,
            "n_par":       n_par,
            "n_sim":       n_sim,
            "n_cmp":       n_cmp,
            "n_cmp_pass":  n_cmp_pass,
            "duration":    format_duration(data.get("total_time_s", 0)),
            "date":        git_date(summary_path, site_root),
            "index_url":   index_url,
        })

    return runs


# ── HTML rendering ────────────────────────────────────────────────────────────

def _pct_cell(num: int, den: int) -> str:
    css = pct_class(num, den)
    label = f"{num}/{den} ({pct_str(num, den)})" if den > 0 else "—"
    return f'<td class="{css}">{label}</td>'


def render(runs: list[dict]) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    if runs:
        rows = []
        for r in runs:
            cmp_cell = (
                _pct_cell(r["n_cmp_pass"], r["n_cmp"])
                if r["n_cmp"] > 0
                else '<td class="na">—</td>'
            )
            rows.append(f"""\
  <tr>
    <td><a href="{r['index_url']}">{r['bm_version']}</a></td>
    <td>{r['library']}</td>
    <td>{r['lib_version']}</td>
    <td>{r['omc_version']}</td>
    <td>{r['date']}</td>
    <td>{r['duration']}</td>
    {_pct_cell(r['n_exp'], r['total'])}
    {_pct_cell(r['n_par'], r['n_exp'])}
    {_pct_cell(r['n_sim'], r['n_par'])}
    {cmp_cell}
  </tr>""")
        rows_html = "\n".join(rows)
    else:
        rows_html = '  <tr><td colspan="10" class="na" style="text-align:center">No results yet.</td></tr>'

    return f"""\
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <title>BaseModelicaLibraryTesting — Test Results</title>
  <style>
    body  {{ font-family: sans-serif; margin: 2em; font-size: 14px; }}
    h1    {{ font-size: 1.4em; }}
    table {{ border-collapse: collapse; }}
    th, td {{ border: 1px solid #ccc; padding: 4px 12px; text-align: left; white-space: nowrap; }}
    th    {{ background: #eee; }}
    td.ok   {{ background: #d4edda; color: #155724; }}
    td.warn {{ background: #fff3cd; color: #856404; }}
    td.fail {{ background: #f8d7da; color: #721c24; }}
    td.na   {{ color: #888; }}
    a {{ color: #0366d6; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
  </style>
</head>
<body>
<h1>BaseModelicaLibraryTesting — Test Results</h1>
<p>Generated: {now}</p>
<table>
  <tr>
    <th>BaseModelica.jl</th>
    <th>Library</th>
    <th>Version</th>
    <th>OpenModelica</th>
    <th>Date</th>
    <th>Duration</th>
    <th>BM Export</th>
    <th>BM Parse</th>
    <th>MTK Sim</th>
    <th>Ref Cmp</th>
  </tr>
{rows_html}
</table>
</body>
</html>
"""


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <site_root>", file=sys.stderr)
        sys.exit(1)

    site_root = Path(sys.argv[1]).resolve()
    runs = load_runs(site_root)
    html = render(runs)

    # Disable Jekyll so GitHub Pages serves files as-is
    (site_root / ".nojekyll").touch()

    out = site_root / "index.html"
    out.write_text(html, encoding="utf-8")
    print(f"Landing page written to {out}  ({len(runs)} run(s) listed)")


if __name__ == "__main__":
    main()
