#!/usr/bin/env bash
set -euo pipefail

# Find a usable Python
PYTHON="$(command -v python3 || true)"
if [ -z "$PYTHON" ]; then
  PYTHON="$(command -v python || true)"
fi
if [ -z "$PYTHON" ]; then
  # Vercel’s Python path when python3.12 is provisioned
  if [ -x /python312/bin/python3 ]; then
    $PYTHON=/python312/bin/python3
  else
    echo "ERROR: Python not found on PATH"; exit 127
  fi
fi

echo "==> Using $($PYTHON -V)"

echo "==> Installing dependencies..."
$PYTHON -m pip install --upgrade pip wheel
$PYTHON -m pip install -r requirements.txt

# ---- OPTIONAL: run migrations during build (guarded) ----
# Set APPLY_MIGRATIONS=1 in Vercel env if you want this to run.
if [ "${APPLY_MIGRATIONS:-0}" = "1" ]; then
  if [ -n "${DATABASE_URL:-}" ]; then
    echo "==> Applying migrations (APPLY_MIGRATIONS=1)..."
    # retry up to 3 times in case DB is briefly unavailable
    n=0
    until [ $n -ge 3 ]; do
      if $PYTHON manage.py migrate --noinput; then
        break
      fi
      n=$((n+1))
      echo "Migration failed (attempt $n). Retrying in 3s..."
      sleep 3
    done
    if [ $n -ge 3 ]; then
      echo "ERROR: Migrations failed after 3 attempts"; exit 1
    fi
  else
    echo "==> Skipping migrations: DATABASE_URL is not set"
  fi
else
  echo "==> Skipping migrations: set APPLY_MIGRATIONS=1 to enable"
fi
# ---------------------------------------------------------

echo "==> Collecting static..."
$PYTHON manage.py collectstatic --noinput --clear

echo "Build step completed."
