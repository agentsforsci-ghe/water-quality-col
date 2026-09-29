# Plan: HTML version of the manuscript with a sortable table and an interactive map

Tracked as GitHub issues #3 to #6. The earlier plan for rebuilding the manuscript
is in the history of this file (commit 36d2764).

## Context

The Q1/Q2 manuscript in `manuscript/` renders to DOCX with a static columns table
(`tbl-columns`, `knitr::kable`) and a static two-panel map (`fig-map`, ggplot +
patchwork) of the annual IRCA by municipality in 2019, the most complete year. The
goal is an HTML rendering of the same manuscript in which the columns table is
sortable and the IRCA 2019 map is interactive: hovering a municipality shows its
name, its department and its IRCA value.

Decisions:

| Choice | Decision |
|---|---|
| Map library | `leaflet`, installed from CRAN into the user library |
| Formats | Keep DOCX and add HTML. DOCX keeps the static exhibits, HTML gets the interactive ones |
| Packaging | Single self-contained `index.html` (`embed-resources: true`), tracked in git like the DOCX |
| Table library | `reactable` |

## Files

| Action | Path |
|---|---|
| Modify | `manuscript/_quarto.yml`: html format, `meca-bundle: false`, notebook links and previews off in both formats |
| Modify | `manuscript/index.qmd`: conditional table and map blocks |
| Modify | `.gitignore`: ignore `site_libs/`, `index_files/`, previews, `search.json`, notebooks under the output folder |
| Track | `manuscript/_manuscript/index.html` |
| Regenerate | `manuscript/_manuscript/index.docx` |

`R/prepare.R` and `data/geo/` are untouched.

## Design

### Conditional exhibits (issues #4 and #5)

One unconditional `include: false` chunk computes the shared data (`cols_df`;
`map_year`, `map_sf`, `dept_sf`). Two mutually exclusive blocks then carry the same
cross-reference div ID, so prose references `@tbl-columns` and `@fig-map` are
unchanged:

```markdown
:::: {.content-visible unless-format="html"}
::: {#tbl-columns}
<chunk columns-kable, eval guarded with !knitr::is_html_output()>
Caption as the last paragraph of the div.
:::
::::

:::: {.content-visible when-format="html"}
::: {#tbl-columns}
<chunk columns-reactable, eval guarded with knitr::is_html_output()>
Caption as the last paragraph of the div.
:::
::::
```

Quarto resolves `content-visible` before the cross-reference pass, so the two divs
never coexist when numbering happens. Chunk labels stay unique and must not start
with `fig-` or `tbl-`. The `eval` guards stop leaflet from running during the DOCX
render and vice versa.

### Table

`reactable` with `sortable = TRUE`, no pagination, compact, initial order equal to
the file order. Backtick spans in "Note on import" become `<code>` with
`html = TRUE` on that column.

### Map

- Web copy of the geometry: `st_transform(3116)`, `st_simplify(500 m)`,
  `st_transform(4326)`, `st_cast("MULTIPOLYGON")`, coordinates rounded to
  5 decimals. Asserted valid and non-empty for all 1,122 units.
- Tooltip: name, department, and "IRCA 2019: value (band)"; blanks show
  "No record for 2019"; the 19 non-municipalised areas show "Non-municipalised
  area (not expected)".
- `colorFactor` over the existing blue ramp plus the two greys, CartoDB Positron
  basemap, department outlines, legend titled "IRCA 2019", initial view fitted
  to mainland Colombia, height 600 px.
- `stopifnot(map_year == 2019L)` guards the captions.

### Render

Always render both formats together with `quarto render manuscript`. Rendering a
single format with `--to` cleans the other format's file out of `_manuscript/`.
Close Word before rendering.

## Verification (issue #6)

1. `Rscript -e 'source("R/prepare.R")'` passes all checks.
2. `quarto render manuscript` exits 0 for both formats with no warnings.
3. `index.html` under 5 MB, no external CSS or JavaScript, two htmlwidgets embedded,
   tooltip strings present, no `?@fig`/`?@tbl`.
4. DOCX text identical to the previous commit apart from the date.
5. Browser check: tooltips on a municipality, a Chocó blank and an Amazonas area;
   sorting on the table; no "Other Formats" or notebook boxes.
6. `git status` shows nothing from `.quarto/`, `index_files/` or `site_libs/`.
