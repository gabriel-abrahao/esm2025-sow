require(tidyverse)
require(quitte)
require(ggstance) # For vertical dodge
require(ggrepel)

climfname <- "climate_output_coresows_v2.csv"
emisfname <- "emissions_climate_output_coresows_v2.csv"
lablfname <- "runcode_PbPW_AbsRev.csv"
welffname <- "welfare_v2.csv"
scenstable <- read.csv2("table_PkTemp_CR4_v2.csv") %>% select(usedbudget, runcode)

ccpscen <- "E25v01-SSP2-Pb760"

ar6data <- readRDS("nenaklims_db_world.rds")


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


# Index calculations ==================================================================
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

# Emissions-related indexes
cemisdf <- inemisdf %>%
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

# Net-zero timing
allinds <- cemisdf %>%
    filter(variable == "Emissions|CO2") %>%
    # select(budgtype,period,value) %>%      #REMOVE!!!!!!!
    group_by(across(-c("period","value"))) %>%    
    slice(which.min(abs(value))) %>%
    mutate(variable = "Net-zero year", unit = "year") %>%
    expand_grid(run_id = allfullrunids$run_id) %>%
    select(-value) %>%
    rename(value = period) %>%
    bind_rows(allinds,.)

# Peak cumulative emissions and timing
temp <- cemisdf %>%
    filter(variable == "Emissions|CO2|Cumulated") %>%
    # select(budgtype,period,value) %>%      #REMOVE!!!!!!!
    group_by(across(-c("period","value"))) %>%
    slice(which.max(value)) 
# Max cum. emisisons
allinds <- temp %>% 
    select(-period)  %>%
    mutate(variable = "Max cum. emissions", unit = "GtCO2") %>%
    expand_grid(run_id = allfullrunids$run_id) %>%
    bind_rows(allinds,.)

# Max cum. emisisons timing, should be the same as net-zero
allinds <- temp %>% 
    select(-value) %>%
    rename(value = period) %>%
    mutate(variable = "Max cum. emissions year", unit = "year") %>%
    expand_grid(run_id = allfullrunids$run_id) %>%
    bind_rows(allinds,.)

# Combined emissions and temperature indexes
# Net-zero warming
allinds <- allinds %>%
    filter(variable == "Net-zero year") %>%
    filter(run_id == first(run_id)) %>%
    rename(selyear = value) %>%
    # select(-variable,-unit) %>%
    select(scenario,selyear) %>%
    left_join(.,climdf %>% filter(variable == gmtvarname)) %>%
    # select(budgtype,period,value,run_id,selyear) %>%      #REMOVE!!!!!!!
    filter(period == selyear) %>%
    select(-selyear,-period) %>%
    mutate(variable = "Net-zero warming", unit = "K") %>%
    bind_rows(allinds,.)


# Plots selected scenarios climate ==================================================================
climdf %>%
    filter(scenario %in% paste0("E25v01-SSP2-Pb",scenstable$usedbudget)) %>%
    left_join(., scenstable, by = c(cbudget = "usedbudget")) %>%
    filter(variable == "Surface Temperature (GSAT)") %>%
    left_join(., rename(labldf,climruncode = runcode), by = c("run_id")) %>%
    arrange(ord1,ord2) %>%
    # mutate(runcode = fct_reorder(runcode,ord1)) %>%
    # mutate(runcode = as.factor(runcode)) %>%
    mutate(climruncode = fct_reorder(climruncode,ord1)) %>%
    filter(period <= 2100) -> pltdata
pltdata$runcode <- factor(pltdata$runcode, levels(pltdata$climruncode))
pltdata %>%
    ggplot(aes(x = period, y = value, color = climruncode)) +
    geom_line(data = filter(pltdata,runcode == climruncode), color = "black", size = 1.2) +
    geom_line() +
    geom_hline(yintercept = 1.5) +
    xlim(2020,2100) +
    facet_wrap(~runcode+cbudget, ncol = 5) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 0.5)) +
    labs(y = "GSAT [K]", x = "", color = "Climate SOW")
ggsave("figure_temperature_SOWs_all.png",height = 5, width = 7)

