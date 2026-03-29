#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# OSSPREY — Docker Stack Smoke Tests
# Run after `docker compose up -d` to verify the full stack.
# Usage:  ./smoke_test.sh
# ──────────────────────────────────────────────────────────────
set -uo pipefail

BACKEND_URL="http://localhost:5001"
FRONTEND_URL="http://localhost:3000"
MONGO_URI="mongodb://ossprey:ossprey_dev_pw@localhost:27017/decal-db?authSource=admin"
TEST_EMAIL="smoke_test_$(date +%s)@ossprey.dev"
TEST_PASSWORD="SmokeTest123!"

PASS=0
FAIL=0
SKIP=0

# ── Helpers ──────────────────────────────────────────────────

green()  { printf "\033[32m✔ PASS\033[0m %s\n" "$1"; PASS=$((PASS + 1)); }
red()    { printf "\033[31m✘ FAIL\033[0m %s\n" "$1"; FAIL=$((FAIL + 1)); }
yellow() { printf "\033[33m⊘ SKIP\033[0m %s\n" "$1"; SKIP=$((SKIP + 1)); }
header() { printf "\n\033[1;36m── %s ──\033[0m\n" "$1"; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then green "$desc"; else red "$desc (expected: $expected, got: $actual)"; fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qi "$needle"; then green "$desc"; else red "$desc (missing: $needle)"; fi
}

assert_http() {
  local desc="$1" url="$2" expected_code="$3"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  assert_eq "$desc" "$expected_code" "$code"
}

# ── 1. Container Health ──────────────────────────────────────

header "Container Health"

for svc in ossprey-mongodb ossprey-backend ossprey-frontend; do
  status=$(docker inspect -f '{{.State.Running}}' "$svc" 2>/dev/null || echo "false")
  assert_eq "Container $svc is running" "true" "$status"
done

# MongoDB healthcheck
mongo_health=$(docker inspect -f '{{.State.Health.Status}}' ossprey-mongodb 2>/dev/null || echo "unknown")
assert_eq "MongoDB healthcheck is healthy" "healthy" "$mongo_health"

# ── 2. Port Accessibility ────────────────────────────────────

header "Port Accessibility"

assert_http "Frontend responds on :3000" "$FRONTEND_URL" "200"
# Backend root may return 404 (no root route) — just not 000 (connection refused)
backend_code=$(curl -s -o /dev/null -w "%{http_code}" "$BACKEND_URL/" 2>/dev/null || echo "000")
if [[ "$backend_code" != "000" ]]; then
  green "Backend responds on :5001 (HTTP $backend_code)"
else
  red "Backend not responding on :5001"
fi

# Verify port 5001 is NOT AirPlay
backend_server=$(curl -sI "$BACKEND_URL/" 2>/dev/null | grep -i "^Server:" || echo "")
if echo "$backend_server" | grep -qi "airtunes"; then
  red "Port 5001 is AirPlay, not the backend!"
else
  green "Port 5001 is not AirPlay (server: ${backend_server:-gunicorn})"
fi

# ── 3. CORS Configuration ───────────────────────────────────

header "CORS Configuration"

