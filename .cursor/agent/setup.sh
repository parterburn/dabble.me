#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() {
  printf '\n== %s ==\n' "$1"
}

run_as_root() {
  if command -v sudo >/dev/null && [ "$(id -u)" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

ensure_asdf() {
  if [ -f "${HOME}/.asdf/asdf.sh" ]; then
    return 0
  fi

  log 'Installing asdf'
  git clone --depth 1 --branch v0.15.0 https://github.com/asdf-vm/asdf.git "${HOME}/.asdf"
}

load_asdf() {
  # shellcheck disable=SC1091
  . "${HOME}/.asdf/asdf.sh"
}

ensure_asdf_in_shell() {
  local marker='# cursor-agent: asdf'
  if ! grep -qF "$marker" "${HOME}/.bashrc" 2>/dev/null; then
    cat >> "${HOME}/.bashrc" <<EOF
$marker
. "\$HOME/.asdf/asdf.sh"
EOF
  fi
}

install_asdf_plugins() {
  load_asdf

  if ! asdf plugin list | grep -qx ruby; then
    asdf plugin add ruby https://github.com/asdf-vm/asdf-ruby.git
  fi

  if ! asdf plugin list | grep -qx nodejs; then
    asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
    if [ -f "${HOME}/.asdf/plugins/nodejs/bin/import-release-team-keyring" ]; then
      "${HOME}/.asdf/plugins/nodejs/bin/import-release-team-keyring"
    fi
  fi
}

install_asdf_runtimes() {
  load_asdf
  install_asdf_plugins

  log 'Installing Ruby and Node.js from .tool-versions'
  cd "$APP_ROOT"
  asdf install
}

install_ruby_build_dependencies() {
  if ! command -v apt-get >/dev/null; then
    return 0
  fi

  log 'Installing Ruby build dependencies'
  run_as_root apt-get update -y
  run_as_root apt-get install -y \
    autoconf \
    bison \
    build-essential \
    curl \
    git \
    libffi-dev \
    libgdbm-dev \
    libgdbm6 \
    libicu-dev \
    libncurses5-dev \
    libpq-dev \
    libreadline-dev \
    libssl-dev \
    libyaml-dev \
    pkg-config \
    zlib1g-dev
}

install_aptfile_packages() {
  if ! command -v apt-get >/dev/null; then
    return 0
  fi

  if [ ! -f "${APP_ROOT}/Aptfile" ]; then
    return 0
  fi

  log 'Installing system packages from Aptfile'
  run_as_root apt-get update -y

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line="${raw_line%%#*}"
    line="$(echo "$line" | xargs)"
    if [ -z "$line" ]; then
      continue
    fi

    if [[ "$line" =~ ^https?:// ]]; then
      # Debian .deb URLs in Aptfile conflict on Ubuntu 24.04; use distro packages instead.
      log "Skipping Aptfile URL on Ubuntu: $line"
      run_as_root apt-get install -y libheif1 || true
      continue
    fi

    if [ "$line" = 'libvips' ]; then
      run_as_root apt-get install -y libvips42t64 libvips-dev
      continue
    fi

    run_as_root apt-get install -y "$line"
  done < "${APP_ROOT}/Aptfile"
}

install_database_and_cache_services() {
  if ! command -v apt-get >/dev/null; then
    return 0
  fi

  log 'Installing PostgreSQL and Redis'
  run_as_root apt-get update -y
  run_as_root apt-get install -y postgresql postgresql-contrib redis-server

  if command -v pg_ctlcluster >/dev/null; then
    local cluster
    cluster="$(pg_lsclusters -h | awk 'NR==1 {print $1}')"
    if [ -n "$cluster" ]; then
      run_as_root pg_ctlcluster "$cluster" main start || true
    fi
  fi

  if command -v redis-server >/dev/null; then
    redis-server --daemonize yes 2>/dev/null || run_as_root systemctl start redis-server 2>/dev/null || true
  fi
}

install_ruby_dependencies() {
  load_asdf
  cd "$APP_ROOT"

  log 'Installing Ruby gems'
  gem install bundler --conservative
  bundle check || bundle install --jobs 4 --retry 3
}

install_js_dependencies() {
  if [ ! -f "${APP_ROOT}/package.json" ]; then
    return 0
  fi

  load_asdf
  cd "$APP_ROOT"

  log 'Installing JavaScript dependencies'
  if [ -f "${APP_ROOT}/package-lock.json" ]; then
    npm ci --no-audit --no-fund
  else
    npm install --no-audit --no-fund
  fi

  if grep -q '"build:css"' "${APP_ROOT}/package.json"; then
    log 'Building marketing CSS'
    npm run build:css
  fi
}

prepare_database_if_requested() {
  if [ "${CURSOR_RUN_DB_SETUP:-}" != '1' ]; then
    log 'Skipping database setup (set CURSOR_RUN_DB_SETUP=1 to enable)'
    return 0
  fi

  load_asdf
  cd "$APP_ROOT"

  log 'Preparing database'
  bin/rails db:prepare
}

main() {
  cd "$APP_ROOT"
  install_ruby_build_dependencies
  install_aptfile_packages
  install_database_and_cache_services
  ensure_asdf
  ensure_asdf_in_shell
  install_asdf_runtimes
  install_ruby_dependencies
  install_js_dependencies
  prepare_database_if_requested
  log 'Cursor agent setup complete'
}

main "$@"
