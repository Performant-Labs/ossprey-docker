# OSSPREY — Testing & Development Instructions (macOS / Docker)

## Prerequisites

- **Docker Desktop** (or OrbStack / Colima) installed and running
- **Git** installed
- A GitHub token with read access to public repos (see [GitHub Tokens](#github-tokens) below)

---

## 1. Clone All Repositories

```bash
cd ~/Sites/OSSPREY

git clone https://github.com/OSS-PREY/OSSPREY-FrontEnd-Server.git
git clone https://github.com/OSS-PREY/OSSPREY-BackEnd-Server.git
git clone https://github.com/OSS-PREY/OSSPREY-ReACT-API.git
git clone https://github.com/OSS-PREY/OSSPREY-Pex-Forecaster.git
git clone https://github.com/OSS-PREY/OSSPREY-OSS-Scraper-Tool.git
```

## 2. Configure Environment Variables

```bash
cp .env.example .env
```

Edit `.env` and replace the placeholder values:

| Variable | Description |
|---|---|
| `GITHUB_TOKEN_1` … `_4` | Your GitHub token(s) — see [GitHub Tokens](#github-tokens) |
| `GITHUB_USERNAME` | Your GitHub username |
| `JWT_SECRET_KEY` | Any random secret string for JWT signing |
| `VITE_API_BASE_URL` | Leave as `http://localhost:5001` for local dev |

The MongoDB credentials (`MONGO_INITDB_*`) are pre-set for local development.

## GitHub Tokens

The backend's GitHub scraper needs tokens to call the GitHub API when processing new repositories. OSSPREY supports up to 4 tokens for rate-limit rotation.

### Option A: Use Your Existing `gh` CLI Token (Easiest)

If you already use the [GitHub CLI](https://cli.github.com/), you can reuse its token:

```bash
# Check if you're logged in
gh auth status

# Get the token
gh auth token
```

Copy the output (`gho_...`) into `GITHUB_TOKEN_1` through `_4` in your `.env` file.

> **Note:** `gho_` prefixed tokens are OAuth tokens managed by `gh`. They work for reading public repos but may expire when your `gh` session refreshes. If you hit auth errors, re-run `gh auth token` to get a fresh one.

### Option B: Create a Fine-Grained Personal Access Token

1. Go to https://github.com/settings/tokens?type=beta
2. Click **"Generate new token"**
3. Name it (e.g., `ossprey-read`)
4. Set expiration (30–90 days recommended)
5. Under **Repository access** → select **"Public Repositories (read-only)"**
6. Click **Generate token** and copy the `ghp_...` value

### Option C: Use a Classic PAT

1. Go to https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Select the `public_repo` scope
4. Copy the `ghp_...` value

### Token Tips

- **You only need 1 token minimum.** Duplicate it across all 4 `GITHUB_TOKEN_*` slots.
- **Multiple unique tokens** allow the scraper to rotate through them and avoid GitHub's per-token rate limits (5,000 requests/hour each).
- **After changing tokens**, recreate the backend container to pick them up:
  ```bash
  docker compose up -d --force-recreate backend
  ```
- **Never commit real tokens.** The `.env` file is gitignored; only `.env.example` with placeholders is tracked.

## 3. Bring the Stack Up

```bash
docker compose up -d --build
```

This builds and starts three containers:

| Container | Port | Description |
|---|---|---|
| `ossprey-mongodb` | `27017` | MongoDB 6.0 with persistent named volume |
| `ossprey-backend` | `5001` | Flask + Gunicorn API server |
| `ossprey-frontend` | `3000` | Vue 3 + Vite dev server (hot reload) |

> **Why port 5001?** macOS Monterey and later use port 5000 for AirPlay Receiver. The backend maps host port 5001 → container port 5000 to avoid this conflict. If you disable AirPlay Receiver (System Preferences → General → AirDrop & Handoff), you can change this back to 5000.

### Verify All Containers Are Running

```bash
docker compose ps
```

All three should show status `Up` (MongoDB should also show `healthy`).

### Build the Rust Scraper

The Rust-based GitHub scraper needs to be compiled once inside the backend container:

```bash
docker exec ossprey-backend bash -c "cd /opt/ossprey/scraper && cargo build"
```

This takes ~1 minute. The compiled binary persists until the container is rebuilt.

### View Logs

```bash
# All services
docker compose logs -f

# Individual service
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f mongodb
```

## 4. Ingest the Zenodo Dataset

The Zenodo dataset contains pre-computed Apache and Eclipse Foundation project data. Without it, the database is empty.

```bash
# Download (~62MB zip)
mkdir -p data
curl -L -o data/mongo_exports.zip \
  "https://zenodo.org/records/15307373/files/mongo_exports.zip?download=1"

# Extract
cd data && unzip -o mongo_exports.zip && cd ..

# Copy into container and import all collections
for f in data/mongo_exports/*.json; do
  collection=$(basename "$f" .json)
  echo ">>> Importing: $collection"
  docker cp "$f" ossprey-mongodb:/tmp/
  docker exec ossprey-mongodb mongoimport \
    --uri "mongodb://ossprey:ossprey_dev_pw@localhost:27017/decal-db?authSource=admin" \
    --collection "$collection" \
    --file "/tmp/$(basename $f)" \
    --jsonArray --drop
done
```

This imports 14 collections (~8,800 documents) including project metrics, network data, and graduation forecasts.

## 5. Access the Application

| Service | URL |
|---|---|
| **Frontend** | [http://localhost:3000](http://localhost:3000) |
| **Backend API** | [http://localhost:5001](http://localhost:5001) |

### Register & Login

1. Click **Register** on the login page
2. Fill in the form (name, email, password, etc.)
3. Log in with your new credentials

### Browse Pre-loaded Data (Instant)

1. In the **Project Selector**, switch to the **"Foundation"** tab
2. Select **Foundation → Apache** (or Eclipse)
3. Pick a project (e.g., "Beam", "Curator", "Sqoop")
4. Use the month slider to explore time periods
5. Dashboard panels populate instantly from the database

### Process a New GitHub Repo

1. Use the **"GitHub Repository URL"** tab
2. Select **"Try a Different GitHub Repo"**
3. Enter any public GitHub URL (e.g., `https://github.com/opencloud-eu/opencloud`)
4. Click **Process Repository**
5. The Rust scraper fetches data from GitHub, then the ML pipeline runs forecasting

> **Note:** Processing a new repo requires valid GitHub tokens and takes 1-5 minutes depending on repo size.

## 6. Stop & Teardown

```bash
# Stop all containers (data persists in named volumes)
docker compose down

# Stop and DELETE all data volumes (destructive!)
docker compose down -v
```

## 7. Rebuild After Code Changes

The backend and frontend bind-mount the source code, so most changes are picked up automatically via Gunicorn's `reload=True` and Vite's HMR.

If you change `requirements.txt` or `package.json`, rebuild:

```bash
docker compose up -d --build
```

If you change `.env`, recreate the affected container:

```bash
docker compose up -d --force-recreate backend
```

---

## Architecture Notes

### AI/ML Components

OSSPREY uses purpose-built ML models, not general-purpose LLMs. **No API keys or external AI services are needed.**

| Component | Technology | What It Does |
|---|---|---|
| **Pex Forecaster** | PyTorch neural network (custom) | Predicts project sustainability probability |
| **TimesFM** | Google TimesFM (200M params, HuggingFace) | Time-series forecasting (optional) |
| **ReACT Extractor** | Rule-based Python (pandas) | Generates actionable recommendations |
| **Chat Widget** | Placeholder (echo only) | Future: connect to OSSPREY team |

All models run on CPU inside Docker. On Apple Silicon, PyTorch cannot access the M1/M2 GPU (Metal/MPS) from within Docker containers. For GPU-accelerated inference, run the backend natively.

### macOS-Specific Adaptations

| Original (Ubuntu) | Docker Adaptation |
|---|---|
| `sudo apt install npm` | `node:18-slim` Docker image |
| `pip install -r requirements.txt` globally | `python:3.10-slim` container with isolated deps |
| `sh install_mongo.sh` (system MongoDB) | `mongo:6.0` official image with named volume |
| Rust/Cargo system install for scraper | Rust installed in backend container, scraper compiled on first use |
| Port 5000 for backend | Port 5001 (avoids macOS AirPlay Receiver conflict) |
| `systemd` service management | `docker compose up -d` with `restart: unless-stopped` |

### Service Networking

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Frontend    │────▶│  Backend    │────▶│  MongoDB    │
│  :3000       │     │  :5001→5000 │     │  :27017     │
│  (Vite HMR)  │     │  (Gunicorn) │     │  (mongo:6)  │
└─────────────┘     └─────────────┘     └─────────────┘
     ▲                     ▲
     │                     │
   Browser            Docker internal
  localhost            network "ossprey_default"
```

The frontend makes API calls to `VITE_API_BASE_URL` (default `http://localhost:5001`). The backend connects to MongoDB using the Docker hostname `mongodb` defined in `docker-compose.yml`.

---

## Running Tests

### Unit Tests (Upstream)

Each sub-repo ships its own unit tests. These use mocks (no live services required) and run in seconds.

#### Backend (pytest + mongomock)

```bash
# Install pytest in the container (first time only)
docker exec ossprey-backend pip install pytest -q

# Run all backend tests
docker exec ossprey-backend python -m pytest tests/ -v
```

| Test File | What It Covers |
|---|---|
| `test_register_user.py` | User registration saves timestamp |
| `test_login_logout_tracking.py` | Login/logout event recording |
| `test_user_endpoints.py` | User listing and repo retrieval |
| `test_process_repo.py` | Repo processing request saved |
| `test_view_tracking.py` | Page view counter and timestamps |

> **Known issue:** `test_view_tracking.py::test_record_view_adds_timestamp` occasionally fails due to microsecond rounding. This is a test timing flake, not a real bug.

#### Frontend (Node test runner)

```bash
docker exec ossprey-frontend npm test
```

| Test File | What It Covers |
|---|---|
| `navigation.test.js` | Route navigation and page transitions |
| `repos-table.test.js` | Repository table rendering |

#### Pex-Forecaster (pytest)

```bash
# Run from host (not containerized)
cd OSSPREY-Pex-Forecaster
pip install -e . && pytest tests/ -v
```

| Test File | What It Covers |
|---|---|
| `test_forecaster.py` | Forecast computation and model inference |

> **Note:** Upstream tests use **mongomock** and do not test real Docker networking, CORS, GitHub API access, or the Rust scraper. This is why the smoke and integration tests below are essential.

---

### Smoke Tests (Stack Validation)

After bringing the stack up, run the automated smoke test to verify everything is working:

```bash
./smoke_test.sh
```

The script validates the full stack in ~3 seconds, registers and logs in a temporary user (cleaned up automatically), and exits with code 0 on success or 1 on any failure.

#### Smoke Test Matrix

| # | Category | Test | What It Checks |
|---|---|---|---|
| 1 | Container Health | `ossprey-mongodb` is running | Docker container exists and is up |
| 2 | Container Health | `ossprey-backend` is running | Docker container exists and is up |
| 3 | Container Health | `ossprey-frontend` is running | Docker container exists and is up |
| 4 | Container Health | MongoDB healthcheck is healthy | `mongosh` can ping the DB |
| 5 | Port Accessibility | Frontend responds on `:3000` | HTTP 200 from Vite dev server |
| 6 | Port Accessibility | Backend responds on `:5001` | HTTP response (not connection refused) |
| 7 | Port Accessibility | Port 5001 is not AirPlay | Server header is gunicorn, not AirTunes |
| 8 | CORS | Allows origin `localhost:3000` | `Access-Control-Allow-Origin` header present |
| 9 | CORS | Allows POST method | OPTIONS preflight returns allowed methods |
| 10 | MongoDB Data | >=10 collections exist | Zenodo dataset was imported |
| 11 | MongoDB Data | `grad_forecast` has documents | Graduation forecast data is populated |
| 12 | GitHub Token | Backend has valid token(s) | `GITHUB_TOKEN_*` values are not placeholders |
| 13 | GitHub Token | `GITHUB_TOKEN` env set | Rust scraper can authenticate with GitHub API |
| 14 | Rust Scraper | Miner binary compiled | `target/debug/miner` exists in scraper volume |
| 15 | Registration | POST `/api/register` works | Creates a user and returns success |
| 16 | Authentication | POST `/api/login` returns JWT | Login returns `access_token` in response |
| 17 | API Endpoints | GET `/api/projects` returns 200 | Project listing endpoint is functional |
| 18 | API Endpoints | GET `/api/eclipse_projects` | Eclipse data endpoint (skipped if no data) |
| 19 | Frontend Content | HTML served with `<html>` tag | Vite is building and serving the app |
| 20 | Frontend Content | Vue app mounts | App div is present in the HTML |
| 21 | Gunicorn Config | Timeout >= 300s | Worker won't be killed during scraper runs |

---

### Integration Test (Full Pipeline)

To verify the end-to-end pipeline (GitHub scraping, ML forecasting, and ReACT extraction), submit a small public repo that is not already in the database:

```bash
curl -s -X POST http://localhost:5001/api/upload_git_link \
  -H "Content-Type: application/json" \
  -d '{"git_link": "https://github.com/Nafiz43/EvidenceBot.git"}'
```

**Expected response:** JSON with keys `forecast_json`, `git_link`, `metadata`, `react`, `social_net`, `tech_net`. Takes 30-120 seconds depending on repo size.

**What this exercises that unit tests do not:**

| Concern | Unit Tests | Integration Test |
|---|---|---|
| Rust scraper binary invocation | Mocked | Live subprocess call via `GITHUB_TOKEN` |
| GitHub API authentication | Mocked | Real token, real API calls |
| Gunicorn worker timeout | Not tested | Long-running request under 600s limit |
| PyTorch forecast on CPU | Mocked | Full model inference |
| ReACT rule extraction | Mocked | All months processed |
| CORS across containers | Not tested | Browser-compatible headers verified |

