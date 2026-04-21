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
if (!exists("table_path", inherits = FALSE)) {
  table_path <- "/Users/foxking/Desktop/FPA_Final/FLMM_Export_CSV/all_sessions_flmm_table.csv"
}
if (!exists("time_axis_path", inherits = FALSE)) {
  time_axis_path <- "/Users/foxking/Desktop/FPA_Final/FLMM_Export_CSV/time_axis.csv"
}
if (!exists("output_dir", inherits = FALSE)) {
  output_dir <- "/Users/foxking/Desktop/FPA_Final/FLMM_Results"
}

# Keep these filters narrow if you want a smaller/faster analysis.
# Set either one to NULL to keep all values.
if (!exists("region_filter", inherits = FALSE)) {
  region_filter <- "AUX"
}
if (!exists("outcome_filter", inherits = FALSE)) {
  outcome_filter <- NULL
}

if (!exists("genotype_reference", inherits = FALSE)) {
  genotype_reference <- "WT"
}
if (!exists("condition_reference", inherits = FALSE)) {
  condition_reference <- NULL
}

# Start coarse for a large export, then decrease if you want finer timing.
if (!exists("ds_by", inherits = FALSE)) {
  ds_by <- 100
}

# Plot only this time window while keeping the full fitted domain.
if (!exists("plot_time_window", inherits = FALSE)) {
  plot_time_window <- c(-2, 10)
}

if (is.null(outcome_filter)) {
  message(
    paste(
      "outcome_filter is NULL, so this FLMM pools Hit, FA, Omission, and Other trials.",
      "For outcome-specific contrasts such as Hit WT vs FX in CleanOnly,",
      "set outcome_filter <- \"Hit\" before sourcing this script or run",
      "FLMM_test_Genotype_Condition_Hit.R."
    )
  )
} else {
  message("Running outcome-specific FLMM with outcome_filter = ", outcome_filter)
}

# =========================================================
# 2) CHECK INPUTS
# =========================================================
if (!file.exists(table_path)) {
  stop(paste("Table file not found:", table_path))
}

