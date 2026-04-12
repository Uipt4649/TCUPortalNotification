#!/bin/zsh
set -euo pipefail

cd /Users/ui/Desktop/LifelsTech/TCUPortalNotification/backend
source .venv/bin/activate

echo "[STEP] Re-authentication flow starts."
python src/run_once.py --init-session
python src/run_once.py
echo "[DONE] Session refreshed and sync completed."
