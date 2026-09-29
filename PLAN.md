# Plan: answer questions 1 and 2 as a Quarto manuscript (DOCX)

## Context

`questions.md` poses three questions about the Colombian drinking-water quality dataset
`data/Calidad_del_Agua_para_Consumo_Humano_en_Colombia_20260915.csv` (annual IRCA index by
place and year, 2007–2024, 19,160 data rows, 11 columns). The user asked to answer questions
1 (observational unit) and 2 (completeness) and write the result as a Quarto manuscript that
renders to DOCX. Q3 is out of scope.

The repo already holds `manuscript/index.qmd` answering both questions. The user chose to
**rebuild it from scratch**: a fresh, independently structured analysis replacing the current
file. Reusable assets: `data/geo/col_admin.gpkg` (DANE MGN 2020 boundaries, 1,122 municipal
units, 33 departments, WGS 84; built by `data/geo/prepare_boundaries.R`) and the
`_quarto.yml` skeleton (type `manuscript`, docx to `_manuscript/`).

Toolchain verified read-only: Quarto 1.7.31, R 4.6.1; dplyr, readr, tidyr, knitr, ggplot2,
scales, sf, forcats, patchwork, rmarkdown installed. No analysis has been run yet; all
magnitudes quoted below come from the previous manuscript's render and are expectations to
recompute, never to copy.

Known file quirks to handle on import: `Año` is text with a thousands separator ("2,024");
`MunicipioCodigo == "#TODOS"` marks department-level aggregate rows; missing urban/rural values
are the string `ND`; risk labels have 8 spellings (`Sin riesgo`, `Bajo riesgo`/`Riesgo bajo`,
`Riesgo medio`, `Alto riesgo`/`Riesgo alto`, `Inviable sanitariamente`, `ND`); names are
unstable (76001 is "Cali" / "Santiago de Cali"); codes keep leading zeros.

## Files

| Action | Path |
|---|---|
| Create first | `PLAN.md` at the repo root, holding this plan (user wants the plan committed to the repo before implementation starts) |
| Rewrite | `manuscript/index.qmd` |
| Create | `R/prepare.R` at the repo root (import, cleaning, validation, reference frames) |
| Create | `manuscript/references.bib` (Resolución 2115/2007; DANE MGN 2020 via HDX; dataset on datos.gov.co) |
| Modify | `manuscript/_quarto.yml` (add `bibliography`, `execute: freeze: false`, `lang: en`; keep the rest) |
| Delete | `manuscript/_manuscript/~$index.docx` (Word lock file, untracked, gitignored; confirm Word has the docx closed first, else render cannot overwrite `index.docx`) |
| Re-render, keep tracked | `manuscript/_manuscript/index.docx` (repo convention treats the docx as the deliverable) |

No changes to `data/`, `.gitignore`, `prompts/`.

## Code organisation

R code lives in a root-level `R/` folder, not inside `manuscript/`. `R/prepare.R` is sourced
from one `setup` chunk in the qmd and must also run standalone from the repo root
(`Rscript R/prepare.R`). It contains formatting helpers (`fmt_n`, `fmt_pct`), import,
cleaning, all `stopifnot` assertions, and the reference frames. The qmd then has short
`include: false` chunks placed right before each subsection, computing only the scalars and
tables that subsection cites, so every number sits next to the prose it feeds.

Paths: all file paths in `prepare.R` go through `here::here()` (installed; the root
`water-quality-col.Rproj` anchors it), e.g. `here("data", "Calidad_...csv")` and
`here("data", "geo", "col_admin.gpkg")`, so the script works whether it is run from the repo
root or sourced by Quarto with `manuscript/` as the working directory. The qmd sources it as
`source(here::here("R", "prepare.R"))`. The map chunk reads the gpkg geometry the same way.

Objects exported by `prepare.R`:
- `raw` (all-character), `wq` (clean: `dept_code, dept_name, mpio_code, mpio_name, year, level,
  irca, risk, irca_urb, risk_urb, irca_rur, risk_rur`; numeric IRCA with NA for `ND`; canonical
  5-level risk factor; `level` in {municipality, department}).
