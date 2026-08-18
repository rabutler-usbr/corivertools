#!/usr/bin/env Rscript

# Refresh the newest three water years in data/historical_inflow.json.
#
# Data sources:
#   1. Observed monthly inflow from HDB through the month before the newest
#      "most" forecast MRID begins.
#   2. Forecast monthly inflow from that MRID through September of the same WY.
#
# Both HDB calls use server = "uc", sdi = 1856, and time_step = "m".
# hdb_query() receives character start_date/end_date values in YYYY-MM format.
#
# Usage:
#   Rscript scripts/update_historical_inflow.R --mrids data/mrids.csv

args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(flag, default = NULL) {
  position <- match(flag, args)
  if (is.na(position)) return(default)
  if (position == length(args)) stop(sprintf("Missing value after %s", flag), call. = FALSE)
  args[[position + 1]]
}

script_path <- tryCatch(normalizePath(sys.frame(1)$ofile), error = function(e) NA_character_)
repo_root <- if (!is.na(script_path)) normalizePath(file.path(dirname(script_path), "..")) else normalizePath(".")
mrids_path <- get_arg("--mrids", file.path(repo_root, "data", "mrids.csv"))
output_path <- get_arg("--output", file.path(repo_root, "data", "historical_inflow.json"))

if (!requireNamespace("rhdb", quietly = TRUE)) stop("Package rhdb is required. Install it with remotes::install_github('BoulderCodeHub/rhdb').", call. = FALSE)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package jsonlite is required.", call. = FALSE)
if (!file.exists(mrids_path)) stop(sprintf("MRID file not found: %s", mrids_path), call. = FALSE)
if (!file.exists(output_path)) stop(sprintf("Historical inflow JSON not found: %s", output_path), call. = FALSE)

month_number <- function(month_name) {
  value <- match(tolower(trimws(month_name)), tolower(month.name))
  if (is.na(value)) stop(sprintf("Invalid month in MRID file: %s", month_name), call. = FALSE)
  value
}

water_year <- function(date) {
  year <- as.integer(format(date, "%Y"))
  month <- as.integer(format(date, "%m"))
  ifelse(month >= 10, year + 1L, year)
}

month_string <- function(date) format(as.Date(date), "%Y-%m")

as_month_date <- function(x) {
  if (inherits(x, "Date")) return(as.Date(format(x, "%Y-%m-01")))
  text <- as.character(x)
  parsed <- suppressWarnings(as.Date(text))
  if (all(is.na(parsed))) parsed <- suppressWarnings(as.Date(paste0(text, "-01")))
  as.Date(format(parsed, "%Y-%m-01"))
}

query_monthly <- function(start_month, end_month, mrid = NULL) {
  query_args <- list(
    server = "uc",
    sdi = 1856,
    time_step = "m",
    start_date = month_string(start_month),
    end_date = month_string(end_month)
  )
  if (!is.null(mrid)) query_args$mrid <- as.integer(mrid)
  result <- do.call(rhdb::hdb_query, query_args)
  if (!is.data.frame(result) || !all(c("time_step", "value") %in% names(result))) {
    stop("Unexpected rhdb result: expected data frame columns including time_step and value.", call. = FALSE)
  }
  result
}

as_month_date <- function(x) {
  if (inherits(x, "POSIXt")) return(as.Date(format(x, "%Y-%m-01")))
  if (inherits(x, "Date")) return(as.Date(format(x, "%Y-%m-01")))
  
  text <- trimws(as.character(x))
  parsed <- as.POSIXct(
    text,
    format = "%m/%d/%Y %I:%M:%S %p",
    tz = "UTC"
  )
  
  if (anyNA(parsed)) {
    stop(
      sprintf(
        "Could not parse one or more HDB time_step values. Example: %s",
        text[which(is.na(parsed))[1]]
      ),
      call. = FALSE
    )
  }
  
  as.Date(format(parsed, "%Y-%m-01"))
}

aggregate_water_year <- function(records) {
  if (!nrow(records)) {
    return(data.frame(water_year = integer(), acre_feet = numeric()))
  }
  
  dates <- as_month_date(records$time_step)
  values <- as.numeric(records$value)
  valid <- !is.na(dates) & is.finite(values)
  
  if (!any(valid)) {
    return(data.frame(water_year = integer(), acre_feet = numeric()))
  }
  
  output <- stats::aggregate(
    values[valid],
    by = list(water_year = water_year(dates[valid])),
    FUN = sum
  )
  names(output)[2] <- "acre_feet"
  output[order(output$water_year), , drop = FALSE]
}

