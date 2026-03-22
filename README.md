# Network Intrusion Detection (R)

Pipeline: encode categoricals, drop near-zero-variance columns, scale features, pick 25 columns by univariate linear-model *p*-values, **80/20 split**, **random forest** (100 trees), then print a **caret** confusion matrix on the hold-out set.

## Requirements

- [R](https://www.r-project.org/) (3.5+ recommended)
- **`Train_data.csv`** in the **project root** (same folder as `network_intrusion_pipeline.R`; see [Run](#run))

## Install R packages

In R or the shell:

```r
install.packages(c("caret", "randomForest"), repos = "https://cloud.r-project.org")
```

```bash
Rscript -e 'install.packages(c("caret", "randomForest"), repos="https://cloud.r-project.org")'
```

`caret` will pull in its dependencies (e.g. `ggplot2`, `lattice`) automatically.

## Data

Keep **`Train_data.csv`** in the **repository root**. The last column is the class label; all other columns are features.

Optional download (needs [Kaggle API credentials](https://www.kaggle.com/settings)):

```bash
export KAGGLE_USERNAME="your_kaggle_username"
export KAGGLE_KEY="your_kaggle_key"
curl -L -o ~/Downloads/network-intrusion-detection.zip \
  -u "${KAGGLE_USERNAME}:${KAGGLE_KEY}" \
  "https://www.kaggle.com/api/v1/datasets/download/sampadab17/network-intrusion-detection"
```

Unzip and copy **`Train_data.csv`** into the project root, or run `bash download_dataset.sh` and unzip the archive the same way.

## Run

From the project root (so `Train_data.csv` and `network_intrusion_pipeline.R` are in the current directory):

```bash
cd /path/to/Network_Intrusion_Detection_R
Rscript network_intrusion_pipeline.R
```
