require(tidyverse)
require(quitte)
require(ggrepel)


source("common.R")
ensure_results_dirs()

fullclimfname <- climate_output_path()
fullclimrdsfname <- cache_path("cache_climate_output_fullar6")

redo_cache <- FALSE
if (!file.exists(fullclimrdsfname) || redo_cache) {
  inclim <- read.quitte(fullclimfname)
  saveRDS(inclim, fullclimrdsfname)
} else {
  inclim <- readRDS(fullclimrdsfname)
}

# Keep just temperature variable to make RAM more manageable
inclim <- inclim %>% filter(variable == "Surface Temperature (GSAT)")

inclim$variable %>%
  unique() %>%
  write.csv(table_path("valist_ar6clim"), row.names = F)


# Index calculations ===========================================================
# Will hold all "indexes", per-scenario values
allinds <- tibble()

# Peak warming and timing
gmtvarname <- "Surface Temperature (GSAT)"
temp <- inclim %>%
  filter(variable == gmtvarname) %>%
  group_by(across(-c("period", "value"))) %>%
  slice(which.max(value)) %>%
  mutate(variable = "Peak warming", unit = "K")

# Peak warming
allinds <- temp %>%
  select(-period) %>%
  bind_rows(allinds, .)

# Peak timing
allinds <- temp %>%
  select(-value) %>%
  rename(value = period) %>%
  mutate(variable = "Peak warming year", unit = "year") %>%
  bind_rows(allinds, .)

# EoC warming
allinds <- inclim %>%
  filter(variable == gmtvarname) %>%
  filter(period == 2099) %>%
  select(-period) %>%
  mutate(variable = "EoC warming", unit = "K") %>%
  bind_rows(allinds, .)

# Derived percentile indexes
# Peak warming percentile
allinds <- allinds %>%
  filter(variable == "Peak warming") %>%
  group_by(scenario, model, climate_model) %>%
  mutate(value = 100 * percent_rank(value)) %>%
  arrange(value) %>%
  mutate(variable = "Peak warming percentile", unit = "%") %>%
  ungroup() %>%
  bind_rows(allinds)

# EoC warming percentile
allinds <- allinds %>%
  filter(variable == "EoC warming") %>%
  group_by(scenario, model, climate_model) %>%
  mutate(value = 100 * percent_rank(value)) %>%
  arrange(value) %>%
  mutate(variable = "EoC warming percentile", unit = "%") %>%
  ungroup() %>%
  bind_rows(allinds)


# Scenario information

sceninfo <- allinds %>%
  select(scenario) %>%
  unique() %>%
  separate(scenario, sep = "-", into = c("vtag", "ssp", "policy"), remove = F) %>%
  mutate(
    budgtype = str_extract(policy, "^[A-Za-z][A-Za-z]*"),
    cbudget = as.numeric(str_extract(policy, "[0-9][0-9]*$"))
  )
allinds <- left_join(allinds, sceninfo)


# Percentile indexes only ============================================================

# usevar <- "Peak warming"
# useperc <- 67
extractPerc <- function(usevar, useperc) {
  pickpercs <- allinds %>%
    select(scenario, variable, run_id, value) %>%
    filter(variable == paste0(usevar, " percentile")) %>%
    mutate(diff = abs(value - useperc)) %>%
    group_by(scenario) %>%
    slice(which.min(diff)) %>%
    select(-value, -diff, -variable) %>%
    mutate(ispicked = TRUE)
  allinds %>%
    filter(variable == usevar) %>%
    left_join(pickpercs, by = join_by(scenario, run_id)) %>%
    filter(ispicked) %>%
    mutate(variable = paste0(usevar, " ", useperc)) %>%
    select(-ispicked) %>%
    return()
}

percdata <-
  bind_rows(
    extractPerc("Peak warming", 33),
    extractPerc("Peak warming", 50),
    extractPerc("Peak warming", 67),
    extractPerc("EoC warming", 33),
    extractPerc("EoC warming", 50),
    extractPerc("EoC warming", 67)
  )



# Criteria CCP1 ============================================================================
# No harmonization, Peak budget, C1-like: 67% under 2K peak warming, 50% under 1.5K EoC warming
options(width = 140)
percdata %>%
  select(-vtag, -ssp, -policy) %>%
  filter(budgtype == "Pb") %>%
  filter(variable %in% c(
    "Peak warming 67",
    "EoC warming 50"
  )) %>%
  select(-unit, -region, -run_id) %>%
  pivot_wider(names_from = variable, values_from = value) %>%
  filter(`Peak warming 67` <= 2) %>%
  filter(`EoC warming 50` <= 1.5) %>%
  group_by(model, climate_model, budgtype) %>%
  slice(which.max(cbudget)) %>%
  mutate(runcode = "CCP1") %>%
  select(model, scenario, climate_model, runcode)


# E25v01-SSP2-Pb760