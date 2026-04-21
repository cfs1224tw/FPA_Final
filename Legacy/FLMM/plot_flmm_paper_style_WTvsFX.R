library(readr)
library(dplyr)
library(ggplot2)
library(gridExtra)

candidate_fit_paths <- c(
  "/Users/foxking/Desktop/FPA_Final/FLMM_Results/FLMM_region_AUX_outcome_Hit_condition_CleanOnly_WT_vs_FX_fit.rds",
  "/Users/foxking/Desktop/FPA_Final/FLMM_Results/FLMM_region_AUX_outcome_Hit_condition_CleanOnly_WT_vs_FX_fit_ds500.rds"
)
candidate_beta_paths <- c(
  "/Users/foxking/Desktop/FPA_Final/FLMM_Results/FLMM_region_AUX_outcome_Hit_condition_CleanOnly_WT_vs_FX_betaHat.csv",
  "/Users/foxking/Desktop/FPA_Final/FLMM_Results/FLMM_region_AUX_outcome_Hit_condition_CleanOnly_WT_vs_FX_betaHat_ds500.csv"
)

input_fit_path <- candidate_fit_paths[file.exists(candidate_fit_paths)][1]
input_beta_path <- candidate_beta_paths[file.exists(candidate_beta_paths)][1]

if (is.na(input_fit_path) || is.na(input_beta_path)) {
  stop("No compatible WT vs FX FLMM result files were found.")
}

suffix <- if (grepl("ds500", input_fit_path)) "_ds500" else ""
output_stub <- paste0(
  "/Users/foxking/Desktop/FPA_Final/FLMM_Results/FLMM_region_AUX_outcome_Hit_condition_CleanOnly_WT_vs_FX_paper_style",
  suffix
)

fit_obj <- readRDS(input_fit_path)
beta_tbl <- read_csv(input_beta_path, show_col_types = FALSE)

coef_names <- c("Intercept (WT)", "Genotype effect (FX - WT)")
beta_cols <- c("Intercept_WT", "Genotype_effect_FX_minus_WT")

if (!all(beta_cols %in% names(beta_tbl))) {
  stop("Expected beta columns were not found in betaHat.csv.")
}

make_sig_label <- function(lower_joint, upper_joint) {
  ifelse(lower_joint > 0 | upper_joint < 0, "Joint 95% CI excludes 0", "NS")
}

make_plot_df <- function(coef_idx, coef_col) {
  df <- data.frame(
    time = beta_tbl$time,
    beta = beta_tbl[[coef_col]]
  )

  if (!is.null(fit_obj$betaHat.var)) {
    beta_se <- sqrt(pmax(diag(fit_obj$betaHat.var[, , coef_idx]), 0))
    df$lower <- df$beta - 1.96 * beta_se
    df$upper <- df$beta + 1.96 * beta_se
    df$lower_joint <- df$beta - fit_obj$qn[coef_idx] * beta_se
    df$upper_joint <- df$beta + fit_obj$qn[coef_idx] * beta_se
    df$sig_joint <- make_sig_label(df$lower_joint, df$upper_joint)
  }

  df
}

make_coef_plot <- function(plot_df, title_text) {
  p <- ggplot(plot_df, aes(x = time, y = beta)) +
    theme_classic(base_size = 12) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold"),
      axis.title = element_text(face = "bold")
    ) +
    labs(
      title = title_text,
      x = "Time from cue onset (s)",
      y = expression(hat(beta)(s))
    ) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "firebrick")

  if (all(c("lower_joint", "upper_joint") %in% names(plot_df))) {
    p <- p +
      geom_ribbon(
        aes(ymin = lower_joint, ymax = upper_joint),
        fill = "grey80",
        alpha = 0.9
      ) +
      geom_ribbon(
        aes(ymin = lower, ymax = upper),
        fill = "grey45",
        alpha = 0.5
      )
  }

  if ("sig_joint" %in% names(plot_df)) {
    sig_df <- plot_df %>%
      filter(sig_joint == "Joint 95% CI excludes 0")

    if (nrow(sig_df) > 0) {
      y_bottom <- min(plot_df$beta, na.rm = TRUE)
      y_span <- diff(range(plot_df$beta, na.rm = TRUE))
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
          size = 1.3,
          color = "black"
        )
    }
  }

  p + geom_line(linewidth = 1.1, color = "black")
}

plot_list <- lapply(seq_along(beta_cols), function(i) {
  plot_df <- make_plot_df(i, beta_cols[i])
  make_coef_plot(plot_df, coef_names[i])
})

pdf_path <- paste0(output_stub, ".pdf")
png_path <- paste0(output_stub, ".png")

grDevices::pdf(pdf_path, width = 14, height = 5.5)
grid.arrange(grobs = plot_list, nrow = 1)
grDevices::dev.off()

grDevices::png(png_path, width = 2800, height = 1100, res = 180)
grid.arrange(grobs = plot_list, nrow = 1)
grDevices::dev.off()

message("Saved paper-style PDF to: ", pdf_path)
message("Saved paper-style PNG to: ", png_path)
