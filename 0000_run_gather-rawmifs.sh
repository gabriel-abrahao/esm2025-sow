#!/bin/bash
# SLURM script that runs 0000_gather-rawmifs.R (copy the raw REMIND mifs, read and concatenate them)
# Submit from the repository root, so the log goes to logs/:
#   sbatch 0000_run_gather-rawmifs.sh
#SBATCH --qos=short
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=128G
#SBATCH --job-name=0000_gather-rawmifs
#SBATCH --output=logs/%x.%j.out

# The R script uses SLURM_CPUS_PER_TASK as the number of parallel workers
cd "$SLURM_SUBMIT_DIR"
Rscript 0000_gather-rawmifs.R
