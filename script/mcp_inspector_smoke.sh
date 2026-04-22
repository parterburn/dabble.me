#!/usr/bin/env bash
# Smoke-test MCP + OAuth discovery using curl and the official MCP Inspector CLI.
# Docs: https://modelcontextprotocol.io/docs/tools/inspector
#       https://claude.com/docs/connectors/build/testing
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT="${PORT:-37654}"
export RAILS_ENV=test
export MAIN_DOMAIN="${MAIN_DOMAIN:-127.0.0.1}"

NPX="${NPX:-$(command -v npx || true)}"
if [[ -z "$NPX" ]] && [[ -x "$HOME/.asdf/shims/npx" ]]; then
  NPX="$HOME/.asdf/shims/npx"
fi
if [[ -z "$NPX" ]]; then
  echo "npx not found; install Node or set NPX to the npx binary." >&2
  exit 1
fi

bundle exec rails db:test:prepare >/dev/null

TOKEN="$(bundle exec rails runner script/print_mcp_inspector_token.rb)"
if [[ -z "$TOKEN" ]]; then
  echo "Failed to mint Doorkeeper token." >&2
  exit 1
fi

BASE="http://127.0.0.1:${PORT}"

cleanup() {
  if [[ -n "${RAILS_PID:-}" ]] && kill -0 "$RAILS_PID" 2>/dev/null; then
    kill "$RAILS_PID" 2>/dev/null || true
    wait "$RAILS_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "==> Starting Rails (test) on ${BASE}"
bundle exec rails server -p "$PORT" -b 127.0.0.1 >/tmp/mcp_inspector_rails.log 2>&1 &
RAILS_PID=$!

for i in {1..60}; do
  if curl -sf -o /dev/null "${BASE}/.well-known/oauth-authorization-server"; then
    break
  fi
  sleep 0.25
  if ! kill -0 "$RAILS_PID" 2>/dev/null; then
    echo "Rails exited early. Log:" >&2
    cat /tmp/mcp_inspector_rails.log >&2 || true
    exit 1
  fi
  if [[ "$i" -eq 60 ]]; then
    echo "Timeout waiting for Rails." >&2
    exit 1
  fi
done

hdr_auth=(-H "Authorization: Bearer ${TOKEN}")

echo "==> GET /.well-known/oauth-authorization-server"
curl -sS "${BASE}/.well-known/oauth-authorization-server" | ruby -rjson -e 'j=JSON.parse(STDIN.read); %w[issuer authorization_endpoint token_endpoint registration_endpoint scopes_supported].each{|k| abort("missing #{k}") unless j.key?(k)}; puts "ok"'

echo "==> GET /.well-known/oauth-authorization-server/mcp"
curl -sS "${BASE}/.well-known/oauth-authorization-server/mcp" | ruby -rjson -e 'JSON.parse(STDIN.read); puts "ok"'

echo "==> GET /.well-known/oauth-protected-resource"
curl -sS "${BASE}/.well-known/oauth-protected-resource" | ruby -rjson -e 'j=JSON.parse(STDIN.read); abort("resource") unless j["resource"].to_s.end_with?("/mcp"); puts "ok"'

echo "==> GET /.well-known/oauth-protected-resource/mcp"
curl -sS "${BASE}/.well-known/oauth-protected-resource/mcp" | ruby -rjson -e 'JSON.parse(STDIN.read); puts "ok"'

echo "==> GET /mcp (expect 405)"
code="$(curl -sS -o /dev/null -w "%{http_code}" "${BASE}/mcp")"
[[ "$code" == "405" ]] || { echo "expected 405, got ${code}" >&2; exit 1; }

echo "==> POST /mcp initialize without token (expect 401)"
code="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/mcp" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')"
[[ "$code" == "401" ]] || { echo "expected 401, got ${code}" >&2; exit 1; }

echo "==> POST /oauth/registrations (dynamic client registration)"
code="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/oauth/registrations" -H "Content-Type: application/json" -d '{"client_name":"Inspector","redirect_uris":["http://127.0.0.1/cb"]}')"
[[ "$code" == "201" ]] || { echo "expected 201, got ${code}" >&2; exit 1; }

INSPECTOR=( "$NPX" -y @modelcontextprotocol/inspector --cli "${BASE}/mcp" --transport http --header "Authorization: Bearer ${TOKEN}" )

echo "==> MCP Inspector: tools/list (connect + initialize + list)"
"${INSPECTOR[@]}" --method tools/list | ruby -rjson -e 'j=JSON.parse(STDIN.read); names=j["tools"].map{|t|t["name"]}; %w[search_entries list_entries analyze_entries create_entry].each{|n| abort("missing tool #{n}") unless names.include?(n)}; puts "ok"'

echo "==> MCP Inspector: tools/call search_entries"
"${INSPECTOR[@]}" --method tools/call --tool-name search_entries --tool-arg query=inspector | ruby -rjson -e 'j=JSON.parse(STDIN.read); e=j.dig("content",0,"text"); abort("no hits") unless e.include?("inspector"); puts "ok"'

echo "==> MCP Inspector: tools/call list_entries"
"${INSPECTOR[@]}" --method tools/call --tool-name list_entries --tool-arg limit=5 | ruby -rjson -e 'j=JSON.parse(STDIN.read); t=j.dig("content",0,"text"); abort("bad list") unless t.match?(/total_entries|"entries"/); puts "ok"'

echo "==> MCP Inspector: tools/call analyze_entries"
"${INSPECTOR[@]}" --method tools/call --tool-name analyze_entries | ruby -rjson -e 'j=JSON.parse(STDIN.read); t=j.dig("content",0,"text"); abort("analyze") unless t.include?("total_entries"); puts "ok"'

echo "==> MCP Inspector: tools/call create_entry (2099-06-20)"
"${INSPECTOR[@]}" --method tools/call --tool-name create_entry --tool-arg date=2099-06-20 --tool-arg body="MCP inspector smoke" | ruby -rjson -e 'j=JSON.parse(STDIN.read); t=j.dig("content",0,"text"); abort("create") unless t.include?("\"success\": true") || t.include?("\"success\":true"); puts "ok"'

echo "==> MCP Inspector: resources/list (expect empty or protocol-compliant)"
set +e
out="$("${INSPECTOR[@]}" --method resources/list 2>&1)"
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "$out" >&2
  echo "(resources/list returned non-zero; acceptable if server omits resources.)" >&2
else
  echo "$out" | head -c 400
  echo
fi

echo "==> MCP Inspector: prompts/list (expect empty or protocol-compliant)"
set +e
out="$("${INSPECTOR[@]}" --method prompts/list 2>&1)"
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "$out" >&2
  echo "(prompts/list returned non-zero; acceptable if server omits prompts.)" >&2
else
  echo "$out" | head -c 400
  echo
fi

echo "==> All smoke checks finished."
