# Step 0002 of the pipeline: harmonize and infill the emissions with the SCI pipeline of gcages
#
# Takes the ScenarioMIP-formatted REMIND emissions of step 0001 (scenariomip_<SVERSION>.mif)
# and runs the SCI June 2026 workflow of gcages (gcages.sci_june_2026) on them:
#   1. pre-processing: keeps the emissions the SCI workflow uses, reclassifies CO2 Other/Waste/
#      Other Capture and Removal/Product Use into CO2|Energy and Industrial Processes,
#      interpolates to annual steps, renames to gcages names
#   2. harmonization to the CMIP7 ScenarioMIP history in HARMONISATION_YEAR (aneris, SCI overrides)
#   3. infilling of the variables REMIND does not report (SCI infilling database + GHG inversions)
# The result ("complete", HARMONISATION_YEAR to 2100) has all the variables MAGICC needs, and is
# written as a single csv with all scenarios in data/scenarios-<SVERSION>/. The harmonized
# variables before infilling are written beside it.
#
# Run with the Python environment of this repository (see the Makefile):
#   .venv/bin/python 0002_harmonize_emissions.py [input_mif] [output_dir]
# The two optional arguments are only meant for tests. Use 0002_run_harmonize_emissions.sh for SLURM.

# %%
import multiprocessing
import os
import re
import sys
import time
from pathlib import Path

import pandas as pd
from gcages.sci_june_2026.harmonisation import create_scijune2026_harmoniser
from gcages.sci_june_2026.infilling import create_scijune2026_infiller
from gcages.sci_june_2026.pre_processing import SCIJune2026PreProcessor

# %%
# Versioning: SVERSION is defined in common.R, and read from there so there is a single source of truth
ROOT = Path(__file__).parent
SVERSION = re.search(r'^SVERSION\s*<-\s*"([^"]+)"', (ROOT / "common.R").read_text(), re.M).group(1)

# Same folder as LOCAL_DATA_DIR in common.R
LOCAL_DATA_DIR = ROOT / "data" / f"scenarios-{SVERSION}"
IN_MIF = LOCAL_DATA_DIR / f"scenariomip_{SVERSION}.mif"  # scenariomip_path("mif") in common.R
OUT_DIR = LOCAL_DATA_DIR
if len(sys.argv) > 1:
    IN_MIF = Path(sys.argv[1])
if len(sys.argv) > 2:
    OUT_DIR = Path(sys.argv[2])

OUT_COMPLETE = OUT_DIR / f"harmonized_emissions_{SVERSION}.csv"
OUT_HARMONISED = OUT_DIR / f"harmonized_emissions_{SVERSION}_before-infilling.csv"

# %%
# Inputs of the SCI workflow, from the gcages clone of this repository (made by `make venv`)
GCAGES_REGRESSION_DIR = ROOT / "gcages" / "tests" / "regression"
CMIP7_INPUT_DIR = GCAGES_REGRESSION_DIR / "cmip7-scenariomip" / "cmip7-scenariomip-workflow-inputs"
SCI_INPUT_DIR = GCAGES_REGRESSION_DIR / "sci_june_2026" / "sci_workflow_inputs"
HISTORY_FILE = CMIP7_INPUT_DIR / "history_cmip7_scenariomip.csv"
GHG_INVERSIONS_FILE = CMIP7_INPUT_DIR / "cmip7_ghg_inversions.csv"
OVERRIDES_FILE = SCI_INPUT_DIR / "sci_overrides.csv"
INFILLING_DB_FILE = SCI_INPUT_DIR / "infilling_db_sci.csv"

# Year in which the scenarios are harmonized to the history (2023 is the year of the SCI infilling database)
HARMONISATION_YEAR = 2023

# Number of processes: the CPUs given by SLURM, or all CPUs when not in SLURM
N_PROCESSES = int(os.environ.get("SLURM_CPUS_PER_TASK", multiprocessing.cpu_count()))
print("SVERSION:", SVERSION, "| input:", IN_MIF, "| processes:", N_PROCESSES, flush=True)

# %%
# The SCI pre-processor
pre_processor = SCIJune2026PreProcessor.from_sci_june2026_config(
    n_processes=N_PROCESSES, progress=False, run_checks=True
)
# Its input check complains about negative values in any non-CO2 variable it receives (e.g. the
# Kyoto Gases aggregates), so we hand it only the variables it uses: the ones it keeps and the
# CO2 components it reclassifies into Energy and Industrial Processes
VARIABLES_USED = set(pre_processor.emissions_out) | {
    v for vs in pre_processor.reclassifications.values() for v in vs
}

# %%
# Read the ScenarioMIP mif
# The mif is big (all regions and variables), but we only need the World emissions used by SCI, so the
# file is read in chunks and filtered. The mif rows end with ";", which pandas reads as an
# extra empty column called "Unnamed: N" at the end, dropped here
t0 = time.time()
chunks = []
for chunk in pd.read_csv(IN_MIF, sep=";", index_col=False, chunksize=500_000):
    chunk = chunk.loc[:, ~chunk.columns.str.startswith("Unnamed")]
    chunk.columns = [c.lower() if not c.isdigit() else c for c in chunk.columns]
    keep = (chunk["region"] == "World") & chunk["variable"].isin(VARIABLES_USED)
    chunks.append(chunk.loc[keep])
emissions = pd.concat(chunks, ignore_index=True)
del chunks

emissions = emissions.set_index(["model", "scenario", "region", "variable", "unit"])
emissions.columns = emissions.columns.astype(int)
# The SCI pre-processor starts in 2010
emissions = emissions.loc[:, 2010:].sort_index(axis="columns").dropna(how="all")
print(f"Read {emissions.shape[0]} World emission series of "
      f"{emissions.index.get_level_values('scenario').nunique()} scenarios "
      f"({time.time() - t0:.0f} s)", flush=True)

# %%
# 1. Pre-processing
pre_processed = pre_processor(emissions)
print("Pre-processed:", pre_processed.shape, flush=True)

# %%
# 2. Harmonization
harmoniser = create_scijune2026_harmoniser(
    historical_emissions_file=HISTORY_FILE,
    aneris_overrides_file=OVERRIDES_FILE,
    harmonisation_year=HARMONISATION_YEAR,
    progress=False,
    n_processes=N_PROCESSES,
)
harmonised = harmoniser(pre_processed)
print("Harmonised:", harmonised.shape, flush=True)

# %%
# 3. Infilling: the output has the harmonized and the infilled variables together
infiller = create_scijune2026_infiller(
    infilling_leader_emissions_file=INFILLING_DB_FILE,
    ghg_inversions_file=GHG_INVERSIONS_FILE,
    historical_emissions_file=HISTORY_FILE,
    harmonisation_year=HARMONISATION_YEAR,
    pre_industrial_year=1750,
    run_checks=True,
)
complete = infiller(harmonised)
print("Complete (harmonised + infilled):", complete.shape, flush=True)

# %%
# Write
OUT_DIR.mkdir(parents=True, exist_ok=True)
harmonised.sort_index().to_csv(OUT_HARMONISED)
complete.sort_index().to_csv(OUT_COMPLETE)
print("Wrote\n ", OUT_COMPLETE, "\n ", OUT_HARMONISED)
print(f"Done in {time.time() - t0:.0f} s")
