#!/usr/bin/env bash
# Download sampadab17/network-intrusion-detection from Kaggle.
# The API usually requires credentials from https://www.kaggle.com/settings (API token).
#   export KAGGLE_USERNAME="your_kaggle_username"
#   export KAGGLE_KEY="your_kaggle_key"
# If both are set, Basic auth is added automatically.

set -euo pipefail

OUT="${1:-$HOME/Downloads/network-intrusion-detection.zip}"
URL="https://www.kaggle.com/api/v1/datasets/download/sampadab17/network-intrusion-detection"

mkdir -p "$(dirname "$OUT")"

if [[ -n "${KAGGLE_USERNAME:-}" && -n "${KAGGLE_KEY:-}" ]]; then
  curl -L -o "$OUT" -u "$KAGGLE_USERNAME:$KAGGLE_KEY" "$URL"
else
  curl -L -o "$OUT" "$URL"
fi

echo "Saved: $OUT"
