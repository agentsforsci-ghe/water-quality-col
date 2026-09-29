# Import, clean and validate the Colombian drinking-water quality file, and build
# the reference frames used to assess completeness. Sourced by manuscript/index.qmd
# and runnable on its own from the repository root: Rscript R/prepare.R
#
# Every structural assumption the manuscript relies on is asserted here with
# stopifnot(), so a change in the data file breaks the render instead of the prose.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(stringr)
  library(here)
})

# Formatting helpers ---------------------------------------------------------

fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE)
fmt_pct <- function(x, acc = 1) scales::percent(x, accuracy = acc)

# Column names and constants -------------------------------------------------

data_file <- here("data", "Calidad_del_Agua_para_Consumo_Humano_en_Colombia_20260915.csv")
gpkg_file <- here("data", "geo", "col_admin.gpkg")

expected_cols <- c(
  "DepartamentoCodigo", "Departamento", "MunicipioCodigo", "Municipio", "Año",
  "IRCA", "Nivel de riesgo", "IRCAurbano", "Nivel de riesgo urbano",
  "IRCArural", "Nivel de riesgo rural"
)

# Raw spellings of the risk categories found in the file
known_labels <- c(
  "Sin riesgo", "Bajo riesgo", "Riesgo bajo", "Riesgo medio",
  "Alto riesgo", "Riesgo alto", "Inviable sanitariamente", "ND"
)

# Resolution 2115 of 2007 risk bands
risk_levels <- c("No risk", "Low risk", "Medium risk", "High risk", "Sanitarily unviable")
risk_breaks <- c(-Inf, 5, 14, 35, 80, Inf)

# Non-municipalised areas (áreas no municipalizadas, corregimientos departamentales)
# in the DANE MGN 2020 register. They belong to Amazonas (91), Guainía (94) and
# Vaupés (97), have no municipal administration and are not expected in the file.
anm_codes <- c(
  "91263", "91405", "91407", "91430", "91460", "91530", "91536", "91669", "91798",
  "94663", "94883", "94884", "94885", "94886", "94887", "94888",
  "97511", "97777", "97889"
)

checks <- list()
check <- function(name, cond) {
  ok <- isTRUE(all(cond))
  checks[[name]] <<- ok
  if (!ok) stop("Validation check failed: ", name, call. = FALSE)
  invisible(ok)
}

# 1. Read ----------------------------------------------------------------------

raw <- read_csv(
  data_file,
  col_types = cols(.default = col_character()),
  locale = locale(encoding = "UTF-8"),
  progress = FALSE
)

check("column names as documented", identical(names(raw), expected_cols))
check("file has 19,160 rows and 11 columns", nrow(raw) == 19160L && ncol(raw) == 11L)
n_empty <- sum(vapply(raw, function(x) sum(is.na(x) | trimws(x) == ""), integer(1)))
check("no empty cells", n_empty == 0L)

# 2. Year ----------------------------------------------------------------------

year <- as.integer(gsub(",", "", raw$Año, fixed = TRUE))
check("year parses as integer", !anyNA(year) && all(year >= 2000L & year <= 2030L))

# 3. Level ---------------------------------------------------------------------

is_dept <- raw$MunicipioCodigo == "#TODOS"
check("#TODOS appears in code and name together", all(is_dept == (raw$Municipio == "#TODOS")))

# 4. Codes ---------------------------------------------------------------------

check("department codes are two digits", all(grepl("^[0-9]{2}$", raw$DepartamentoCodigo)))
check("municipality codes are five digits",
      all(grepl("^[0-9]{5}$", raw$MunicipioCodigo[!is_dept])))
check("municipality code starts with department code",
      all(substr(raw$MunicipioCodigo[!is_dept], 1, 2) == raw$DepartamentoCodigo[!is_dept]))

# 5. Numeric IRCA --------------------------------------------------------------

to_num <- function(x) suppressWarnings(as.numeric(x))
for (v in c("IRCA", "IRCAurbano", "IRCArural")) {
  num <- to_num(raw[[v]])
  check(paste0(v, ": only ND is non-numeric"), all(is.na(num) == (raw[[v]] == "ND")))
  check(paste0(v, ": values within 0-100"), all(num >= 0 & num <= 100, na.rm = TRUE))
}
n_irca_nd <- sum(raw$IRCA == "ND")

# 6. Risk labels ---------------------------------------------------------------

label_cols <- c("Nivel de riesgo", "Nivel de riesgo urbano", "Nivel de riesgo rural")
check("risk labels take only the eight known spellings",
      setequal(unique(unlist(raw[label_cols])), known_labels))

canon_risk <- function(x) {
  lx <- tolower(x)
  out <- case_when(
    str_detect(lx, "sin") ~ risk_levels[1],
    str_detect(lx, "bajo") ~ risk_levels[2],
    str_detect(lx, "medio") ~ risk_levels[3],
    str_detect(lx, "alto") ~ risk_levels[4],
    str_detect(lx, "inviable") ~ risk_levels[5],
    TRUE ~ NA_character_
  )
  factor(out, levels = risk_levels)
}