usecode <- "P10_R1"
pltdata %>%
    filter(runcode == usecode) %>%
    ggplot(aes(x = period, y = value, color = climruncode)) +
    geom_line(data = filter(pltdata,runcode == climruncode, runcode == usecode), color = "black", size = 1.2) +
    geom_line() +
    # geom_hline(yintercept = 1.5) +
    geom_vline(xintercept = 2025, lty = 2) +
    geom_segment(x = 2015, xend = 2024, y = 1.0, yend = 1.0, lwd = 1, color = "red") +
    geom_segment(x = 2015, xend = 2024, y = 1.5, yend = 1.5, lwd = 1, color = "red") +
    geom_segment(x = 2020, xend = 2020, y = 1.0, yend = 1.5, lwd = 1, color = "red") +
    geom_point(x = 2020, y = 1.22, size = 2, color = "red") +
    # geom_errorbar(ymin = 1.0, ymax = 1.5, x = 2020) + 
    # annotate(
    #     "rect", xmin = 2015, xmax = 2024, ymin = 1.0, ymax = 1.5,
    #     alpha = 0, color = "red", lwd = 1
    #     ) + 
    facet_wrap(~runcode+cbudget, ncol = 5) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 0.5)) +
    labs(y = "GSAT [K]", x = "", color = "Climate SOW")
ggsave("figure_temperature_SOWs_520.png",height = 5, width = 7)



# Plots selected scenarios emissions ==================================================================
options(width = 160)
cemisdf %>%
    left_join(., sceninfo) %>%
    filter(scenario %in% paste0("E25v01-SSP2-Pb",scenstable$usedbudget)) %>%
    left_join(., scenstable, by = c(cbudget = "usedbudget")) %>%
    filter(variable == "Emissions|CO2") %>%
    left_join(., labldf) %>%
    arrange(ord1,ord2) %>%
    mutate(runcode = fct_reorder(runcode,ord1)) %>%
    filter(period <= 2100) %>%
    ggplot(aes(x = period, y = value)) +
    geom_line() +
    geom_hline(yintercept = 0) +
    facet_wrap(~runcode+cbudget, ncol = 5) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 0.5)) +
    labs(y = "Emissions|CO2 [MtCO2/yr]", x = "")
ggsave("figure_emissions_SOWs.png",height = 5, width = 7)

cemisdf %>%
    left_join(., sceninfo) %>%
    filter(scenario %in% paste0("E25v01-SSP2-Pb",scenstable$usedbudget)) %>%
    left_join(., scenstable, by = c(cbudget = "usedbudget")) %>%
    filter(variable == "Emissions|CO2|Cumulated") %>%
    left_join(., labldf) %>%
    arrange(ord1,ord2) %>%
    mutate(runcode = fct_reorder(runcode,ord1)) %>%
    filter(period <= 2100) %>%
    ggplot(aes(x = period, y = value)) +
    geom_line() +
    geom_hline(yintercept = 0) +
    facet_wrap(~runcode+cbudget, ncol = 5) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 0.5)) +
    labs(y = "Emissions|CO2|Cumulated [GtCO2]", x = "")
ggsave("figure_cumemissions_SOWs.png",height = 5, width = 7)

pltdata <- cemisdf %>%
    left_join(., sceninfo) %>%
    filter(scenario %in% paste0("E25v01-SSP2-Pb",scenstable$usedbudget)) %>%
    left_join(., scenstable, by = c(cbudget = "usedbudget")) %>%
    filter(variable == "Emissions|CO2") %>%
    left_join(., labldf) %>%
    arrange(ord1,ord2) %>%
    mutate(runcode = fct_reorder(runcode,ord1)) %>%
    filter(period <= 2100) 
pltdata %>%
    ggplot(aes(x = period, y = value, color = runcode)) +
    geom_line() +
    geom_label(data = filter(pltdata,period == 2100), aes(label = runcode), 
               position = position_dodge(width = 0.5), 
               vjust = 0.5, hjust = -0.1, size = 3) +
    geom_hline(yintercept = 0) +
    xlim(2020,2110) +
    ylim(-25000,50000) +
    # facet_wrap(~runcode+cbudget, ncol = 5) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 0.5)) +
    labs(y = "Emissions|CO2 [MtCO2/yr]", x = "")
ggsave("figure_emissions_SOWs_single.png",height = 5, width = 7)

# Carbon prices


