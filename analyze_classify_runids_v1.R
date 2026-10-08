require(tidyverse)
require(quitte)


sowclimfname <- "climate_output_coresows_v1.csv"
fullclimfname <- "climate_output_fullar6_v1.csv"
emisfname <- "emissions_climate_output_coresows_v1.csv"

# fullclimdf <- read.quitte(fullclimfname) %>%
#     filter(region == "World") %>%
#     select(-region,-model,-climate_model)
# saveRDS(fullclimdf,"cache_fullclimdf.rds")
fullclimdf <- readRDS("cache_fullclimdf.rds") %>%
    mutate(run_id = paste0("full_",run_id))

sowclimdf <- read.quitte(sowclimfname) %>%
    filter(region == "World") %>%
    select(-region,-model,-climate_model)

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
    filter(cbudget == 500)

inemisdf <- read.quitte(emisfname) %>%
    left_join(sceninfo,.) %>%
    filter(budgtype %in% c("Pb","Eb")) %>%
    filter(cbudget == 500)



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

write.table(allinds,"allinds.csv", sep = ";", row.names = F, quote = F)



# ========================================================================
# run_id characterization
chardf <- allinds %>%
    mutate(variable = paste0(budgtype," ",variable)) %>%
    select(variable,unit,run_id,value) %>% 
    # select(variable) %>% unique
    calc_addVariable(
        `Relative reversibility` = "100*`Pb Peak warming`/`Eb EoC warming`",
        unit = "%",
        na.rm = F,only.new = F) %>%
    calc_addVariable(
        `Absolute reversibility` = "`Pb Peak warming`-`Eb EoC warming`",
        unit = "K",
        na.rm = F,only.new = F) %>%
    calc_addVariable(
        `Pb ZEC` = "`Pb Peak warming`-`Pb Net-zero warming`",
        `Eb ZEC` = "`Eb Peak warming`-`Eb Net-zero warming`",
        unit = "K",
        na.rm = F,only.new = F) %>%
    calc_addVariable(
        `Pb Peak warming delay` = "`Pb Peak warming year`-`Pb Net-zero year`",
        `Eb Peak warming delay` = "`Eb Peak warming year`-`Eb Net-zero year`",
        unit = "years",
        na.rm = F,only.new = F)

chardf %>%
    filter(str_detect(run_id,"full_")) %>%
    calc_addVariable(
        `Pb Peak warming delay` = "`Pb Peak warming year`-`Pb Net-zero year`",
        `Eb Peak warming delay` = "`Eb Peak warming year`-`Eb Net-zero year`",
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
ggsave("class_PkW_RelRev_runids.png")


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
ggsave("class_PkW_RelRev.png")


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
ggsave("class_PkW_AbsRev.png")

sowlabeller <- c(
    "78"  = "wH_rL",
    "158" = "wH_rL",
    "168" = "wH_rL",
    "213" = "wH_rL",
    "224" = "wH_rL",
    "267" = "wH_rL",
    "320" = "wH_rL",
    "324" = "wH_rL",
    "355" = "wH_rL",
    "396" = "wH_rL"
)



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
write.csv(dfruncodes,"runcode_PbPW_AbsRev.csv",row.names = F)

pltdf <- chardf %>%
    select(-unit) %>%
    pivot_wider(names_from = variable, values_from = value) %>%
    left_join(dfruncodes) 

write.table(pltdf,"pltdf.csv", sep = ";", row.names = F, quote = F)

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
ggsave("class_PkW_AbsRev_runcodes.png")


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
ggsave("class_PkW_ZEC_runcodes.png")

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
ggsave("class_PkW_Wdelay_runcodes.png")


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
ggsave("class_Wdelay_PbZEC_runcodes.png")


# Climate =============================================================== 

left_join(sceninfo, sowclimdf) %>%
   filter(variable == "Surface Temperature (GSAT)") %>%
    # filter(run_id == 78) %>%
    # filter(budgtype!="Eb") %>%
    filter(cbudget==500) %>%
    left_join(dfruncodes) %>%
    # filter(between(period,2000,2100)) %>%
    ggplot(aes(x=period,y=value,
            color=runcode,subgroup=interaction(run_id,budgtype))
            ) +
    geom_path() +
    geom_hline(yintercept = c(1.5), lty=2) +
    geom_vline(xintercept = 2015, lty=2) +
    # facet_wrap(~variable+unit+budgtype)
    facet_wrap(~variable+unit+budgtype) 
ggsave("temperature_single_500.png", height = 5, width = 10)

# Probability distributions ==========================================================================
pltdf %>% colnames
pltdf$runcode

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
ggsave("prob_hist_pkwarm_500.png", height = 5, width = 10)

cdf <- ecdf(filter(usedata,subset!="SOWs")$value)
cdf(2)
percdf <- longdf %>%
    filter(variable == usevar) %>%
    filter(subset ==  "SOWs") %>%
    mutate(dist = cdf(value)) %>%
    mutate(perc = round(100*dist,2)) %>%
    write.csv("prob_table_SOWs_500.csv", row.names = F)


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
ggsave("prob_ecdf_pkwarm_500.png", height = 5, width = 10)


# x.gam<-rgamma(200,rate=0.5,shape=3.5) ## sampling from a gamma distribution with λ=0.5 (scale parameter12) and α=3.5 (shape parameter)
x.gam <- filter(usedata,subset != "SOWs")$value
med.gam<-mean(x.gam) ## sample mean
var.gam<-var(x.gam) ## sample variance
l.est<-med.gam/var.gam ## lambda estimate (corresponds to rate)
a.est<-((med.gam)^2)/var.gam ## alfa estimate

dgamma(x.gam, scale=l.est, shape=a.est)

png("dummy.png")
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

png("dummy.png")
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


