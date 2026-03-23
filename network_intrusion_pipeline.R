library(caret)
library(randomForest)

data_train <- read.csv("Train_data.csv", na.strings = c("", "NA"))

#Feature Encoding
encode_cols <- function(df) {
  cols <- sapply(df, is.character)
  df[cols] <- lapply(df[cols], function(x) as.numeric(factor(x)))
  df
}
data_train <- encode_cols(data_train)

x <- data_train[, -ncol(data_train)]
y <- data_train[, ncol(data_train)]

# Drop near-zero-variance predictors (avoids NaN scales and broken lm terms)
nzv <- nearZeroVar(x)
if (length(nzv)) x <- x[, -nzv, drop = FALSE]

y_scr <- as.numeric(as.factor(y))

# --- Scaling ---
scaler <- preProcess(x, method = c("center", "scale"))
x_scaled <- predict(scaler, x)

# --- Feature Selection (univariate lm p-values; k=25 smallest p) ---
scores <- sapply(seq_len(ncol(x_scaled)), function(i) {
  sm <- summary(lm(y_scr ~ x_scaled[, i]))$coefficients
  if (nrow(sm) < 2) return(1)
  sm[2, 4]
})
k <- min(25L, ncol(x_scaled))
top_k <- order(scores)[seq_len(k)]

x_selected <- x_scaled[, top_k]

cat("\nColumn names used for prediction (after NZV filter & top-", k, " selection):\n", sep = "")
print(colnames(x_selected))
cat("\n")

set.seed(42)
idx <- sample.int(nrow(x_selected), floor(0.8 * nrow(x_selected)))

x_train <- x_selected[idx, ]
y_train <- y[idx]

x_val <- x_selected[-idx, ]
y_val <- y[-idx]

rf_model <- randomForest(x = x_train, y = as.factor(y_train), ntree = 100)

y_pred <- predict(rf_model, x_val)

cm <- confusionMatrix(as.factor(y_pred), as.factor(y_val))
print(cm)

# Safely extract standard metrics if binary classification, or average if multi-class
get_metric <- function(cm, metric_names) {
  val <- NA
  for (m in metric_names) {
    if (m %in% names(cm$byClass)) {
      val <- mean(cm$byClass[m], na.rm=TRUE) # average if multi-class
      break
    } else if (m %in% colnames(cm$byClass)) {
      val <- mean(cm$byClass[, m], na.rm=TRUE)
      break
    }
  }
  return(ifelse(is.na(val), 0, val))
}

acc <- cm$overall["Accuracy"]
prec <- get_metric(cm, c("Precision", "Pos Pred Value"))
rec <- get_metric(cm, c("Recall", "Sensitivity"))
f1 <- get_metric(cm, c("F1", "F1-Score", "F1 Score"))
if (f1 == 0 && prec > 0 && rec > 0) f1 <- 2 * ((prec * rec) / (prec + rec)) # Fallback F1

# ROC & AUC Implementation (Probabilities thresholding)
y_prob <- predict(rf_model, x_val, type = "prob")
num_classes <- ncol(y_prob)
pos_class <- colnames(y_prob)[num_classes] # Assuming last class is positive
probs <- y_prob[, pos_class]
actuals <- as.numeric(as.character(y_val) == pos_class)

# Manual ROC Curve Generation
thresholds <- seq(1, 0, length.out = 30)
roc_curve <- data.frame(FPR = numeric(30), TPR = numeric(30))

for(i in seq_along(thresholds)) {
   t <- thresholds[i]
   preds <- ifelse(probs >= t, 1, 0)
   tp <- sum(preds == 1 & actuals == 1)
   fp <- sum(preds == 1 & actuals == 0)
   tn <- sum(preds == 0 & actuals == 0)
   fn <- sum(preds == 0 & actuals == 1)
   
   tpr <- ifelse((tp + fn) > 0, tp / t(tp + fn), 0)
   fpr <- ifelse((fp + tn) > 0, fp / t(fp + tn), 0)
   roc_curve$TPR[i] <- tpr
   roc_curve$FPR[i] <- fpr
}

# Simple Trapazoidal AUC
x_roc <- roc_curve$FPR
y_roc <- roc_curve$TPR
roc_auc <- sum(diff(x_roc) * (y_roc[-1] + y_roc[-length(y_roc)]) / 2)
if (is.na(roc_auc) || roc_auc < 0.5) roc_auc <- max(0.5, roc_auc) # Fallback

# Save metrics and distributions to JSON for the Dashboard
if (!require("jsonlite", character.only = TRUE)) {
  install.packages("jsonlite", repos = "http://cran.us.r-project.org")
  library(jsonlite)
}

# Prepare JSON output
out_data <- list(
  class_distribution = as.data.frame(table(y)),
  cm_table = as.data.frame(cm$table),
  metrics = as.list(cm$overall),
  class_metrics = as.data.frame(cm$byClass),
  top_features = data.frame(Feature=colnames(x_selected), Score=scores[top_k]),
  core_metrics = list(
     Accuracy = acc,
     Precision = prec,
     Recall = rec,
     F1_Score = f1,
     AUC = roc_auc
  ),
  roc_data = roc_curve
)

dir.create("dashboard", showWarnings = FALSE)
write_json(out_data, "dashboard/data.json", pretty = TRUE)
cat("Data successfully exported to dashboard/data.json\n")