wq <- tibble(
  dept_code = raw$DepartamentoCodigo,
  dept_name_raw = raw$Departamento,
  mpio_code = raw$MunicipioCodigo,
  mpio_name_raw = raw$Municipio,
  year = year,
  level = if_else(is_dept, "department", "municipality"),
  irca = to_num(raw$IRCA),
  risk = canon_risk(raw$`Nivel de riesgo`),
  irca_urb = to_num(raw$IRCAurbano),
  risk_urb = canon_risk(raw$`Nivel de riesgo urbano`),
  irca_rur = to_num(raw$IRCArural),
  risk_rur = canon_risk(raw$`Nivel de riesgo rural`)
)

check("value and label missing together", with(wq,
  all(is.na(irca) == is.na(risk)) &&
  all(is.na(irca_urb) == is.na(risk_urb)) &&
  all(is.na(irca_rur) == is.na(risk_rur))))

# Agreement between the reported label and the Resolution 2115 band of the value
band_of <- function(x) cut(x, risk_breaks, labels = risk_levels, right = TRUE)
label_agreement <- bind_rows(
  tibble(component = "total", value = wq$irca, label = wq$risk),
  tibble(component = "urban", value = wq$irca_urb, label = wq$risk_urb),
  tibble(component = "rural", value = wq$irca_rur, label = wq$risk_rur)
) |>
  filter(!is.na(value)) |>
  mutate(agree = as.character(band_of(value)) == as.character(label)) |>
  summarise(n = n(), n_disagree = sum(!agree), share_agree = mean(agree))

# 7. Keys ----------------------------------------------------------------------

muni <- filter(wq, level == "municipality")
dept <- filter(wq, level == "department")

check("municipality code + year is unique", !any(duplicated(muni[c("mpio_code", "year")])))
check("department code + year is unique among aggregates",
      !any(duplicated(dept[c("dept_code", "year")])))
check("department + municipality + year is unique overall",
      !any(duplicated(wq[c("dept_code", "mpio_code", "year")])))

years <- sort(unique(wq$year))
year_min <- min(years)
year_max <- max(years)
n_years <- length(years)
n_muni_codes <- n_distinct(muni$mpio_code)
n_dept_codes <- n_distinct(wq$dept_code)

# 8. Names ---------------------------------------------------------------------

names_by_code <- muni |>
  group_by(mpio_code) |>
  summarise(mpio_name = mpio_name_raw[which.max(year)],
            n_names = n_distinct(mpio_name_raw), .groups = "drop")
check("one canonical name per municipality code",
      n_distinct(names_by_code$mpio_code) == nrow(names_by_code))

dept_names <- wq |>
  group_by(dept_code) |>
  summarise(dept_name = dept_name_raw[which.max(year)],
            n_names = n_distinct(dept_name_raw), .groups = "drop")

n_codes_multi_name <- sum(names_by_code$n_names > 1)
n_names_multi_code <- muni |>
  distinct(mpio_code, mpio_name_raw) |>
  count(mpio_name_raw) |>
  filter(n > 1) |>
  nrow()

wq <- wq |>
  left_join(select(dept_names, dept_code, dept_name), by = "dept_code") |>
  left_join(select(names_by_code, mpio_code, mpio_name), by = "mpio_code") |>
  mutate(mpio_name = if_else(level == "department", "#TODOS", mpio_name)) |>
  select(dept_code, dept_name, mpio_code, mpio_name, year, level,
         irca, risk, irca_urb, risk_urb, irca_rur, risk_rur)
muni <- filter(wq, level == "municipality")
dept <- filter(wq, level == "department")

# 9. Register (DANE MGN 2020) --------------------------------------------------

register <- sf::st_read(gpkg_file, layer = "municipalities", quiet = TRUE) |>
  sf::st_drop_geometry() |>
  as_tibble()

check("register has 1,122 units with unique codes",
      nrow(register) == 1122L && !any(duplicated(register$mpio_code)))
check("all non-municipalised areas are in the register",
      all(anm_codes %in% register$mpio_code))
check("non-municipalised areas belong to Amazonas, Guainía or Vaupés",
      all(substr(anm_codes, 1, 2) %in% c("91", "94", "97")))

# If a code in the file is ever absent from the register, list it here and treat
# it as an orphan in the manuscript rather than silently dropping it.
codes_not_in_register <- setdiff(unique(muni$mpio_code), register$mpio_code)
check("every municipality code in the file exists in the register",
      length(codes_not_in_register) == 0)
check("no non-municipalised area appears in the file",
      !any(anm_codes %in% muni$mpio_code))

register_muni <- filter(register, !mpio_code %in% anm_codes)
n_register_muni <- nrow(register_muni)

# 10. Reference frames ---------------------------------------------------------

observed_my <- muni |> transmute(mpio_code, year, observed = TRUE)

frame_internal <- expand_grid(mpio_code = sort(unique(muni$mpio_code)), year = years) |>
  left_join(observed_my, by = c("mpio_code", "year")) |>
  mutate(observed = !is.na(observed), dept_code = substr(mpio_code, 1, 2))

frame_external <- expand_grid(mpio_code = sort(register_muni$mpio_code), year = years) |>
  left_join(observed_my, by = c("mpio_code", "year")) |>
  mutate(observed = !is.na(observed), dept_code = substr(mpio_code, 1, 2))

check("internal frame reproduces the municipal rows", sum(frame_internal$observed) == nrow(muni))
check("external frame reproduces the municipal rows", sum(frame_external$observed) == nrow(muni))

rm(observed_my, year, is_dept, v, num)
