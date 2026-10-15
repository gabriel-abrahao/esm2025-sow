# Gathers harmonized scenarios and runs MAGICC 7.5.3, also writing the harmonized emissions in a single file.
# %%
import scmdata
# import climate_assessment
import pyam
import pandas as pd
import xarray as xr
import copy
import json
import os
import glob
import sys
import re
import argparse
import multiprocessing
from gcages.cmip7_scenariomip.harmonisation import load_cmip7_scenariomip_historical_emissions
from gcages.cmip7_scenariomip.scm_running import CMIP7ScenarioMIPSCMRunner
from gcages.renaming import SupportedNamingConventions, convert_variable_name
from gcages.scm_running import convert_openscm_runner_output_names_to_magicc_output_names
from pandas_openscm.index_manipulation import update_index_levels_func
from wg3 import *

# %env MAGICC_EXECUTABLE_7=/p/projects/piam/abrahao/scratch/module_climate_tests/climate-assessment-files/magicc-v7.5.3/bin/magicc
# %env MAGICC_WORKER_ROOT_DIR=/p/projects/piam/abrahao/scratch/methane/methane_scm/workers

# export MAGICC_EXECUTABLE_7=/p/projects/piam/abrahao/scratch/module_climate_tests/climate-assessment-files/magicc-v7.5.3/bin/magicc
# export MAGICC_WORKER_ROOT_DIR=/p/projects/piam/abrahao/scratch/methane/methane_scm/workers
        
#%%
# basescenfname = "emimif_ar6_harmonized_infilled.csv"
# basescenfname = "/p/projects/piam/abrahao/esm2025/iamc2024/remind_iamc2024/ESM2025v03_rem-5_harmonized.csv"
# basescenfname = "/p/projects/piam/abrahao/esm2025/iamc2024/remind_iamc2024/ESM2025v03_rem-5_partial_harmonized.csv"

# Versioning: SVERSION is read from common.R, so it is defined in a single place
SVERSION = re.search(r'^SVERSION\s*<-\s*"([^"]+)"', open("common.R").read(), re.M).group(1)
datadir = "data/scenarios-" + SVERSION + "/"

# Parameter set to use: "fullar6" (the 600 member ensemble) or "coresows" (the SoW members)
# Can be given as a command line argument, e.g. python 0003_run_magicc_raw_v4.py --parmode coresows
# parse_known_args ignores any other arguments (like the ones of the interactive window),
# and stops with an error if --parmode is not one of the choices
parser = argparse.ArgumentParser()
parser.add_argument("--parmode", choices = ["fullar6", "coresows"], default = "fullar6")
# Test mode (-t): small runs for testing, default is False
parser.add_argument("-t", dest = "testmode", action = "store_true")
args = parser.parse_known_args()[0]
parmode = args.parmode
testmode = args.testmode

# # TODO: REMOVE THIS!!!!
# testmode = True

# baseparsetsfname = "esm2025_climate_core_sows_for_pik_2024_06_17_144827.json"
# baseparsetsfname = "0fd0f62-derived-metrics-id-f023edb-drawnset.json"
# The json with just the SoW parametrizations is made by 0003_select_parsets.py. Its name is defined in common.R
SELECT_ID = re.search(r'^SELECT_ENSEMBLE_MEMBERS_ID\s*<-\s*"([^"]+)"', open("common.R").read(), re.M).group(1)
COREFNAME = re.search(r'^CORESOWS_PARSETS_FNAME\s*<-\s*"([^"]+)"', open("common.R").read(), re.M).group(1).replace("{ID}", SELECT_ID)
FULLNAME = re.search(r'^FULLENSEMBLE_PARSETS_FNAME\s*<-\s*"([^"]+)"', open("common.R").read(), re.M).group(1)
baseparsetsfnames = {
    # "fullar6": "parametrizations/0fd0f62-derived-metrics-id-f023edb-drawnset.json",
    "fullar6": "parametrizations/" + FULLNAME,  # the AR7 fast track drawn set (same 600 members, MAGICC v7.6.0a3)
    "coresows": "parametrizations/" + SELECT_ID + "/" + COREFNAME,
}
baseparsetsfname = baseparsetsfnames[parmode]

# outfname = "climate_output_coresows_v2.csv"
# outfname = "climate_output_fullar6_v2.csv"
outfname = "climate_output_" + parmode + "_" + SVERSION + ".csv"

# allrunsdir = "output/"
# allemicsvpaths = glob.glob(allrunsdir + "/*/climate-assessment-data/ar6_climate_assessment_*_harmonized_infilled.csv")
allemicsvpaths = [datadir + "harmonized_emissions_" + SVERSION + ".csv"]

