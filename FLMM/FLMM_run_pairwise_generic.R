library(readr)
library(dplyr)
library(ggplot2)

fastfmm_local_path <- "/Users/foxking/Desktop/FPA_Final/fastFMM-main"

if (dir.exists(fastfmm_local_path) && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(fastfmm_local_path, export_all = FALSE, quiet = TRUE)
} else if (requireNamespace("fastFMM", quietly = TRUE)) {
  library(fastFMM)
} else {
  stop(
    paste(
      "Could not load fastFMM.",
      "Install the package or install pkgload so the local toolbox can be loaded from:",
      fastfmm_local_path
    )
  )
}

if (!requireNamespace("gridExtra", quietly = TRUE)) {
  stop("The 'gridExtra' package is required for multi-panel coefficient plots.")
}

parse_cli_args <- function(args) {
  out <- list()

  for (arg in args) {
    if (!startsWith(arg, "--")) {
      next
    }

    arg <- substring(arg, 3)
    parts <- strsplit(arg, "=", fixed = TRUE)[[1]]
    key <- parts[1]
    value <- if (length(parts) > 1) {
      paste(parts[-1], collapse = "=")
    } else {
      "TRUE"
    }

    out[[key]] <- value
  }

  out
}

get_arg <- function(arg_map, key, default = NULL, required = FALSE) {
  if (!is.null(arg_map[[key]])) {
    return(arg_map[[key]])
  }

  if (required) {
    stop(paste("Missing required argument --", key, sep = ""))
  }

  default
}

normalize_scalar <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }

  x <- trimws(as.character(x))
  if (!nzchar(x) || tolower(x) %in% c("all", "<all>", "null", "none", "na")) {
    return(NULL)
  }

  x
}

normalize_levels <- function(x) {
  vals <- strsplit(as.character(x), ",", fixed = TRUE)[[1]]
  vals <- unique(trimws(vals))
  vals[nzchar(vals)]
}

safe_num <- function(x, default = NULL) {
  if (is.null(x) || length(x) == 0) {
    return(default)
  }

  val <- suppressWarnings(as.numeric(x))
  if (length(val) == 0 || is.na(val)) {
    default
  } else {
    val
  }
}

null_to_empty <- function(x) {
  if (is.null(x)) "" else x
}

make_safe_name <- function(x) {
  gsub("[^A-Za-z0-9]+", "_", x)
}

pretty_var_name <- function(x) {
  switch(
    x,
    genotype = "Genotype",
    outcome = "Outcome",
    condition = "Condition",
    region = "Region",
    x
  )
}

build_output_stub <- function(compare_var, reference_level, contrast_level, filters) {
  label_parts <- c("FLMM_GUI")

  filter_names <- names(filters)
  for (i in seq_along(filters)) {
    if (!is.null(filters[[i]])) {
      label_parts <- c(label_parts, paste0(filter_names[i], "_", filters[[i]]))
    }
  }

  label_parts <- c(
    label_parts,
    paste0("compare_", compare_var),
    paste0(reference_level, "_vs_", contrast_level)
  )

  make_safe_name(paste(label_parts, collapse = "_"))
}

compute_windows <- function(time_vec, sig_vec, beta_vec) {
  if (!any(sig_vec)) {
    return(
      tibble(
        window_start = numeric(0),
        window_end = numeric(0),
        n_timepoints = integer(0),
        direction = character(0)
      )
    )
  }

  runs <- rle(sig_vec)
  run_ends <- cumsum(runs$lengths)
  run_starts <- run_ends - runs$lengths + 1
  keep_idx <- which(runs$values)

  bind_rows(lapply(keep_idx, function(i) {
    idx <- run_starts[i]:run_ends[i]
    direction <- if (mean(beta_vec[idx], na.rm = TRUE) >= 0) "positive" else "negative"

    tibble(
      window_start = time_vec[min(idx)],
      window_end = time_vec[max(idx)],
      n_timepoints = length(idx),
      direction = direction
    )
  }))
}

args <- parse_cli_args(commandArgs(trailingOnly = TRUE))

table_path <- get_arg(args, "table_path", required = TRUE)
time_axis_path <- get_arg(args, "time_axis_path", required = TRUE)
output_dir <- get_arg(args, "output_dir", required = TRUE)
compare_var <- get_arg(args, "compare_var", required = TRUE)
reference_level <- get_arg(args, "reference_level", required = TRUE)
contrast_level <- get_arg(args, "contrast_level", required = TRUE)
output_stub <- get_arg(args, "output_stub", default = NULL)

