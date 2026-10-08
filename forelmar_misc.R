require(tidyverse)
require(quitte)

# bigmif <- read.quitte("/p/projects/piam/abrahao/esm2025/task133/pilot_v1/remind_t133/forelmar_remind_reports_v2.mif")
# saveRDS(bigmif, "forelmar_remind_reports_v2.rds")

bigmif %>% select(scenario) %>% unique

bigmif %>%
    filter(
        region == "World",
        scenario %in% 
        c(
            "E25v01-SSP2-Pb700",
            "E25v01-SSP2-Pb900",
            "E25v01-SSP2-Pb1600"
        ))  %>%
        filter(variable == "Price|Carbon") %>%
        filter(period <= 2100) %>%
        ggplot(aes(x = period, y = value, color = scenario)) +
        geom_line() +
        labs(y = "Carbon Price [USD2017/tCO2]", x ="")
ggsave("forelmar_cprice.png")
