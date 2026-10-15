#!/bin/bash
# SLURM script that runs 0002_harmonize_emissions.py (SCI harmonization and infilling with gcages)
# Submit from the repository root, so the log goes to logs/:
#   sbatch 0002_run_harmonize_emissions.sh
#SBATCH --qos=short
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=64G
#SBATCH --job-name=0002_harmonize_emissions
#SBATCH --output=logs/%x.%j.out

# The Python script uses SLURM_CPUS_PER_TASK as the number of parallel processes
cd "$SLURM_SUBMIT_DIR"
.venv/bin/python 0002_harmonize_emissions.py
