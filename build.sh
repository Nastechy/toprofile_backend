#!/usr/bin/env bash
set -euo pipefail

# Find a usable Python
PYTHON="$(command -v python3 || true)"
if [ -z "$PYTHON" ]; then
  PYTHON="$(command -v python || true)"
fi
if [ -z "$PYTHON" ]; then
  # Vercel’s Python path when python3.12 is provisioned /
  if [ -x /python312/bin/python3 ]; then
    PYTHON=/python312/bin/python3
  else
    echo "ERROR: Python not found on PATH"; exit 127
  fi
fi

echo "==> Using $($PYTHON -V)"

echo "==> Installing dependencies..."
$PYTHON -m pip install --upgrade pip wheel
$PYTHON -m pip install -r requirements.txt

echo "==> Collecting static..."
$PYTHON manage.py collectstatic --noinput --clear

echo "Build step completed."