inallscens = pyam.concat([pyam.IamDataFrame(fname) for fname in allemicsvpaths])

# basescen = pyam.IamDataFrame(basescenfname).as_pandas()

# basescenname = basescen["scenario"].unique()[0]

# In test mode, keep just 2 scenarios
if testmode:
    inallscens = inallscens.filter(scenario = list(inallscens["scenario"].unique()[:2]))

print("Found harmonized emissions for " + str(len(inallscens["scenario"].unique())) + " scenarios")
print(list(inallscens["scenario"].unique()))

# allscens = clean_wg3_scenarios(inallscens)
# The harmonized emissions are already MAGICC ready, so the cleaning is not needed. We only need
# the flat data frame with Timestamp year columns that the rest of the script (and ScmRun) uses
allscens = inallscens.timeseries().reset_index()
allscens.columns = [pd.Timestamp(str(i) + '-01-01 00:00:00') if str(i).isdigit() else i for i in allscens.columns]

#%%


#%%
# Emissions extension: future
# Extending emissions to 2250, by keeping the 2100 values constant until 2250.
# We need this because some scenarios are still warming by 2100, and
# might not classify as "stabilization" scenarios, so we run them
# a bit further to see if they stabilize or not.  
exyref = 2100
exyend = 2250

for exy in range(exyref+1,exyend+1):
    allscens[pd.Timestamp(str(exy)+'-01-01 00:00:00')] = allscens[pd.Timestamp(str(exyref)+'-01-01 00:00:00')]

#%%
# Write extended emissions to a single file, so that it can be used by other scripts 
outallscens = copy.deepcopy(allscens)
yearcols = [i.year if isinstance(i,pd.Timestamp) else i for i in outallscens.columns.values]
outallscens.columns = yearcols


# The file name template is defined in common.R (EMISSIONS_EXTENDED_FNAME), so that other scripts find this file
emissionsextfname = re.search(r'^EMISSIONS_EXTENDED_FNAME\s*<-\s*"([^"]+)"', open("common.R").read(), re.M).group(1)
emissionsextfname = emissionsextfname.replace("{SVERSION}", SVERSION)
outallscens.to_csv(datadir + emissionsextfname, index = False)

#%%
# Emissions extension: past
# The scenarios start in 2023, but MAGICC needs emissions from 2015 (when it switches from its
# internal history to the scenario data). The runner below adds the history to the scenarios.
# This is the history used to harmonize in 0002, with the variable names converted to gcages
# 
# Thankfully, we don't have to append the history to the scenarios ourselves, 
# because the CMIP7ScenarioMIPSCMRunner does it for us. 
# We just need to give it the history as a ScmRun, and it will add it to the scenarios 
# before running MAGICC.
 
histfname = "gcages/tests/regression/cmip7-scenariomip/cmip7-scenariomip-workflow-inputs/history_cmip7_scenariomip.csv"
history = load_cmip7_scenariomip_historical_emissions(filepath = histfname, check_hash = True)
history = update_index_levels_func(
    history,
    {"variable": lambda x: convert_variable_name(
        x,
        from_convention = SupportedNamingConventions.CMIP7_SCENARIOMIP,
        to_convention = SupportedNamingConventions.GCAGES)}
)
history = history.reset_index(level = [l for l in ["model", "scenario"] if l in history.index.names], drop = True)

#%%
# Read original parameter set
with open(baseparsetsfname) as f:
    inallparsets = json.load(f)


if isinstance(inallparsets,dict):
    # allparsets = [i["nml_allcfgs"].update({"run_id":i["paraset_id"]}) for i in inallparsets["configurations"]]
    allparsets = list()
    for el in inallparsets["configurations"]:
        use = el["nml_allcfgs"]
        use.update({"run_id":el["paraset_id"]})
        allparsets.append(use)
else:
    allparsets = inallparsets

if testmode:
    allparsets = allparsets[:3]

#%%
modparsets = copy.deepcopy(allparsets)
# Set endyear in all parsets 
for parset in modparsets:
    parset["endyear"] = int(2250)




# %%
# dir(scmdata)
# allscens = allscens[allscens["scenario"] == "E25v01-SSP2-Eb020"]
# %%
# Actual runs ==================================
print(scmdata.ScmRun(allscens))

