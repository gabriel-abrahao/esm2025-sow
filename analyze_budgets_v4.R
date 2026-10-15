require(tidyverse)
require(quitte)

source("common.R")
ensure_results_dirs()

climfname <- climate_output_coresows_path()
emisfname <- harmonized_emissions_path()
lablfname <- runcode_path("PbPW_AbsRev")
welffname <- welfare_path()


# Cache of inclimdf, as it is filtered below (World only, without region, model and climate_model).
# The cache name is specific to this script, as other scripts keep different content in variables with the same name.
# TRUE: always read the climate output again. FALSE: use the cache, unless it does not exist
# or is older than the climate output (which means the climate output was made again)
redo_inclimdf_cache <- FALSE
inclimcachefname <- cache_path("cache_budgets_inclimdf")
if (!file.exists(inclimcachefname) || redo_inclimdf_cache || file.mtime(inclimcachefname) < file.mtime(climfname)) {
    inclimdf <- read.quitte(climfname) %>%
        filter(region == "World") %>%
        select(-region,-model,-climate_model)
    saveRDS(inclimdf, inclimcachefname)
} else {
    inclimdf <- readRDS(inclimcachefname)
}

inclimdf %>% select(variable) %>% unique %>% write.csv(table_path("varlist_clim"),row.names=F)

labldf <- read.csv(lablfname) %>%
    separate(runcode, remove = F, sep = "_", into = c("ord1","ord2")) %>%
    mutate(ord1 = as.numeric(str_extract(ord1,"[0-9][0-9]*"))) %>%
    mutate(ord2 = as.numeric(str_extract(ord2,"[0-9][0-9]*"))) %>%
    arrange(ord1,ord2) %>%
    mutate(run_id = as.factor(run_id))

    # arrange(runcode)

allclimscens <- inclimdf %>% select(scenario) %>% unique

sceninfo <- allclimscens %>%
    separate(scenario,sep="-",into = c("vtag","ssp","policy"),remove = F) %>%
    mutate(
        budgtype = str_extract(policy,"^[A-Za-z][A-Za-z]*"),
        cbudget = as.numeric(str_extract(policy,"[0-9][0-9]*$"))
        )

climdf <- left_join(sceninfo, inclimdf) %>%
    filter(budgtype %in% c("Pb","Eb"))

# All run_id identifiers
allrunids <- climdf %>% select(run_id) %>% unique %>% 
    as.vector() %>% unlist() %>% as.character.factor()


# Read and calculate actual budgets

# Same caching scheme as inclimdf above, with a cache name specific to this script
redo_emisdf_cache <- FALSE
emiscachefname <- cache_path("cache_budgets_emisdf")
if (!file.exists(emiscachefname) || redo_emisdf_cache || file.mtime(emiscachefname) < file.mtime(emisfname)) {
    emisdf <- read.quitte(emisfname)
    saveRDS(emisdf, emiscachefname)
} else {
    emisdf <- readRDS(emiscachefname)
}

emisdf %>% select(variable) %>% unique %>% write.csv(table_path("varlist_emis"),row.names=F)


# Actual budgets calculation 

# cemisdf <- 
cemisdf <- emisdf %>%
    filter(variable %in% c(
        "Emissions|CO2|Biosphere",
        "Emissions|CO2|Fossil"
    )) %>%
    calc_addVariable(
        `Emissions|CO2` = "`Emissions|CO2|Biosphere` + `Emissions|CO2|Fossil`",
        unit = "MtCO2/yr", only.new = T
        ) %>%
    interpolate_missing_periods()

# Cumulated emissions, from 2020 inclusive: the value in 2020 is the emissions of 2020 itself.
cemisdf <- cemisdf %>%
    filter(period >= 2020) %>%
    filter(variable == "Emissions|CO2") %>%
    group_by(across(-c("period","value"))) %>%
    arrange(period, .by_group = TRUE) %>%
    mutate(value = cumsum(value)) %>%
    ungroup() %>%
    mutate(value = 1e-3*value, unit = "GtCO2") %>%
    tibble %>% mutate(variable = "Emissions|CO2|Cumulated") %>%
    bind_rows(cemisdf) 
    
