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

print(confusionMatrix(as.factor(y_pred), as.factor(y_val)))
