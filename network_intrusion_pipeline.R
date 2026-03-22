# =============================================================================
# Network Intrusion Detection — KDD-style cleanup + logistic regression (R)
# =============================================================================
# Default data: ./data/Train_data.csv (has `class`: normal / anomaly)
#               ./data/Test_data.csv   (same features, no labels)
# Optional: NID_TRAIN_CSV, NID_TEST_CSV to override paths.
# Zip fallback: set NID_ZIP_PATH and ensure Train CSV is absent, or use
#   bash download_dataset.sh  then extract to data/raw/
# Run: Rscript network_intrusion_pipeline.R
# =============================================================================

# --- paths -------------------------------------------------------------------
TRAIN_CSV <- path.expand(Sys.getenv(
  "NID_TRAIN_CSV",
  unset = file.path(getwd(), "data", "Train_data.csv")
))
TEST_CSV <- path.expand(Sys.getenv(
  "NID_TEST_CSV",
  unset = file.path(getwd(), "data", "Test_data.csv")
))
ZIP_PATH <- path.expand(Sys.getenv(
  "NID_ZIP_PATH",
  unset = "~/Downloads/network-intrusion-detection.zip"
))
EXTRACT_DIR <- file.path(getwd(), "data", "raw")

# --- helpers -----------------------------------------------------------------
detect_label_col <- function(df) {
  nms <- names(df)
  candidates <- c(
    "class", "Class", "label", "Label", "attack", "Attack",
    "target", "Target", "outcome", "Outcome", "type", "Type"
  )
  hit <- candidates[candidates %in% nms]
  if (length(hit)) return(hit[1])
  nms[ncol(df)]
}

# normal / benign -> normal; anomaly and everything else -> malicious
to_binary_factor <- function(x) {
  s <- tolower(trimws(as.character(x)))
  is_normal <- s %in% c("normal", "benign")
  factor(ifelse(is_normal, "normal", "malicious"),
         levels = c("normal", "malicious"))
}

impute_col <- function(x) {
  if (is.numeric(x)) {
    m <- stats::median(x, na.rm = TRUE)
    x[is.na(x)] <- m
    x
  } else {
    x <- as.character(x)
    tab <- sort(table(x[!is.na(x)]), decreasing = TRUE)
    mode_val <- if (length(tab)) names(tab)[1] else "unknown"
    x[is.na(x)] <- mode_val
    x
  }
}

strip_id_columns <- function(df) {
  drop <- names(df)[grepl("^(id|index)$", names(df), ignore.case = TRUE)]
  if (length(drop)) df[, !names(df) %in% drop, drop = FALSE] else df
}

clean_labeled <- function(raw, label_name) {
  df <- raw
  y <- to_binary_factor(df[[label_name]])
  df[[label_name]] <- NULL
  df <- strip_id_columns(df)
  ok <- !duplicated(df)
  df <- df[ok, , drop = FALSE]
  y <- y[ok]

  keep <- vapply(df, function(col) {
    if (all(is.na(col))) return(FALSE)
    if (is.numeric(col)) stats::sd(col, na.rm = TRUE) > 0
    else length(unique(stats::na.omit(col))) > 1
  }, logical(1))
  df <- df[, keep, drop = FALSE]
  for (j in names(df)) df[[j]] <- impute_col(df[[j]])
  list(X = df, y = y)
}

# Test set: same feature columns as training `X`; no label column.
prepare_test <- function(raw_te, feature_names) {
  df <- strip_id_columns(raw_te)
  miss <- setdiff(feature_names, names(df))
  for (nm in miss) df[[nm]] <- NA
  df <- df[, feature_names, drop = FALSE]
  ok <- !duplicated(df)
  df <- df[ok, , drop = FALSE]
  for (j in names(df)) df[[j]] <- impute_col(df[[j]])
  df
}

resolve_csv_paths_from_zip <- function() {
  if (!file.exists(ZIP_PATH)) {
    stop(
      "No training CSV at ", TRAIN_CSV, " and no zip at ", ZIP_PATH, "\n",
      "Place Train_data.csv under data/ or run: bash download_dataset.sh"
    )
  }
  dir.create(EXTRACT_DIR, recursive = TRUE, showWarnings = FALSE)
  unzip(ZIP_PATH, exdir = EXTRACT_DIR)
  csv_files <- list.files(EXTRACT_DIR, pattern = "\\.[Cc][Ss][Vv]$",
                          full.names = TRUE, recursive = TRUE)
  if (length(csv_files) == 0) {
    stop("No CSV files under ", EXTRACT_DIR, " after unzip.")
  }
  pick_train <- function(paths) {
    low <- tolower(basename(paths))
    w <- grep("train", low)
    if (length(w)) paths[w[1]] else paths[1]
  }
  pick_test <- function(paths, train_p) {
    low <- tolower(basename(paths))
    w <- grep("test", low)
    if (length(w) == 0) return(NULL)
    for (i in w) {
      if (paths[i] != train_p) return(paths[i])
    }
    NULL
  }
  tr <- pick_train(csv_files)
  te <- pick_test(csv_files, tr)
  list(train = tr, test = te)
}

# --- KDD 1: Selection ---------------------------------------------------------
if (file.exists(TRAIN_CSV)) {
  train_path <- TRAIN_CSV
  test_path <- if (file.exists(TEST_CSV)) TEST_CSV else NULL
} else {
  zp <- resolve_csv_paths_from_zip()
  train_path <- zp$train
  test_path <- zp$test
}

