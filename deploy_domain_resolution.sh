#!/usr/bin/env bash
set -Eeuo pipefail

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
    err "$1 is required."
    exit 1
  }
}

backup_file_if_exists() {
  local target="$1"
  if $SUDO test -f "$target"; then
    local ts
    ts="$(date +%Y%m%d%H%M%S)"
    local bak="${target}.bak.${ts}"
    $SUDO cp "$target" "$bak"
    log "Backed up $target to $bak"
  fi
}

ensure_line_in_file() {
  local file="$1"
  local line="$2"
  grep -qF "$line" "$file" || printf "%s\n" "$line" >> "$file"
}

require_cmd dig
require_cmd curl

read -r -p "Apex domain [toprofile.com]: " APEX_DOMAIN
APEX_DOMAIN=${APEX_DOMAIN:-toprofile.com}

read -r -p "Frontend domain [www.${APEX_DOMAIN}]: " FRONTEND_DOMAIN
FRONTEND_DOMAIN=${FRONTEND_DOMAIN:-www.${APEX_DOMAIN}}

read -r -p "API domain [api.${APEX_DOMAIN}]: " API_DOMAIN
API_DOMAIN=${API_DOMAIN:-api.${APEX_DOMAIN}}

read -r -p "Server IPv4 [138.68.157.12]: " SERVER_IP
SERVER_IP=${SERVER_IP:-138.68.157.12}

read -r -p "Frontend upstream port [5500]: " FRONTEND_PORT
FRONTEND_PORT=${FRONTEND_PORT:-5500}

read -r -p "Backend upstream port [8000]: " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-8000}

read -r -p "Certbot email (required): " CERTBOT_EMAIL
if [[ -z "${CERTBOT_EMAIL}" ]]; then
  err "Certbot email is required."
  exit 1
fi

read -r -p "Frontend .env.production path [/var/www/toprofile_frontend/admin-dashboard/.env.production]: " FRONTEND_ENV_FILE
FRONTEND_ENV_FILE=${FRONTEND_ENV_FILE:-/var/www/toprofile_frontend/admin-dashboard/.env.production}

read -r -p "Frontend app dir for build/restart [/var/www/toprofile_frontend/admin-dashboard]: " FRONTEND_APP_DIR
FRONTEND_APP_DIR=${FRONTEND_APP_DIR:-/var/www/toprofile_frontend/admin-dashboard}

read -r -p "Frontend PM2 app name [toprofile-frontend]: " FRONTEND_PM2_NAME
FRONTEND_PM2_NAME=${FRONTEND_PM2_NAME:-toprofile-frontend}

read -r -p "Backend .env path [/var/www/toprofile_backend/.env]: " BACKEND_ENV_FILE
BACKEND_ENV_FILE=${BACKEND_ENV_FILE:-/var/www/toprofile_backend/.env}

read -r -p "Backend systemd service [toprofile-backend]: " BACKEND_SERVICE
BACKEND_SERVICE=${BACKEND_SERVICE:-toprofile-backend}

log "Checking DNS resolution"
APEX_IPS="$(dig +short "${APEX_DOMAIN}" | tr '\n' ' ' | xargs)"
FRONTEND_IPS="$(dig +short "${FRONTEND_DOMAIN}" | tr '\n' ' ' | xargs)"
API_IPS="$(dig +short "${API_DOMAIN}" | tr '\n' ' ' | xargs)"

printf "DNS -> %s: %s\n" "${APEX_DOMAIN}" "${APEX_IPS}"
printf "DNS -> %s: %s\n" "${FRONTEND_DOMAIN}" "${FRONTEND_IPS}"
printf "DNS -> %s: %s\n" "${API_DOMAIN}" "${API_IPS}"

if [[ " ${APEX_IPS} " != *" ${SERVER_IP} "* ]]; then
  err "${APEX_DOMAIN} does not resolve to ${SERVER_IP}."
  exit 1
fi
if [[ " ${FRONTEND_IPS} " != *" ${SERVER_IP} "* ]]; then
  err "${FRONTEND_DOMAIN} does not resolve to ${SERVER_IP}."
  exit 1
fi
if [[ " ${API_IPS} " != *" ${SERVER_IP} "* ]]; then
  err "${API_DOMAIN} does not resolve to ${SERVER_IP}."
  exit 1
fi

log "Installing certbot packages"
$SUDO apt-get update -y
$SUDO apt-get install -y certbot python3-certbot-nginx

FRONTEND_SITE="/etc/nginx/sites-available/toprofile_frontend_domain"
API_SITE="/etc/nginx/sites-available/toprofile_api_domain"

backup_file_if_exists "$FRONTEND_SITE"
backup_file_if_exists "$API_SITE"

