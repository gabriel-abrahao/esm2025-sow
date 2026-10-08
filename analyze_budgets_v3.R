require(tidyverse)
require(quitte)


climfname <- "climate_output_coresows_v2.csv"
emisfname <- "emissions_climate_output_coresows_v2.csv"
lablfname <- "runcode_PbPW_AbsRev.csv"
welffname <- "welfare_v2.csv"


inclimdf <- read.quitte(climfname) %>%
    filter(region == "World") %>%
    select(-region,-model,-climate_model)

inclimdf %>% select(variable) %>% unique %>% write.csv("varlist_clim.csv",row.names=F)

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
emisdf <- read.quitte(emisfname)

emisdf %>% select(variable) %>% unique %>% write.csv("varlist_emis.csv",row.names=F)


# Actual budgets calculation 

# cemisdf <- 
cemisdf <- emisdf %>%
    filter(variable %in% c(
        "Emissions|CO2|MAGICC AFOLU",
        "Emissions|CO2|MAGICC Fossil and Industrial"
    )) %>%
    calc_addVariable(
        `Emissions|CO2` = "`Emissions|CO2|MAGICC AFOLU` + `Emissions|CO2|MAGICC Fossil and Industrial`",
        unit = "MtCO2/yr", only.new = T
        ) %>%
    interpolate_missing_periods()

cemisdf <- cemisdf %>%
    filter(period >= 2020) %>%
    calcCumulatedDiscount(nameVar = "Emissions|CO2", discount = 0) %>%
    mutate(value = 1e-3*value, unit = "GtCO2") %>%
    tibble %>% mutate(variable = "Emissions|CO2|Cumulated") %>%
    bind_rows(cemisdf) 
    

cemisdf %>%
    left_join(., sceninfo) %>%
    filter(budgtype %in% c("Eb","Pb")) %>%
    filter(variable == "Emissions|CO2|Cumulated") %>%
    filter(between(period,2020,2100)) %>%
    ggplot(aes(x = period, y = value, color = budgtype)) +
    geom_line() +
    geom_hline(aes(yintercept = cbudget)) +
    facet_wrap(~cbudget) +
    ylim(0,1500) +
    theme(axis.text.x = element_text(angle = -90, vjust = 1))
ggsave("figure_actual_budgets.png", width = 10, height = 10)

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
ggsave("figure_emissions_GHG_CO2.png", width = 10, height = 10)

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
ggsave("figure_emissions.png", width = 10, height = 10)


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
ggsave("figure_actual_budgets_just500.png", width = 5, height = 5)




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
ggsave("figure_emissions_CO2.png", width = 5, height = 5)


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
ggsave("temperature_large.png", height = 12, width = 12)

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
ggsave("temperature_budgets_Pb.png", height = 6, width = 12)


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
ggsave("temperature_budgets_Pb_long.png", height = 6, width = 12)



climdf %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    # filter(run_id == 78) %>%
    filter(budgtype=="Eb") %>%
    # filter(cbudget==500) %>%
    filter(period>=2000) %>%
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
ggsave("temperature_budgets_Eb.png", height = 6, width = 12)

climdf %>% 
    select(variable) %>% 
    unique() %>% 
    write.csv("unique_climdf_variables.csv", row.names = FALSE)



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
ggsave("temperature_Pb.png", height = 12, width = 12)

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
# ggsave("temperature_scenarios.png", height = 6, width = 12)



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
    filter(period == 2099) %>%
    select(-period) %>%
    mutate(variable = "EoC warming", unit = "K") %>%
    bind_rows(allinds,.)