ds_by <- max(1, as.integer(safe_num(get_arg(args, "ds_by", default = "100"), 100)))
plot_xmin <- safe_num(get_arg(args, "plot_xmin", default = "-2"), -2)
plot_xmax <- safe_num(get_arg(args, "plot_xmax", default = "10"), 10)
plot_ymin <- safe_num(get_arg(args, "plot_ymin", default = NULL), NULL)
plot_ymax <- safe_num(get_arg(args, "plot_ymax", default = NULL), NULL)

compare_var <- normalize_scalar(compare_var)
reference_level <- normalize_scalar(reference_level)
contrast_level <- normalize_scalar(contrast_level)

valid_compare_vars <- c("genotype", "outcome", "condition", "region")
if (!(compare_var %in% valid_compare_vars)) {
  stop("compare_var must be one of: genotype, outcome, condition, region")
}

if (is.null(reference_level) || is.null(contrast_level)) {
  stop("reference_level and contrast_level must both be provided.")
}

if (identical(reference_level, contrast_level)) {
  stop("reference_level and contrast_level must be different.")
}

filters <- list(
  region = normalize_scalar(get_arg(args, "filter_region", default = NULL)),
  genotype = normalize_scalar(get_arg(args, "filter_genotype", default = NULL)),
  condition = normalize_scalar(get_arg(args, "filter_condition", default = NULL)),
  outcome = normalize_scalar(get_arg(args, "filter_outcome", default = NULL))
)

if (is.null(output_stub)) {
  output_stub <- build_output_stub(
    compare_var = compare_var,
    reference_level = reference_level,
    contrast_level = contrast_level,
    filters = filters
  )
}

if (!file.exists(table_path)) {
  stop(paste("Table file not found:", table_path))
}

if (!file.exists(time_axis_path)) {
  stop(paste("Time axis file not found:", time_axis_path))
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
figures_dir <- file.path(output_dir, "Figures")
tables_dir <- file.path(output_dir, "Tables")
models_dir <- file.path(output_dir, "Models")
dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)

table_header <- read_csv(table_path, n_max = 0, show_col_types = FALSE)
Y_cols <- grep("^Y[._]", names(table_header), value = TRUE)

if (length(Y_cols) == 0) {
  stop("No functional Y columns found.")
}

meta_cols <- c("id", "genotype_label", "region", "condition", "outcome")
select_cols <- c(meta_cols, Y_cols)

all_sessions_flmm_table <- read_csv(
  table_path,
  col_select = all_of(select_cols),
  show_col_types = FALSE,
  progress = TRUE
)

time_axis_raw <- read_csv(
  time_axis_path,
  show_col_types = FALSE
)

if ("time_sec" %in% names(time_axis_raw)) {
  t_full <- as.numeric(time_axis_raw$time_sec)
} else {
  numeric_cols <- names(time_axis_raw)[vapply(time_axis_raw, is.numeric, logical(1))]

  if (length(numeric_cols) == 0) {
    stop("time_axis.csv did not contain a usable numeric time column.")
  }

  t_full <- as.numeric(time_axis_raw[[numeric_cols[length(numeric_cols)]]])
}

t_full <- t_full[!is.na(t_full)]

if (length(t_full) != length(Y_cols)) {
  stop(
    paste0(
      "Time axis length (", length(t_full),
      ") does not match number of Y columns (", length(Y_cols), ")."
    )
  )
}

df <- all_sessions_flmm_table

filter_specs <- list(
  region = "region",
  genotype = "genotype_label",
  condition = "condition",
  outcome = "outcome"
)

for (filter_name in names(filter_specs)) {
  filter_value <- filters[[filter_name]]
  if (is.null(filter_value)) {
    next
  }

  source_col <- filter_specs[[filter_name]]
  df <- df %>% filter(.data[[source_col]] == filter_value)
}

compare_source_col <- switch(
  compare_var,
  genotype = "genotype_label",
  outcome = "outcome",
  condition = "condition",
  region = "region"
)

df <- df %>%
  filter(.data[[compare_source_col]] %in% c(reference_level, contrast_level)) %>%
  mutate(
    id = factor(id),
    compare = factor(.data[[compare_source_col]], levels = c(reference_level, contrast_level))
  ) %>%
  filter(!is.na(id), !is.na(compare))

if (nrow(df) == 0) {
  stop("No rows remain after applying the requested filters.")
}