actbudgdf <- cemisdf %>%
    filter(variable == "Emissions|CO2|Cumulated") %>%
    filter(period <= 2100) %>%
    group_by(scenario) %>%
    summarise(peakemi = round(max(value)))
    
cemisdf %>%
    left_join(., sceninfo) %>%
    left_join(., actbudgdf) %>%
    filter(budgtype %in% c("Eb","Pb")) %>%
    filter(variable == "Emissions|CO2|Cumulated") %>%
    filter(between(period,2020,2150)) %>%
    ggplot(aes(x = period, y = value, color = budgtype)) +
    geom_line() +
    geom_hline(aes(yintercept = cbudget)) +
    geom_vline(xintercept = 2100) +
    facet_wrap(~cbudget+peakemi) +
    # ylim(0,1500) +
    theme(axis.text.x = element_text(angle = -90, vjust = 1))
ggsave(figure_path("figure_actual_budgets"), width = 10, height = 10)
print(figure_path("figure_actual_budgets"))


cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("Pb")) %>%
    filter(variable %in% c("Emissions|CO2", "Emissions|GHG")) %>%
    filter(between(period,2020,2100)) %>%
    ggplot(aes(x = period, y = value, color = variable)) +
    geom_line() +
    geom_hline(aes(yintercept = cbudget)) +
    facet_wrap(~cbudget) +
    # ylim(0,1500) +
    theme(axis.text.x = element_text(angle = -90, vjust = 1))
ggsave(figure_path("figure_emissions_GHG_CO2"), width = 10, height = 10)

cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("Eb","Pb")) %>%
    filter(variable == "Emissions|CO2") %>%
    filter(between(period,2020,2100)) %>%
    ggplot(aes(x = period, y = value, color = budgtype)) +
    geom_line() +
    geom_hline(aes(yintercept = cbudget)) +
    facet_wrap(~cbudget) +
    # ylim(0,1500) +
    theme(axis.text.x = element_text(angle = -90, vjust = 1))
ggsave(figure_path("figure_emissions"), width = 10, height = 10)


cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("Eb","Pb")) %>%
    filter(variable == "Emissions|CO2|Cumulated") %>%
    filter(period == 2100) %>%
    select(cbudget,budgtype,value) %>%
    pivot_wider(names_from = budgtype, values_from = value) %>%
    arrange(cbudget) %>%
    print(n=100)

cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("Eb","Pb")) %>%
    filter(cbudget == 500) %>%
    filter(variable == "Emissions|CO2|Cumulated") %>%
    filter(between(period,2020,2100)) %>%
    ggplot(aes(x = period, y = value, color = budgtype)) +
    geom_line() +
    geom_hline(aes(yintercept = cbudget)) +
    facet_wrap(~cbudget) +
    ylim(0,1500) +
    theme(axis.text.x = element_text(angle = -90, vjust = 1))
ggsave(figure_path("figure_actual_budgets_just500"), width = 5, height = 5)




cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("NPi")) %>%
    filter(variable == "Emissions|CO2|Cumulated") %>%
    filter(period %in% seq(2030,2100,10)) %>%
    select(period,value)

cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("Eb","Pb")) %>%
    # filter(cbudget == 500) %>%
    filter(variable == "Emissions|CO2") %>%
    filter(between(period,2020,2099)) %>% #print(n=100)
    ggplot(aes(x = period, y = value, color = cbudget)) +
    geom_path() +
    geom_hline(aes(yintercept = 0)) +
    facet_wrap(~budgtype, ncol =1) +
    scale_color_distiller(palette = "Spectral", direction = 1) +
    # ylim(0,1500) +
    theme(axis.text.x = element_text(angle = -90, vjust = 1))
ggsave(figure_path("figure_emissions_CO2"), width = 5, height = 5)


cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("Pb")) %>%
    # filter(cbudget == 500) %>%
    filter(variable == "Emissions|CO2") %>%
    filter(period == 2100) %>%
    select(policy,value) %>% print(n=100000)
#print(n=100)

cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("Pb")) %>%
    filter(cbudget == 640) %>%
    filter(variable == "Emissions|CO2") %>%
    select(policy,period,value) %>%
    print(n=100)
    # filter(period == 2100) %>%




# unique(cemisdf$scenario)


# Prelim: Plot temperature outcomes ================================================================================

climdf %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    # filter(run_id == 78) %>%
    # filter(budgtype=="Pb") %>%
    # filter(cbudget==500) %>%
    ggplot(aes(x=period,y=value,
            lty = budgtype,            
            color=as.character(cbudget),subgroup=interaction(run_id,budgtype))
            ) +
    geom_path() +
    geom_hline(yintercept = c(1.5,1.6,1.7)) +
    geom_hline(yintercept = 1.6) +
    # facet_wrap(~variable+unit+budgtype)
    facet_wrap(~run_id) 
ggsave(figure_path("temperature_large"), height = 12, width = 12)

climdf %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    # filter(run_id == 78) %>%
    filter(budgtype=="Pb") %>%
    # filter(cbudget==500) %>%
    filter(between(period,2000,2100)) %>%
    left_join(labldf) %>%
    arrange(ord1,ord2) %>%
    mutate(runcode = fct_reorder(runcode,ord1)) %>%
    ggplot(aes(x=period,y=value,
            lty = budgtype,            
            color=as.numeric(cbudget),subgroup=interaction(run_id,budgtype,cbudget))
            ) +
    geom_path() +
    geom_hline(yintercept = c(1.5,1.6,1.7)) +
    geom_hline(yintercept = 1.6) +
    scale_color_distiller(palette = "Spectral", direction = 1) +
    # facet_wrap(~variable+unit+budgtype)
    facet_wrap(~runcode, nrow=2) 
ggsave(figure_path("temperature_budgets_Pb"), height = 6, width = 12)


climdf %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    # filter(run_id == 78) %>%
    filter(budgtype=="Pb") %>%
    # filter(cbudget==500) %>%
    filter(between(period,2000,2200)) %>%
    left_join(labldf) %>%
    arrange(ord1,ord2) %>%
    mutate(runcode = fct_reorder(runcode,ord1)) %>%
    ggplot(aes(x=period,y=value,
            lty = budgtype,            
            color=as.numeric(cbudget),subgroup=interaction(run_id,budgtype,cbudget))
            ) +
    geom_path() +
    geom_hline(yintercept = c(1.5,1.6,1.7)) +
    geom_hline(yintercept = 1.6) +
    geom_vline(xintercept = 2100) +
    scale_color_distiller(palette = "Spectral", direction = 1) +
    # facet_wrap(~variable+unit+budgtype)
    facet_wrap(~runcode, nrow=2) 
ggsave(figure_path("temperature_budgets_Pb_long"), height = 6, width = 12)


climdf %>% 
    select(variable) %>% 
    unique() %>% 
    write.csv(table_path("unique_climdf_variables"), row.names = FALSE)



climdf %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    # filter(run_id == 78) %>%
    filter(budgtype=="Pb") %>% 
    # mutate(cbudget = droplevels(cbudget))
    filter(cbudget>=700) %>% #select(cbudget) %>% unique
    ggplot(aes(x=period,y=value,
            lty = budgtype,
            color=as.character(cbudget),subgroup=interaction(run_id,budgtype))
            ) +
    geom_path() +
    geom_hline(yintercept = c(1.5,1.6,1.7)) +
    geom_hline(yintercept = 1.6) +
    # facet_wrap(~variable+unit+budgtype)
    facet_wrap(~run_id) 
ggsave(figure_path("temperature_Pb"), height = 12, width = 12)

