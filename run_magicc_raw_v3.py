# Gathers harmonized scenarios and runs MAGICC 7.5.3, also writing the harmonized emissions in a single file.
# %%
import pymagicc
import openscm_runner
import scmdata
import climate_assessment
import pyam
import pandas as pd
import xarray as xr
import copy
import json
import os
import glob
import sys
from wg3 import *

# %env MAGICC_EXECUTABLE_7=/p/projects/piam/abrahao/scratch/module_climate_tests/climate-assessment-files/magicc-v7.5.3/bin/magicc
# %env MAGICC_WORKER_ROOT_DIR=/p/projects/piam/abrahao/scratch/methane/methane_scm/workers

# export MAGICC_EXECUTABLE_7=/p/projects/piam/abrahao/scratch/module_climate_tests/climate-assessment-files/magicc-v7.5.3/bin/magicc
# export MAGICC_WORKER_ROOT_DIR=/p/projects/piam/abrahao/scratch/methane/methane_scm/workers
        
#%%
# basescenfname = "emimif_ar6_harmonized_infilled.csv"
# basescenfname = "/p/projects/piam/abrahao/esm2025/iamc2024/remind_iamc2024/ESM2025v03_rem-5_harmonized.csv"
# basescenfname = "/p/projects/piam/abrahao/esm2025/iamc2024/remind_iamc2024/ESM2025v03_rem-5_partial_harmonized.csv"

# baseparsetsfname = "esm2025_climate_core_sows_for_pik_2024_06_17_144827.json"
baseparsetsfname = "0fd0f62-derived-metrics-id-f023edb-drawnset.json"

# outfname = "climate_output_coresows_v2.csv"
outfname = "climate_output_fullar6_v2.csv"

allrunsdir = "output/"
allemicsvpaths = glob.glob(allrunsdir + "/*/climate-assessment-data/ar6_climate_assessment_*_harmonized_infilled.csv")

inallscens = pyam.concat([pyam.IamDataFrame(fname) for fname in allemicsvpaths])

# basescen = pyam.IamDataFrame(basescenfname).as_pandas()

# basescenname = basescen["scenario"].unique()[0]

print("Found harmonized emissions for " + str(len(inallscens["scenario"].unique())) + " scenarios")
print(list(inallscens["scenario"].unique()))

allscens = clean_wg3_scenarios(inallscens)

#%%
# Extending emissions
exyref = 2100
exyend = 2250

for exy in range(exyref+1,exyend+1):
    allscens[pd.Timestamp(str(exy)+'-01-01 00:00:00')] = allscens[pd.Timestamp(str(exyref)+'-01-01 00:00:00')]


#%%
outallscens = copy.deepcopy(allscens)
yearcols = [i.year if isinstance(i,pd.Timestamp) else i for i in outallscens.columns.values]
outallscens.columns = yearcols


outallscens.to_csv("emissions_" + outfname, index = False)

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

runresults = openscm_runner.run(
    climate_models_cfgs={
        # "MAGICC7" : [{}]
        "MAGICC7" : modparsets
        # "MAGICC7" : [inallparsets["configurations"][0]["nml_allcfgs"]]
    },
    output_variables=(
        "Surface Air Temperature Change",
        "Net Atmosphere to Land Flux|CO2",
        "Atmospheric Concentrations|CO2",
        "Net Atmosphere to Ocean Flux|CO2"
    ),
    # scenarios=scmdata.ScmRun("rcmip_scen_ssp_world_emissions.csv", lowercase_cols = True).filter(scenario = ["ssp245","ssp585"])
    # scenarios = scmdata.ScmRun(basescen)
    scenarios = scmdata.ScmRun(allscens)
    )

#%%
# runresults.to_csv("dummy.csv")
print("===================== FINISHED RUNNING MODEL ====================")
print("===================== ADJUSTING MEDIAN WARMING ====================")

historical_warming=0.85
historical_warming_reference_period="1850-1900"
historical_warming_evaluation_period="1995-2014"

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

filtresults.to_iamdataframe().swap_time_for_year().to_csv(outfname)
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

