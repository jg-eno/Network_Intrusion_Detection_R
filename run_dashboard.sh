#!/bin/bash

# Network Intrusion Detection - Dashboard Replication Script
# This script runs the full ML pipeline and launches the UI securely.

echo "========================================================"
echo "   Network Intrusion Detection System - R Pipeline"
echo "========================================================"
echo ""

# Step 1: Execute the R Machine Learning Pipeline
echo "[1/3] Executing Random Forest models and generating data..."
Rscript network_intrusion_pipeline.R

# Step 2: Verify data output
if [ ! -f "dashboard/data.json" ]; then
    echo "❌ Error: dashboard/data.json was not generated."
    echo "Please ensure you have R installed along with 'caret', 'randomForest', and 'jsonlite' packages."
    exit 1
fi
echo "[2/3] Data successfully aggregated into dashboard/data.json!"

# Step 3: Launch Web Server to view the UI
echo "[3/3] Launching interactive Shadcn Dashboard..."
cd dashboard

echo ""
echo "========================================================"
echo "✅ Dashboard is Live!"
echo "🌐 Open your browser and navigate to: http://localhost:8000"
echo "🛑 Press Ctrl+C to stop the local server"
echo "========================================================"

# Try Python 3 first, fallback to Python 2 if necessary
if command -v python3 &>/dev/null; then
    python3 -m http.server 8000
elif command -v python &>/dev/null; then
    python -m SimpleHTTPServer 8000
else
    echo "❌ Error: Python is required to run the local web server."
    echo "Alternatively, you can open dashboard/index.html directly in your browser."
    exit 1
fi
