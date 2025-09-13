#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing dependencies..."
python -m pip install --upgrade pip wheel
python -m pip install -r requirements.txt

echo "==> Collecting static files..."
python manage.py collectstatic --noinput --clear

echo "Build step completed."