# MAGICC is run through gcages, with the runner of the CMIP7 ScenarioMIP workflow (the one the SCI
# pipeline uses). On top of calling MAGICC, it does what the harmonized emissions need:
#  - adds the history (2015-2022) before the first year of the scenarios (2023), because MAGICC
#    switches from its internal history to the scenario data in 2015
#  - converts the variable names from gcages to openscm-runner names
#  - runs the scenarios in batches, in parallel
# The runner is built directly, instead of with from_cmip7_scenariomip_config, to keep our own MAGICC
# (MAGICC_EXECUTABLE_7, 7.5.3, set in the submission script) and our own parameter sets
output_variables = (
    "Surface Air Temperature Change",
    "Net Atmosphere to Land Flux|CO2",
    "Atmospheric Concentrations|CO2",
    "Net Atmosphere to Ocean Flux|CO2"
)

# The MAGICC configurations: our parameter sets (lower case names, with the run_id), plus the
# settings common to all of them (output variables and the binary output format)
run_config = [
    {
        "startyear": 1750,
        "out_dynamic_vars": convert_openscm_runner_output_names_to_magicc_output_names(output_variables),
        "out_ascii_binary": "BINARY",
        "out_binary_format": 2,
        **{k.lower(): v for k, v in parset.items()},
    }
    for parset in modparsets  # modparsets already have the endyear set above
]

# The runner needs the emissions with the identifiers as index and the years (integers) as columns
scenarios = outallscens.set_index(["model", "scenario", "region", "variable", "unit"])

# openscm-runner finds MAGICC through this environment variable. It is set explicitly here (also when
# running interactively) to the MAGICC v7.6.0a3 that comes with gcages, the version of the CMIP7
# ScenarioMIP workflow and of the metrics used to select the SoW. The path is absolute because the
# runs happen in other working directories
os.environ["MAGICC_EXECUTABLE_7"] = os.path.abspath(
    "gcages/tests/regression/cmip7-scenariomip/cmip7-scenariomip-workflow-inputs/magicc-v7.6.0a3/bin/magicc"
)

# Number of parallel processes: the CPUs given by SLURM, or all of them
n_processes =int(os.environ.get("SLURM_CPUS_PER_TASK", multiprocessing.cpu_count()))
batch_size_scenarios = 5

# Print the whole setup that is about to be run, so it is also in the log of the job
scennames = list(scenarios.index.get_level_values("scenario").unique())
print("===================== SETUP OF THE RUN ====================")
print("SVERSION:", SVERSION, "| parmode:", parmode, "| testmode:", testmode)
print("Emissions input:", allemicsvpaths)
print("Parameter sets file:", baseparsetsfname)
print("Output files:", datadir + emissionsextfname, "and", datadir + outfname)
print("Scenarios (" + str(len(scennames)) + "):", scennames)
print("Parameter sets (" + str(len(run_config)) + "), run_ids:", [c["run_id"] for c in run_config])
print("Total MAGICC runs:", len(scennames) * len(run_config))
print("Emissions years:", scenarios.columns.min(), "to", scenarios.columns.max(), "(the history is added before)")
print("Output variables:", output_variables)
print("Settings common to all parameter sets:", {k: run_config[0][k] for k in ["startyear", "endyear", "out_dynamic_vars", "out_ascii_binary", "out_binary_format"]})
print("MAGICC executable:", os.environ.get("MAGICC_EXECUTABLE_7"), "| worker dir:", os.environ.get("MAGICC_WORKER_ROOT_DIR"))
print("Parallel processes:", n_processes, "| scenarios per batch:", batch_size_scenarios)

runner = CMIP7ScenarioMIPSCMRunner(
    climate_models_cfgs = {"MAGICC7": run_config},
    output_variables = output_variables,
    historical_emissions = history,
    harmonisation_year = 2023,
    n_processes = n_processes,
    batch_size_scenarios = batch_size_scenarios,
)
res = runner(scenarios)

# The rest of the script works with scmdata
runresults = scmdata.ScmRun(res)

#%%
# runresults.to_csv("dummy.csv")
print("===================== FINISHED RUNNING MODEL ====================")
print("===================== ADJUSTING MEDIAN WARMING ====================")

# The old climate-assessment pipeline (AR6) used to adjust the median warming
# to match a historical 0.85 warming from 1850-1900 to 1995-2014, 
# based on AR6 WGI numbers. Here we update it to use:
# Forster et al. (https://essd.copernicus.org/articles/17/2641/2025/#section7)
# 2015-2024 (inclusive) is 1.24 [1.11-1.35, very likely range] rel. to 1850-1900
# 2005-2024 (inclusive) is 1.09 [0.93-1.20, very likely range] rel. to 1850-1900

historical_warming=1.24
historical_warming_reference_period="1850-1900"
historical_warming_evaluation_period="2015-2024"

def check_hist_warming_period(period):
    period = period
    split = period.split("-")
    return range(int(split[0]), int(split[1]) + 1)