if (!file.exists(time_axis_path)) {
  stop(paste("Time axis file not found:", time_axis_path))
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# =========================================================
# 3) DISCOVER FUNCTIONAL COLUMNS
# =========================================================
table_header <- read_csv(table_path, n_max = 0, show_col_types = FALSE)
Y_cols <- grep("^Y[._]", names(table_header), value = TRUE)

if (length(Y_cols) == 0) {
  stop("No functional Y columns found.")
}

meta_cols <- c("id", "genotype_label", "condition", "region", "outcome")
select_cols <- c(meta_cols, Y_cols)

# =========================================================
# 4) READ DATA
#    Read only the columns needed for this FLMM.
# =========================================================
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

  # Prefer the last numeric column so files like [time_index, time_sec]
  # resolve to the actual time axis instead of the integer index.
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
# 5) FILTER AND PREP FACTORS
# =========================================================
df <- all_sessions_flmm_table

if (!is.null(region_filter)) {
  df <- df %>% filter(region == region_filter)
}

if (!is.null(outcome_filter)) {
  df <- df %>% filter(outcome == outcome_filter)
}

df <- df %>%
  mutate(
    id = factor(id),
    genotype = factor(genotype_label)
  ) %>%
  filter(
    !is.na(id),
    !is.na(genotype),
    !is.na(condition),
    nzchar(as.character(condition))
  )

if (nrow(df) == 0) {
  stop("No rows remain after applying filters.")
}

if (genotype_reference %in% unique(as.character(df$genotype))) {
  genotype_levels <- c(
    genotype_reference,
    sort(setdiff(unique(as.character(df$genotype)), genotype_reference))
  )
} else {
  genotype_levels <- sort(unique(as.character(df$genotype)))
}

df$genotype <- factor(df$genotype, levels = genotype_levels)

condition_levels <- sort(unique(as.character(df$condition)))
if (!is.null(condition_reference) && condition_reference %in% condition_levels) {
  condition_levels <- c(
    condition_reference,
    setdiff(condition_levels, condition_reference)
  )
}
df$condition <- factor(df$condition, levels = condition_levels)

# =========================================================
# 6) DOWNSAMPLE FUNCTIONAL DOMAIN
# =========================================================
ds_idx <- seq(1, length(Y_cols), by = ds_by)
Y_cols_ds <- Y_cols[ds_idx]
t_ds <- t_full[ds_idx]

message("Original timepoints: ", length(Y_cols))
message("Downsampled timepoints: ", length(Y_cols_ds))
message("Rows before complete-case filtering: ", nrow(df))

# =========================================================
# 7) BUILD MATRIX
# =========================================================
Y_mat <- as.matrix(df[, Y_cols_ds])
storage.mode(Y_mat) <- "numeric"

keep <- complete.cases(Y_mat)
df <- df[keep, , drop = FALSE]
Y_mat <- Y_mat[keep, , drop = FALSE]

if (nrow(df) == 0) {
  stop("No complete cases remain after removing rows with missing Y values.")
}

message("Rows after complete-case filtering: ", nrow(df))
message("Genotype levels used: ", paste(levels(df$genotype), collapse = ", "))
message("Condition levels used: ", paste(levels(df$condition), collapse = ", "))

# =========================================================
# 8) BUILD fastFMM INPUT AND FORMULA
# =========================================================
fixed_terms <- character(0)

if (nlevels(df$genotype) > 1 && nlevels(df$condition) > 1) {
  fixed_terms <- "genotype * condition"
} else if (nlevels(df$genotype) > 1) {
  fixed_terms <- "genotype"
} else if (nlevels(df$condition) > 1) {
  fixed_terms <- "condition"
}

fixed_formula <- if (length(fixed_terms) == 0) "1" else fixed_terms
model_formula <- as.formula(paste("Y ~", fixed_formula, "+ (1 | id)"))

flmm_dat <- data.frame(
  Y = I(Y_mat),
  id = df$id,
  genotype = df$genotype,
  condition = df$condition
)

design_formula <- as.formula(paste("~", fixed_formula))
design_matrix <- model.matrix(design_formula, data = flmm_dat)
coef_names <- colnames(design_matrix)

message("Model formula: ", deparse(model_formula))

# =========================================================
# 9) FIT MODEL
# =========================================================
fit_genotype_condition <- fui(
  model_formula,
  data = flmm_dat,
  argvals = t_ds
)

# =========================================================
# 10) EXPORT FIT + COEFFICIENT TABLE
# =========================================================
make_safe_name <- function(x) {
  gsub("[^A-Za-z0-9]+", "_", x)
}

label_parts <- c("FLMM")
if (!is.null(region_filter)) {
  label_parts <- c(label_parts, paste0("region_", region_filter))
}
if (!is.null(outcome_filter)) {
  label_parts <- c(label_parts, paste0("outcome_", outcome_filter))
}
label_parts <- c(label_parts, "genotype_condition")
output_stub <- make_safe_name(paste(label_parts, collapse = "_"))

saveRDS(
  fit_genotype_condition,
  file = file.path(output_dir, paste0(output_stub, "_fit.rds"))
)

beta_export <- data.frame(time = t_ds)
for (i in seq_len(nrow(fit_genotype_condition$betaHat))) {
  beta_export[[make_safe_name(coef_names[i])]] <- fit_genotype_condition$betaHat[i, ]
}

write_csv(
  beta_export,
  file.path(output_dir, paste0(output_stub, "_betaHat.csv"))
)

# =========================================================
# 10B) BUILD PER-CONDITION GENOTYPE CONTRASTS
#     Goal: FX - WT within each condition over time.
# =========================================================
make_interaction_name <- function(genotype_level, condition_level) {
  paste0("genotype", genotype_level, ":condition", condition_level)
}

make_condition_label <- function(condition_level) {
  gsub("([a-z])([A-Z])", "\\1 \\2", condition_level)
}

extract_condition_genotype_contrasts <- function(
  fit_obj,
  coef_names,
  x_time,
  df_model,
  genotype_reference
) {
  genotype_levels <- levels(df_model$genotype)
  condition_levels <- levels(df_model$condition)

  nonref_genotypes <- setdiff(genotype_levels, genotype_reference)
  if (length(nonref_genotypes) == 0) {
    return(list(contrast_df = NULL, contrast_plots = list()))
  }

  count_table <- with(df_model, table(genotype, condition))
  contrast_rows <- list()
  contrast_plots <- list()

  for (geno_level in nonref_genotypes) {
    main_name <- paste0("genotype", geno_level)
    main_idx <- which(coef_names == main_name)

    if (length(main_idx) != 1) {
      next
    }

    for (cond_level in condition_levels) {
      wt_n <- if (genotype_reference %in% rownames(count_table) &&
                  cond_level %in% colnames(count_table)) {
        as.integer(count_table[genotype_reference, cond_level])
      } else {
        0L
      }

      geno_n <- if (geno_level %in% rownames(count_table) &&
                    cond_level %in% colnames(count_table)) {
        as.integer(count_table[geno_level, cond_level])
      } else {
        0L
      }

      # Skip conditions where the requested genotype contrast is not
      # empirically estimable because one genotype is absent.
      if (wt_n == 0L || geno_n == 0L) {
        next
      }

      interaction_name <- make_interaction_name(geno_level, cond_level)
      interaction_idx <- which(coef_names == interaction_name)

      estimate <- fit_obj$betaHat[main_idx, ]
      source_terms <- main_name
      approx_var <- NULL

      if (length(interaction_idx) == 1) {
        estimate <- estimate + fit_obj$betaHat[interaction_idx, ]
        source_terms <- paste(main_name, interaction_name, sep = " + ")

        # fastFMM stores variance by coefficient, but not cross-coefficient
        # covariance, so this interval is approximate when combining terms.
        if (!is.null(fit_obj$betaHat.var)) {
          approx_var <- diag(fit_obj$betaHat.var[, , main_idx]) +
            diag(fit_obj$betaHat.var[, , interaction_idx])
        }
      } else if (!is.null(fit_obj$betaHat.var)) {
        approx_var <- diag(fit_obj$betaHat.var[, , main_idx])
      }

      contrast_df <- data.frame(
        time = x_time,
        condition = cond_level,
        genotype_contrast = paste(geno_level, genotype_reference, sep = " - "),
        estimate = estimate,
        source_terms = source_terms,
        wt_n = wt_n,
        contrast_n = geno_n
      )

      if (!is.null(approx_var)) {
        approx_se <- sqrt(pmax(approx_var, 0))
        contrast_df$lower_approx <- estimate - 2 * approx_se
        contrast_df$upper_approx <- estimate + 2 * approx_se
      }

      contrast_rows[[paste(geno_level, cond_level, sep = "__")]] <- contrast_df
    }
  }

  if (length(contrast_rows) == 0) {
    return(list(contrast_df = NULL, contrast_plots = list()))
  }

  contrast_df <- bind_rows(contrast_rows)

  split_keys <- unique(contrast_df[, c("genotype_contrast", "condition")])
  for (i in seq_len(nrow(split_keys))) {
    geno_contrast <- split_keys$genotype_contrast[i]
    cond_level <- split_keys$condition[i]
    plot_df <- contrast_df %>%
      filter(
        genotype_contrast == geno_contrast,
        condition == cond_level
      )

    title_text <- paste0(
      geno_contrast,
      " in ",
      make_condition_label(cond_level)
    )

    p <- ggplot(plot_df, aes(x = time, y = estimate)) +
      theme_classic() +
      theme(plot.title = element_text(hjust = 0.5, face = "bold")) +
      labs(
        title = title_text,
        x = "Time",
        y = "Estimate"
      ) +
      coord_cartesian(xlim = plot_time_window)

    if (all(c("lower_approx", "upper_approx") %in% names(plot_df))) {
      p <- p +
        geom_ribbon(
          aes(ymin = lower_approx, ymax = upper_approx),
          fill = "steelblue4",
          alpha = 0.2
        )
    }

    p <- p +
      geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
      geom_line(linewidth = 1, color = "steelblue4")

    contrast_plots[[paste(geno_contrast, cond_level, sep = "__")]] <- p
  }

  list(
    contrast_df = contrast_df,
    contrast_plots = contrast_plots
  )
}

contrast_results <- extract_condition_genotype_contrasts(
  fit_obj = fit_genotype_condition,
  coef_names = coef_names,
  x_time = t_ds,
  df_model = df,
  genotype_reference = genotype_reference
)

if (!is.null(contrast_results$contrast_df)) {
  write_csv(
    contrast_results$contrast_df,
    file.path(output_dir, paste0(output_stub, "_genotype_contrasts_by_condition.csv"))
  )
}

# =========================================================
# 11) PLOT COEFFICIENTS
# =========================================================
pretty_coef_name <- function(x) {
  x <- gsub("^\\(Intercept\\)$", "Intercept", x)
  x <- gsub(":", " x ", x)
  x <- gsub("([a-z])([A-Z])", "\\1 \\2", x)
  x
}

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
  }

  p +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    geom_line(linewidth = 1, color = "black")
}

