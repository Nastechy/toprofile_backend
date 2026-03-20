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

fail_fast_on_nginx_conflicts() {
  local server_ip="$1"
  local count
  count="$($SUDO sh -c "grep -Rsl 'server_name[[:space:]]\\+${server_ip//./\\.}\\([[:space:];]\\|$\\)' /etc/nginx/sites-enabled 2>/dev/null | wc -l")"
  if [[ "$count" -gt 1 ]]; then
    err "Fail-fast: multiple enabled nginx sites reference ${server_ip}. Keep exactly one."
    $SUDO grep -Rsl "server_name[[:space:]]\\+${server_ip//./\\.}\\([[:space:];]\\|$\\)" /etc/nginx/sites-enabled || true
    exit 1
  fi
}

fail_fast_on_missing_includes() {
  local site_file="$1"
  local includes=()
  local inc
  while IFS= read -r inc; do
    [[ -n "$inc" ]] && includes+=("$inc")
  done < <($SUDO sed -n 's/^[[:space:]]*include[[:space:]]\+\([^;[:space:]]\+\);.*$/\1/p' "$site_file")

  for inc in "${includes[@]}"; do
    if ! $SUDO test -e "$inc"; then
      err "Fail-fast: include target not found in ${site_file}: ${inc}"
      exit 1
    fi
  done
}

command -v curl >/dev/null 2>&1 || {
  err "curl is required before running this script."
  exit 1
}

