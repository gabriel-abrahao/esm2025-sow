#!/bin/bash
#SBATCH --qos=short
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=128
#### SBATCH --mem=60000
#SBATCH --job-name=test_climate
#SBATCH --output=PYTHONLOG-%x.%j.out

export MAGICC_EXECUTABLE_7=/p/projects/piam/abrahao/scratch/module_climate_tests/climate-assessment-files/magicc-v7.5.3/bin/magicc
export MAGICC_WORKER_ROOT_DIR="/p/projects/piam/abrahao/esm2025/calibrate_magicc/workers/runid_"$1

mkdir $MAGICC_WORKER_ROOT_DIR

usepy=/home/abrahao/.conda/envs/test-scm/bin/python 
# $usepy run_magicc_raw_v2.py
$usepy run_magicc_raw_v3.py

