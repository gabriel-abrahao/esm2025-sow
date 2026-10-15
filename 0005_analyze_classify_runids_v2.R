require(tidyverse)
require(quitte)


source("common.R")
ensure_results_dirs()

# Budget to be used for the actual classification of the run_ids. 
# The indexes are calculated for all budgets, 
# but the tables and figures are made for this budget only 
usebudget <- 500

# Use this if you had to rerun the climate model and didn't run the coresows specific one
# TRUE: redo the filtering of the full climate output by the selected ensemble members
# and write the coresows file. FALSE: read the coresows file directly
REDO_CORESOWS_FILTER <- FALSE

sowclimfname <- climate_output_coresows_path()
fullclimfname <- climate_output_path()
emisfname <- harmonized_emissions_path()

# TRUE: read the full climate output (big file) and save it as a cache. FALSE: read the cache,
# unless it does not exist yet, then it is made. It is the same cache as in analyze_chanceconstrained_criteria_v2.R,
# with all regions and variables, so we filter it below
redo_clim_cache <- FALSE
climcachefname <- cache_path("cache_climate_output_fullar6")
if (!file.exists(climcachefname) || redo_clim_cache) {
    fullclimdf <- read.quitte(fullclimfname)
    saveRDS(fullclimdf,climcachefname)
} else {
    fullclimdf <- readRDS(climcachefname)
}
fullclimdf <- fullclimdf %>%
    filter(region == "World") %>%
    select(-region,-model,-climate_model) %>%
    mutate(run_id = paste0("full_",run_id))

if (REDO_CORESOWS_FILTER) {
    selmembers <- read.csv(selected_members_weights_path())$paraset_id
    read_csv_chunked(
        fullclimfname,
        DataFrameCallback$new(function(x, pos) filter(x, run_id %in% selmembers)),
        chunk_size = 1e5
    ) %>% write_csv(sowclimfname)
}

sowclimdf <- read.quitte(sowclimfname) %>%
    filter(region == "World") %>%
    select(-region,-model,-climate_model)

# This is OK because we added the full_ prefix to the run_id of the full climate output, 
# so there is no overlap with the coresows run_ids.
# Keeping them both makes it easier to operate on everything and filter later
inclimdf = bind_rows(fullclimdf,sowclimdf)

allclimscens <- inclimdf %>% select(scenario) %>% unique
allsowrunids <- sowclimdf %>% select(run_id) %>% unique
allfullrunids <- inclimdf %>% select(run_id) %>% unique


sceninfo <- allclimscens %>%
    separate(scenario,sep="-",into = c("vtag","ssp","policy"),remove = F) %>%
    mutate(
        budgtype = str_extract(policy,"^[A-Za-z][A-Za-z]*"),
        cbudget = as.numeric(str_extract(policy,"[0-9][0-9]*$"))
        )

climdf <- left_join(sceninfo, inclimdf) %>%
    filter(budgtype %in% c("Pb","Eb")) %>%
    filter(cbudget == usebudget)

inemisdf <- read.quitte(emisfname) %>%
    left_join(sceninfo,.) %>%
    filter(budgtype %in% c("Pb","Eb")) %>%
    filter(cbudget == usebudget)



# Index calculations ===========================================================
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

allinds %>% filter(variable == "Peak warming year")
allinds %>% filter(variable == "Peak warming")
allinds %>%
    filter(run_id == first(run_id)) 

write.table(allinds,table_path("allinds"), sep = ";", row.names = F, quote = F)
allinds %>%
    select(-unit,-model,-region) %>%
    pivot_wider(names_from = variable, values_from = value) %>%
    write.table(table_path("allinds_wide"), sep = ";", row.names = F, quote = F)
print(table_path("allinds_wide"))
# ========================================================================
# run_id characterization
chardf <- allinds %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    select(variable,unit,run_id,value) %>% 
    # select(variable) %>% unique
    calc_addVariable(
        `Relative reversibility` = "100*`Pb Peak warming`/`Pb EoC warming`",
        unit = "%",
        na.rm = F,only.new = F) %>%
    calc_addVariable(
        `Absolute reversibility` = "`Pb Peak warming`-`Pb EoC warming`",
        unit = "K",
        na.rm = F,only.new = F) %>%
    calc_addVariable(
        `Pb ZEC` = "`Pb Peak warming`-`Pb Net-zero warming`",
        unit = "K",
        na.rm = F,only.new = F) %>%
    calc_addVariable(
        `Pb Peak warming delay` = "`Pb Peak warming year`-`Pb Net-zero year`",
        unit = "years",
        na.rm = F,only.new = F)