if (nlevels(droplevels(df$compare)) < 2) {
  stop("Both comparison levels must be present after filtering.")
}

ds_idx <- seq(1, length(Y_cols), by = ds_by)
Y_cols_ds <- Y_cols[ds_idx]
t_ds <- t_full[ds_idx]

message("Original timepoints: ", length(Y_cols))
message("Downsampled timepoints: ", length(Y_cols_ds))
message("Rows before complete-case filtering: ", nrow(df))

Y_mat <- as.matrix(df[, Y_cols_ds])
storage.mode(Y_mat) <- "numeric"

keep <- complete.cases(Y_mat)
df <- droplevels(df[keep, , drop = FALSE])
Y_mat <- Y_mat[keep, , drop = FALSE]

if (nrow(df) == 0) {
  stop("No complete cases remain after removing rows with missing Y values.")
}

if (nlevels(df$compare) < 2) {
  stop("Only one comparison level remains after complete-case filtering.")
}

message("Rows after complete-case filtering: ", nrow(df))
message("Compare counts:")
print(table(df$compare))

counts_df <- df %>%
  group_by(compare) %>%
  summarise(
    n_trials = n(),
    n_animals = n_distinct(id),
    .groups = "drop"
  ) %>%
  rename(level = compare)

flmm_dat <- data.frame(
  Y = I(Y_mat),
  id = df$id,
  compare = df$compare
)

fit_obj <- fui(
  Y ~ compare + (1 | id),
  data = flmm_dat,
  argvals = t_ds
)

compare_label <- pretty_var_name(compare_var)
title_names <- c(
  paste0("Intercept (", reference_level, ")"),
  paste0(compare_label, " effect (", contrast_level, " - ", reference_level, ")")
)

wide_beta <- data.frame(
  time = t_ds
)

coef_keys <- c(
  paste0("Intercept_", make_safe_name(reference_level)),
  paste0(make_safe_name(compare_var), "_effect_", make_safe_name(contrast_level), "_minus_", make_safe_name(reference_level))
)

coef_rows <- vector("list", length = nrow(fit_obj$betaHat))
window_rows <- vector("list", length = nrow(fit_obj$betaHat))

for (i in seq_len(nrow(fit_obj$betaHat))) {
  beta <- fit_obj$betaHat[i, ]
  wide_beta[[coef_keys[i]]] <- beta

  coef_df <- tibble(
    coefficient_index = i,
    coefficient_key = coef_keys[i],
    coefficient_title = title_names[i],
    time = t_ds,
    beta = beta
  )

  if (!is.null(fit_obj$betaHat.var)) {
    beta_se <- sqrt(pmax(diag(fit_obj$betaHat.var[, , i]), 0))
    coef_df <- coef_df %>%
      mutate(
        lower = beta - 1.96 * beta_se,
        upper = beta + 1.96 * beta_se,
        lower_joint = beta - fit_obj$qn[i] * beta_se,
        upper_joint = beta + fit_obj$qn[i] * beta_se,
        sig_joint = lower_joint > 0 | upper_joint < 0
      )

    window_rows[[i]] <- compute_windows(t_ds, coef_df$sig_joint, coef_df$beta) %>%
      mutate(
        coefficient_index = i,
        coefficient_key = coef_keys[i],
        coefficient_title = title_names[i]
      ) %>%
      relocate(coefficient_index, coefficient_key, coefficient_title)
  } else {
    coef_df$sig_joint <- FALSE
    window_rows[[i]] <- tibble(
      coefficient_index = integer(0),
      coefficient_key = character(0),
      coefficient_title = character(0),
      window_start = numeric(0),
      window_end = numeric(0),
      n_timepoints = integer(0),
      direction = character(0)
    )
  }

  coef_rows[[i]] <- coef_df
}

coef_long <- bind_rows(coef_rows)
window_df <- bind_rows(window_rows)

summary_df <- tibble(
  compare_var = compare_var,
  reference_level = reference_level,
  contrast_level = contrast_level,
  filter_region = null_to_empty(filters$region),
  filter_genotype = null_to_empty(filters$genotype),
  filter_condition = null_to_empty(filters$condition),
  filter_outcome = null_to_empty(filters$outcome),
  ds_by = ds_by,
  plot_xmin = plot_xmin,
  plot_xmax = plot_xmax,
  plot_ymin = if (is.null(plot_ymin)) NA_real_ else plot_ymin,
  plot_ymax = if (is.null(plot_ymax)) NA_real_ else plot_ymax,
  n_rows_model = nrow(df)
)

