# Builds data/geo/col_admin.gpkg: simplified municipal and departmental
# boundaries of Colombia with DANE codes, used for the maps in manuscript/.
#
# Source: Colombia administrative boundaries (COD-AB), DANE Marco
# Geoestadístico Nacional 2020, distributed by the Humanitarian Data Exchange:
# https://data.humdata.org/dataset/cod-ab-col (geodatabase resource, ~60 MB).
# P-codes are "CO" followed by the DANE code, e.g. CO05001 = Medellín.
#
# Run from the repository root: Rscript data/geo/prepare_boundaries.R

library(sf)
library(dplyr)

url <- paste0("https://data.humdata.org/dataset/50ea7fee-f9af-45a7-8a52-abb9c790a0b6/",
              "resource/da4a3090-43d7-4f0b-8b51-2de9718f69c4/download/",
              "col-administrative-divisions-geodatabase.zip")
tmp <- tempfile(fileext = ".zip")
download.file(url, tmp, mode = "wb")
exdir <- tempfile()
unzip(tmp, exdir = exdir)
gdb <- list.files(exdir, pattern = "\\.gdb$", full.names = TRUE, include.dirs = TRUE)[1]

a2 <- st_read(gdb, layer = "col_admbnda_adm2_mgn_20200416", quiet = TRUE) |>
  mutate(mpio_code = sub("^CO", "", admin2Pcode),
         dept_code = sub("^CO", "", admin1Pcode)) |>
  select(mpio_code, dept_code, mpio_name = admin2Name_es, dept_name = admin1Name_es) |>
  st_simplify(dTolerance = 500)

a1 <- st_read(gdb, layer = "col_admbnda_adm1_mgn_20200416", quiet = TRUE) |>
  mutate(dept_code = sub("^CO", "", admin1Pcode)) |>
  select(dept_code, dept_name = admin1Name_es) |>
  st_simplify(dTolerance = 500)

stopifnot(all(st_is_valid(a2)), all(st_is_valid(a1)))
out <- "data/geo/col_admin.gpkg"
unlink(out)
st_write(a2, out, layer = "municipalities", quiet = TRUE)
st_write(a1, out, layer = "departments", quiet = TRUE, append = TRUE)
