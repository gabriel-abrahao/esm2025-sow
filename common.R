# Common configuration, to be sourced by all R scripts in this repository:
#   source("common.R")   # or source(file.path(<repo root>, "common.R"))
#
# This repository ANALYZES the outputs of the MAGICC runs done in
# esm2025-states-of-world-selection (the "MAGICC repo"), which itself starts from
# REMIND runs. The data layout and versioning mirror notebooks/utils.py and
# notebooks/0200_run-scenarios-t133.py there. See DATA_ORGANIZATION.md.

# %%
library(tidyverse)

# Repository paths ----
# Directory of this file, whether it was source()d or the script is run from the repo root
.common_find_root <- function() {
  ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(ofile)) return(normalizePath(dirname(ofile)))
  normalizePath(getwd())
}

REPO_ROOT_DIR <- .common_find_root()

# The MAGICC repo, whose data/ folder holds the harmonized emissions, the MAGICC output
# and the ensemble member selection. Read-only from here.
MAGICC_REPO_DIR <- "/p/projects/piam/abrahao/esm2025/esm2025-states-of-world-selection"
RAW_DATA_DIR <- file.path(MAGICC_REPO_DIR, "data", "raw")
INTERIM_DATA_DIR <- file.path(MAGICC_REPO_DIR, "data", "interim")
PROCESSED_DATA_DIR <- file.path(MAGICC_REPO_DIR, "data", "processed")

# Version IDs ----
# SVERSION identifies one set of REMIND runs, and everything derived from it.
# Same value as SVERSION in notebooks/0200_run-scenarios-t133.py of the MAGICC repo.
SVERSION <- "t133v6p0"

# Same IDs as in notebooks/utils.py of the MAGICC repo
EXTRACTION_ID <- "20250901-message-offline_0003_0003_0002"
CALCULATE_METRICS_ID <- "0001"
SELECT_ENSEMBLE_MEMBERS_ID <- "0001"

# Climate output ensemble, as in the MAGICC repo file names
ENSEMBLE <- "fullar6"

# REMIND raw output ----
# Folder holding the REMIND run folders and .mif files. Specific to the REMIND
# batch that SVERSION refers to.
REMIND_OUTPUT_DIR <- "/p/projects/piam/abrahao/esm2025/task133/pilot_v06/remind/output"
REMIND_RUNS_PREFIX <- "C_E25t3v06-SSP2-"
REMIND_RUNS_SUFFIX <- "-rem-5"

# Data of this repository ----
# Hand-made or REMIND-derived inputs that do not come from the MAGICC repo
# (runcode labels, welfare), versioned by SVERSION
LOCAL_DATA_DIR <- file.path(REPO_ROOT_DIR, "data", paste0("scenarios-", SVERSION))
# Raw REMIND reporting files (.mif) copied from REMIND_OUTPUT_DIR by 0000_gather-rawmifs.R
RAWMIFS_DIR <- file.path(LOCAL_DATA_DIR, "rawmifs")
# All the raw .mif files concatenated in one file (extension "mif" or "rds"), beside the rawmifs folder
allmifs_path <- function(ext = "mif", sversion = SVERSION, dir = LOCAL_DATA_DIR) {
  file.path(dir, paste0("rawmifs_all_", sversion, ".", ext))
}
# ScenarioMIP-formatted submission (extension "xlsx", "mif" or "rds") made by 0001_apply_scenariomip_mapping.R
scenariomip_path <- function(ext = "mif", sversion = SVERSION, dir = LOCAL_DATA_DIR) {
  file.path(dir, paste0("scenariomip_", sversion, ".", ext))
}
# Folder with the per-scenario batches of that script (one rds, log and summation check per scenario)
SCENARIOMIP_BATCH_DIR <- file.path(LOCAL_DATA_DIR, "scenariomip_batches")
# MAGICC parametrizations. The full ensemble json and, in a subfolder per SELECT_ENSEMBLE_MEMBERS_ID,
# the files of the selected ensemble members (copied from the MAGICC repo) and the json with just them
PARAMETRIZATIONS_DIR <- file.path(REPO_ROOT_DIR, "parametrizations")
# Tables, figures and caches produced by the analysis scripts
RESULTS_DIR <- file.path(REPO_ROOT_DIR, "results", paste0("scenarios-", SVERSION))
TABLES_DIR <- file.path(RESULTS_DIR, "tables")
FIGURES_DIR <- file.path(RESULTS_DIR, "figures")
CACHE_DIR <- file.path(RESULTS_DIR, "cache")

# Path helpers ----
# REMIND raw: <REMIND_OUTPUT_DIR>/<run>/ and <run>.mif
remind_run_dir <- function(run, dir = REMIND_OUTPUT_DIR) file.path(dir, run)
remind_mif_path <- function(run, dir = REMIND_OUTPUT_DIR) file.path(dir, paste0(run, ".mif"))
remind_run_dirs <- function(dir = REMIND_OUTPUT_DIR, prefix = REMIND_RUNS_PREFIX, suffix = REMIND_RUNS_SUFFIX) {
  Sys.glob(file.path(dir, paste0(prefix, "*", suffix)))
}

# Harmonized (and infilled) emissions of the REMIND runs, input to MAGICC: the emissions extended to
# 2250 that 0004_run_magicc_raw_v4.py writes (see emissions_extended_path), with the SCI (gcages)
# harmonization of 0002_harmonize_emissions.py and its variable names. It replaces the file of the MAGICC repo,
# data/raw/scenarios-<SVERSION>/emissions_climate_output_<ensemble>_<SVERSION>.csv
harmonized_emissions_path <- function(sversion = SVERSION, dir = LOCAL_DATA_DIR) {
  emissions_extended_path(sversion, dir)
}