# climdf %>%
#     filter(variable == "Surface Temperature (GSAT)") %>%
#     # filter(run_id == 78) %>%
#     filter(budgtype=="Pb") %>%
#     # filter(cbudget==500) %>%
#     filter(between(period,2000,2100)) %>%
#     left_join(labldf) %>%
#     arrange(ord1,ord2) %>%
#     mutate(runcode = fct_reorder(runcode,ord1)) %>%
#     print
#     # ggplot(aes(x=period,y=value,
#             lty = budgtype,            
#             color=as.numeric(cbudget),subgroup=interaction(run_id,budgtype,cbudget))
#             ) +
#     geom_path() +
#     geom_hline(yintercept = c(1.5,1.6,1.7)) +
#     geom_hline(yintercept = 1.6) +
#     scale_color_distiller(palette = "Spectral", direction = 1) +
#     # facet_wrap(~variable+unit+budgtype)
#     facet_wrap(~runcode, nrow=2) 
# ggsave(figure_path("temperature_scenarios"), height = 6, width = 12)



# Index calculations ========================================================================
# Will hold all "indexes", per-scenario values
allinds <- tibble()

# Peak warming and timing
gmtvarname <- "Surface Temperature (GSAT)"
temp <- climdf %>%
    filter(variable == gmtvarname) %>%
    group_by(across(-c("period","value"))) %>%
    slice(which.max(value)) %>%
    mutate(variable = "Peak warming", unit = "K")

# Peak warming
allinds <- temp %>% 
    select(-period) %>%
    bind_rows(allinds,.)

# Peak timing
allinds <- temp %>% 
    select(-value) %>%
    rename(value = period) %>%
    mutate(variable = "Peak warming year", unit = "year") %>%
    bind_rows(allinds,.)

# EoC warming
allinds <- climdf %>%
    filter(variable == gmtvarname) %>%
    filter(period == 2100) %>%
    select(-period) %>%
    mutate(variable = "EoC warming", unit = "K") %>%
    bind_rows(allinds,.)

# 2200 warming
if (2200 %in% climdf$period) {
    allinds <- climdf %>%
        filter(variable == gmtvarname) %>%
        filter(period == 2200) %>%
        select(-period) %>%
        mutate(variable = "Y2200 warming", unit = "K") %>%
        bind_rows(allinds,.)
}

#Overshoot-years
allinds <- climdf %>%
    filter(variable == gmtvarname) %>%
    mutate(os = value - 1.5) %>%
    mutate(os = ifelse(os < 0, 0, os)) %>%
    group_by(across(-c("value","os","period"))) %>%
    select(-value) %>%
    summarize(value = sum(os, na.rm=T)) %>%
    ungroup() %>%
    mutate(variable = "Overshoot-years 1.5", unit = "K yr") %>%
    bind_rows(allinds,.)

# Welfare metrics
welfdf <- read.csv(welffname)
welfdf <- left_join(sceninfo, welfdf) %>%
    filter(budgtype %in% c("Pb","Eb"))

# REMIND welfare
allinds <- welfdf %>%
    filter(variable == "Welfare|per capita|Real and undiscounted|Yearly|aggregated") %>%
    filter(period == 2100) %>%
    select(-period) %>%
    mutate(variable = "Welfare REMIND 2100", unit = "utils") %>%
    bind_rows(allinds,.)


# ========================================================================
# run_id characterization
chardf <- allinds %>%
    filter(cbudget == 500) %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    select(variable,unit,run_id,value) %>%
    calc_addVariable(
        `Relative reversibility` = "`Pb Peak warming`/`Eb EoC warming`",
        only.new = F)

climdf %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    # filter(run_id == 78) %>%
    # filter(budgtype=="Pb") %>%
    filter(cbudget==500) %>%
    ggplot(aes(x=period,y=value,
            lty = budgtype,
            color=as.character(cbudget),subgroup=interaction(run_id,budgtype))
            ) +
    geom_path() +
    geom_hline(yintercept = c(1.5,1.6,1.7)) +
    geom_hline(yintercept = 1.6) +
    # facet_wrap(~variable+unit+budgtype)
    facet_wrap(~run_id) 
ggsave(figure_path("temperature_Budg500"), height = 12, width = 12)

chardf %>%
    select(-unit) %>%
    pivot_wider(names_from = variable, values_from = value) %>%
    ggplot(aes(
        x = `Pb Peak warming`,
        y = `Relative reversibility`
    )) +
    geom_point()
ggsave(figure_path("dummy"))

# Criteria ================================================================================


