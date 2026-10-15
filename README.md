# esm2025-sow
States of the World (SoW) analysis for the ESM2025 project.

## Goal
Use a states-of-the-world approach to inform which mitigation scenario is "Paris-compatible".
A **state of the world** is a single parametrization of the MAGICC climate model, i.e. one
climate response. A set of REMIND mitigation scenarios, each respecting a CO2 carbon budget
(`PbXXXX`, in GtCO2), is evaluated against each SoW.

## Workflow
1. **Gather** the emissions of every REMIND scenario from
   `/p/projects/piam/abrahao/esm2025/task133/pilot_v06/remind/output` (`C_E25t3v06-SSP2-*-PbXXXX.mif`).
2. **Harmonize** them with the SCI harmonization in `gcages`.
3. **Run MAGICC** on each scenario with the full probabilistic ensemble (600 parametrizations),
   then either select or rerun only the small set of SoW parametrizations
   (currently 13; taken from the results of another repository, may change).
4. **Define climate criteria** for Paris-compatibility. Four are defined in the R scripts;
   the analysis focuses mostly on criterion 4 (CR4).
5. **Match**, for each SoW, the REMIND scenario whose budget satisfies the criterion.
6. **Analyze** the resulting set of scenarios.

## Repository layout
- Root: the maintained analysis scripts (R/Python/bash), `common.R` (shared paths/config),
  `DATA_DEPENDENCIES.md` (inputs each script needs), `parametrizations/`.
- `cmem/`: notes for Claude Code sessions (not needed to use the repository).
- `ctemp/`: scratch scripts and intermediate files produced during assisted analyses.

## Scripts
(To be filled in as the setup progresses; see `DATA_DEPENDENCIES.md` for inputs.)

| Script | Role |
|---|---|
| `analyze_budgets_v*.R` | Budget analysis across scenarios and climate outcomes tables |
| `analyze_classify_runids_v*.R` | Classification of ensemble members (run IDs) |
| `analyze_chanceconstrained_criteria_v*.R` | Chance-constrained climate criteria |
| `analyze_comparisons_CR4_v1.R` | Scenario comparison under CR4 against AR6 climate response |
| `run_magicc_raw_v3.py`, `wg3.py` | MAGICC runs on harmonized scenarios and helper module |
| `submit_magicc.sh` | SLURM submission of the MAGICC run |
| `test_magicc.py`, `test_submit.sh` | Quick test of running MAGICC with `gcages` (few scenarios and parametrizations); submit with `sbatch test_submit.sh` |
| `export_for_elmar.R`, `forelmar_misc.R`, `dummy.R` | Export and miscellaneous utilities |

## Python environment
Python tooling (e.g. running MAGICC with `gcages`) uses a local virtual environment `.venv/`
(Python 3.11, built with `uv`) and an editable clone of [gcages](https://github.com/openscm/gcages)
(main branch) in `gcages/`. Both are untracked. Activate with `source .venv/bin/activate`.
Note that `xarray` is pinned to 2025.9.0 for compatibility with `scmdata`.
The installed packages are listed in `ctemp/python_requirements_freeze.txt`.