hist_temp_ref_period = check_hist_warming_period(
    historical_warming_reference_period
)
hist_temp_evaluation_period = check_hist_warming_period(
    historical_warming_evaluation_period
)

exceedance_probability_timeseries_raw = runresults.filter(
    variable=f"Surface Air Temperature Change"
)

exceedance_probability_timeseries_rel_ref_period = (
    exceedance_probability_timeseries_raw.relative_to_ref_period_mean(
        year=hist_temp_ref_period
    ).drop_meta(["reference_period_start_year", "reference_period_end_year"])
)

exceedance_probability_timeseries = (
    exceedance_probability_timeseries_rel_ref_period.adjust_median_to_target(
        historical_warming,
        hist_temp_evaluation_period,
        process_over=("run_id",),
    )
)

exceedance_probability_timeseries["variable"] = "Surface Temperature (GSAT)"

# %%
print("===================== WRITING OUTPUT ====================")
# os.mkdir("caltests_v1/")
print(outfname)

outresults = runresults.append(exceedance_probability_timeseries)
filtresults = outresults.filter(region = "World",year = range(1950,2250))

filtresults.to_iamdataframe().swap_time_for_year().to_csv(datadir + outfname)
print("===================== DONE ====================")

# # %%
# import pyam
# outdf = runresults.to_iamdataframe()

# # %%
# outdf.filter(
#     region = "World",year = range(1950,2100)
#     ).filter(
#         variable = "Surface Air Temperature Change"
#     ).plot(
#         color = "scenario"
#     )

# %%
# exceedance_probability_timeseries_raw.filter(
# exceedance_probability_timeseries_rel_ref_period.filter(
#         scenario = "C_ESM2025v03-LPJml-SSP2-PkBudg600-rem-5",
#         variable = "Surface Air Temperature Change",
#         region = "World",
#         # year = hist_temp_ref_period
#         year = hist_temp_evaluation_period
#         # year = range(2050,2060)
# ).values.mean()
# #%%
# inp = inallscens
# inp.filter(
#     variable=[
#         "*Infilled|Emissions|CO2",
#         "*Infilled|Emissions|F-Gases",
#         "*Infilled|Emissions|HFC",
#         "*Infilled|Emissions|PFC",
#         "*Infilled|Emissions|Kyoto Gases (AR5-GWP100)",
#         "*Infilled|Emissions|Kyoto Gases (AR6-GWP100)",
#     ],
#     keep=False,
#     inplace=True,
# )

# infilled_emms_filter = "*Infilled*"
# df_clean = inp.filter(variable=infilled_emms_filter).data.copy()
# # if df_clean.empty:
# #     LOGGER.error("No '%s' data available", infilled_emms_filter)

# #     return None

# replacements_variables = {
#     r".*\|Infilled\|": "",
#     "AFOLU": "MAGICC AFOLU",
#     "Energy and Industrial Processes": "MAGICC Fossil and Industrial",
#     "HFC43-10": "HFC4310mee",
#     # "Sulfur": "SOx",
#     # "VOC": "NMVOC",
#     r"HFC\|": "",
#     r"PFC\|": "",
#     "HFC245ca": "HFC245fa",  # still needed?
# }
# for old, new in replacements_variables.items():
#     df_clean["variable"] = df_clean["variable"].str.replace(old, new)

# replacements_units = {
#     "HFC43-10": "HFC4310mee",
# }
# for old, new in replacements_units.items():
#     df_clean["unit"] = df_clean["unit"].str.replace(old, new)

# # avoid MAGICC's weird end year effects by ensuring scenarios go just beyond
# # the years we're interested in
# scens_scmrun = scmdata.ScmRun(df_clean)
# output_times = [
#     dt.datetime(y, 1, 1) for y in scens_scmrun["year"].tolist() + [2110]
# ]
# scens_scmrun = scens_scmrun.interpolate(
#     output_times,
#     extrapolation_type="constant",
# )
# clean_scenarios = scens_scmrun.timeseries().reset_index()

# def fix_hfc_unit(variable):
#     if "HFC" not in variable:
#         raise NotImplementedError(variable)

#     return "kt {}/yr".format(variable.split("|")[-1])

# hfc_rows = clean_scenarios["variable"].str.contains("HFC")
# clean_scenarios.loc[hfc_rows, "unit"] = clean_scenarios.loc[
#     hfc_rows, "variable"
# ].apply(fix_hfc_unit)

# try:
#     # if extra col is floating around, remove it
#     clean_scenarios = clean_scenarios.drop("unnamed: 0", axis="columns")
# except KeyError:
#     pass

