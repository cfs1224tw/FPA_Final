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
# 1) USER SETTINGS
# =========================================================
table_path <- "/Users/foxking/Desktop/FPA_Final/FLMM_Export_CSV/all_sessions_flmm_table.csv"
time_axis_path <- "/Users/foxking/Desktop/FPA_Final/FLMM_Export_CSV/time_axis.csv"
output_dir <- "/Users/foxking/Desktop/FPA_Final/FLMM_Results"

region_filter <- "AUX"   # Change to "PFC" if you want PFC instead.
genotype_filter <- "WT"
condition_filter <- "CleanOnly"
outcomes_keep <- c("FA", "Hit")

# Set Hit as the reference so the intercept is Hit and the
# second coefficient is FA - Hit.
outcome_levels <- c("Hit", "FA")

# Start coarse for speed, then reduce if you want finer timing.
ds_by <- 100

# Plot only this time window while keeping the full fitted domain.
plot_time_window <- c(-2, 10)

if (!file.exists(table_path)) {
  stop(paste("Table file not found:", table_path))
}

if (!file.exists(time_axis_path)) {
  stop(paste("Time axis file not found:", time_axis_path))
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# =========================================================
# 2) READ DATA
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

if (length(t_full) != length(Y_cols)) {
  stop(
    paste0(
      "Time axis length (", length(t_full),
      ") does not match number of Y columns (", length(Y_cols), ")."
    )
  )
}

# =========================================================
# 3) FILTER: region + WT + CleanOnly + Hit/FA
# =========================================================
df <- all_sessions_flmm_table %>%
  filter(
    region == region_filter,
    genotype_label == genotype_filter,
    condition == condition_filter,
    outcome %in% outcomes_keep
  ) %>%
  mutate(
    id = factor(id),
    outcome = factor(outcome, levels = outcome_levels)
  ) %>%
  filter(!is.na(id), !is.na(outcome))

if (nrow(df) == 0) {
  stop(
    paste(
      "No rows remain after filtering for",
      paste(c(region_filter, genotype_filter, condition_filter), collapse = " + "),
      "with outcomes",
      paste(outcomes_keep, collapse = " vs ")
    )
  )
}

if (nlevels(droplevels(df$outcome)) < 2) {
  stop("Both FA and Hit rows are required to fit Hit vs FA.")
}

# =========================================================
# 4) DOWNSAMPLE FUNCTIONAL DOMAIN
# =========================================================
ds_idx <- seq(1, length(Y_cols), by = ds_by)
Y_cols_ds <- Y_cols[ds_idx]
t_ds <- t_full[ds_idx]

cat("Original timepoints:", length(Y_cols), "\n")
cat("Downsampled timepoints:", length(Y_cols_ds), "\n")
cat("Rows before complete-case filtering:", nrow(df), "\n")

# =========================================================
# 5) BUILD MATRIX
# =========================================================
Y_mat <- as.matrix(df[, Y_cols_ds])
storage.mode(Y_mat) <- "numeric"

keep <- complete.cases(Y_mat)
df <- droplevels(df[keep, , drop = FALSE])
Y_mat <- Y_mat[keep, , drop = FALSE]

if (nrow(df) == 0) {
  stop("No complete cases remain after removing rows with missing signal values.")
}

if (nlevels(df$outcome) < 2) {
  stop("Only one outcome level remains after complete-case filtering.")
}

cat("Rows after complete-case filtering:", nrow(df), "\n")
cat("Outcome counts:\n")
print(table(df$outcome))
cat("Animals represented:", nlevels(df$id), "\n")

# =========================================================
# 6) BUILD fastFMM INPUT
# =========================================================
flmm_dat <- data.frame(
  Y = I(Y_mat),
  id = df$id,
  outcome = df$outcome
)

# =========================================================
# 7) FIT MODEL
#    With Hit as reference, outcomeFA is FA - Hit.
# =========================================================
fit_hit_vs_fa_wt_clean <- fui(
  Y ~ outcome + (1 | id),
  data = flmm_dat,
  argvals = t_ds
)

# =========================================================
# 8) EXPORT FIT + COEFFICIENT TABLE
# =========================================================
title_names <- c("Intercept (Hit)", "Outcome effect (FA - Hit)")

make_safe_name <- function(x) {
  gsub("[^A-Za-z0-9]+", "_", x)
}

output_stub <- make_safe_name(
  paste(
    "FLMM",
    paste0("region_", region_filter),
    paste0("genotype_", genotype_filter),
    paste0("condition_", condition_filter),
    "outcome_Hit_vs_FA",
    sep = "_"
  )
)

fit_path <- file.path(output_dir, paste0(output_stub, "_fit.rds"))
beta_path <- file.path(output_dir, paste0(output_stub, "_betaHat.csv"))
pdf_path <- file.path(output_dir, paste0(output_stub, "_coefficients.pdf"))
png_path <- file.path(output_dir, paste0(output_stub, "_coefficients.png"))

saveRDS(fit_hit_vs_fa_wt_clean, fit_path)

beta_export <- data.frame(
  time = t_ds,
  Intercept_Hit = fit_hit_vs_fa_wt_clean$betaHat[1, ],
  Outcome_effect_FA_minus_Hit = fit_hit_vs_fa_wt_clean$betaHat[2, ]
)
write_csv(beta_export, beta_path)

# =========================================================
# 9) PLOT COEFFICIENTS
# =========================================================
make_coef_plot <- function(fit_obj, coef_idx, x_time, title_text) {
  beta_df <- data.frame(
    time = x_time,
    beta = fit_obj$betaHat[coef_idx, ]
  )

  if (!is.null(fit_obj$betaHat.var)) {
    beta_se <- sqrt(pmax(diag(fit_obj$betaHat.var[, , coef_idx]), 0))
    beta_df$lower <- beta_df$beta - 1.96 * beta_se
    beta_df$upper <- beta_df$beta + 1.96 * beta_se
    beta_df$lower_joint <- beta_df$beta - fit_obj$qn[coef_idx] * beta_se
    beta_df$upper_joint <- beta_df$beta + fit_obj$qn[coef_idx] * beta_se
  }

  p <- ggplot(beta_df, aes(x = time, y = beta)) +
    theme_classic() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold")) +
    labs(
      title = title_text,
      x = "Time from cue onset (s)",
      y = "Estimate"
    ) +
    coord_cartesian(xlim = plot_time_window)

  if (!is.null(fit_obj$betaHat.var)) {
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

    sig_df <- beta_df %>%
      filter(lower_joint > 0 | upper_joint < 0)

    if (nrow(sig_df) > 0) {
      y_bottom <- min(beta_df$beta, na.rm = TRUE)
      y_span <- diff(range(beta_df$beta, na.rm = TRUE))
      if (!is.finite(y_span) || y_span == 0) {
        y_span <- 1
      }
      sig_df$y_sig <- y_bottom - 0.08 * y_span

      p <- p +
        geom_point(
          data = sig_df,
          aes(x = time, y = y_sig),
          inherit.aes = FALSE,
          shape = 15,
          size = 1.2,
          color = "black"
        )
    }
  }

  p +
    geom_hline(yintercept = 0, linetype = "dashed", color = "firebrick") +
    geom_line(linewidth = 1, color = "black")
}

plot_list <- lapply(seq_len(nrow(fit_hit_vs_fa_wt_clean$betaHat)), function(i) {
  make_coef_plot(
    fit_obj = fit_hit_vs_fa_wt_clean,
    coef_idx = i,
    x_time = t_ds,
    title_text = title_names[i]
  )
})

grDevices::pdf(pdf_path, width = 14, height = 5.5)
gridExtra::grid.arrange(grobs = plot_list, nrow = 1)
grDevices::dev.off()

grDevices::png(png_path, width = 2800, height = 1100, res = 180)
gridExtra::grid.arrange(grobs = plot_list, nrow = 1)
grDevices::dev.off()

cat("Saved fit to:", fit_path, "\n")
cat("Saved beta coefficients to:", beta_path, "\n")
cat("Saved coefficient PDF to:", pdf_path, "\n")
cat("Saved coefficient PNG to:", png_path, "\n")
