#!/usr/bin/env bash
set -Eeuo pipefail

GIT_ASKPASS_FILE=""
cleanup() {
  if [[ -n "${GIT_ASKPASS_FILE:-}" && -f "${GIT_ASKPASS_FILE:-}" ]]; then
    rm -f "$GIT_ASKPASS_FILE"
  fi
}
trap cleanup EXIT

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

log() { printf "\n[INFO] %s\n" "$1"; }
warn() { printf "\n[WARN] %s\n" "$1"; }
err() { printf "\n[ERROR] %s\n" "$1" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "$1 is required before running this script."
    exit 1
  }
}

escape_squote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

read_multiline_env() {
  declare -gA EXTRA_ENV=()
  printf "\nPaste extra env values as KEY=VALUE (one per line).\n"
  printf "Press Enter on an empty line when done.\n\n"

  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" != *=* ]]; then
      warn "Skipping invalid entry (expected KEY=VALUE): $line"
      continue
    fi

    local key value
    key="${line%%=*}"
    value="${line#*=}"
    key="$(printf "%s" "$key" | xargs)"

    if [[ -z "$key" ]]; then
      warn "Skipping empty key in line: $line"
      continue
    fi

    EXTRA_ENV["$key"]="$value"
  done
}

require_cmd curl

read -r -p "GitHub repo URL [https://github.com/Nastechy/toprofile_backend.git]: " REPO_URL
REPO_URL=${REPO_URL:-https://github.com/Nastechy/toprofile_backend.git}

read -r -p "Git branch [main]: " GIT_BRANCH
GIT_BRANCH=${GIT_BRANCH:-main}

read -r -p "Is this a private GitHub repo? [y/N]: " PRIVATE_REPO_INPUT
PRIVATE_REPO_INPUT=${PRIVATE_REPO_INPUT:-N}
PRIVATE_REPO_INPUT=$(printf "%s" "$PRIVATE_REPO_INPUT" | tr '[:upper:]' '[:lower:]')

if [[ "$PRIVATE_REPO_INPUT" == "y" || "$PRIVATE_REPO_INPUT" == "yes" ]]; then
  read -r -p "GitHub username: " GIT_USERNAME
  read -r -s -p "GitHub token (PAT): " GIT_PASSWORD
  printf "\n"

  GIT_ASKPASS_FILE="$(mktemp)"
  chmod 700 "$GIT_ASKPASS_FILE"
  cat > "$GIT_ASKPASS_FILE" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "${GIT_USERNAME:-}" ;;
  *Password*) printf '%s\n' "${GIT_PASSWORD:-}" ;;
  *) printf '\n' ;;
esac
ASKPASS

  export GIT_TERMINAL_PROMPT=0
  export GIT_ASKPASS="$GIT_ASKPASS_FILE"
  export GIT_USERNAME
  export GIT_PASSWORD
fi

DEFAULT_USER="${SUDO_USER:-$USER}"
read -r -p "Linux user to own/run app [${DEFAULT_USER}]: " APP_USER
APP_USER=${APP_USER:-$DEFAULT_USER}
id "$APP_USER" >/dev/null 2>&1 || {
  err "User '$APP_USER' does not exist."
  exit 1
}

read -r -p "Deploy directory [/var/www/toprofile_backend]: " DEPLOY_DIR
DEPLOY_DIR=${DEPLOY_DIR:-/var/www/toprofile_backend}

read -r -p "Python version package [python3.12]: " PYTHON_PKG
PYTHON_PKG=${PYTHON_PKG:-python3.12}

read -r -p "Virtualenv directory name [.venv]: " VENV_NAME
VENV_NAME=${VENV_NAME:-.venv}

read -r -p "Systemd service name [toprofile-backend]: " SERVICE_NAME
SERVICE_NAME=${SERVICE_NAME:-toprofile-backend}

read -r -p "Gunicorn bind port [8000]: " GUNICORN_PORT
GUNICORN_PORT=${GUNICORN_PORT:-8000}