- `muni`, `dept` subsets; `years`, `year_min`, `year_max`, `n_years`.
- `names_by_code`: one canonical name per code (latest year), also handles dept 88.
- `register` (gpkg attributes, no geometry), `anm_codes` (19 hard-coded non-municipalised
  areas: 91263, 91405, 91407, 91430, 91460, 91530, 91536, 91669, 91798, 94663, 94883, 94884,
  94885, 94886, 94887, 94888, 97511, 97777, 97889; verified against the register, the other 7
  units in depts 91/94/97 are municipalities), `register_muni` = register minus ANM.
- `frame_internal` (codes seen at least once × years) and `frame_external`
  (`register_muni` × years), full grids with an `observed` logical.
- `checks`: named list of assertion outcomes.

## Import and validation steps (in `prepare.R`, in order)

1. `read_csv` with `col_types = cols(.default = col_character())`, UTF-8. Assert exact column
   names, `nrow == 19160`, `ncol == 11`, no NA and no blank cells.
2. `year = as.integer(gsub(",", "", Año))`; assert no NA, range 2000–2030.
3. `level` from `MunicipioCodigo == "#TODOS"`; assert it agrees with `Municipio == "#TODOS"`.
4. Codes: dept matches `^[0-9]{2}$`; municipal codes match `^[0-9]{5}$` and their first two
   digits equal the department code.
5. Numeric IRCA columns: assert `is.na(as.numeric(x)) == (x == "ND")` and values in [0, 100].
   Count `n_irca_nd` for the total column (report, expected 0).
6. Risk labels: map by keyword (sin/bajo/medio/alto/inviable) to a 5-level factor; assert the
   set of raw labels equals the 8 known strings; assert value and label are NA together.
   Compute label-vs-Resolution-2115-band agreement as a reported statistic.
7. Keys: assert no duplicates on (`mpio_code`, `year`) in `muni`, (`dept_code`, `year`) in
   `dept`, and (`dept_code`, `mpio_code`, `year`) overall.
8. Names: build `names_by_code`; count codes with several names and names shared by several
   codes (for the Q1 key table).
9. Register: assert 1,122 rows, unique codes, all `anm_codes` present and in depts 91/94/97;
   assert every file code is in the register (keep `codes_not_in_register` computed, with a
   comment on what to do if it is non-empty); assert no ANM code ever appears in the file.
10. Frames: `expand_grid` for both frames; assert `sum(observed) == nrow(muni)` in each.

## Manuscript structure (`index.qmd`)

YAML: title, subtitle, author (Adriana Clavijo Daza, ETH Zurich), `date: last-modified`,
abstract with qualitative or rounded figures only, keywords, `bibliography: references.bib`.

1. **Data and validation** (~0.6 page): source and IRCA definition with the Resolution 2115
   bands; import rules; the checks enforced at render time; the two reference frames
   (internal = file-implied panel; external = DANE 2020 register minus ANM, with one-sentence
   caveat that municipalities created after 2007, e.g. Barrancominas 2019, slightly overstate
   the external shortfall).
   - `tbl-columns`: Column | Role | Cleaned type | Note on import (11 rows).
   - `fig-map` (patchwork, 6.5 × 3.8 in): left, municipal IRCA in the most complete year
     classed into the 5 risk bands plus "no record" (reuse existing colours and
     `coord_sf` frame); right, number of years observed per municipality (0–18, sequential),
     ANM in a distinct "not expected" grey, never-observed municipalities outlined. Caption
     via `!expr` injecting the year.