# =========================================================================================
# CRiterion #4: Peak budget, remain below 2.0K, get to under 1.5K by EoC, remain under 1.5K until 2200, highest budget
# =========================================================================================
target_PW <- 2.0
target_EoCW <- 1.5
target_2200W <- 1.5

optinds <- allinds %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    select(cbudget,variable,run_id,value) %>%
    # arrange(run_id,cbudget) %>% 
    pivot_wider(names_from = variable, values_from = value) %>%
    group_by(run_id) %>% 
    filter(`Pb Peak warming` <= target_PW & `Pb EoC warming` <= target_EoCW & `Pb Y2200 warming` <= target_2200W) %>%
    group_by(run_id) %>% #write.csv(table_path("dummy"))
    slice(which.max(cbudget)) %>%
    rename(maxcbudget = cbudget)
    # print(n=1000)

# run_id's that didn't have any feasible budgets for this criterion
infesrunids <- setdiff(allrunids, optinds$run_id)

fulloptinds <- optinds %>%
    bind_rows(tibble(run_id = infesrunids))

tabvar <- "Pb Peak warming"
tabinddf <- allinds %>%
    filter(budgtype == "Pb") %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    filter(variable == tabvar) %>%
    select(cbudget,run_id,value)

nrunids <- length(allrunids)
fullmat <- matrix(
    nrow = nrunids, ncol = nrunids, 
    dimnames = list(planned = allrunids,actual = allrunids)
    )
usedbudgets <- vector("character",nrunids)
names(usedbudgets) <- allrunids

# ridplan <- allrunids[1]
# ridplan <- "168"
for (ridplan in allrunids) {
    usedbudgets[ridplan] <- fulloptinds$maxcbudget[fulloptinds$run_id == ridplan]
    usebudgind <- tabinddf[tabinddf$cbudget == usedbudgets[ridplan],c("run_id","value")]
    usebudgind$run_id <- as.character(usebudgind$run_id)
    if (is.na(usedbudgets[ridplan])) {
        fullmat[ridplan,] <- NA
    } else {
        fullmat[ridplan,usebudgind$run_id] <- usebudgind$value
    }
}
fullmat

# Proper labelling and ordering
lablmapping <- labldf %>%
    select(run_id,runcode) %>%
    deframe()

ordmat <- fullmat
rownames(ordmat) <- rownames(ordmat) %>%
    recode(!!!lablmapping)

colnames(ordmat) <- colnames(ordmat) %>%
    recode(!!!lablmapping)

ordmat <- ordmat[lablmapping,lablmapping]

usedbudgetdf <- usedbudgets %>%
    enframe(name = "run_id", value = "usedbudget") %>%
    left_join(labldf) %>%
    select(runcode,usedbudget)

as.data.frame(ordmat) %>%
    mutate(across(everything(), \(x) sprintf("%0.2f",x))) %>%    
    rownames_to_column("runcode") %>%
    left_join(usedbudgetdf) %>%
    relocate(usedbudget) %>%
    write.table(table_path("table_PkTemp_CR4"), sep = ";", quote = F, row.names = F)

# Add OS-Years
tabvar <- "Overshoot-years 1.5"
tabinddf <- allinds %>%
    filter(budgtype == "Pb") %>%
    # mutate(variable = paste0(budgtype," ",variable)) %>%
    filter(variable == tabvar) %>%
    select(cbudget,run_id,value)

nrunids <- length(allrunids)
fullmat <- matrix(
    nrow = nrunids, ncol = nrunids, 
    dimnames = list(planned = allrunids,actual = allrunids)
    )
usedbudgets <- vector("character",nrunids)
names(usedbudgets) <- allrunids

# ridplan <- allrunids[1]
# ridplan <- "168"
for (ridplan in allrunids) {
    usedbudgets[ridplan] <- fulloptinds$maxcbudget[fulloptinds$run_id == ridplan]
    usebudgind <- tabinddf[tabinddf$cbudget == usedbudgets[ridplan],c("run_id","value")]
    usebudgind$run_id <- as.character(usebudgind$run_id)
    if (is.na(usedbudgets[ridplan])) {
        fullmat[ridplan,] <- NA
    } else {
        fullmat[ridplan,usebudgind$run_id] <- usebudgind$value
    }
}
fullmat