read -r -p "Public IPv4 for nginx server_name [138.68.157.12]: " SERVER_IP
SERVER_IP=${SERVER_IP:-138.68.157.12}

read -r -p "Expose API base path [/api/v1/]: " API_BASE_PATH
API_BASE_PATH=${API_BASE_PATH:-/api/v1/}

read -r -p "PostgreSQL DB name [toprofile_db]: " PG_DB
PG_DB=${PG_DB:-toprofile_db}

read -r -p "PostgreSQL DB user [toprofile_user]: " PG_USER
PG_USER=${PG_USER:-toprofile_user}

read -r -s -p "PostgreSQL DB password: " PG_PASSWORD
printf "\n"
if [[ -z "$PG_PASSWORD" ]]; then
  err "PostgreSQL password cannot be empty."
  exit 1
fi

read -r -p "PostgreSQL host [127.0.0.1]: " PG_HOST
PG_HOST=${PG_HOST:-127.0.0.1}

read -r -p "PostgreSQL port [5432]: " PG_PORT
PG_PORT=${PG_PORT:-5432}

read -r -p "Redis URL [redis://127.0.0.1:6379/0]: " REDIS_URL
REDIS_URL=${REDIS_URL:-redis://127.0.0.1:6379/0}

read -r -p "DJANGO_SETTINGS_MODULE [toprofile.settings]: " DJANGO_SETTINGS_MODULE
DJANGO_SETTINGS_MODULE=${DJANGO_SETTINGS_MODULE:-toprofile.settings}

read -r -p "DEBUG [False]: " DEBUG_VALUE
DEBUG_VALUE=${DEBUG_VALUE:-False}

read -r -p "ALLOWED_HOSTS [127.0.0.1,localhost,${SERVER_IP}]: " ALLOWED_HOSTS_VALUE
ALLOWED_HOSTS_VALUE=${ALLOWED_HOSTS_VALUE:-127.0.0.1,localhost,${SERVER_IP}}

read -r -s -p "NEW_SECRET (leave empty to auto-generate): " NEW_SECRET
printf "\n"
if [[ -z "$NEW_SECRET" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    NEW_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
  else
    NEW_SECRET="$(date +%s)-$(whoami)-toprofile-secret"
    warn "openssl not found; generated fallback NEW_SECRET."
  fi
fi

DATABASE_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PG_DB}"

printf "\nDefault env values this script will create (you can override in the next prompt):\n"
printf "- DEBUG=%s\n" "$DEBUG_VALUE"
printf "- DJANGO_SETTINGS_MODULE=%s\n" "$DJANGO_SETTINGS_MODULE"
printf "- NEW_SECRET=***hidden***\n"
printf "- ALLOWED_HOSTS=%s\n" "$ALLOWED_HOSTS_VALUE"
printf "- DATABASE_URL=%s\n" "$DATABASE_URL"
printf "- REDIS_URL=%s\n" "$REDIS_URL"
printf "- EMAIL_HOST_USER=\n"
printf "- EMAIL_HOST_PASSWORD=\n"
printf "- CLOUDINARY_CLOUD_NAME=\n"
printf "- CLOUDINARY_API_KEY=\n"
printf "- CLOUDINARY_API_SECRET=\n"

read_multiline_env

log "Installing system packages (Ubuntu 24: nginx, git, Python, PostgreSQL, Redis)"
$SUDO apt-get update -y
$SUDO apt-get install -y nginx git build-essential libpq-dev \
  "$PYTHON_PKG" "${PYTHON_PKG}-venv" "${PYTHON_PKG}-dev" python3-pip \
  postgresql postgresql-contrib redis-server

$SUDO systemctl enable postgresql
$SUDO systemctl restart postgresql
$SUDO systemctl enable redis-server
$SUDO systemctl restart redis-server

log "Configuring PostgreSQL database/user"
PG_USER_ESCAPED="$(escape_squote "$PG_USER")"
PG_DB_ESCAPED="$(escape_squote "$PG_DB")"
PG_PASSWORD_ESCAPED="$(escape_squote "$PG_PASSWORD")"

if ! $SUDO -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER_ESCAPED}'" | grep -q 1; then
  $SUDO -u postgres psql -c "CREATE USER \"${PG_USER}\" WITH PASSWORD '${PG_PASSWORD_ESCAPED}';"
else
  warn "PostgreSQL user '${PG_USER}' already exists."
  $SUDO -u postgres psql -c "ALTER USER \"${PG_USER}\" WITH PASSWORD '${PG_PASSWORD_ESCAPED}';"
fi

if ! $SUDO -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${PG_DB_ESCAPED}'" | grep -q 1; then
  $SUDO -u postgres psql -c "CREATE DATABASE \"${PG_DB}\" OWNER \"${PG_USER}\";"
else
  warn "PostgreSQL database '${PG_DB}' already exists."
fi

log "Preparing deploy directory: ${DEPLOY_DIR}"
$SUDO mkdir -p "$DEPLOY_DIR"
$SUDO chown -R "$APP_USER":"$APP_USER" "$DEPLOY_DIR"

if [[ -d "$DEPLOY_DIR/.git" ]]; then
  log "Existing repo found. Pulling latest branch ${GIT_BRANCH}"
  git -C "$DEPLOY_DIR" remote set-url origin "$REPO_URL"
  git -C "$DEPLOY_DIR" fetch --all --prune
  git -C "$DEPLOY_DIR" checkout "$GIT_BRANCH"
  git -C "$DEPLOY_DIR" pull --ff-only origin "$GIT_BRANCH"
else
  log "Cloning repository"
  rm -rf "$DEPLOY_DIR"/*
  git clone --branch "$GIT_BRANCH" "$REPO_URL" "$DEPLOY_DIR"
fi
$SUDO chown -R "$APP_USER":"$APP_USER" "$DEPLOY_DIR"

APP_DIR="$DEPLOY_DIR"
VENV_PATH="$APP_DIR/$VENV_NAME"

if [[ ! -f "$APP_DIR/manage.py" ]]; then
  err "Could not find manage.py in $APP_DIR"
  exit 1
fi

log "Writing backend environment file"
ENV_FILE="$APP_DIR/.env"
mkdir -p "$APP_DIR/media"
cat > "$ENV_FILE" <<EOF
DEBUG=${DEBUG_VALUE}
DJANGO_SETTINGS_MODULE=${DJANGO_SETTINGS_MODULE}
NEW_SECRET=${NEW_SECRET}
ALLOWED_HOSTS=${ALLOWED_HOSTS_VALUE}
DATABASE_URL=${DATABASE_URL}
REDIS_URL=${REDIS_URL}
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
CLOUDINARY_CLOUD_NAME=
CLOUDINARY_API_KEY=
CLOUDINARY_API_SECRET=
EOF

for key in "${!EXTRA_ENV[@]}"; do
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${EXTRA_ENV[$key]}|" "$ENV_FILE"
  else
    printf "%s=%s\n" "$key" "${EXTRA_ENV[$key]}" >> "$ENV_FILE"
  fi
done

chown "$APP_USER":"$APP_USER" "$ENV_FILE"
chmod 640 "$ENV_FILE"

log "Creating virtualenv and installing Python dependencies"
if [[ ! -d "$VENV_PATH" ]]; then
  "$PYTHON_PKG" -m venv "$VENV_PATH"
fi

"$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel
"$VENV_PATH/bin/pip" install -r "$APP_DIR/requirements.txt"

log "Running Django migrations and collectstatic"
cd "$APP_DIR"
set -a
source "$ENV_FILE"
set +a
"$VENV_PATH/bin/python" manage.py migrate --noinput
"$VENV_PATH/bin/python" manage.py collectstatic --noinput

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
log "Writing systemd service: $SERVICE_FILE"
$SUDO tee "$SERVICE_FILE" >/dev/null <<SYSTEMD
[Unit]
Description=Gunicorn for ${SERVICE_NAME}
After=network.target

[Service]
User=${APP_USER}
Group=www-data
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_PATH}/bin/gunicorn toprofile.wsgi:application --workers 3 --bind 127.0.0.1:${GUNICORN_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD

$SUDO systemctl daemon-reload
$SUDO systemctl enable "${SERVICE_NAME}"
$SUDO systemctl restart "${SERVICE_NAME}"

HOOK_FILE="$APP_DIR/.git/hooks/post-merge"
log "Configuring auto-deploy hook on git pull: $HOOK_FILE"
cat > "$HOOK_FILE" <<HOOK
#!/usr/bin/env bash
set -Eeuo pipefail
cd "${APP_DIR}"
"${VENV_PATH}/bin/pip" install -r requirements.txt
set -a
source "${ENV_FILE}"
set +a
"${VENV_PATH}/bin/python" manage.py migrate --noinput
"${VENV_PATH}/bin/python" manage.py collectstatic --noinput
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  sudo systemctl restart "${SERVICE_NAME}"
else
  systemctl restart "${SERVICE_NAME}" || true
fi
HOOK
chmod +x "$HOOK_FILE"
chown "$APP_USER":"$APP_USER" "$HOOK_FILE"

NGINX_SITE="/etc/nginx/sites-available/${SERVICE_NAME}"
log "Writing nginx config: $NGINX_SITE"
$SUDO tee "$NGINX_SITE" >/dev/null <<NGINXCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_IP};

    client_max_body_size 50M;

    location /static/ {
        alias ${APP_DIR}/staticfiles_build/static/;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000";
    }

    location /media/ {
        alias ${APP_DIR}/media/;
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
    }

    location / {
        proxy_pass http://127.0.0.1:${GUNICORN_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXCONF

$SUDO ln -sf "$NGINX_SITE" "/etc/nginx/sites-enabled/${SERVICE_NAME}"
$SUDO rm -f /etc/nginx/sites-enabled/default

log "Testing and restarting nginx"
$SUDO nginx -t
$SUDO systemctl enable nginx
$SUDO systemctl restart nginx

read -r -p "Configure UFW firewall (allow OpenSSH, 80, 443)? [y/N]: " UFW_INPUT
UFW_INPUT=${UFW_INPUT:-N}
UFW_INPUT=$(printf "%s" "$UFW_INPUT" | tr '[:upper:]' '[:lower:]')
if [[ "$UFW_INPUT" == "y" || "$UFW_INPUT" == "yes" ]]; then
  $SUDO apt-get install -y ufw
  $SUDO ufw allow OpenSSH
  $SUDO ufw allow 80/tcp
  $SUDO ufw allow 443/tcp
  $SUDO ufw --force enable
fi

log "Deployment complete"
printf "\nDetected current DB mode from app settings:\n"
printf -- "- DEBUG=True -> sqlite3 (local db.sqlite3)\n"
printf -- "- DEBUG=False -> DATABASE_URL (now configured to PostgreSQL)\n"
printf "\nExposed API routes:\n"
printf -- "- API base: http://%s%s\n" "$SERVER_IP" "$API_BASE_PATH"
printf -- "- Swagger UI: http://%s/\n" "$SERVER_IP"
printf -- "- Admin: http://%s/admin/\n" "$SERVER_IP"
printf "\nUseful checks:\n"
printf -- "- systemctl status %s\n" "$SERVICE_NAME"
printf -- "- journalctl -u %s -f\n" "$SERVICE_NAME"
printf -- "- sudo nginx -t\n"
printf -- "- redis-cli ping\n"
printf -- "- psql -h %s -U %s -d %s\n" "$PG_HOST" "$PG_USER" "$PG_DB"
printf -- "- curl -I http://%s%s\n" "$SERVER_IP" "$API_BASE_PATH"