2. `{{< pagebreak >}}` **Question 1: What is the observational unit?** (≤ 2 pages)
   - 2.1 What a row looks like. `tbl-example`: verbatim raw rows, 7 columns
     (`DepartamentoCodigo, MunicipioCodigo, Municipio, Año, IRCA, IRCAurbano, IRCArural`),
     selected in code: 76001 in two consecutive years with different names, one municipality
     with rural `ND`, and the `76 / #TODOS` row for the same year.
   - 2.2 What identifies a row. `tbl-keys`: Candidate key | Distinct combinations | Rows |
     Duplicated rows, for `MunicipioCodigo`; `Municipio + Año`; `Departamento + Municipio +
     Año`; `MunicipioCodigo + Año`; `DepartamentoCodigo + Año` on `#TODOS` rows. One helper
     `key_check(df, cols)`.
   - 2.3 Answer: unit = municipality-year, with department-year aggregates stacked in the
     same file; measurement = annual consolidation of samples with total/urban/rural values
     and derived categories; what the unit is not (sample, supply system, site, month); codes
     not names are the key.
3. `{{< pagebreak >}}` **Question 2: How complete are the data?** (≤ 2 pages). Define
   cell-level (item non-response, `ND`), unit-level (no row), year-level, panel balance.
   - 3.1 Missing values within rows: empty cells (0), `n_irca_nd`, `ND` share per component,
     urban × rural 2×2 pattern, per-municipality rural pattern (always / never /
     intermittent), `ND` vs true absence (rural `ND` rows still carry a total; share where
     total equals urban within 0.05 vs differs by > 1 point), label-band agreement.
     `fig-nd-year` (6.5 × 2.4 in): `ND` share by year, lines for urban, rural, both.
   - 3.2 Missing observational units. `tbl-frames`: rows municipality-years (internal),
     municipality-years (external), municipalities never observed (external),
     department-years; columns Expected | Observed | Missing | Share. Assert
     Expected = Observed + Missing. Prose: best and worst year, departments with zero
     missing, never-observed municipalities listed by department with register names,
     department aggregates absent exactly when no municipal row exists (count exceptions).
     `fig-heatmap` (6.5 × 3.4 in): dept × year share absent on the external denominator,
     departments ordered by overall share, y labels "Chocó (30)" style.
   - 3.3 Missing years and panel balance: calendar continuity 2007–2024, 2025 absent
     (file dated 2026-09-15, publication lag). `tbl-series`: series pattern per municipality
     (complete / late start / early end / interior gaps / combinations, 5–6 rows) with count,
     share, missing municipality-years; assert counts sum to the number of codes. Plus
     balanced sub-panel sizes for windows 2007–, 2010–, 2015–, 2019–2024 as one sentence.
   - 3.4 Answer mapped to the three sub-questions, with one sentence on implications.
4. Hidden `check-abstract` chunk asserting the rounded abstract figures lie within tolerance
   of the computed values.

DOCX rules: `fig-width`/`fig-height` per chunk, ggplot base size 8–9 pt; `knitr::kable()`
only, numbers pre-formatted as strings, ≤ 7 columns; every `fig-*`/`tbl-*` label has a caption;
inline numbers only through `fmt_n()`/`fmt_pct()`, never a vector.

## Verification

1. From the repo root, `Rscript -e 'source("R/prepare.R"); str(checks)'` exits 0.
2. Delete `manuscript/.quarto/` (gitignored cache), run `quarto render manuscript`; exit 0,
   no unresolved cross-reference or knitr warnings.
3. `pandoc manuscript/_manuscript/index.docx -t plain` and grep for `NA`, `NaN`, `Inf`,
   `NULL`, `` `r ``, `@fig`, `@tbl`, `!expr`, `??`, `TRUE`, `FALSE` in prose; any hit is a bug.
4. Reconciliation assertions in code (frames, series counts, heatmap denominators,
   abstract tolerance) all pass.
5. Word count per question section ≤ ~700 via `pandoc -t plain | wc -w`; confirm each
   question fits ~2 pages (convert with `soffice --headless --convert-to pdf` if available,
   otherwise inspect the docx); trim figure heights first, prose second.
6. View the figure PNGs under `manuscript/.quarto/_freeze/index/figure-docx/` for
   legibility, legend fit, and visibly distinct ANM on the map.
7. `git status` shows only `R/prepare.R`, `manuscript/index.qmd`, `manuscript/_quarto.yml`,
   `manuscript/references.bib`, `manuscript/_manuscript/index.docx`. No commit unless the
   user asks.
