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
      deb_path="$(mktemp /tmp/aptfile.XXXXXX.deb)"
      curl -fsSL "$line" -o "$deb_path"
      run_as_root dpkg -i "$deb_path" || run_as_root apt-get -f install -y
      rm -f "$deb_path"
    else
      run_as_root apt-get install -y "$line"
    fi
  done < "${APP_ROOT}/Aptfile"
}

install_ruby_dependencies() {
  log 'Installing Ruby dependencies'
  gem install bundler --conservative
  bundle check || bundle install
}

install_js_dependencies() {
  if [ ! -f "${APP_ROOT}/package.json" ]; then
    return 0
  fi

  if ! command -v npm >/dev/null; then
    return 0
  fi

  log 'Installing JavaScript dependencies'
  if [ -f "${APP_ROOT}/package-lock.json" ]; then
    npm ci --no-audit --no-fund
  else
    npm install --no-audit --no-fund
  fi
}

prepare_database_if_requested() {
  if [ "${CURSOR_RUN_DB_SETUP:-}" != '1' ]; then
    log 'Skipping database setup (set CURSOR_RUN_DB_SETUP=1 to enable)'
    return 0
  fi

  log 'Preparing database'
  bin/rails db:prepare
}

main() {
  cd "$APP_ROOT"
  install_aptfile_packages
  install_ruby_dependencies
  install_js_dependencies
  prepare_database_if_requested
  log 'Cursor agent setup complete'
}

main "$@"