cors_response=$(curl -sI -X OPTIONS "$BACKEND_URL/api/register" \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Content-Type" 2>/dev/null)

assert_contains "CORS allows origin localhost:3000" "Access-Control-Allow-Origin" "$cors_response"
assert_contains "CORS allows POST method" "POST" "$cors_response"

# ── 4. MongoDB Data ──────────────────────────────────────────

header "MongoDB Data (Zenodo)"

collection_count=$(docker exec ossprey-mongodb mongosh "$MONGO_URI" --quiet \
  --eval "db.getCollectionNames().length" 2>/dev/null || echo "0")

if [[ "$collection_count" -ge 10 ]]; then
  green "MongoDB has $collection_count collections (≥10 expected)"
else
  red "MongoDB has only $collection_count collections (≥10 expected)"
fi

# Check a known collection
grad_count=$(docker exec ossprey-mongodb mongosh "$MONGO_URI" --quiet \
  --eval "db.grad_forecast.countDocuments()" 2>/dev/null || echo "0")

if [[ "$grad_count" -gt 0 ]]; then
  green "grad_forecast collection has $grad_count documents"
else
  yellow "grad_forecast collection is empty (run Zenodo import)"
fi

# ── 5. GitHub Token ──────────────────────────────────────────

header "GitHub Token"

token_count=$(docker exec ossprey-backend python -c "
from app.config import Config
tokens = Config.collect_github_tokens()
valid = [t for t in tokens if not t.startswith('ghp_REPLACE')]
print(len(valid))
" 2>/dev/null || echo "0")

if [[ "$token_count" -gt 0 ]]; then
  green "Backend has $token_count valid GitHub token(s)"
else
  red "No valid GitHub tokens configured (tokens still have placeholder values)"
fi

# Check GITHUB_TOKEN env for Rust scraper
rust_token=$(docker exec ossprey-backend printenv GITHUB_TOKEN 2>/dev/null || echo "")
if [[ -n "$rust_token" && "$rust_token" != *"REPLACE"* ]]; then
  green "GITHUB_TOKEN env var set for Rust scraper"
else
  red "GITHUB_TOKEN env var missing or placeholder (Rust scraper will fail)"
fi

# ── 6. Rust Scraper Binary ───────────────────────────────────

header "Rust Scraper"

if docker exec ossprey-backend test -f /opt/ossprey/scraper/target/debug/miner 2>/dev/null; then
  green "Rust miner binary is compiled"
else
  red "Rust miner binary not found (run: docker exec ossprey-backend bash -c 'cd /opt/ossprey/scraper && cargo build')"
fi

# ── 7. User Registration ────────────────────────────────────

header "User Registration & Authentication"

reg_response=$(curl -s -X POST "$BACKEND_URL/api/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"full_name\": \"Smoke Test\",
    \"email\": \"$TEST_EMAIL\",
    \"password\": \"$TEST_PASSWORD\",
    \"affiliation\": \"CI\",
    \"referral\": \"smoke_test\"
  }" 2>/dev/null)

if echo "$reg_response" | grep -qi "registered successfully\|already registered"; then
  green "Registration endpoint works"
else
  red "Registration failed: $reg_response"
fi

# ── 8. User Login ────────────────────────────────────────────

login_response=$(curl -s -X POST "$BACKEND_URL/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$TEST_EMAIL\", \"password\": \"$TEST_PASSWORD\"}" 2>/dev/null)

if echo "$login_response" | grep -qi "access_token"; then
  green "Login endpoint returns JWT token"
else
  red "Login failed: $login_response"
fi

# ── 9. API Endpoints ────────────────────────────────────────

header "API Endpoints"

assert_http "GET /api/projects returns 200" "$BACKEND_URL/api/projects" "200"

eclipse_code=$(curl -s -o /dev/null -w "%{http_code}" "$BACKEND_URL/api/eclipse_projects" 2>/dev/null || echo "000")
if [[ "$eclipse_code" == "200" ]]; then
  green "GET /api/eclipse_projects returns 200"
else
  yellow "GET /api/eclipse_projects returns $eclipse_code (may need data)"
fi

# ── 10. Frontend Content ────────────────────────────────────

header "Frontend Content"

frontend_html=$(curl -s "$FRONTEND_URL" 2>/dev/null)
assert_contains "Frontend serves HTML" "<html" "$frontend_html"
assert_contains "Frontend loads Vue app" "app" "$frontend_html"

# ── 11. Gunicorn Configuration ──────────────────────────────

header "Gunicorn Configuration"

timeout_val=$(docker exec ossprey-backend python -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('gc', '/app/gunicorn.conf.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(getattr(mod, 'timeout', 30))
" 2>/dev/null || echo "30")

if [[ "$timeout_val" -ge 300 ]]; then
  green "Gunicorn timeout is ${timeout_val}s (sufficient for scraper)"
else
  red "Gunicorn timeout is ${timeout_val}s (too low — scraper will be killed)"
fi

# ── 12. Cleanup ──────────────────────────────────────────────

# Remove smoke test user
docker exec ossprey-mongodb mongosh "$MONGO_URI" --quiet \
  --eval "db.users.deleteOne({email: '$TEST_EMAIL'})" >/dev/null 2>&1 || true

# ── Summary ──────────────────────────────────────────────────

header "Summary"
printf "\n"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ "$FAIL" -gt 0 ]]; then printf ", \033[31m%d failed\033[0m" "$FAIL"; fi
if [[ "$SKIP" -gt 0 ]]; then printf ", \033[33m%d skipped\033[0m" "$SKIP"; fi
printf "\n\n"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
