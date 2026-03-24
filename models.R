# Load required libraries
library(caret)
library(rpart)
library(randomForest)
library(e1071)
library(class)
library(nnet)

# Load data
data_train <- read.csv("Train_data.csv", na.strings = c("", "NA"))

# Feature Encoding
encode_cols <- function(df) {
  cols <- sapply(df, is.character)
  df[cols] <- lapply(df[cols], function(x) as.numeric(factor(x)))
  df
}
data_train <- encode_cols(data_train)

x <- data_train[, -ncol(data_train)]
y <- data_train[, ncol(data_train)]

# Drop near-zero-variance predictors
nzv <- nearZeroVar(x)
if (length(nzv)) x <- x[, -nzv, drop = FALSE]

y_scr <- as.numeric(as.factor(y))

# --- Scaling ---
scaler <- preProcess(x, method = c("center", "scale"))
x_scaled <- predict(scaler, x)

# --- Feature Selection ---
scores <- sapply(seq_len(ncol(x_scaled)), function(i) {
  sm <- summary(lm(y_scr ~ x_scaled[, i]))$coefficients
  if (nrow(sm) < 2) return(1)
  sm[2, 4]
})

k <- min(25L, ncol(x_scaled))
top_k <- order(scores)[seq_len(k)]
x_selected <- x_scaled[, top_k]

cat("\nColumn names used for prediction:\n")
print(colnames(x_selected))
cat("\n")

# Train-test split
set.seed(42)
idx <- sample.int(nrow(x_selected), floor(0.8 * nrow(x_selected)))

x_train <- x_selected[idx, ]
y_train <- as.factor(y[idx])

x_val <- x_selected[-idx, ]
y_val <- as.factor(y[-idx])

# -------------------------------
# Evaluation Function
# -------------------------------
evaluate_model <- function(pred, true, model_name) {
  cat("\n====================================================\n")
  cat(model_name, "Evaluation\n")
  cat("====================================================\n")
  
  cm <- confusionMatrix(as.factor(pred), as.factor(true))
  
  # Print full confusion matrix
  print(cm)
  
  # Overall metrics
  acc <- cm$overall["Accuracy"]
  kappa <- cm$overall["Kappa"]
  
  # Handle binary vs multiclass
  if (is.matrix(cm$byClass)) {
    precision <- mean(cm$byClass[, "Precision"], na.rm = TRUE)
    recall    <- mean(cm$byClass[, "Recall"], na.rm = TRUE)
    f1        <- mean(cm$byClass[, "F1"], na.rm = TRUE)
  } else {
    precision <- cm$byClass["Precision"]
    recall    <- cm$byClass["Recall"]
    f1        <- cm$byClass["F1"]
  }
  
  cat("\nSummary Metrics:\n")
  cat("Accuracy :", acc, "\n")
  cat("Kappa    :", kappa, "\n")
  cat("Precision:", precision, "\n")
  cat("Recall   :", recall, "\n")
  cat("F1 Score :", f1, "\n")
}

# -------------------------------
# 1. Logistic Regression
# -------------------------------
lr_model <- multinom(y_train ~ ., data = data.frame(x_train, y_train = y_train), trace = FALSE)
lr_pred <- predict(lr_model, data.frame(x_val))
evaluate_model(lr_pred, y_val, "Logistic Regression")

# -------------------------------
# 2. Decision Tree
# -------------------------------
dt_model <- rpart(y_train ~ ., data = data.frame(x_train, y_train = y_train), method = "class")
dt_pred <- predict(dt_model, data.frame(x_val), type = "class")
evaluate_model(dt_pred, y_val, "Decision Tree")

# -------------------------------
# 3. Random Forest
# -------------------------------
rf_model <- randomForest(x = x_train, y = y_train, ntree = 100)
rf_pred <- predict(rf_model, x_val)
evaluate_model(rf_pred, y_val, "Random Forest")

# -------------------------------
# 4. SVM
# -------------------------------
svm_model <- svm(x = x_train, y = y_train, type = "C-classification", kernel = "radial")
svm_pred <- predict(svm_model, x_val)
evaluate_model(svm_pred, y_val, "SVM")

# -------------------------------
# 5. KNN
# -------------------------------
knn_pred <- knn(train = x_train, test = x_val, cl = y_train, k = 5)
evaluate_model(knn_pred, y_val, "KNN")