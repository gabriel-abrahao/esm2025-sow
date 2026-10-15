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

# Harmonized (and infilled) emissions gathered from the REMIND runs, input to MAGICC
# MAGICC repo: data/raw/scenarios-<SVERSION>/emissions_climate_output_<ensemble>_<SVERSION>.csv
harmonized_emissions_path <- function(sversion = SVERSION, ensemble = ENSEMBLE, dir = RAW_DATA_DIR) {
  in_name <- paste0("emissions_climate_output_", ensemble, "_", sversion, ".csv")
  file.path(dir, paste0("scenarios-", sversion), in_name)
}

# MAGICC output (climate output)
# MAGICC repo: data/processed/scenarios-<SVERSION>/magicc-output_<name of the harmonized emissions file>.csv
# (the doubled .csv.csv in the file name is as written by the MAGICC repo)
climate_output_path <- function(sversion = SVERSION, ensemble = ENSEMBLE, dir = PROCESSED_DATA_DIR) {
  in_name <- basename(harmonized_emissions_path(sversion, ensemble))
  file.path(dir, paste0("scenarios-", sversion), paste0("magicc-output_", in_name, ".csv"))
}

# Selected ensemble members and their weights (0004_select-ensemble-members.py)
# MAGICC repo: data/processed/<id>/<id>_selected-ensemble-member-weights.csv
selected_members_weights_path <- function(id = SELECT_ENSEMBLE_MEMBERS_ID, dir = PROCESSED_DATA_DIR) {
  file.path(dir, id, paste0(id, "_selected-ensemble-member-weights.csv"))
}

# Metrics used for the selection (0010_calculate-metrics.py)
# MAGICC repo: data/processed/<id>/<id>_metrics.csv
metrics_path <- function(id = CALCULATE_METRICS_ID, dir = PROCESSED_DATA_DIR) {
  file.path(dir, id, paste0(id, "_metrics.csv"))
}

# MAGICC output restricted to the selected ensemble members (core SOWs). Derived here from the
# full climate output with the weights file, so it lives in this repository, not in the MAGICC repo
# data/scenarios-<SVERSION>/magicc-output_emissions_climate_output_coresows_<SVERSION>_<id>.csv
# <id> is the ensemble member selection ID, the prefix of the weights file
climate_output_coresows_path <- function(sversion = SVERSION, id = SELECT_ENSEMBLE_MEMBERS_ID, dir = LOCAL_DATA_DIR) {
  fname <- paste0("magicc-output_emissions_climate_output_coresows_", sversion, "_", id, ".csv")
  file.path(dir, fname)
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
