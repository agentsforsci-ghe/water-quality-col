# CLAUDE.md

Guidance for working in this repository. It answers the questions in `questions.md`
about Colombia's drinking-water quality data (the IRCA index by municipality and
year) with a Quarto manuscript that renders to DOCX and HTML.

## Folder template

```
.
├── CLAUDE.md                  this file
├── PLAN.md                    the plan for the work in progress (see Workflow)
├── questions.md               the research questions being answered
├── README.md
├── data/
│   ├── Calidad_del_Agua_..._20260915.csv   raw file from datos.gov.co, never edited
│   ├── geo/
│   │   ├── col_admin.gpkg     DANE MGN 2020 boundaries (layers: municipalities,
│   │   │                      departments), simplified, WGS 84
│   │   └── prepare_boundaries.R   rebuilds col_admin.gpkg from HDX
│   └── metadata/
│       └── codebook.csv       codebook of the derived table `wq` (see below)
├── R/
│   └── prepare.R              import, cleaning, validation, reference frames
├── manuscript/                Quarto manuscript project
│   ├── _quarto.yml            formats: html (self-contained) and docx
│   ├── index.qmd              the article
│   ├── references.bib
│   └── _manuscript/           rendered outputs; index.docx and index.html are
│                              tracked, everything else there is gitignored
└── prompts/                   archive of the prompts behind Claude-assisted commits
```

Rules that follow from the template:

- R scripts live in `R/` at the repository root, never inside `manuscript/`.
- The raw CSV in `data/` is read-only. Anything derived is computed at render
  time by `R/prepare.R`; nothing derived is written back to `data/`.
- `data/geo/col_admin.gpkg` is a build artefact of `prepare_boundaries.R`; rerun
  that script rather than editing the file.
- Only `index.docx` and `index.html` are committed from `_manuscript/`. Quarto's
  side files there (`site_libs/`, `index_files/`, previews, notebooks,
  `search.json`) are gitignored.

## Naming rules

- **Prompt archives:** `prompts/YYYY-MM-DD-NNN-slug.md`, `NNN` zero-padded and
  sequential per day, slug from the first words of the prompt in kebab-case.
  Front matter carries `id`, `timestamp`, `model` and `files_touched`. The
  `ghe-skills:commit` skill writes these.
- **Commits:** Conventional Commits (`feat`, `fix`, `docs`, `chore`, ...) with the
  scope `manuscript` for the article and its outputs. Claude-assisted commits end
  with `Prompts:` (archive ids) and `Assisted-by: Claude <model-id>`; human-only
  commits carry `Human-authored: true`. Issues are referenced with `Refs #n`.
- **Branches:** work happens on `dev`; pull requests always go from `dev` into
  `main` and are merged with a merge commit. `dev` is never deleted.
- **Chunk labels in `index.qmd`:** `fig-*` and `tbl-*` only for exhibits that are
  cross-referenced and carry their caption in chunk options. Exhibits that exist
  in a format-conditional block use a plain label (`map-static`, `map-html`,
  `columns-kable`, `columns-reactable`) inside a `::: {#fig-...}` or
  `::: {#tbl-...}` div whose last paragraph is the caption. Labels are unique
  across the file. Data-only chunks use `include: false` and a noun label
  (`map-data`, `columns-data`).
- **Objects in `R/prepare.R`:** snake_case; `dept_` and `mpio_` prefixes for
  department and municipality fields; `n_` for counts, `pct_` for shares;
  `frame_internal` and `frame_external` for the two reference panels.
- **Style:** lines of at most 80 characters in `index.qmd`; comments only where
  they explain a decision; numbers in prose always through `fmt_n()` or
  `fmt_pct()`; section titles describe content, not the question asked.

## The codebook

`data/metadata/codebook.csv` documents the derived table `wq` built by
`R/prepare.R`: one row per department-year or municipality-year, with the
cleaned identifiers, the three IRCA values and their risk bands. Update it
whenever a column of `wq` is added, renamed or recoded. Columns of the codebook:
`variable`, `type`, `description`, `values`, `missing`, `source_column`,
`derivation`.

Quirks of the raw file that the derivation handles, so they are not rediscovered:
the year is text with a thousands separator ("2,024"); `MunicipioCodigo ==
"#TODOS"` marks department aggregate rows; missing urban or rural values are the
string `ND`; risk labels have two spellings per band; names are not stable across
years (76001 is "Cali" and "Santiago de Cali"), so codes, not names, are keys.

## How to render the manuscript

```
Rscript -e 'source("R/prepare.R")'   # data checks alone; must print no error
quarto render manuscript             # both formats, always together
```

- Always render both formats with one command. `quarto render manuscript --to html`
  cleans the DOCX out of `_manuscript/` (and vice versa); if that happens,
  restore it with `git checkout -- manuscript/_manuscript/index.docx`.
- Close Microsoft Word first. A `~$index.docx` lock file in `_manuscript/` means
  the DOCX is open.
- `R/prepare.R` asserts the structure of the raw file with `stopifnot()`. A
  failing check is the intended way to learn that the data changed; fix the
  script, not the check.
- `index.qmd` pins the repository root with `here::i_am("manuscript/index.qmd")`
  because `_quarto.yml` makes `manuscript/` look like a project root to `here()`.
- Packages: those loaded by `prepare.R` (dplyr, readr, tidyr, stringr, here, sf),
  plus ggplot2, scales, knitr and patchwork for both formats, and leaflet,
  reactable and htmltools for HTML. There is no renv; install from CRAN.
- The HTML basemap is Esri World Gray Canvas. CARTO tiles need an API key and
  show "API KEY REQUIRED" placeholders; do not switch back to them.
- Format-conditional chunks are guarded with
  `eval: !expr isFALSE(knitr::is_html_output())` or `knitr::is_html_output()`.
  Do not write `!expr !knitr::...`; the second `!` breaks Quarto's YAML parser.

Checks after a render (all must hold before committing outputs):

- `grep -c '?@' ` on `pandoc -t plain` of the DOCX and on `index.html` finds no
  `?@fig` or `?@tbl`.
- The DOCX plain text has no `NA`, `NaN`, backtick-r code or `TODO:`; the
  string `#TODOS` is a data token and is expected.
- `index.html` has no external `<script src>` or `<link href>` and stays under
  5 MB.
- `git status` shows only the source files and the two tracked outputs.

## Workflow

1. Plan first. Write the plan to `PLAN.md` at the repository root before
   implementing; larger plans are split into GitHub issues, each with a title, at
   most five "done when" checkboxes and the files it touches.
2. Implement, render, run the checks above.
3. Commit with the `ghe-skills:commit` skill. Push is done by the user, never by
   Claude.
4. Open the pull request with the `ghe-skills:open-pr` skill (`dev` into
   `main`), run its test plan, tick what passed, leave visual items for the
   author, and merge only when asked.