# 2200 warming
if (2199 %in% climdf$period) {
    allinds <- climdf %>%
        filter(variable == gmtvarname) %>%
        filter(period == 2199) %>%
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
ggsave("temperature_Budg500.png", height = 12, width = 12)

chardf %>%
    select(-unit) %>%
    pivot_wider(names_from = variable, values_from = value) %>%
    ggplot(aes(
        x = `Pb Peak warming`,
        y = `Relative reversibility`
    )) +
    geom_point()
ggsave("dummy.png")

# Criteria ================================================================================
# =========================================================================================
# CRiterion #1: Peak budget, remain below 1.7K and get to under 1.5K by EoC, highest budget
# =========================================================================================
target_PW <- 1.7
target_EoCW <- 1.5

optinds <- allinds %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    select(cbudget,variable,run_id,value) %>%
    # arrange(run_id,cbudget) %>% 
    pivot_wider(names_from = variable, values_from = value) %>%
    group_by(run_id) %>%
    filter(`Pb Peak warming` <= target_PW & `Pb EoC warming`  <= target_EoCW) %>%
    group_by(run_id) %>% #write.csv("dummy.csv")
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

# require(formattable)
# #Set a few color variables to make our table more visually appealing
# customGreen0 = "#DeF7E9"
# customGreen = "#71CA97"
# customRed = "#ff7f7f"

# colorlow = "#fdaaaa"
# colorhig = "#ff0000"

# as.data.frame(fullmat) %>%
#     rownames_to_column() %>%
#     formattable(.,list(
#         `78` = color_tile(colorlow, colorhig)
#     ))

# as.data.frame(fullmat) %>%
#     rownames_to_column() %>%
#     formattable(.,setNames(lapply(1:nrunids,\(x) color_tile(colorlow, colorhig)),allrunids))

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
    write.table("table_PkTemp_CR1_v2.csv", sep = ";", quote = F, row.names = F)

# as.data.frame(ordmat) %>%
#     rownames_to_column() %>%
#     formattable(.,setNames(lapply(1:nrunids,\(x) color_tile(colorlow, colorhig)),lablmapping))


# =========================================================================================
# CRiterion #2 EoC budget, get to under 1.5K by EoC, highest budget
# =========================================================================================

# target_PW <- 10000
target_EoCW <- 1.5

optinds <- allinds %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    select(cbudget,variable,run_id,value) %>%
    # arrange(run_id,cbudget) %>% 
    pivot_wider(names_from = variable, values_from = value) %>%
    group_by(run_id) %>%
    # filter(`Pb Peak warming` <= target_PW & `Pb EoC warming`  <= target_EoCW) %>%
    filter(`Eb EoC warming` <= target_EoCW) %>%    
    group_by(run_id) %>% #write.csv("dummy.csv")
    slice(which.max(cbudget)) %>%
    rename(maxcbudget = cbudget)

write.table(optinds, "dummy.csv", sep = ";", quote = F, row.names = F)

# run_id's that didn't have any feasible budgets for this criterion
infesrunids <- setdiff(allrunids, optinds$run_id)

fulloptinds <- optinds %>%
    bind_rows(tibble(run_id = infesrunids))

# tabvar <- "Eb EoC warming"
tabvar <- "Eb Peak warming"
tabinddf <- allinds %>%
    filter(budgtype == "Eb") %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    filter(variable == tabvar) %>%
    select(cbudget,run_id,value)

write.table(tabinddf, "dummy.csv", sep = ";", quote = F, row.names = F)


nrunids <- length(allrunids)
fullmat <- matrix(
    nrow = nrunids, ncol = nrunids, 
    dimnames = list(planned = allrunids,actual = allrunids)
    )
usedbudgets <- vector("character",nrunids)
names(usedbudgets) <- allrunids

# ridplan <- allrunids[6]
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
    write.table(paste0("table_",str_replace_all(tabvar," ","_"),"_CR2.csv"), sep = ";", quote = F, row.names = F)

# =========================================================================================
# CRiterion #3: Peak budget, remain below 2.0K and get to under 1.5K by EoC, highest budget
# =========================================================================================
target_PW <- 2.0
target_EoCW <- 1.5


optinds <- allinds %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    select(cbudget,variable,run_id,value) %>%
    # arrange(run_id,cbudget) %>% 
    pivot_wider(names_from = variable, values_from = value) %>%
    group_by(run_id) %>%
    filter(`Pb Peak warming` <= target_PW & `Pb EoC warming`  <= target_EoCW) %>%
    group_by(run_id) %>% #write.csv("dummy.csv")
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
    write.table("table_PkTemp_CR3_v2.csv", sep = ";", quote = F, row.names = F)

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
    write.table("table_OSYrs_CR3_v2.csv", sep = ";", quote = F, row.names = F)


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
    write.table("table_Welfare_CR3_v2.csv", sep = ";", quote = F, row.names = F)



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
    group_by(run_id) %>% #write.csv("dummy.csv")
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
    write.table("table_PkTemp_CR4_v2.csv", sep = ";", quote = F, row.names = F)

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
    write.table("table_OSYrs_CR4_v2.csv", sep = ";", quote = F, row.names = F)


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
    write.table("table_Welfare_CR4_v2.csv", sep = ";", quote = F, row.names = F)

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
ggsave("temperature_CR4.png", height = 6, width = 12)


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
ggsave("temperature_CR4.png", height = 6, width = 12)
