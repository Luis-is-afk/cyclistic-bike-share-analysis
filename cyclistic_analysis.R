# 1. Setup
required_packages <- c("readr", "readxl", "dplyr", "lubridate", "ggplot2", "stringr", "scales")
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages) > 0) install.packages(missing_packages)
invisible(lapply(required_packages, library, character.only = TRUE))

# Point this at a data FILE (.csv/.xlsx/.xls) or a FOLDER of monthly CSVs.
# NOTE: do not point it at this .R script; that was the original bug.
DATA_PATH  <- "C:/Users/luisa/OneDrive/Desktop/bike-share-company/data"
# 12-month analysis window (change if your data covers different months)
START_DATE <- as.Date("2025-09-01")
END_DATE   <- as.Date("2026-08-31")
OUTPUT_DIR <- "cyclistic_outputs"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

DAY_LEVELS <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")  # locale-proof

# 2. Prepare: import and inspect
read_one <- function(path) {
  if (grepl("\\.xlsx?$", path, ignore.case = TRUE)) {
    readxl::read_excel(path)
  } else if (grepl("\\.csv$", path, ignore.case = TRUE)) {
    # read as text so column types never clash when stacking months
    readr::read_csv(path, col_types = readr::cols(.default = "c"),
                    na = c("", "NA"), show_col_types = FALSE)
  } else {
    stop("Unsupported file type: ", path)
  }
}

if (!file.exists(DATA_PATH) && !dir.exists(DATA_PATH)) {
  stop("DATA_PATH not found: ", DATA_PATH)
}

files <- if (dir.exists(DATA_PATH)) {
  list.files(DATA_PATH, pattern = "\\.(csv|xlsx?)$", full.names = TRUE,
             ignore.case = TRUE)
} else DATA_PATH
if (length(files) == 0) stop("No .csv/.xlsx files found in: ", DATA_PATH)

rides_raw <- dplyr::bind_rows(lapply(files, function(f) {
  df <- read_one(f)
  df[] <- lapply(df, function(col) if (inherits(col, "POSIXt")) format(col) else as.character(col))
  df
}))

cat("Files read:", length(files), "\n")
cat("Rows:", nrow(rides_raw), "\n")
cat("Columns:", ncol(rides_raw), "\n")
print(names(rides_raw))


# 3. Process: clean and transform
parse_dt <- function(x) lubridate::parse_date_time(
  x, orders = c("Ymd HMS", "Ymd HM", "mdY HMS", "mdY HM"), tz = "UTC", quiet = TRUE
)

rides <- rides_raw %>%
  mutate(
    started_at    = parse_dt(started_at),
    ended_at      = parse_dt(ended_at),
    member_casual = str_to_lower(str_trim(member_casual)),
    member_casual = case_when(
      member_casual %in% c("member", "memb") ~ "member",
      member_casual == "casual"               ~ "casual",
      TRUE                                    ~ NA_character_
    ),
    ride_length_minutes = as.numeric(difftime(ended_at, started_at, units = "mins")),
    ride_date   = as.Date(started_at),
    year        = year(started_at),
    month       = month(started_at, label = TRUE, abbr = TRUE),
    wday_num    = wday(started_at, week_start = 1),            # 1 = Mon ... 7 = Sun
    day_of_week = factor(DAY_LEVELS[wday_num], levels = DAY_LEVELS),
    start_hour  = hour(started_at),
    is_weekend  = wday_num >= 6
  )

rides_clean <- rides %>%
  filter(
    !is.na(ride_id), !is.na(started_at), !is.na(ended_at),
    !is.na(member_casual),
    !is.na(ride_length_minutes),
    ride_length_minutes >= 1,              # drops sub-minute false starts
    ride_length_minutes <= 24 * 60,
    ride_date >= START_DATE, ride_date <= END_DATE
  ) %>%
  distinct(ride_id, .keep_all = TRUE)


# 4. Process: validation report
na_count <- function(df, col) if (col %in% names(df)) sum(is.na(df[[col]])) else NA_integer_

validation <- data.frame(
  metric = c("Raw rows", "Clean rows", "Rows removed", "Duplicate ride IDs",
             "Unparseable start/end times",
             "Missing start station names", "Missing end station names",
             "Minimum ride length (min)", "Maximum ride length (min)"),
  value = c(nrow(rides_raw), nrow(rides_clean), nrow(rides_raw) - nrow(rides_clean),
            sum(duplicated(rides$ride_id)),
            sum(is.na(rides$started_at) | is.na(rides$ended_at)),
            na_count(rides, "start_station_name"), na_count(rides, "end_station_name"),
            min(rides_clean$ride_length_minutes), max(rides_clean$ride_length_minutes))
)
write.csv(validation, file.path(OUTPUT_DIR, "validation_report.csv"), row.names = FALSE)
print(validation)


