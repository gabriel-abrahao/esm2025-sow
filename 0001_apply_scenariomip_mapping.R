# Step 0001 of the pipeline: apply the ScenarioMIP mapping to the REMIND mifs
#
# Takes the concatenated raw mifs of step 0000 (rawmifs_all_<SVERSION>.rds) and runs
# piamInterfaces::generateIIASASubmission with the ScenarioMIP mapping ONLY (no other
# mapping is applied), which renames/converts the variables and units to the ScenarioMIP
# standard, interpolates to annual timesteps and runs the ScenarioMIP summation checks.
# The result is written as xlsx, mif and rds, in data/scenarios-<SVERSION>/ (see common.R).
#
# generateIIASASubmission is slow (about 5 min per scenario) and memory hungry, so the
# scenarios are processed in batches of one scenario each, in parallel. The result of each
# batch (rds, log, summation check) is kept in SCENARIOMIP_BATCH_DIR, so a failed run
# does not need to redo the batches that are done.

source("common.R")
require(quitte)
require(piamInterfaces)
require(parallel)

# TRUE: redo all the batches. FALSE: reuse the batches already saved in SCENARIOMIP_BATCH_DIR
REDO_BATCHES <- FALSE

# Read and split ----
allmifs <- readRDS(allmifs_path("rds"))
# One quitte data frame per scenario
scenlist <- split(allmifs, allmifs$scenario, drop = TRUE)
rm(allmifs)
cat("Applying the ScenarioMIP mapping to", length(scenlist), "scenarios\n")

dir.create(SCENARIOMIP_BATCH_DIR, recursive = TRUE, showWarnings = FALSE)

# Process one scenario ----
# Returns the ScenarioMIP data of the scenario. The log and the summation checks go to
# SCENARIOMIP_BATCH_DIR. The result is also saved there as rds
apply_mapping_one <- function(scenname) {
    batchrds <- file.path(SCENARIOMIP_BATCH_DIR, paste0(scenname, ".rds"))
    if (file.exists(batchrds) && !REDO_BATCHES) {
        return(readRDS(batchrds))
    }
    cat(format(Sys.time()), "start", scenname, "\n")
    # outputFilename = NULL: the data is returned instead of written. Only the log
    # and the summation checks are written to outputDirectory
    out <- generateIIASASubmission(
        scenlist[[scenname]],
        mapping = "ScenarioMIP",
        outputDirectory = SCENARIOMIP_BATCH_DIR,
        outputFilename = NULL,
        logFile = paste0(scenname, "_log.txt")
    )
    saveRDS(out, batchrds)
    cat(format(Sys.time()), "done ", scenname, "\n")
    return(out)
}

# Run the batches in parallel ----
# Number of parallel workers: the CPUs given by SLURM, or 1 if not running in SLURM.
# Each worker needs several GB of RAM, so SLURM_CPUS_PER_TASK might be more than the memory
# allows. MAX_WORKERS is the limit to avoid that
MAX_WORKERS <- 12
ncores <- min(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "1")), MAX_WORKERS, length(scenlist))
cat("Using", ncores, "workers\n")

# mc.preschedule = FALSE: a new worker per scenario, so the workers stay balanced
outlist <- mclapply(names(scenlist), apply_mapping_one, mc.cores = ncores, mc.preschedule = FALSE)

# mclapply returns "try-error" objects instead of stopping when a worker fails. Check them
failed <- sapply(outlist, function(x) inherits(x, "try-error"))
if (any(failed)) {
    stop("Failed scenarios:\n", paste(names(scenlist)[failed], collapse = "\n"))
}
rm(scenlist)

# Concatenate and write ----
scenmip <- bind_rows(outlist)
rm(outlist)
cat("ScenarioMIP data:", nrow(scenmip), "rows,",
    n_distinct(scenmip$scenario), "scenarios,",
    n_distinct(scenmip$variable), "variables\n")

saveRDS(scenmip, scenariomip_path("rds"))
write.mif(scenmip, scenariomip_path("mif"))
# The xlsx is the format of the ScenarioMIP submission
write.IAMCxlsx(scenmip, scenariomip_path("xlsx"))
cat("Wrote\n ", scenariomip_path("rds"), "\n ", scenariomip_path("mif"), "\n ", scenariomip_path("xlsx"), "\n")