chardf %>%
    filter(str_detect(run_id,"full_")) %>%
    calc_addVariable(
        `Pb Peak warming delay` = "`Pb Peak warming year`-`Pb Net-zero year`",
        unit = "years",
        na.rm = F,only.new = T) 

chardf <- chardf %>%
    mutate(subset = ifelse(str_detect(run_id,"full_"),"AR6-600","SOWs"))

pltdf <- chardf %>%
    select(-unit) %>%
    pivot_wider(names_from = variable, values_from = value) 
pltdf %>% 
    ggplot(aes(
        x = `Pb Peak warming`,
        y = `Relative reversibility`,
        label = run_id
    )) +
    geom_point(color = "grey40") +
    # geom_point(
    #     data = pltdf %>% filter(subset == "SOWs"),
    #     color = "red", shape = "x", size = 10
    #     ) +
    geom_label(
        data = pltdf %>% filter(subset == "SOWs")
        # color = "red", shape = "x", size = 10
        ) +        
    geom_hline(yintercept = 100) +
    geom_vline(xintercept = 1.5)
ggsave(figure_path("class_PkW_RelRev_runids"))


pltdf <- chardf %>%
    select(-unit) %>%
    pivot_wider(names_from = variable, values_from = value) 
pltdf %>% 
    ggplot(aes(
        x = `Pb Peak warming`,
        y = `Relative reversibility`,
        label = run_id
    )) +
    geom_point(color = "grey40") +
    # geom_point(
    #     data = pltdf %>% filter(subset == "SOWs"),
    #     color = "red", shape = "x", size = 10
    #     ) +
    geom_label(
        data = pltdf %>% filter(subset == "SOWs")
        # color = "red", shape = "x", size = 10
        ) +        
    geom_hline(yintercept = c(90,100,110,120,130,140)) +
    geom_vline(xintercept = c(1.5,1.6,1.7,1.8,1.9,2.0), color = "grey40")
ggsave(figure_path("class_PkW_RelRev"))
print(figure_path("class_PkW_RelRev"))

pltdf <- chardf %>%
    select(-unit) %>%
    pivot_wider(names_from = variable, values_from = value) 
pltdf %>% 
    ggplot(aes(
        x = `Pb Peak warming`,
        y = `Absolute reversibility`,
        label = run_id
    )) +
    geom_point(color = "grey40") +
    # geom_point(
    #     data = pltdf %>% filter(subset == "SOWs"),
    #     color = "red", shape = "x", size = 10
    #     ) +
    geom_label(
        data = pltdf %>% filter(subset == "SOWs")
        # color = "red", shape = "x", size = 10
        ) +        
    geom_hline(yintercept = c(0.1,0.3)) +
    geom_vline(xintercept = c(1.5,1.7), color = "grey40")
ggsave(figure_path("class_PkW_AbsRev"))
print(figure_path("class_PkW_AbsRev"))


# sowlabeller <- c(
#     "78"  = "wH_rL",
#     "158" = "wH_rL",
#     "168" = "wH_rL",
#     "213" = "wH_rL",
#     "224" = "wH_rL",
#     "267" = "wH_rL",
#     "320" = "wH_rL",
#     "324" = "wH_rL",
#     "355" = "wH_rL",
#     "396" = "wH_rL"
# )



# Here we classify the run_ids based on the indexes calculated above, 
# and assign a runcode to each run_id. 
dfruncodes <- chardf %>%
    select(-unit) %>%
    pivot_wider(names_from = variable, values_from = value) %>%
    filter(subset == "SOWs") %>%
    select(run_id,`Pb Peak warming`,`Absolute reversibility`) %>%
    arrange(`Pb Peak warming`) %>%
    mutate(pwrank = row_number()) %>%
    arrange(`Absolute reversibility`) %>%
    mutate(arrank = row_number()) %>%
    mutate(runcode = paste0("P",pwrank,"_R",arrank)) %>%
    select(run_id,runcode)
write.csv(dfruncodes,runcode_path("PbPW_AbsRev"),row.names = F)
print(dfruncodes)
print(runcode_path("PbPW_AbsRev"))

# Extra plots =======================================================================

pltdf <- chardf %>%
    select(-unit) %>%
    pivot_wider(names_from = variable, values_from = value) %>%
    left_join(dfruncodes) 

write.table(pltdf,table_path("pltdf"), sep = ";", row.names = F, quote = F)

