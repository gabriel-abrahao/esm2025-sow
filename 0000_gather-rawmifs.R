# Step 0000 of the pipeline: gather the raw REMIND reporting files (.mif)
#
# Copies the .mif of the selected REMIND runs from REMIND_OUTPUT_DIR (read-only here,
# nothing is ever written there) to RAWMIFS_DIR, i.e.
#   data/scenarios-<SVERSION>/rawmifs/
# Both folders are defined in common.R and refer to the SVERSION set there.
#
# Selected runs: all the carbon budget scenarios C_E25t3v06-SSP2-PbXXXX
# (XXXX = budget in GtCO2) plus the reference C_E25t3v06-SSP2-NPi2025.
# The "-D-" variants and test runs in the REMIND folder are NOT included.

source("common.R")

# Hardcoded list of runs ----
# Budgets in GtCO2: 500 to 1000 in steps of 20, then 1100 to 2500 in steps of 100
budgets <- c(seq(500, 1000, by = 20), seq(1100, 2500, by = 100))

# Run names, e.g. C_E25t3v06-SSP2-Pb0520. Budgets are zero padded to 4 digits
runs <- c(
    paste0(REMIND_RUNS_PREFIX, "Pb", sprintf("%04d", budgets)),
    paste0(REMIND_RUNS_PREFIX, "NPi2025")
)

# Check the source files ----
srcfiles <- sapply(runs, remind_mif_path)
missing <- srcfiles[!file.exists(srcfiles)]
if (length(missing) > 0) {
    stop("These .mif files do not exist in ", REMIND_OUTPUT_DIR, ":\n",
        paste(basename(missing), collapse = "\n"))
}

# Copy ----
dir.create(RAWMIFS_DIR, recursive = TRUE, showWarnings = FALSE)

# overwrite = TRUE so a rerun refreshes the files. copy.date keeps the REMIND modification dates
ok <- file.copy(srcfiles, RAWMIFS_DIR, overwrite = TRUE, copy.date = TRUE)
if (!all(ok)) {
    stop("Failed to copy:\n", paste(basename(srcfiles[!ok]), collapse = "\n"))
}

cat("Copied", sum(ok), "mif files\n  from", REMIND_OUTPUT_DIR, "\n  to  ", RAWMIFS_DIR, "\n")

# Read and concatenate ----
require(quitte)
require(parallel)

# Number of parallel workers: the CPUs given by SLURM, or 1 if not running in SLURM
ncores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "1"))
cat("Reading", length(runs), "mif files with", ncores, "cores\n")

# Each file is read independently of the others, so we can just hand one file to each
# worker (mclapply forks the R session, one file per worker at a time) and bind the results.
# mc.preschedule = FALSE: a new worker per file, so the workers stay balanced even if
# some files are much larger than others
mifs <- list.files(RAWMIFS_DIR, pattern = "\\.mif$", full.names = TRUE)
dflist <- mclapply(mifs, read.quitte, mc.cores = ncores, mc.preschedule = FALSE)

# mclapply does not stop on errors in a worker, it returns a "try-error" instead. Check them
failed <- sapply(dflist, function(x) inherits(x, "try-error"))
if (any(failed)) {
    stop("Failed to read:\n", paste(basename(mifs[failed]), collapse = "\n"))
}

allmifs <- bind_rows(dflist)
rm(dflist)

# Sanity check: every run must be in the final data frame
if (!setequal(as.character(unique(allmifs$scenario)), runs)) {
    stop("The scenarios in the concatenated data do not match the list of runs")
}
cat("Concatenated data:", nrow(allmifs), "rows,",
    n_distinct(allmifs$scenario), "scenarios,",
    n_distinct(allmifs$variable), "variables\n")

# Write, beside the rawmifs folder ----
# rds keeps the quitte data frame as is, and is much faster to read back
saveRDS(allmifs, allmifs_path("rds"))
# write.mif writes the quitte data frame back as a mif (wide in the periods)
write.mif(allmifs, allmifs_path("mif"))
cat("Wrote\n ", allmifs_path("rds"), "\n ", allmifs_path("mif"), "\n")