# 5. Analyze: summary tables
share_within <- function(df, ...) {
  df %>%
    count(member_casual, ...) %>%
    group_by(member_casual) %>%
    mutate(share_within_rider_type = n / sum(n)) %>%
    ungroup()
}

summary_by_rider <- rides_clean %>%
  group_by(member_casual) %>%
  summarise(
    rides           = n(),
    average_minutes = mean(ride_length_minutes),
    median_minutes  = median(ride_length_minutes),
    weekend_share   = mean(is_weekend),
    .groups = "drop"
  ) %>%
  mutate(ride_share = rides / sum(rides))

rides_by_day  <- share_within(rides_clean, day_of_week)
rides_by_hour <- share_within(rides_clean, start_hour)
rides_by_month <- rides_clean %>%
  mutate(year_month = floor_date(ride_date, "month")) %>%
  count(member_casual, year_month)

rides_by_bike <- if ("rideable_type" %in% names(rides_clean)) {
  share_within(rides_clean, rideable_type)
} else NULL

rides_by_station <- if ("start_station_name" %in% names(rides_clean)) {
  rides_clean %>%
    filter(!is.na(start_station_name)) %>%
    count(member_casual, start_station_name, sort = TRUE)
} else NULL

save_csv <- function(x, name) {
  if (!is.null(x)) write.csv(x, file.path(OUTPUT_DIR, name), row.names = FALSE)
}
save_csv(summary_by_rider, "summary_by_rider.csv")
save_csv(rides_by_day,     "rides_by_day.csv")
save_csv(rides_by_hour,    "rides_by_hour.csv")
save_csv(rides_by_month,   "rides_by_month.csv")
save_csv(rides_by_bike,    "rides_by_bike.csv")
save_csv(rides_by_station, "rides_by_station.csv")

print(summary_by_rider)
print(rides_by_day)

# 6. Share: charts
set.seed(42)
plot_data <- if (nrow(rides_clean) > 3e5) slice_sample(rides_clean, n = 3e5) else rides_clean

plot_duration <- ggplot(plot_data, aes(member_casual, ride_length_minutes, fill = member_casual)) +
  geom_boxplot(outlier.alpha = 0.25) +
  coord_cartesian(ylim = c(0, quantile(rides_clean$ride_length_minutes, 0.99))) +
  labs(title = "Ride duration by rider type", x = "Rider type", y = "Minutes") +
  theme_minimal() +
  theme(legend.position = "none")
ggsave(file.path(OUTPUT_DIR, "ride_duration_by_rider_type.png"), plot_duration,
       width = 8, height = 5, dpi = 300)

plot_day <- ggplot(rides_by_day, aes(day_of_week, n, fill = member_casual)) +
  geom_col(position = "dodge") +
  labs(title = "Rides by day of week", x = "Day", y = "Number of rides", fill = "Rider type") +
  scale_y_continuous(labels = scales::comma) +
  theme_minimal()
ggsave(file.path(OUTPUT_DIR, "rides_by_day.png"), plot_day, width = 9, height = 5, dpi = 300)

plot_hour <- ggplot(rides_by_hour, aes(start_hour, n, color = member_casual)) +
  geom_line(linewidth = 1) +
  geom_point() +
  scale_x_continuous(breaks = 0:23) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Ride start times by rider type", x = "Hour of day",
       y = "Number of rides", color = "Rider type") +
  theme_minimal()
ggsave(file.path(OUTPUT_DIR, "rides_by_hour.png"), plot_hour, width = 10, height = 5, dpi = 300)

plot_month <- ggplot(rides_by_month, aes(year_month, n, color = member_casual)) +
  geom_line(linewidth = 1) +
  geom_point() +
  scale_x_date(date_labels = "%b %y", date_breaks = "1 month") +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Monthly rides by rider type", x = NULL,
       y = "Number of rides", color = "Rider type") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(OUTPUT_DIR, "rides_by_month.png"), plot_month, width = 10, height = 5, dpi = 300)

cat("Analysis complete. Results saved in:", normalizePath(OUTPUT_DIR), "\n")