pltdf %>% 
    ggplot(aes(
        x = `Pb Peak warming`,
        y = `Absolute reversibility`,
        label = runcode
    )) +
    geom_point(color = "grey40") +
    # geom_point(
    #     data = pltdf %>% filter(subset == "SOWs"),
    #     color = "red", shape = "x", size = 10
    #     ) +
    geom_label(
        data = pltdf %>% filter(subset == "SOWs")
        # color = "red", shape = "x", size = 10
        ) +        
    geom_hline(yintercept = c(0), color = "grey40") +
    geom_vline(xintercept = c(1.5), color = "grey40")    
    # geom_hline(yintercept = c(0.1,0.3)) +
    # geom_vline(xintercept = c(1.5,1.7), color = "grey40")
ggsave(figure_path("class_PkW_AbsRev_runcodes"))
print(figure_path("class_PkW_AbsRev_runcodes"))

pltdf %>% 
    ggplot(aes(
        x = `Pb Peak warming`,
        y = `Pb ZEC`,
        label = runcode
    )) +
    geom_point(color = "grey40") +
    # geom_point(
    #     data = pltdf %>% filter(subset == "SOWs"),
    #     color = "red", shape = "x", size = 10
    #     ) +
    geom_label(
        data = pltdf %>% filter(subset == "SOWs")
        # color = "red", shape = "x", size = 10
        ) +        
    geom_hline(yintercept = c(0), color = "grey40") +
    geom_vline(xintercept = c(1.5), color = "grey40")    
    # geom_hline(yintercept = c(0.1,0.3)) +
    # geom_vline(xintercept = c(1.5,1.7), color = "grey40")
ggsave(figure_path("class_PkW_ZEC_runcodes"))
print(figure_path("class_PkW_ZEC_runcodes"))

pltdf %>% 
    ggplot(aes(
        x = `Pb Peak warming`,
        y = `Pb Peak warming delay`,
        label = runcode
    )) +
    geom_point(color = "grey40") +
    # geom_point(
    #     data = pltdf %>% filter(subset == "SOWs"),
    #     color = "red", shape = "x", size = 10
    #     ) +
    geom_label(
        data = pltdf %>% filter(subset == "SOWs")
        # color = "red", shape = "x", size = 10
        ) +        
    geom_hline(yintercept = c(0), color = "grey40") +
    geom_vline(xintercept = c(1.5), color = "grey40")    
    # geom_hline(yintercept = c(0.1,0.3)) +
    # geom_vline(xintercept = c(1.5,1.7), color = "grey40")
ggsave(figure_path("class_PkW_Wdelay_runcodes"))
print(figure_path("class_PkW_Wdelay_runcodes"))

pltdf %>% 
    ggplot(aes(
        x = `Pb Peak warming delay`,
        y = `Pb ZEC`,
        label = runcode
    )) +
    geom_point(color = "grey40") +
    # geom_point(
    #     data = pltdf %>% filter(subset == "SOWs"),
    #     color = "red", shape = "x", size = 10
    #     ) +
    geom_label(
        data = pltdf %>% filter(subset == "SOWs")
        # color = "red", shape = "x", size = 10
        ) +        
    # geom_hline(yintercept = c(0), color = "grey40") +
    geom_vline(xintercept = c(1.5), color = "grey40")    
    # geom_hline(yintercept = c(0.1,0.3)) +
    # geom_vline(xintercept = c(1.5,1.7), color = "grey40")
ggsave(figure_path("class_Wdelay_PbZEC_runcodes"))
print(figure_path("class_Wdelay_PbZEC_runcodes"))


# Climate =============================================================== 
# Forster et al. (https://essd.copernicus.org/articles/17/2641/2025/#section7)
# 2015-2024 (inclusive) is 1.24 [1.11-1.35, very likely range] rel. to 1850-1900
# 2005-2024 (inclusive) is 1.09 [0.93-1.20, very likely range] rel. to 1850-1900
forster_start_year <- 2015
forster_end_year <- 2024
forster_warming_median <- 1.24
forster_warming_lower <- 1.11
forster_warming_upper <- 1.35


