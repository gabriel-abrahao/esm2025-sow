require(tidyverse)
require(quitte)


climfname <- "climate_output_coresows_v2.csv"
emisfname <- "emissions_climate_output_coresows_v2.csv"
lablfname <- "runcode_PbPW_AbsRev.csv"
welffname <- "welfare_v2.csv"


allmifnames <- Sys.glob("output/*/REMIND*.mif")
allmifnames <- allmifnames[!str_detect(allmifnames, "_withoutPlus")]

inclimdf <- read.quitte(climfname) %>%
    filter(region == "World") %>%
    select(-model,-climate_model)

labldf <- read.csv(lablfname) %>%
    separate(runcode, remove = F, sep = "_", into = c("ord1","ord2")) %>%
    mutate(ord1 = as.numeric(str_extract(ord1,"[0-9][0-9]*"))) %>%
    mutate(ord2 = as.numeric(str_extract(ord2,"[0-9][0-9]*"))) %>%
    arrange(ord1,ord2) %>%
    mutate(run_id = as.factor(run_id))

climdf <- left_join(inclimdf, labldf) %>%
    rename(model = runcode) %>%
    select(-ord1,-ord2,-run_id) %>%
    relocate(c("model","scenario","region","variable","unit","period","value",)) 

write.mif(climdf, paste0("forelmar_",climfname))

# SLOOOOOW
# inbigmif <- read.quitte(allmifnames)

mifname <- allmifnames[1]
mif <- read.quitte(mifname, filter.function = \(x) filter(x, region == "World"))

biglist <- lapply(allmifnames, \(mifname) read.quitte(mifname, filter.function = \(x) filter(x, region == "World")))

# inbigmif <- read.quitte(allmifnames, filter.function = \(x) filter(x, region == "World"))
# write.mif(inbigmif, paste0("forelmar_","remind_reports_v2.mif"))