raw_tr <- utils::read.csv(train_path, check.names = TRUE,
                          na.strings = c("", "NA", "N/A"))
label_tr <- detect_label_col(raw_tr)

# --- KDD 2–3: Preprocessing & transformation ---------------------------------
labeled_test <- FALSE
if (!is.null(test_path) && test_path != train_path && file.exists(test_path)) {
  raw_te <- utils::read.csv(test_path, check.names = TRUE,
                            na.strings = c("", "NA", "N/A"))
  label_te <- intersect(
    c("class", "Class", label_tr),
    names(raw_te)
  )
  labeled_test <- length(label_te) > 0
}

if (labeled_test) {
  label_te <- label_te[1]
  feats <- intersect(
    setdiff(names(raw_tr), label_tr),
    setdiff(names(raw_te), label_te)
  )
  raw_tr <- raw_tr[, c(feats, label_tr), drop = FALSE]
  names(raw_tr)[ncol(raw_tr)] <- ".__label__"
  raw_te <- raw_te[, c(feats, label_te), drop = FALSE]
  names(raw_te)[ncol(raw_te)] <- ".__label__"

  tr <- clean_labeled(raw_tr, ".__label__")
  te <- clean_labeled(raw_te, ".__label__")
  common <- intersect(names(tr$X), names(te$X))
  tr$X <- tr$X[, common, drop = FALSE]
  te$X <- te$X[, common, drop = FALSE]

  tr$X$row_part <- factor("train", levels = c("train", "test"))
  te$X$row_part <- factor("test", levels = c("train", "test"))
  combo <- rbind(tr$X, te$X)
  y_all <- c(tr$y, te$y)
  mm <- stats::model.matrix(~ . - 1 - row_part, data = combo)
  part <- combo$row_part
  X_train_full <- mm[part == "train", , drop = FALSE]
  y_train_full <- y_all[part == "train"]
  X_test_eval <- mm[part == "test", , drop = FALSE]
  y_test_eval <- y_all[part == "test"]

  fit_full <- stats::glm(
    .y ~ .,
    data = data.frame(.y = y_train_full, X_train_full, check.names = FALSE),
    family = stats::binomial()
  )
  probs_te <- stats::predict(fit_full, newdata = data.frame(X_test_eval, check.names = FALSE),
                              type = "response")
  pred_te <- factor(ifelse(probs_te >= 0.5, "malicious", "normal"),
                    levels = c("normal", "malicious"))

  cat("\n=== Labeled test set (train fit on all training rows) ===\n")
  print(table(Actual = y_test_eval, Predicted = pred_te))
  cat("Accuracy:", round(mean(pred_te == y_test_eval), 4), "\n")

  cat("\n=== First 20 coefficients ===\n")
  print(utils::head(stats::coef(fit_full), 20))
} else {
  tr <- clean_labeled(raw_tr, label_tr)
  raw_te_path <- if (!is.null(test_path)) test_path else NULL

  if (!is.null(raw_te_path)) {
    raw_te <- utils::read.csv(raw_te_path, check.names = TRUE,
                              na.strings = c("", "NA", "N/A"))
    te_X <- prepare_test(raw_te, names(tr$X))
    combo <- rbind(tr$X, te_X)
    mm <- stats::model.matrix(~ . - 1, data = combo)
    n_tr <- nrow(tr$X)
    mm_tr <- mm[seq_len(n_tr), , drop = FALSE]
    mm_te <- mm[-seq_len(n_tr), , drop = FALSE]
  } else {
    mm_tr <- stats::model.matrix(~ . - 1, data = tr$X)
    mm_te <- NULL
  }

  y_tr <- tr$y
  set.seed(42)
  n <- nrow(mm_tr)
  idx <- sample.int(n, size = floor(0.8 * n))
  X_train <- mm_tr[idx, , drop = FALSE]
  y_train <- y_tr[idx]
  X_val <- mm_tr[-idx, , drop = FALSE]
  y_val <- y_tr[-idx]

  fit <- stats::glm(.y ~ ., data = data.frame(.y = y_train, X_train, check.names = FALSE),
                    family = stats::binomial())
  probs_val <- stats::predict(fit, newdata = data.frame(X_val, check.names = FALSE),
                               type = "response")
  pred_val <- factor(ifelse(probs_val >= 0.5, "malicious", "normal"),
                     levels = c("normal", "malicious"))

  cat("\n=== Validation: 80/20 split on Train_data (labeled) ===\n")
  print(table(Actual = y_val, Predicted = pred_val))
  cat("Accuracy:", round(mean(pred_val == y_val), 4), "\n")

  fit_full <- stats::glm(
    .y ~ .,
    data = data.frame(.y = y_tr, mm_tr, check.names = FALSE),
    family = stats::binomial()
  )

  cat("\n=== First 20 coefficients (full train fit) ===\n")
  print(utils::head(stats::coef(fit_full), 20))

  if (!is.null(mm_te)) {
    probs_te <- stats::predict(fit_full, newdata = data.frame(mm_te, check.names = FALSE),
                                 type = "response")
    pred_te <- factor(ifelse(probs_te >= 0.5, "malicious", "normal"),
                      levels = c("normal", "malicious"))
    cat("\n=== Test_data.csv: predictions (no labels in file) ===\n")
    print(table(Predicted = pred_te))
    cat("(Rows scored:", length(pred_te), ")\n")
  }
}

cat("\nDone.\n")