title_names <- vapply(coef_names, pretty_coef_name, character(1))

plot_list <- lapply(seq_len(nrow(fit_genotype_condition$betaHat)), function(i) {
  make_coef_plot(
    fit_obj = fit_genotype_condition,
    coef_idx = i,
    x_time = t_ds,
    title_text = title_names[i]
  )
})

ncol_plots <- max(1, min(2, length(plot_list)))
pdf_path <- file.path(output_dir, paste0(output_stub, "_coefficients.pdf"))
png_path <- file.path(output_dir, paste0(output_stub, "_coefficients.png"))

grDevices::pdf(pdf_path, width = 7 * ncol_plots, height = 5 * ceiling(length(plot_list) / ncol_plots))
gridExtra::grid.arrange(grobs = plot_list, ncol = ncol_plots)
grDevices::dev.off()

grDevices::png(png_path, width = 1400 * ncol_plots, height = 900 * ceiling(length(plot_list) / ncol_plots), res = 160)
gridExtra::grid.arrange(grobs = plot_list, ncol = ncol_plots)
grDevices::dev.off()

message("Saved fit to: ", file.path(output_dir, paste0(output_stub, "_fit.rds")))
message("Saved beta coefficients to: ", file.path(output_dir, paste0(output_stub, "_betaHat.csv")))
message("Saved coefficient PDF to: ", pdf_path)
message("Saved coefficient PNG to: ", png_path)

