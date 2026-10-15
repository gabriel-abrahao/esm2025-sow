# Selects the MAGICC parametrizations of the states of the world (SoW), the "coresows".
# Takes the selected ensemble members (paraset_id column of the weights file of the MAGICC repo
# selection), keeps just those parametrizations of the full 600 member json, and writes them to a
# new json that 0004_run_magicc_raw_v4.py reads when run with --parmode coresows.
# %%
import json
import re

import pandas as pd

# %%
# File names are defined in common.R, so that all scripts find the same files
# Super hacky way to read the R variables from common.R, but it works and avoids having 
# to maintain some sort of config file in two languages. The R variables are read as strings
def read_common(name):
    return re.search(r'^' + name + r'\s*<-\s*"([^"]+)"', open("common.R").read(), re.M).group(1)

SELECT_ENSEMBLE_MEMBERS_ID = read_common("SELECT_ENSEMBLE_MEMBERS_ID")
parsetsdir = "parametrizations/" + SELECT_ENSEMBLE_MEMBERS_ID + "/"
weightsfname = parsetsdir + read_common("SELECTED_MEMBERS_WEIGHTS_FNAME").replace("{ID}", SELECT_ENSEMBLE_MEMBERS_ID)
outfname = parsetsdir + read_common("CORESOWS_PARSETS_FNAME").replace("{ID}", SELECT_ENSEMBLE_MEMBERS_ID)

# The full ensemble, from which the selected members are taken
baseparsetsfname = "parametrizations/" + read_common("FULLENSEMBLE_PARSETS_FNAME")

# %%
# Selected ensemble members: just the ids of the parametrizations, the weights are not used here
selparsetids = pd.read_csv(weightsfname)["paraset_id"].tolist()
print("Selected " + str(len(selparsetids)) + " parametrizations: " + str(selparsetids))

# %%
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

# %%
# Keep only the selected ones, and check that all of them were found
allparsets = [parset for parset in allparsets if parset["run_id"] in selparsetids]
foundids = [parset["run_id"] for parset in allparsets]
if sorted(foundids) != sorted(selparsetids):
    raise ValueError("Selected ids not found in " + baseparsetsfname + ": " + str(set(selparsetids) - set(foundids)))

# %%
# Write in the same format as the original json (a "configurations" list with paraset_id and
# nml_allcfgs), so that 0004 reads it as it reads the full ensemble. The other keys (contact,
# license, etc) are kept, as the license asks to keep the attribution, and the description says
# that this is a subset
outparsets = {k: v for k, v in inallparsets.items() if k != "configurations"}
outparsets["description"] = outparsets["description"] + " Subset of " + str(len(allparsets)) + " configurations selected as states of the world (selection " + SELECT_ENSEMBLE_MEMBERS_ID + ")."
outparsets["configurations"] = [
    {"paraset_id": parset["run_id"], "nml_allcfgs": {k: v for k, v in parset.items() if k != "run_id"}}
    for parset in allparsets
]

with open(outfname, "w") as f:
    json.dump(outparsets, f, indent = 2)
print("Wrote " + str(len(allparsets)) + " parametrizations to " + outfname)