# MAGICC output (climate output) of this repository, made by 0004_run_magicc_raw_v4.py
# data/scenarios-<SVERSION>/climate_output_<ensemble>_<SVERSION>.csv, with <ensemble> = "fullar6" (the 600
# member ensemble, the default ENSEMBLE) or "coresows" (just the selected SoW members). It replaces the
# output of the MAGICC repo (data/processed/scenarios-<SVERSION>/magicc-output_..._<SVERSION>.csv.csv)
# The file name template is a plain string so the Python script can read it from here too
# ({SVERSION} and {PARMODE} are replaced). This is the only place where the name is defined
CLIMATE_OUTPUT_FNAME <- "climate_output_{PARMODE}_{SVERSION}.csv"
climate_output_path <- function(sversion = SVERSION, ensemble = ENSEMBLE, dir = LOCAL_DATA_DIR) {
  fname <- sub("{SVERSION}", sversion, CLIMATE_OUTPUT_FNAME, fixed = TRUE)
  fname <- sub("{PARMODE}", ensemble, fname, fixed = TRUE)
  file.path(dir, fname)
}

# Selected ensemble members and their weights (0004_select-ensemble-members.py of the MAGICC repo)
# parametrizations/<id>/<id>_selected-ensemble-member-weights.csv, copied from data/processed/<id>/ of the MAGICC repo
# The file name template is a plain string so 0003_select_parsets.py can read it from here too
# ({ID} is replaced by the selection ID). This is the only place where the name is defined
SELECTED_MEMBERS_WEIGHTS_FNAME <- "{ID}_selected-ensemble-member-weights.csv"
selected_members_weights_path <- function(id = SELECT_ENSEMBLE_MEMBERS_ID, dir = PARAMETRIZATIONS_DIR) {
  file.path(dir, id, sub("{ID}", id, SELECTED_MEMBERS_WEIGHTS_FNAME, fixed = TRUE))
}

# Full MAGICC ensemble (600 parametrizations, json): the AR7 fast track drawn set that comes with gcages
# (MAGICC v7.6.0a3), copied to parametrizations/. Plain string so the Python scripts can read it from here too
FULLENSEMBLE_PARSETS_FNAME <- "magicc-ar7-fast-track-drawnset-v0-3-0.json"
fullensemble_parsets_path <- function(dir = PARAMETRIZATIONS_DIR) {
  file.path(dir, FULLENSEMBLE_PARSETS_FNAME)
}

# MAGICC parametrizations (json) of just the selected ensemble members, made by 0003_select_parsets.py
# and read by 0004_run_magicc_raw_v4.py for the coresows. Same template idea as above
CORESOWS_PARSETS_FNAME <- "{ID}_coresows_parsets.json"
coresows_parsets_path <- function(id = SELECT_ENSEMBLE_MEMBERS_ID, dir = PARAMETRIZATIONS_DIR) {
  file.path(dir, id, sub("{ID}", id, CORESOWS_PARSETS_FNAME, fixed = TRUE))
}

# Metrics used for the selection (0010_calculate-metrics.py)
# MAGICC repo: data/processed/<id>/<id>_metrics.csv
metrics_path <- function(id = CALCULATE_METRICS_ID, dir = PROCESSED_DATA_DIR) {
  file.path(dir, id, paste0(id, "_metrics.csv"))
}

# MAGICC output of just the selected ensemble members (core SOWs): the "coresows" output of
# 0004_run_magicc_raw_v4.py (--parmode coresows), run with the parametrizations of 0003_select_parsets.py
# (the members of the weights file of the selection). Before, it was the full climate output filtered by
# the weights file (data/scenarios-<SVERSION>/magicc-output_emissions_climate_output_coresows_<SVERSION>_<id>.csv)
climate_output_coresows_path <- function(sversion = SVERSION, dir = LOCAL_DATA_DIR) {
  climate_output_path(sversion = sversion, ensemble = "coresows", dir = dir)
}

# Emissions extended to 2250 (the input of MAGICC), written by 0003_run_magicc_raw_v4.py
# data/scenarios-<SVERSION>/emissions_extended_<SVERSION>.csv
# The file name template is a plain string so the Python script can read it from here too
# ({SVERSION} is replaced by the version). This is the only place where the name is defined
EMISSIONS_EXTENDED_FNAME <- "emissions_extended_{SVERSION}.csv"
emissions_extended_path <- function(sversion = SVERSION, dir = LOCAL_DATA_DIR) {
  file.path(dir, sub("{SVERSION}", sversion, EMISSIONS_EXTENDED_FNAME, fixed = TRUE))
}

# Inputs of this repository
runcode_path <- function(name, sversion = SVERSION, dir = LOCAL_DATA_DIR) {
  file.path(dir, paste0("runcode_", name, "_", sversion, ".csv"))
}
welfare_path <- function(sversion = SVERSION, dir = LOCAL_DATA_DIR) {
  file.path(dir, paste0("welfare_", sversion, ".csv"))
}

# Outputs of this repository: file names carry SVERSION
table_path <- function(name, ext = "csv", sversion = SVERSION, dir = TABLES_DIR) {
  file.path(dir, paste0(name, "_", sversion, ".", ext))
}
figure_path <- function(name, ext = "png", sversion = SVERSION, dir = FIGURES_DIR) {
  file.path(dir, paste0(name, "_", sversion, ".", ext))
}
cache_path <- function(name, ext = "rds", sversion = SVERSION, dir = CACHE_DIR) {
  file.path(dir, paste0(name, "_", sversion, ".", ext))
}

# Create the output directories of this repository if needed. Never touches the MAGICC repo.
ensure_results_dirs <- function() {
  for (d in c(LOCAL_DATA_DIR, TABLES_DIR, FIGURES_DIR, CACHE_DIR)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(NULL)
}