mrids <- utils::read.csv(mrids_path, stringsAsFactors = FALSE, check.names = FALSE)
required_mrid_columns <- c("year", "month", "inflow", "mrid")
if (!all(required_mrid_columns %in% names(mrids))) {
  stop(sprintf("MRID CSV must contain columns: %s", paste(required_mrid_columns, collapse = ", ")), call. = FALSE)
}

most_rows <- mrids[tolower(trimws(mrids$inflow)) == "most", required_mrid_columns, drop = FALSE]
if (!nrow(most_rows)) stop("MRID CSV has no row with inflow == 'most'.", call. = FALSE)
most_rows$year <- as.integer(most_rows$year)
most_rows$month_num <- vapply(most_rows$month, month_number, integer(1))
most_rows$mrid <- as.integer(most_rows$mrid)
most_rows <- most_rows[is.finite(most_rows$year) & is.finite(most_rows$mrid), , drop = FALSE]
if (!nrow(most_rows)) stop("No valid year/month/MRID values found among inflow == 'most' rows.", call. = FALSE)
most_rows <- most_rows[order(most_rows$year, most_rows$month_num, most_rows$mrid, decreasing = TRUE), , drop = FALSE]
current <- most_rows[1, , drop = FALSE]

forecast_start <- as.Date(sprintf("%04d-%02d-01", current$year, current$month_num))
current_wy <- water_year(forecast_start)
wy_end_month <- as.Date(sprintf("%04d-09-01", current_wy))
refresh_start_month <- as.Date(sprintf("%04d-10-01", current_wy - 3L))
observed_end_month <- seq(forecast_start, by = "-1 month", length.out = 2)[2]

observed <- if (observed_end_month >= refresh_start_month) query_monthly(refresh_start_month, observed_end_month) else data.frame()
forecast <- query_monthly(forecast_start, wy_end_month, mrid = current$mrid)

observed_wy <- aggregate_water_year(observed)
forecast_wy <- aggregate_water_year(forecast)
names(observed_wy)[2] <- "observed_af"
names(forecast_wy)[2] <- "forecast_af"

all_wys <- sort(unique(c(observed_wy$water_year, forecast_wy$water_year)))
combined <- data.frame(water_year = all_wys)
combined <- merge(combined, observed_wy, by = "water_year", all.x = TRUE)
combined <- merge(combined, forecast_wy, by = "water_year", all.x = TRUE)
combined$observed_af[is.na(combined$observed_af)] <- 0
combined$forecast_af[is.na(combined$forecast_af)] <- 0
combined$acre_feet <- round(combined$observed_af + combined$forecast_af)

refresh_wys <- seq.int(current_wy - 2L, current_wy)
updated <- combined[combined$water_year %in% refresh_wys, c("water_year", "acre_feet"), drop = FALSE]
if (!all(refresh_wys %in% updated$water_year)) {
  missing <- setdiff(refresh_wys, updated$water_year)
  stop(sprintf("HDB response did not provide data for required water year(s): %s", paste(missing, collapse = ", ")), call. = FALSE)
}
if (any(!is.finite(updated$acre_feet))) stop("Computed non-finite annual inflow value.", call. = FALSE)

payload <- jsonlite::fromJSON(output_path, simplifyVector = FALSE)
if (is.null(payload$years) || !is.list(payload$years)) stop("Unexpected historical inflow JSON: missing top-level years object.", call. = FALSE)
for (i in seq_len(nrow(updated))) payload$years[[as.character(updated$water_year[[i]])]] <- as.integer(updated$acre_feet[[i]])
ordered_years <- sort(as.integer(names(payload$years)))
payload$years <- stats::setNames(lapply(ordered_years, function(year) unname(payload$years[[as.character(year)]])), as.character(ordered_years))
payload$last_updated <- format(Sys.Date(), "%Y-%m-%d")
payload$source <- sprintf("HDB API: server=uc, sdi=1856, time_step=m; observed %s through %s plus MRID %s from %s through %s.", month_string(refresh_start_month), month_string(observed_end_month), current$mrid, month_string(forecast_start), month_string(wy_end_month))

writeLines(jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE, digits = NA), output_path, useBytes = TRUE)
message(sprintf("Updated WY%s–WY%s using observed monthly HDB data through %s plus MRID %s from %s through %s.", min(refresh_wys), max(refresh_wys), month_string(observed_end_month), current$mrid, month_string(forecast_start), month_string(wy_end_month)))