left_join(sceninfo, sowclimdf) %>%
   filter(variable == "Surface Temperature (GSAT)") %>%
   filter(period <= 2100) %>%
    # filter(run_id == 78) %>%
    # filter(budgtype!="Eb") %>%
    filter(cbudget==usebudget) %>%
    left_join(dfruncodes) %>%
    # filter(between(period,2000,2100)) %>%
    ggplot(aes(x=period,y=value,
            color=runcode,subgroup=interaction(run_id,budgtype))
            ) +
    geom_path() +
    geom_hline(yintercept = c(1.5), lty=2) +
    # geom_vline(xintercept = 2015, lty=2) +
    geom_segment(
        x = forster_start_year, xend = forster_end_year,
        y = forster_warming_upper, yend = forster_warming_upper,
        color = "black", size = 0.5
    ) +
    geom_segment(
        x = forster_start_year, xend = forster_end_year,
        y = forster_warming_lower, yend = forster_warming_lower,
        color = "black", size = 0.5
    ) +
    geom_segment(
        x = forster_start_year+3, xend = forster_end_year-3,
        y = forster_warming_median, yend = forster_warming_median,
        color = "black", size = 0.5
    ) +
    geom_segment(
        x = (forster_end_year+forster_start_year)/2, xend = (forster_end_year+forster_start_year)/2,
        y = forster_warming_lower, yend = forster_warming_upper,
        color = "black", size = 0.5
    ) +
    # geom_point(
    #     x = (forster_end_year+forster_start_year)/2,
    #     y = forster_warming_median,
    #     shape = "+",
    #     color = "black", size = 5.0
    # ) +
    # ylim(1.0,1.5) +
    # facet_wrap(~variable+unit+budgtype)
    facet_wrap(~variable+unit+budgtype) 
ggsave(figure_path("temperature_single_500"), height = 5, width = 10)
print(figure_path("temperature_single_500"))


# Probability distributions ==========================================================================

longdf <- pltdf %>%
    mutate(run_id = ifelse(!is.na(runcode), runcode, run_id)) %>%
    select(-runcode) %>%
    pivot_longer(3:22, names_to = "variable")

usevar <- "Pb EoC warming"
usedata <- longdf %>% 
    filter(variable == usevar) 

usedata %>%
    ggplot(aes(value)) +
    geom_histogram(binwidth = 0.1) +
    labs(x = usevar, y = "Count") +
    geom_vline(
        xintercept = filter(usedata,subset=="SOWs")$value
    ) +
    geom_text(data = filter(usedata,subset=="SOWs"),
        aes(
            x = value,
            label = run_id,
            y = 40
            ),
            angle = -90, vjust = "bottom", position = "jitter"
            
    )
ggsave(figure_path("prob_hist_pkwarm_500"), height = 5, width = 10)

cdf <- ecdf(filter(usedata,subset!="SOWs")$value)
cdf(2)
percdf <- longdf %>%
    filter(variable == usevar) %>%
    filter(subset ==  "SOWs") %>%
    mutate(dist = cdf(value)) %>%
    mutate(perc = round(100*dist,2)) %>%
    write.csv(table_path("prob_table_SOWs_500"), row.names = F)


usedata %>%
    filter(subset != "SOWs") %>%
    ggplot(aes(value)) +
    stat_ecdf(color = "black", size =1) + 
    labs(x = usevar, y = "CDF") +
    geom_hline(
        yintercept = percdf$dist,
        color = "grey50"
    ) +
    geom_label(data = percdf,
        aes(
            y = dist,
            label = run_id,
            x = 1.5
            ),
            vjust = "bottom", 
            position = "jitter"
            
    )
ggsave(figure_path("prob_ecdf_pkwarm_500"), height = 5, width = 10)


# x.gam<-rgamma(200,rate=0.5,shape=3.5) ## sampling from a gamma distribution with λ=0.5 (scale parameter12) and α=3.5 (shape parameter)
x.gam <- filter(usedata,subset != "SOWs")$value
med.gam<-mean(x.gam) ## sample mean
var.gam<-var(x.gam) ## sample variance
l.est<-med.gam/var.gam ## lambda estimate (corresponds to rate)
a.est<-((med.gam)^2)/var.gam ## alfa estimate

dgamma(x.gam, scale=l.est, shape=a.est)

png(figure_path("dummy"))
curve(dgamma(x.gam, scale=l.est, shape=a.est),from=0, to=2, main="Gamma distribution")
dev.off()

# install.packages(c("fitdistrplus", "stats4", "survival", "actuar", "distrMod"))
# renv::install("MASS@7.3-60")
require(fitdistrplus)
require(stats4)
require(MASS)
require(survival)
require(actuar)
require(distrMod)

obs <- filter(usedata,subset != "SOWs")$value
gamma.f <- fitdist(obs, "gamma") 

png(figure_path("dummy"))
par(mfrow = c(2, 2), mar = c(4, 4, 2, 1))
fw <- fitdist(obs, "weibull")
fg <- fitdist(obs, "gamma")
fln <- fitdist(obs, "lnorm")
# plot.legend <- c("Weibull", "lognormal", "gamma")
plot.legend <- c("lognormal", "gamma")
denscomp(list(fln, fg), legendtext = plot.legend)
qqcomp(list(fln, fg), legendtext = plot.legend)
cdfcomp(list(fln, fg), legendtext = plot.legend)
ppcomp(list(fln, fg), legendtext = plot.legend)
dev.off()

summary(fg)
summary(fln)