make_coef_plot <- function(plot_df, title_text) {
  p <- ggplot(plot_df, aes(x = time, y = beta)) +
    theme_classic() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold")) +
    labs(
      title = title_text,
      x = "Time from cue onset (s)",
      y = "Estimate"
    ) +
    coord_cartesian(
      xlim = c(plot_xmin, plot_xmax),
      ylim = if (!is.null(plot_ymin) && !is.null(plot_ymax)) c(plot_ymin, plot_ymax) else NULL
    )

  if (all(c("lower_joint", "upper_joint") %in% names(plot_df))) {
    p <- p +
      geom_ribbon(
        aes(ymin = lower_joint, ymax = upper_joint),
        fill = "gray20",
        alpha = 0.2
      ) +
      geom_ribbon(
        aes(ymin = lower, ymax = upper),
        fill = "gray10",
        alpha = 0.4
      )

    sig_df <- plot_df %>%
      filter(sig_joint)

    if (nrow(sig_df) > 0) {
      y_bottom <- if (!is.null(plot_ymin)) {
        plot_ymin
      } else {
        min(c(plot_df$beta, plot_df$lower_joint), na.rm = TRUE)
      }

      y_top <- if (!is.null(plot_ymax)) {
        plot_ymax
      } else {
        max(c(plot_df$beta, plot_df$upper_joint), na.rm = TRUE)
      }

      y_span <- y_top - y_bottom
      if (!is.finite(y_span) || y_span <= 0) {
        y_span <- 1
      }

      sig_df$y_sig <- y_bottom + 0.03 * y_span

      p <- p +
        geom_point(
          data = sig_df,
          aes(x = time, y = y_sig),
          inherit.aes = FALSE,
          shape = 15,
          size = 1.1,
          color = "black"
        )
    }
  }

  p +
    geom_hline(yintercept = 0, linetype = "dashed", color = "firebrick") +
    geom_line(linewidth = 1, color = "black")
}

plot_list <- lapply(seq_along(title_names), function(i) {
  make_coef_plot(
    coef_long %>% filter(coefficient_index == i),
    title_names[i]
  )
})

fit_path <- file.path(models_dir, "fit.rds")
beta_path <- file.path(tables_dir, "betaHat.csv")
coef_long_path <- file.path(tables_dir, "coefficients_long.csv")
counts_path <- file.path(tables_dir, "summary_counts.csv")
windows_path <- file.path(tables_dir, "significance_windows.csv")
summary_path <- file.path(tables_dir, "run_summary.csv")
manifest_path <- file.path(tables_dir, "export_manifest.csv")
pdf_path <- file.path(figures_dir, "coefficients.pdf")
png_path <- file.path(figures_dir, "coefficients.png")

saveRDS(fit_obj, fit_path)
write_csv(wide_beta, beta_path)
write_csv(coef_long, coef_long_path)
write_csv(counts_df, counts_path)
write_csv(window_df, windows_path)
write_csv(summary_df, summary_path)
write_csv(
  tibble(
    run_folder = basename(normalizePath(output_dir, winslash = "/", mustWork = FALSE)),
    compare_var = compare_var,
    reference_level = reference_level,
    contrast_level = contrast_level,
    figures_dir = normalizePath(figures_dir, winslash = "/", mustWork = FALSE),
    tables_dir = normalizePath(tables_dir, winslash = "/", mustWork = FALSE),
    models_dir = normalizePath(models_dir, winslash = "/", mustWork = FALSE),
    output_stub = output_stub
  ),
  manifest_path
)

grDevices::pdf(pdf_path, width = 14, height = 5.5)
gridExtra::grid.arrange(grobs = plot_list, nrow = 1)
grDevices::dev.off()

grDevices::png(png_path, width = 2800, height = 1100, res = 180)
gridExtra::grid.arrange(grobs = plot_list, nrow = 1)
grDevices::dev.off()

message("Saved fit to: ", fit_path)
message("Saved beta coefficients to: ", beta_path)
message("Saved coefficient-long table to: ", coef_long_path)
message("Saved counts summary to: ", counts_path)
message("Saved significance windows to: ", windows_path)
message("Saved run summary to: ", summary_path)
message("Saved export manifest to: ", manifest_path)
message("Saved coefficient PDF to: ", pdf_path)
message("Saved coefficient PNG to: ", png_path)