log "Writing frontend domain site: $FRONTEND_SITE"
$SUDO tee "$FRONTEND_SITE" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${APEX_DOMAIN};
    return 301 http://${FRONTEND_DOMAIN}\$request_uri;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${FRONTEND_DOMAIN};

    client_max_body_size 20M;

    location / {
        proxy_pass http://127.0.0.1:${FRONTEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

log "Writing API domain site: $API_SITE"
$SUDO tee "$API_SITE" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${API_DOMAIN};

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

log "Enabling canonical domain sites and disabling conflicting legacy sites"
$SUDO ln -sf "$FRONTEND_SITE" /etc/nginx/sites-enabled/toprofile_frontend_domain
$SUDO ln -sf "$API_SITE" /etc/nginx/sites-enabled/toprofile_api_domain
$SUDO rm -f /etc/nginx/sites-enabled/default
$SUDO rm -f /etc/nginx/sites-enabled/toprofile_frontend
$SUDO rm -f /etc/nginx/sites-enabled/toprofile-backend
$SUDO rm -f /etc/nginx/sites-enabled/toprofile_main
$SUDO rm -f /etc/nginx/sites-enabled/toprofile_api

log "Testing and restarting nginx (HTTP mode)"
$SUDO nginx -t
$SUDO systemctl restart nginx

log "Issuing SSL certificates and enabling HTTPS redirects"
$SUDO certbot --nginx \
  -d "${APEX_DOMAIN}" \
  -d "${FRONTEND_DOMAIN}" \
  -d "${API_DOMAIN}" \
  -m "${CERTBOT_EMAIL}" \
  --agree-tos \
  --no-eff-email \
  --redirect \
  --non-interactive

log "Updating backend ALLOWED_HOSTS in ${BACKEND_ENV_FILE}"
if [[ ! -f "$BACKEND_ENV_FILE" ]]; then
  err "Backend env file not found: $BACKEND_ENV_FILE"
  exit 1
fi
if grep -qE '^ALLOWED_HOSTS=' "$BACKEND_ENV_FILE"; then
  sed -i "s|^ALLOWED_HOSTS=.*|ALLOWED_HOSTS=127.0.0.1,localhost,${SERVER_IP},${APEX_DOMAIN},${FRONTEND_DOMAIN},${API_DOMAIN}|" "$BACKEND_ENV_FILE"
else
  ensure_line_in_file "$BACKEND_ENV_FILE" "ALLOWED_HOSTS=127.0.0.1,localhost,${SERVER_IP},${APEX_DOMAIN},${FRONTEND_DOMAIN},${API_DOMAIN}"
fi

log "Restarting backend service"
$SUDO systemctl restart "$BACKEND_SERVICE"

read -r -p "Update frontend API env and rebuild now? [Y/n]: " REBUILD_FE
REBUILD_FE=${REBUILD_FE:-Y}
REBUILD_FE=$(printf "%s" "$REBUILD_FE" | tr '[:upper:]' '[:lower:]')

if [[ "$REBUILD_FE" == "y" || "$REBUILD_FE" == "yes" ]]; then
  if [[ ! -d "$FRONTEND_APP_DIR" ]]; then
    err "Frontend app dir not found: $FRONTEND_APP_DIR"
    exit 1
  fi
  if [[ ! -f "${FRONTEND_APP_DIR}/package.json" ]]; then
    err "package.json not found in ${FRONTEND_APP_DIR}"
    exit 1
  fi

  log "Updating frontend API base URL in ${FRONTEND_ENV_FILE}"
  mkdir -p "$(dirname "$FRONTEND_ENV_FILE")"
  if [[ -f "$FRONTEND_ENV_FILE" ]]; then
    if grep -qE '^NEXT_PUBLIC_API_BASE_URL=' "$FRONTEND_ENV_FILE"; then
      sed -i "s|^NEXT_PUBLIC_API_BASE_URL=.*|NEXT_PUBLIC_API_BASE_URL=https://${API_DOMAIN}/api/v1|" "$FRONTEND_ENV_FILE"
    else
      ensure_line_in_file "$FRONTEND_ENV_FILE" "NEXT_PUBLIC_API_BASE_URL=https://${API_DOMAIN}/api/v1"
    fi
  else
    printf "NEXT_PUBLIC_API_BASE_URL=https://%s/api/v1\n" "$API_DOMAIN" > "$FRONTEND_ENV_FILE"
  fi

  log "Rebuilding frontend and restarting PM2 app"
  cd "$FRONTEND_APP_DIR"
  npm run build
  pm2 restart "$FRONTEND_PM2_NAME" --update-env
fi

log "Final validation"
$SUDO nginx -t
printf "\nValidation URLs:\n"
printf -- "- Frontend: https://%s/\n" "$FRONTEND_DOMAIN"
printf -- "- API root: https://%s/api/v1/\n" "$API_DOMAIN"
printf -- "- Swagger: https://%s/api/swagger/\n" "$API_DOMAIN"
printf -- "- Admin: https://%s/api/admin/\n" "$API_DOMAIN"

printf "\nQuick checks:\n"
printf -- "- curl -I https://%s/\n" "$FRONTEND_DOMAIN"
printf -- "- curl -I https://%s/api/v1/\n" "$API_DOMAIN"
printf -- "- curl -I https://%s/api/swagger/\n" "$API_DOMAIN"
printf -- "- systemctl status %s\n" "$BACKEND_SERVICE"
printf -- "- pm2 status\n"