# Proper labelling and ordering
lablmapping <- labldf %>%
    select(run_id,runcode) %>%
    deframe()

ordmat <- fullmat
rownames(ordmat) <- rownames(ordmat) %>%
    recode(!!!lablmapping)

colnames(ordmat) <- colnames(ordmat) %>%
    recode(!!!lablmapping)

ordmat <- ordmat[lablmapping,lablmapping]

usedbudgetdf <- usedbudgets %>%
    enframe(name = "run_id", value = "usedbudget") %>%
    left_join(labldf) %>%
    select(runcode,usedbudget)

as.data.frame(ordmat) %>%
    # mutate(across(everything(), \(x) sprintf("%0.2f",x))) %>%    
    rownames_to_column("runcode") %>%
    left_join(usedbudgetdf) %>%
    relocate(usedbudget) %>%
    write.table(table_path("table_OSYrs_CR4"), sep = ";", quote = F, row.names = F)


# Add welfare metrics
tabvar <- "Welfare REMIND 2100"
tabinddf <- allinds %>%
    filter(budgtype == "Pb") %>%
    # mutate(variable = paste0(budgtype," ",variable)) %>%
    filter(variable == tabvar) %>%
    select(cbudget,run_id,value)

welfall <- tabinddf %>% select(-run_id) 

nrunids <- length(allrunids)
usedbudgets <- vector("character",nrunids)
names(usedbudgets) <- allrunids
usedwelf <- vector("numeric",nrunids)
names(usedwelf) <- allrunids


# ridplan <- allrunids[1]
# ridplan <- "168"
for (ridplan in allrunids) {
    usedbudgets[ridplan] <- fulloptinds$maxcbudget[fulloptinds$run_id == ridplan]
    usedwelf[ridplan] <- welfall[tabinddf$cbudget == usedbudgets[ridplan],c("value")] %>% unlist
}

welfdf <- tibble(run_id = names(usedbudgets), usedbudgets = usedbudgets,usedwelf = usedwelf)

# Proper labelling and ordering
lablmapping <- labldf %>%
    select(run_id,runcode) %>%
    deframe()

welfdf <- welfdf %>%
    mutate(runcode = recode(run_id,!!!lablmapping)) %>%
    select(runcode,usedbudgets,usedwelf) 

rownames(welfdf) <- welfdf$runcode
welfdf <- welfdf[lablmapping,]
welfdf %>%
    write.table(table_path("table_Welfare_CR4"), sep = ";", quote = F, row.names = F)

usedbudgetdf
climdf %>%
    filter(budgtype == "Pb") %>%
    left_join(labldf) %>%
    left_join(usedbudgetdf) %>%
    mutate(runcode == as.character(runcode)) %>%
    arrange(ord1,ord2) %>%
    mutate(runcode = fct_reorder(runcode,ord1)) %>%
    filter(cbudget == usedbudget) %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    filter(between(period, 2020, 2100)) %>% #select(runcode,ord1,ord2) %>% print(n=1000)
    ggplot(aes(x=period,y=value)) +
    geom_path() +
    geom_hline(yintercept = c(1.5)) +
    facet_wrap(~runcode+cbudget, nrow = 2)
ggsave(figure_path("temperature_CR4"), height = 6, width = 12)


cemisdf %>%
    filter(budgtype == "Pb") %>%
    left_join(usedbudgetdf) %>%
    mutate(runcode == as.character(runcode)) %>%
    arrange(ord1,ord2) %>%
    mutate(runcode = fct_reorder(runcode,ord1)) %>%
    filter(cbudget == usedbudget) %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    filter(between(period, 2020, 2100)) %>% #select(runcode,ord1,ord2) %>% print(n=1000)
    ggplot(aes(x=period,y=value)) +
    geom_path() +
    geom_hline(yintercept = c(1.5)) +
    facet_wrap(~runcode+cbudget, nrow = 2)
ggsave(figure_path("temperature_CR4"), height = 6, width = 12)
