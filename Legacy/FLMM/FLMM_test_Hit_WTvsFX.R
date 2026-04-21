library(readr)
library(dplyr)
library(ggplot2)

# =========================================================
# 0) LOAD fastFMM
#    Prefer the local toolbox copy in this project folder.
# =========================================================
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

# =========================================================
# 1) SET INPUT FILE PATHS
# =========================================================
table_path <- "/Users/foxking/Desktop/FPA_Final/FLMM_Export_CSV/all_sessions_flmm_table.csv"
time_axis_path <- "/Users/foxking/Desktop/FPA_Final/FLMM_Export_CSV/time_axis.csv"
output_dir <- "/Users/foxking/Desktop/FPA_Final/FLMM_Results"

if (!file.exists(table_path)) {
  stop(paste("Table file not found:", table_path))
}

if (!file.exists(time_axis_path)) {
  stop(paste("Time axis file not found:", time_axis_path))
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# =========================================================
# 2) READ DATA
#    Read only the metadata + functional columns needed
#    for this AUX / Hit / CleanOnly FLMM.
# =========================================================
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

if (length(t_full) == 0) {
  stop("time_axis.csv did not contain any numeric time values.")
}

# =========================================================
# 3) FILTER: AUX + Hit + CleanOnly only
# =========================================================
df <- all_sessions_flmm_table %>%
  filter(
    region == "AUX",
    outcome == "Hit",
    condition == "CleanOnly"
  ) %>%
  mutate(
    id = factor(id),
    genotype = factor(genotype_label, levels = c("WT", "FX"))
  ) %>%
  filter(!is.na(id), !is.na(genotype))

if (nrow(df) == 0) {
  stop("No rows remain after filtering for AUX + Hit + CleanOnly.")
}

# =========================================================
# 4) GET FUNCTIONAL COLUMNS
#    Keep the original exported names (for example Y.1, Y.2, ...)
# =========================================================
if (length(t_full) != length(Y_cols)) {
  stop(
    paste0(
      "Time axis length (", length(t_full),
      ") does not match number of Y columns (", length(Y_cols), ")."
    )
  )
}

# =========================================================
# 5) OPTIONAL: DOWNSAMPLE THE TIME AXIS
#    Start with every 100th point
# =========================================================
ds_by <- 100
plot_time_window <- c(-2, 10)
Y_cols_ds <- Y_cols[seq(1, length(Y_cols), by = ds_by)]

cat("Original timepoints:", length(Y_cols), "\n")
cat("Downsampled timepoints:", length(Y_cols_ds), "\n")
cat("Rows before complete-case filtering:", nrow(df), "\n")

t_ds   <- t_full[seq(1, length(Y_cols), by = ds_by)]
# =========================================================
# 6) BUILD MATRIX
# =========================================================
Y_mat <- as.matrix(df[, Y_cols_ds])
storage.mode(Y_mat) <- "numeric"

# remove rows with missing signal values
keep <- complete.cases(Y_mat)
df <- df[keep, , drop = FALSE]
Y_mat <- Y_mat[keep, , drop = FALSE]

if (nrow(df) == 0) {
  stop("No complete cases remain after removing rows with missing signal values.")
}

cat("Rows after complete-case filtering:", nrow(df), "\n")
cat("Genotype counts:\n")
print(table(df$genotype))

# =========================================================
# 7) BUILD fastFMM INPUT
# =========================================================
flmm_dat <- data.frame(
  Y = I(Y_mat),
  id = df$id,
  genotype = df$genotype
)

# =========================================================
# 8) FIT MODEL
#    Use argvals to match the downsampled grid
# =========================================================
L <- ncol(Y_mat)

fit_hit_aux_wt_fx <- fui(
  Y ~ genotype + (1 | id),
  data = flmm_dat,
  argvals = t_ds
)

# =========================================================
# 9) PLOT WITH THE TRUE TIME AXIS
#    In analytic mode, fastFMM uses an internal regular index.
#    We remap the fitted coefficients onto the exported time axis
#    for display.
# =========================================================
title_names <- c("Intercept (WT)", "Genotype effect (FX - WT)")

make_coef_plot <- function(fit_obj, coef_idx, x_time, title_text) {
  beta_df <- data.frame(
    time = x_time,
    beta = fit_obj$betaHat[coef_idx, ]
  )

  if (!is.null(fit_obj$betaHat.var)) {
    beta_se <- sqrt(diag(fit_obj$betaHat.var[, , coef_idx]))
    beta_df$lower <- beta_df$beta - 2 * beta_se
    beta_df$upper <- beta_df$beta + 2 * beta_se
    beta_df$lower_joint <- beta_df$beta - fit_obj$qn[coef_idx] * beta_se
    beta_df$upper_joint <- beta_df$beta + fit_obj$qn[coef_idx] * beta_se
  }

  p <- ggplot(beta_df, aes(x = time, y = beta)) +
    theme_classic() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold")) +
    labs(
      title = title_text,
      x = "Time",
      y = "Estimate"
    ) +
    coord_cartesian(xlim = plot_time_window)

  if (!is.null(fit_obj$betaHat.var)) {
    p <- p +
      geom_ribbon(aes(ymin = lower_joint, ymax = upper_joint),
                  fill = "gray20", alpha = 0.2) +
      geom_ribbon(aes(ymin = lower, ymax = upper),
                  fill = "gray10", alpha = 0.4)
  }

  p +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    geom_line(linewidth = 1, color = "black")
}

plot_list <- lapply(seq_len(nrow(fit_hit_aux_wt_fx$betaHat)), function(i) {
  make_coef_plot(
    fit_obj = fit_hit_aux_wt_fx,
    coef_idx = i,
    x_time = t_ds,
    title_text = title_names[i]
  )
})

output_stub <- "FLMM_region_AUX_outcome_Hit_condition_CleanOnly_WT_vs_FX"
fit_path <- file.path(output_dir, paste0(output_stub, "_fit.rds"))
beta_path <- file.path(output_dir, paste0(output_stub, "_betaHat.csv"))
pdf_path <- file.path(output_dir, paste0(output_stub, "_coefficients.pdf"))
png_path <- file.path(output_dir, paste0(output_stub, "_coefficients.png"))

saveRDS(fit_hit_aux_wt_fx, fit_path)

beta_export <- data.frame(
  time = t_ds,
  Intercept_WT = fit_hit_aux_wt_fx$betaHat[1, ],
  Genotype_effect_FX_minus_WT = fit_hit_aux_wt_fx$betaHat[2, ]
)
write_csv(beta_export, beta_path)

grDevices::pdf(pdf_path, width = 14, height = 5)
gridExtra::grid.arrange(grobs = plot_list, nrow = 1)
grDevices::dev.off()

grDevices::png(png_path, width = 2800, height = 1000, res = 160)
gridExtra::grid.arrange(grobs = plot_list, nrow = 1)
grDevices::dev.off()

cat("Saved fit to:", fit_path, "\n")
cat("Saved beta coefficients to:", beta_path, "\n")
cat("Saved coefficient PDF to:", pdf_path, "\n")
cat("Saved coefficient PNG to:", png_path, "\n")
