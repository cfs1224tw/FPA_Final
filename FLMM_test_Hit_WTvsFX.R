library(readr)
library(dplyr)
library(fastFMM)
library(ggplot2)

# =========================================================
# 1) READ DATA
# =========================================================
all_sessions_flmm_table <- read_csv(
  "Desktop/FP_Project/FLMM_Table/all_sessions_flmm_table.csv",
  show_col_types = FALSE
)

# =========================================================
# 2) RENAME FUNCTIONAL COLUMNS: Y.1 -> Y_1
# =========================================================
colnames(all_sessions_flmm_table) <- gsub("^Y\\.", "Y_", colnames(all_sessions_flmm_table))

# =========================================================
# 3) FILTER: AUX + Hit only
# =========================================================
df <- all_sessions_flmm_table %>%
  filter(region == "AUX", outcome == "Hit") %>% #region: AUX/PFC
  mutate(
    id = factor(id),
    genotype = factor(genotype_label, levels = c("WT", "FX"))
  ) %>%
  filter(!is.na(id), !is.na(genotype))

# =========================================================
# 4) GET FUNCTIONAL COLUMNS
# =========================================================
Y_cols <- grep("^Y_", names(df), value = TRUE)

if (length(Y_cols) == 0) {
  stop("No Y_ columns found.")
}

# =========================================================
# 5) OPTIONAL: DOWNSAMPLE THE TIME AXIS
#    Start with every 100th point
# =========================================================
ds_by <- 100
Y_cols_ds <- Y_cols[seq(1, length(Y_cols), by = ds_by)]

cat("Original timepoints:", length(Y_cols), "\n")
cat("Downsampled timepoints:", length(Y_cols_ds), "\n")

t_full <- seq(-12, 12, length.out = length(Y_cols))
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
# 9) PLOT
# =========================================================
p <- plot_fui(
  fit_hit_aux_wt_fx,
  title_names = c("Intercept (WT)", "Genotype effect (FX - WT)"),
  xlab = "Downsampled time index"
)

print(p)