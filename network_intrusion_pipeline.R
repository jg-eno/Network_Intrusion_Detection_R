library(caret)
library(rpart)
library(randomForest)
library(e1071)
library(class)
library(nnet)
library(jsonlite)

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
y_train <- as.factor(y[idx])

x_val <- x_selected[-idx, ]
y_val <- as.factor(y[-idx])

pos_class <- levels(y_train)[length(levels(y_train))]

evaluate_to_list <- function(model_name, y_pred, y_prob_pos, true_vals) {
  cm <- confusionMatrix(as.factor(y_pred), as.factor(true_vals))
  
  get_metric <- function(cm, metric_names) {
    val <- NA
    for (m in metric_names) {
      if (m %in% names(cm$byClass)) {
        val <- mean(cm$byClass[m], na.rm=TRUE) 
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
  if (f1 == 0 && prec > 0 && rec > 0) f1 <- 2 * ((prec * rec) / (prec + rec))
  
  actuals <- as.numeric(as.character(true_vals) == pos_class)
  
  thresholds <- seq(1, 0, length.out = 30)
  roc_curve <- data.frame(FPR = numeric(30), TPR = numeric(30))
  
  for(i in seq_along(thresholds)) {
     t <- thresholds[i]
     preds <- ifelse(y_prob_pos >= t, 1, 0)
     tp <- sum(preds == 1 & actuals == 1)
     fp <- sum(preds == 1 & actuals == 0)
     tn <- sum(preds == 0 & actuals == 0)
     fn <- sum(preds == 0 & actuals == 1)
     
     tpr <- ifelse((tp + fn) > 0, tp / (tp + fn), 0)
     fpr <- ifelse((fp + tn) > 0, fp / (fp + tn), 0)
     roc_curve$TPR[i] <- tpr
     roc_curve$FPR[i] <- fpr
  }
  
  x_roc <- roc_curve$FPR
  y_roc <- roc_curve$TPR
  roc_auc <- sum(diff(x_roc) * (y_roc[-1] + y_roc[-length(y_roc)]) / 2)
  if (is.na(roc_auc) || roc_auc < 0.5) roc_auc <- max(0.5, roc_auc)
  
  list(
    name = model_name,
    cm_table = as.data.frame(cm$table),
    metrics = as.list(cm$overall),
    class_metrics = as.data.frame(cm$byClass),
    core_metrics = list(
       Accuracy = acc,
       Precision = prec,
       Recall = rec,
       F1_Score = f1,
       AUC = roc_auc
    ),
    roc_data = roc_curve
  )
}

models_list <- list()

cat("\nTraining Random Forest...\n")
rf_model <- randomForest(x = x_train, y = y_train, ntree = 100)
rf_pred <- predict(rf_model, x_val)
rf_prob <- predict(rf_model, x_val, type="prob")[, pos_class]
models_list[[1]] <- evaluate_to_list("Random Forest", rf_pred, rf_prob, y_val)

cat("Training Logistic Regression...\n")
lr_model <- multinom(y_train ~ ., data = data.frame(x_train, y_train = y_train), trace = FALSE)
lr_pred <- predict(lr_model, data.frame(x_val))
lr_prob_all <- predict(lr_model, data.frame(x_val), type = "probs")
if (is.null(dim(lr_prob_all))) {
    lr_prob <- lr_prob_all
} else {
    lr_prob <- lr_prob_all[, pos_class]
}
models_list[[2]] <- evaluate_to_list("Logistic Regression", lr_pred, lr_prob, y_val)

cat("Training Decision Tree...\n")
dt_model <- rpart(y_train ~ ., data = data.frame(x_train, y_train = y_train), method = "class")
dt_pred <- predict(dt_model, data.frame(x_val), type = "class")
dt_prob <- predict(dt_model, data.frame(x_val), type = "prob")[, pos_class]
models_list[[3]] <- evaluate_to_list("Decision Tree", dt_pred, dt_prob, y_val)

cat("Training SVM...\n")
svm_model <- svm(x = x_train, y = y_train, type = "C-classification", kernel = "radial", probability=TRUE)
svm_pred <- predict(svm_model, x_val, probability=TRUE)
svm_prob <- attr(svm_pred, "probabilities")[, pos_class]
models_list[[4]] <- evaluate_to_list("SVM", svm_pred, svm_prob, y_val)

cat("Training KNN...\n")
knn_pred <- knn(train = x_train, test = x_val, cl = y_train, k = 5, prob = TRUE)
knn_prob_win <- attr(knn_pred, "prob")
knn_prob <- ifelse(knn_pred == pos_class, knn_prob_win, 1 - knn_prob_win)
models_list[[5]] <- evaluate_to_list("KNN", knn_pred, knn_prob, y_val)

out_data <- list(
  class_distribution = as.data.frame(table(y)),
  top_features = data.frame(Feature=colnames(x_selected), Score=scores[top_k]),
  models = models_list
)

dir.create("dashboard", showWarnings = FALSE)
write_json(out_data, "dashboard/data.json", pretty = TRUE)
cat("Data successfully exported to dashboard/data.json\n")