if (length(contrast_results$contrast_plots) > 0) {
  contrast_pdf_path <- file.path(output_dir, paste0(output_stub, "_genotype_contrasts_by_condition.pdf"))
  contrast_png_path <- file.path(output_dir, paste0(output_stub, "_genotype_contrasts_by_condition.png"))
  contrast_plot_list <- unname(contrast_results$contrast_plots)
  contrast_ncol <- max(1, min(2, length(contrast_plot_list)))

  grDevices::pdf(
    contrast_pdf_path,
    width = 7 * contrast_ncol,
    height = 5 * ceiling(length(contrast_plot_list) / contrast_ncol)
  )
  gridExtra::grid.arrange(grobs = contrast_plot_list, ncol = contrast_ncol)
  grDevices::dev.off()

  grDevices::png(
    contrast_png_path,
    width = 1400 * contrast_ncol,
    height = 900 * ceiling(length(contrast_plot_list) / contrast_ncol),
    res = 160
  )
  gridExtra::grid.arrange(grobs = contrast_plot_list, ncol = contrast_ncol)
  grDevices::dev.off()

  message(
    "Saved genotype contrasts by condition CSV to: ",
    file.path(output_dir, paste0(output_stub, "_genotype_contrasts_by_condition.csv"))
  )
  message("Saved genotype contrast PDF to: ", contrast_pdf_path)
  message("Saved genotype contrast PNG to: ", contrast_png_path)
} else {
  message("No estimable genotype-by-condition contrasts were available to plot.")
}
