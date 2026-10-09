data_dir <- "C:/Users/null/OneDrive/Desktop/bike-share-company/data"
dir.create(data_dir, showWarnings = FALSE)

months <- format(seq(as.Date("2025-09-01"), as.Date("2026-08-01"), by = "month"), "%Y%m")

for (m in months) {
  zip_file <- file.path(tempdir(), paste0(m, "-divvy-tripdata.zip"))
  url <- paste0("https://divvy-tripdata.s3.amazonaws.com/", m, "-divvy-tripdata.zip")
  ok <- tryCatch({ download.file(url, zip_file, mode = "wb"); TRUE },
                 error = function(e) { message("Failed: ", m); FALSE })
  if (ok) unzip(zip_file, exdir = data_dir, junkpaths = TRUE)
}
list.files(data_dir)
