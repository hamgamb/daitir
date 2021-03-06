## code to prepare `jobseeker_sa2` dataset goes here

library(dplyr)
library(purrr)
library(readxl)
library(tidyr)
library(xml2)
library(rvest)
library(stringr)
library(absmapsdata)

jobseeker_latest <- read_html("https://data.gov.au/data/dataset/728daa75-06e8-442d-931c-93ecc6a57880") %>%
  html_nodes(xpath = '//*[@id="content"]/div[3]/div/article/div/section[3]/table/tbody/tr[9]/td') %>%
  html_text() %>%
  as.Date()


files <- data.frame(
  url = read_html("https://data.gov.au/data/dataset/728daa75-06e8-442d-931c-93ecc6a57880") %>% html_nodes("#dataset-resources a") %>% html_attr("href")
) %>%
  filter(grepl(".xlsx", url)) %>%
  mutate(date = str_extract(url, "(january|february|march|april|may|june|july|august|september|october|november|december)-\\d{4}"),
         date = as.Date(paste0(date, "-01"), "%B-%Y-%d"))

if (max(files$date) <= max(jobseeker_sa2$date)) {
  message("Skipping: `jobseeker_state.rda`, `jobseeker_sa2.rda`: appears to be up-to-date") 
} else {
  
  message("Updating `jobseeker_state.rda`, `jobseeker_sa2.rda`")
  file_paths <- purrr::map(files$url, ~download_file(.x))

  jobseeker_all <- data.frame(
    "sa2" = numeric(),
    "sa2_name" = character(),
    "jobseeker_payment" = numeric(),
    "youth_allowance_other" = numeric()
  )

  for (i in seq_along(file_paths)) {
    dss_month <- read_excel(file_paths[[i]],
      sheet = "Table 4 - By SA2",
      skip = 7,
      n_max = 2292,
      col_names = c("sa2", "sa2_name", "jobseeker_payment", "youth_allowance_other"),
      col_types = c("numeric", "text", "numeric", "numeric")
    ) %>%
      mutate(date = files$date[i]) %>%
      replace_na(list(jobseeker_payment = 5, youth_allowance_other = 5))

    jobseeker_all <- bind_rows(jobseeker_all, dss_month)
  }

  jobseeker_sa2 <- jobseeker_all %>%
    left_join(sa22016, by = c("sa2_name" = "sa2_name_2016")) %>%
    select(sa2_main_2016, jobseeker_payment, youth_allowance_other, date) %>%
    arrange(date) %>%
    group_by(sa2_main_2016) %>%
    mutate(
      jobseeker_growth = jobseeker_payment - lag(jobseeker_payment),
      youth_allowance_growth = youth_allowance_other - lag(youth_allowance_other)
    ) %>%
    ungroup() %>%
    pivot_longer(cols = c(-sa2_main_2016, -date), names_to = "indicator", values_to = "value") %>%
    mutate(indicator = str_to_sentence(str_replace_all(indicator, "_", " ")))
  
  jobseeker_state <- jobseeker_all %>%
    left_join(sa22016, by = c("sa2_name" = "sa2_name_2016")) %>%
    select(state_name_2016, jobseeker_payment, youth_allowance_other, date) %>%
    arrange(date) %>%
    group_by(state_name_2016, date) %>%
    summarise(across(c(jobseeker_payment, youth_allowance_other), ~sum(.,na.rm = T))) %>%
    ungroup() %>%
    pivot_longer(cols = c(-state_name_2016, -date), names_to = "indicator", values_to = "value") %>%
    mutate(indicator = str_to_sentence(str_replace_all(indicator, "_", " ")),
           series_type = "Original",
           unit = "000", 
           year = lubridate::year(date),
           month = lubridate::month(date, abbr = FALSE, label = TRUE)) %>%
    rename(state = state_name_2016)
  
  usethis::use_data(jobseeker_state, compress = "xz", overwrite = TRUE)
  usethis::use_data(jobseeker_sa2, compress = "xz", overwrite = TRUE)
  
  map(file_paths, file.remove)
}

