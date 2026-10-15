#!/bin/bash
# SLURM script that runs 0004_run_magicc_raw_v4.py with --parmode fullar6 (the full 600 member ensemble)
# Submit from the repository root, so the log goes to logs/:
#   sbatch 0004_run_magicc_raw_v4_fullar6.sh
#SBATCH --qos=short
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=128
#SBATCH --mem-per-cpu=4G
#SBATCH --job-name=0004_magicc_fullar6
#SBATCH --output=logs/%x.%j.out

# The Python script uses SLURM_CPUS_PER_TASK as the number of parallel MAGICC processes.
# It also sets the MAGICC executable (the v7.6.0a3 that comes with gcages) by itself
cd "$SLURM_SUBMIT_DIR"

# Scratch folder for the MAGICC workers, one per job to avoid clashes between jobs
export MAGICC_WORKER_ROOT_DIR=${TMP:-/tmp}"/magiccworkers_"$SLURM_JOB_ID
mkdir -p $MAGICC_WORKER_ROOT_DIR

.venv/bin/python 0004_run_magicc_raw_v4.py --parmode fullar6

# The workers are only needed during the run
rm -rf $MAGICC_WORKER_ROOT_DIR
