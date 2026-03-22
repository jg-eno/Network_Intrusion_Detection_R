# Network Intrusion Detection (R)

KDD-style cleanup and **logistic regression** to distinguish **normal** vs **malicious** traffic (`anomaly` in the data is treated as malicious). Default inputs are `data/Train_data.csv` (labeled) and `data/Test_data.csv` (features only).

## Prerequisites

- [R](https://www.r-project.org/) (uses base R only: `stats`, `utils`)
- `bash` and `curl` if you download the dataset from the command line

## Get the data

### Option 1: Files already in the repo

If `data/Train_data.csv` and `data/Test_data.csv` are present, you can skip downloading.

### Option 2: Download with cURL (Kaggle API)

The API normally requires your Kaggle credentials (from [Kaggle → Settings → API](https://www.kaggle.com/settings): create a token and use the username and key).

```bash
export KAGGLE_USERNAME="your_kaggle_username"
export KAGGLE_KEY="your_kaggle_key"

curl -L -o ~/Downloads/network-intrusion-detection.zip \
  -u "${KAGGLE_USERNAME}:${KAGGLE_KEY}" \
  "https://www.kaggle.com/api/v1/datasets/download/sampadab17/network-intrusion-detection"
```

Then unzip and copy the CSVs into this project’s `data/` folder (names should match **`Train_data.csv`** and **`Test_data.csv`**, or set paths via environment variables below).

### Option 3: Helper script

From the project root:

```bash
export KAGGLE_USERNAME="your_kaggle_username"
export KAGGLE_KEY="your_kaggle_key"

bash download_dataset.sh
```

This saves `~/Downloads/network-intrusion-detection.zip` by default. You can pass another path: `bash download_dataset.sh /path/to/archive.zip`.

Unzip the archive and place **`Train_data.csv`** and **`Test_data.csv`** under `data/`.

## Run the pipeline

From the project root:

```bash
cd /path/to/Network_Intrusion_Detection_R
Rscript network_intrusion_pipeline.R
```

### Optional environment variables

| Variable | Purpose |
|----------|---------|
| `NID_TRAIN_CSV` | Path to the training CSV (default: `./data/Train_data.csv`) |
| `NID_TEST_CSV` | Path to the test CSV (default: `./data/Test_data.csv`) |
| `NID_ZIP_PATH` | Zip path used only if the training CSV is **missing** (default: `~/Downloads/network-intrusion-detection.zip`) |

Example:

```bash
NID_TRAIN_CSV="$HOME/mydata/Train_data.csv" \
NID_TEST_CSV="$HOME/mydata/Test_data.csv" \
Rscript network_intrusion_pipeline.R
```

## What the script does

- **KDD-style steps**: selection, cleaning (duplicates, empty/constant columns, simple imputation), dummy encoding, **logistic regression** (`glm` binomial), evaluation.
- **Train file**: `class` column (`normal` / `anomaly`); reports an **80/20 validation** accuracy on the training set and fits on all training rows for scoring.
- **Test file**: if there is no `class` column, the script prints **prediction counts** only (no test accuracy without labels).

Extracted zip contents (when using the zip fallback) are written under `data/raw/`.
