#!/bin/bash
# SLURM script that runs 0001_apply_scenariomip_mapping.R (ScenarioMIP mapping of the concatenated raw mifs)
# Submit from the repository root, so the log goes to logs/:
#   sbatch 0001_run_apply_scenariomip_mapping.sh
#SBATCH --qos=short
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=12
#SBATCH --mem=100G
#SBATCH --job-name=0001_apply_scenariomip_mapping
#SBATCH --output=logs/%x.%j.out

# The R script uses SLURM_CPUS_PER_TASK (capped by MAX_WORKERS = 12 in the script) as the number of parallel workers.
# Memory: 12 workers x 8 GB + the parent process holding the data
cd "$SLURM_SUBMIT_DIR"
Rscript 0001_apply_scenariomip_mapping.R