# Chance Constrained Programming plots ==================================================================
# Criterion CCP1 
# No harmonization, Peak budget, C1-like: 67% under 2K peak warming, 50% under 1.5K EoC warming
# That's scenario E25v01-SSP2-Pb760
cemisdf %>%
    filter(scenario == ccpscen) %>%
    mutate(runcode = "Chance Constrained Prog.") %>%
    left_join(., sceninfo) %>%
    # filter(scenario %in% paste0("E25v01-SSP2-Pb",scenstable$usedbudget)) %>%
    # left_join(., scenstable, by = c(cbudget = "usedbudget")) %>%
    filter(variable == "Emissions|CO2") %>%
    # left_join(., labldf) %>%
    # arrange(ord1,ord2) %>%
    # mutate(runcode = fct_reorder(runcode,ord1)) %>%
    filter(period <= 2100) %>%
    ggplot(aes(x = period, y = value)) +
    geom_line() +
    geom_hline(yintercept = 0) +
    ylim(-20000,40000) +
    facet_wrap(~runcode+cbudget, ncol = 5) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 0.5)) +
    labs(y = "Emissions|CO2 [MtCO2/yr]", x = "")
ggsave("figure_emissions_CCP1.png",height = 5, width = 3)


# AR6 Plots ==================================================================
ar6data %>% select(variable) %>% unique %>% write.csv("varlist_ar6.csv",row.names=F)


compat <- ar6data %>%
 filter(variable == "AR6 climate diagnostics|Surface Temperature (GSAT)|MAGICCv7.5.3|67.0th Percentile") %>%
 filter(period == 2100) %>%
 filter(value <= 1.5) %>%
 select(scenario,model) %>%
 mutate(iscompat = 1)

ar6data %>% 
    filter(variable == "Emissions|CO2") %>%
    filter(scenario %in% compat$scenario) %>%
    ggplot(aes(x = period, y = value, group = interaction(scenario,model))) +
    geom_line(color = "grey40")+
    geom_hline(yintercept = 0) +
    xlim(2020,2110) +
    ylim(-25000,50000) +
    # facet_wrap(~runcode+cbudget, ncol = 5) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 0.5)) +
    labs(y = "Emissions|CO2 [MtCO2/yr]", x = "")
ggsave("figure_emissions_AR6_single.png",height = 5, width = 7)


# Combined ===================================================================
pltdata <- cemisdf %>%
    left_join(., sceninfo) %>%
    filter(scenario %in% paste0("E25v01-SSP2-Pb",scenstable$usedbudget)) %>%
    left_join(., scenstable, by = c(cbudget = "usedbudget")) %>%
    filter(variable == "Emissions|CO2") %>%
    left_join(., labldf) %>%
    arrange(ord1,ord2) %>%
    mutate(runcode = fct_reorder(runcode,ord1)) %>%
    filter(period <= 2100) 

far6data <- ar6data %>% 
    filter(variable == "Emissions|CO2") %>%
    filter(category %in% c("C1","C2")) %>%
    filter(project == "AR6 v1.1")

pltdata %>%
    ggplot(aes(x = period, y = value, color = runcode)) +
    geom_hline(yintercept = 0) +
    geom_line(
        aes(x = period, y = value, group = interaction(scenario,model)),
        data = far6data,
        color = "grey40", size = 0.1
    ) +
    geom_line(size = 1.5) +
    # geom_label(data = filter(pltdata,period == 2100), aes(label = runcode), 
    #         #    position = position_jitter(width = 0, height = 1000),             
    #         #    position = position_dodge(width = 1), 
    #         #    position = position_dodgev(height = 5000), # from the ggstance package
    #            vjust = 0.5, hjust = -0.1, size = 3) +
    geom_label_repel(data = filter(pltdata,period == 2100), aes(label = runcode),
            direction = "y", max.overlaps = 9,
            nudge_x = 10,
            vjust = 0.5, hjust = -0.1, size = 3.5) +
    xlim(2020,2110) +
    ylim(-25000,50000) +
    # facet_wrap(~runcode+cbudget, ncol = 5) +
    # theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 0.5)) +
    theme(legend.position = "none") +
    theme(text = element_text(size = 15)) +
    # theme_classic() +
    labs(y = "Emissions|CO2 [MtCO2/yr]", x = "")
ggsave("figure_emissions_COMBINED_single.png",height = 5, width = 7, scale = 1, dpi = 500)
# ggsave("figure_emissions_COMBINED_single.png",height = 5, width = 7)