read -r -p "GitHub repo URL [https://github.com/Nastechy/toprofile_frontend.git]: " REPO_URL
REPO_URL=${REPO_URL:-https://github.com/Nastechy/toprofile_frontend.git}

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

read -r -p "Deploy directory [/var/www/toprofile_frontend]: " DEPLOY_DIR
DEPLOY_DIR=${DEPLOY_DIR:-/var/www/toprofile_frontend}

read -r -p "Next.js app subdirectory inside repo [admin-dashboard]: " APP_SUBDIR
APP_SUBDIR=${APP_SUBDIR:-admin-dashboard}

read -r -p "PM2 process name [toprofile-frontend]: " PM2_APP_NAME
PM2_APP_NAME=${PM2_APP_NAME:-toprofile-frontend}

read -r -p "Public IPv4 for nginx server_name [138.68.157.12]: " SERVER_IP
SERVER_IP=${SERVER_IP:-138.68.157.12}

read -r -p "Expose app at path [/app]: " BASE_PATH
BASE_PATH=${BASE_PATH:-/app}
if [[ "${BASE_PATH}" != /* ]]; then
  BASE_PATH="/${BASE_PATH}"
fi
BASE_PATH="${BASE_PATH%/}"

read -r -p "NEXT_PUBLIC_API_BASE_URL [http://${SERVER_IP}/api/v1]: " NEXT_PUBLIC_API_BASE_URL
NEXT_PUBLIC_API_BASE_URL=${NEXT_PUBLIC_API_BASE_URL:-http://${SERVER_IP}/api/v1}

read -r -p "App port [5500]: " APP_PORT
APP_PORT=${APP_PORT:-5500}

read -r -p "Attach frontend routes to existing nginx site with this IP if found? [Y/n]: " ATTACH_EXISTING_INPUT
ATTACH_EXISTING_INPUT=${ATTACH_EXISTING_INPUT:-Y}
ATTACH_EXISTING_INPUT=$(printf "%s" "$ATTACH_EXISTING_INPUT" | tr '[:upper:]' '[:lower:]')

read -r -p "Preferred nginx site name to attach [toprofile_frontend]: " PREFERRED_ATTACH_SITE
PREFERRED_ATTACH_SITE=${PREFERRED_ATTACH_SITE:-toprofile_frontend}

read -r -p "If target nginx site exists, action [attach/overwrite] [overwrite]: " EXISTING_SITE_ACTION
EXISTING_SITE_ACTION=${EXISTING_SITE_ACTION:-overwrite}
EXISTING_SITE_ACTION=$(printf "%s" "$EXISTING_SITE_ACTION" | tr '[:upper:]' '[:lower:]')
if [[ "$EXISTING_SITE_ACTION" != "attach" && "$EXISTING_SITE_ACTION" != "overwrite" ]]; then
  warn "Invalid action '$EXISTING_SITE_ACTION', defaulting to overwrite."
  EXISTING_SITE_ACTION="overwrite"
fi

log "Installing system packages (nginx, git, build tools)"
$SUDO apt-get update -y
$SUDO apt-get install -y nginx git build-essential

if ! command -v node >/dev/null 2>&1; then
  log "Installing Node.js 20"
  curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO bash -
  $SUDO apt-get install -y nodejs
else
  NODE_MAJOR="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  if [[ "$NODE_MAJOR" -ne 20 ]]; then
    warn "Node $(node -v) detected. Reinstalling Node.js 20 as requested."
    curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO bash -
    $SUDO apt-get install -y nodejs
  fi
fi

if ! command -v pm2 >/dev/null 2>&1; then
  log "Installing PM2 globally"
  $SUDO npm install -g pm2
fi

log "Preparing deploy directory: ${DEPLOY_DIR}"
$SUDO mkdir -p "$DEPLOY_DIR"
$SUDO chown -R "$USER":"$USER" "$DEPLOY_DIR"

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

APP_DIR="$DEPLOY_DIR/$APP_SUBDIR"
if [[ ! -f "$APP_DIR/package.json" ]]; then
  err "Could not find package.json in $APP_DIR"
  exit 1
fi

log "Writing production environment file"
cat > "$APP_DIR/.env.production" <<ENVVARS
NEXT_PUBLIC_API_BASE_URL=${NEXT_PUBLIC_API_BASE_URL}
ENVVARS

log "Installing dependencies and building Next.js app"
cd "$APP_DIR"
npm ci
npm run build

log "Starting/reloading app with PM2"
if pm2 describe "$PM2_APP_NAME" >/dev/null 2>&1; then
  pm2 restart "$PM2_APP_NAME" --update-env
else
  pm2 start npm --name "$PM2_APP_NAME" -- start
fi
pm2 save

if [[ -n "${SUDO_USER:-}" ]]; then
  DEPLOY_USER="$SUDO_USER"
  DEPLOY_HOME="$(eval echo "~$SUDO_USER")"
else
  DEPLOY_USER="$USER"
  DEPLOY_HOME="$HOME"
fi

log "Configuring PM2 startup service"
$SUDO env PATH="$PATH" pm2 startup systemd -u "$DEPLOY_USER" --hp "$DEPLOY_HOME" >/tmp/pm2-startup.log 2>&1 || true

FRONTEND_SNIPPET="/etc/nginx/snippets/toprofile-frontend-routes.conf"
log "Writing frontend nginx routes snippet: $FRONTEND_SNIPPET"
$SUDO tee "$FRONTEND_SNIPPET" >/dev/null <<NGINXSNIPPET
# Managed by deploy_frontend_droplet.sh
location = ${BASE_PATH} {
    return 301 ${BASE_PATH}/;
}

location ${BASE_PATH}/ {
    rewrite ^${BASE_PATH}/?(.*) /\$1 break;
    proxy_pass http://127.0.0.1:${APP_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_cache_bypass \$http_upgrade;
}
NGINXSNIPPET

TARGET_NGINX_SITE=""
if [[ "$ATTACH_EXISTING_INPUT" == "y" || "$ATTACH_EXISTING_INPUT" == "yes" ]]; then
  if [[ -e "/etc/nginx/sites-enabled/${PREFERRED_ATTACH_SITE}" ]]; then
    TARGET_NGINX_SITE="$($SUDO readlink -f "/etc/nginx/sites-enabled/${PREFERRED_ATTACH_SITE}")"
  else
    for f in /etc/nginx/sites-enabled/*; do
      [[ -f "$f" || -L "$f" ]] || continue
      CANDIDATE="$($SUDO readlink -f "$f")"
      if $SUDO grep -qE "server_name[[:space:]]+${SERVER_IP//./\\.}([[:space:];]|$)" "$CANDIDATE"; then
        TARGET_NGINX_SITE="$CANDIDATE"
        break
      fi
    done
  fi
fi

INCLUDE_LINE="include ${FRONTEND_SNIPPET};"
if [[ -n "$TARGET_NGINX_SITE" && -f "$TARGET_NGINX_SITE" ]]; then
  log "Attaching frontend routes to existing nginx site: $TARGET_NGINX_SITE"
  backup_file_if_exists "$TARGET_NGINX_SITE"

  if [[ "$EXISTING_SITE_ACTION" == "overwrite" ]]; then
    EXTRA_INCLUDES=""
    for snippet in /etc/nginx/snippets/*-routes.conf; do
      [[ -f "$snippet" ]] || continue
      [[ "$snippet" == "$FRONTEND_SNIPPET" ]] && continue
      EXTRA_INCLUDES="${EXTRA_INCLUDES}    include ${snippet};"$'\n'
    done

    $SUDO tee "$TARGET_NGINX_SITE" >/dev/null <<NGINXCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_IP};

    client_max_body_size 20M;
${EXTRA_INCLUDES}    ${INCLUDE_LINE}

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXCONF
  else
    SITE_HAS_ROOT=0
    SITE_HAS_BASE=0
    if $SUDO grep -qE "location[[:space:]]+/[[:space:]]*\\{" "$TARGET_NGINX_SITE"; then
      SITE_HAS_ROOT=1
    fi
    if $SUDO grep -qF "location = ${BASE_PATH}" "$TARGET_NGINX_SITE" || $SUDO grep -qF "location ${BASE_PATH}/" "$TARGET_NGINX_SITE"; then
      SITE_HAS_BASE=1
    fi

    if [[ "$SITE_HAS_ROOT" -eq 1 && "$SITE_HAS_BASE" -eq 1 ]]; then
      warn "Target nginx site already has frontend root and base-path routes; skipping include injection."
      # Clean up stale include from older runs to prevent duplicate location blocks.
      $SUDO sed -i "\|^[[:space:]]*${INCLUDE_LINE//\//\\/}[[:space:]]*$|d" "$TARGET_NGINX_SITE"
    elif ! $SUDO grep -qF "$INCLUDE_LINE" "$TARGET_NGINX_SITE"; then
      $SUDO sed -i "/server_name[[:space:]].*${SERVER_IP//./\\.}.*/a\\    ${INCLUDE_LINE}" "$TARGET_NGINX_SITE"
      if ! $SUDO grep -qF "$INCLUDE_LINE" "$TARGET_NGINX_SITE"; then
        $SUDO sed -i "/server_name[[:space:]]/a\\    ${INCLUDE_LINE}" "$TARGET_NGINX_SITE"
      fi
    fi
  fi
else
  NGINX_SITE="/etc/nginx/sites-available/toprofile_frontend"
  log "No existing site selected/found. Writing dedicated nginx site: $NGINX_SITE"
  backup_file_if_exists "$NGINX_SITE"
  $SUDO tee "$NGINX_SITE" >/dev/null <<NGINXCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_IP};

    client_max_body_size 20M;
    ${INCLUDE_LINE}

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXCONF

  $SUDO ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/toprofile_frontend
  $SUDO rm -f /etc/nginx/sites-enabled/default
fi

log "Testing and reloading nginx"
if [[ -n "${TARGET_NGINX_SITE:-}" && -f "${TARGET_NGINX_SITE:-}" ]]; then
  fail_fast_on_missing_includes "$TARGET_NGINX_SITE"
fi
fail_fast_on_nginx_conflicts "$SERVER_IP"
$SUDO nginx -t
$SUDO systemctl enable nginx
$SUDO systemctl restart nginx

log "Deployment complete"
printf "\nAccess URLs:\n"
printf -- "- Frontend root: http://%s/\n" "$SERVER_IP"
printf -- "- Frontend base path: http://%s%s\n" "$SERVER_IP" "$BASE_PATH"
printf -- "- Backend API (expected): http://%s/api/v1\n" "$SERVER_IP"
printf "\nUseful checks:\n"
printf -- "- pm2 status\n"
printf -- "- pm2 logs %s\n" "$PM2_APP_NAME"
printf -- "- sudo nginx -t\n"
printf -- "- curl -I http://%s/\n" "$SERVER_IP"
printf -- "- curl -I http://%s/api/v1\n" "$SERVER_IP"
