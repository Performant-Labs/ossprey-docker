# OSSPREY — Architecture

**OSSPREY** (Open Source Software PRojEct sustainabilitY tracker) is a web-based platform that predicts whether open source projects will remain sustainable. It collects socio-technical metrics from GitHub repositories, runs them through machine learning models, and presents forecasts with actionable recommendations.

---

## System Overview

```
                          ┌──────────────────────────────────────────┐
                          │              Docker Host (macOS)          │
                          │                                          │
  Browser ──────────────▶ │  ┌────────────┐    ┌────────────────┐   │
  http://localhost:3000   │  │  Frontend   │───▶│   Backend API  │   │
                          │  │  (Vue 3)    │    │   (Flask)      │   │
                          │  │  :3000      │    │   :5001→5000   │   │
                          │  └────────────┘    └───────┬────────┘   │
                          │                            │            │
                          │           ┌────────────────┼──────────┐ │
                          │           │                │          │ │
                          │    ┌──────▼──────┐  ┌──────▼──────┐  │ │
                          │    │  MongoDB    │  │ Rust Scraper │  │ │
                          │    │  :27017     │  │ (miner)      │  │ │
                          │    └─────────────┘  └──────┬──────┘  │ │
                          │                            │          │ │
                          │    ┌─────────────┐  ┌──────▼──────┐  │ │
                          │    │ ReACT API   │  │ Pex          │  │ │
                          │    │ (extractor) │  │ Forecaster   │  │ │
                          │    └─────────────┘  └─────────────┘  │ │
                          │           │                │          │ │
                          │           └────── ML Tools ┘          │ │
                          └──────────────────────────────────────────┘
```

---

## Repositories

The project is split across 6 repositories, each with its own Git history:

| Repository | Language | Purpose |
|---|---|---|
| `OSSPREY-FrontEnd-Server` | Vue 3 / JavaScript | Dashboard UI, data visualization, user auth |
| `OSSPREY-BackEnd-Server` | Python / Flask | REST API, pipeline orchestrator, auth |
| `OSSPREY-OSS-Scraper-Tool` | Rust | GitHub data miner (issues, commits, file changes) |
| `OSSPREY-Pex-Forecaster` | Python / PyTorch | Sustainability prediction neural network |
| `OSSPREY-ReACT-API` | Python | Rule-based actionable recommendation extractor |
| `OSSPREY-Website` | HTML | Public-facing marketing site |

---

## Frontend (`OSSPREY-FrontEnd-Server`)

**Stack:** Vue 3, Vuetify 3, Pinia, Plotly.js, Vite

### Key Files

| Path | Purpose |
|---|---|
| `src/main.js` | App entry point, plugin registration |
| `src/App.vue` | Root component, inactivity logout timer |
| `src/pages/dashboard.vue` | Main dashboard page layout |
| `src/pages/login.vue` | Login form with Google OAuth option |
| `src/pages/register.vue` | Registration form with password validation |
| `src/stores/projectStore.js` | Pinia store — project selection, API calls, state |

### Dashboard Components (`src/views/dashboard/`)

| Component | What It Renders |
|---|---|
| `ProjectSelector.vue` | Foundation/local toggle, project autocomplete, month slider |
| `GraduationForecast.vue` | Probability of sustainability chart (Plotly line/area) |
| `Actionables.vue` | ReACT recommendations table (Critical/Medium/Low) |
| `ProjectDetails.vue` | Project metadata, monthly actionables, commit stats |
| `SocialNetwork.vue` | Developer collaboration network graph |
| `TechnicalNetwork.vue` | File co-change network graph |
| `SocialNetworkNode.vue` | Individual node detail view (social) |
| `TechnicalNetworkNode.vue` | Individual node detail view (technical) |
| `CommitsPerCommitters.vue` | Contribution distribution chart |
| `ChatWidget.vue` | Placeholder chat widget (echo only, future feature) |

### Data Flow

1. User selects a project in `ProjectSelector.vue`
2. `projectStore.js` calls backend APIs (`/api/grad_forecast/:id`, `/api/predictions/:id/:month`)
3. Vuetify components reactively render from Pinia state
4. Charts update via Plotly.js with the forecast data

---

## Backend (`OSSPREY-BackEnd-Server`)

**Stack:** Flask 2, Gunicorn, PyMongo, Flask-JWT-Extended, Flask-CORS

### App Factory (`app/__init__.py`)

```python
create_app() → Flask app
  ├── CORS(app, origins="*")
  ├── JWTManager(app)
  ├── app.register_blueprint(main_routes)
  └── app.register_blueprint(auth_routes)
```

### Route Modules

| File | Key Endpoints |
|---|---|
| `app/routes.py` | `/api/projects`, `/api/grad_forecast/<id>`, `/api/predictions/<id>/<month>`, `/api/upload_git_link`, `/api/eclipse_projects`, user tracking |
| `app/auth_routes.py` | `/api/register`, `/api/login`, `/api/logout`, `/api/google_login` |
| `app/config.py` | `Config` class — collects `GITHUB_TOKEN_1..N` from env, MongoDB URI |

### Pipeline (`app/pipeline/`)

The pipeline orchestrates the end-to-end processing of a new GitHub repository:

```
orchestrator.run_pipeline(git_link)
  │
  ├── 1. github_metadata.get_github_metadata()   ← REST API (stars, forks, license, etc.)
  │
  ├── 2. rust_runner.run_rust_code()              ← Invokes compiled Rust binary
  │      ├── miner --fetch-github-issues          ← Issues CSV
  │      └── miner --commit-devs-files            ← Commit/file/dev CSV
  │
  ├── 3. run_pex.run_forecast()                   ← PyTorch sustainability prediction
  │      └── decalfc.app.server.compute_forecast()
  │
  ├── 4. run_react.run_react_all()                ← Rule-based recommendations
  │
  └── 5. Return JSON with forecast + network + metadata + ReACTs
```

| Pipeline Module | What It Does |
|---|---|
| `orchestrator.py` | Coordinates all pipeline steps, checks for pre-computed data |
| `rust_runner.py` | Invokes the Rust `miner` binary via `subprocess` |
| `run_pex.py` | Delegates to Pex-Forecaster's `compute_forecast()` |
| `run_react.py` | Runs the ReACT extractor for all months |
| `github_metadata.py` | Fetches repo metadata from the GitHub REST API |
| `store_commit_issues.py` | Parses CSVs and stores commit/issue data in MongoDB |
| `update_pex.py` | Ensures the Pex-Forecaster repo is cloned and up-to-date |

### Service Layer (`app/services/`)

| Service | What It Does |
|---|---|
| `apache_services.py` | Fetches and processes Apache Foundation project data |
| `eclipse_services.py` | Fetches Eclipse Foundation project metadata |
| `github_services.py` | GitHub REST API helpers (repo info, issues) |
| `graphql_services.py` | GitHub GraphQL API client (commit details, async) |
| `processing.py` | Data transformation and normalization |

---

## Rust Scraper (`OSSPREY-OSS-Scraper-Tool`)

**Stack:** Rust, `reqwest`, `git2`, `tokei`, `serde`

A command-line tool that mines GitHub repositories for socio-technical data. It produces two CSV files per project:

| Output | Contents |
|---|---|
| `<project>_issues.csv` | Issue metadata (authors, timestamps, labels, comments) |
| `<project>-commit-file-dev.csv` | Commit-file-developer triples (who changed what, when) |

### Invocation

```bash
# Fetch issues via GitHub API
miner --fetch-github-issues --github-url=<URL> --github-output-folder=output

# Mine commit/file/developer relationships
miner --commit-devs-files --time-window=30 --threads=16 \
      --output-folder=output --git-online-url=<URL>
```

**Requires:** `GITHUB_TOKEN` environment variable for GitHub API authentication.

---

## Pex Forecaster (`OSSPREY-Pex-Forecaster`)

**Stack:** Python, PyTorch, pandas, scikit-learn

A custom neural network that predicts OSS project sustainability (graduation vs. retirement) based on socio-technical network metrics.

### Key Directories

| Path | Purpose |
|---|---|
| `decalfc/` | Core forecasting library (`compute_forecast()` entry point) |
| `model-weights/` | Pre-trained PyTorch model weights (shipped with repo) |
| `net-caches/` | Cached network computation results |
| `Forecasting-Paper-Utils/` | Research utilities including TimesFM integration |

### Models

| Model | Type | Parameters | Input |
|---|---|---|---|
| **DecalFC** | Custom PyTorch NN | Small (< 10M) | Social + technical network CSV features |
| **TimesFM** | Google foundation model | 200M | Univariate time series (optional, for research) |

Both models run on **CPU only** inside Docker (Apple Metal/MPS is not available through Docker's Linux VM).

### Data Flow

```
Technical CSV ─┐
               ├──▶ compute_forecast() ──▶ Monthly sustainability probabilities
Social CSV ────┘
```

---

## ReACT API (`OSSPREY-ReACT-API`)

**Stack:** Python, pandas

A **rule-based** extractor (not an LLM) that maps pre-defined research recommendations to project metrics. It is backed by a static JSON file (`react_set.json`) containing ~100 recommendations sourced from peer-reviewed software engineering papers.

### How It Works

1. Loads the static rule set from `react_set.json`
2. For each month, checks which network features exist in the computed data
3. Returns matching recommendations sorted by an `Importance` score (based on how many research papers cited the recommendation — **not** project-specific risk)
4. Labels each as **Critical** (importance ≥ 5), **High** (3–4), or **Medium** (1–2)

### Current Limitations

The ReACT system currently provides **generic academic advice** rather than project-specific insights:

- Recommendations are not parameterized with the project's actual metrics (e.g., "you have 15 developers" is not shown)
- Priority is based on citation count, not computed risk
- No bus factor, trend analysis, or developer-level detail is provided
- No consequence explanations or suggested actions

See `docs/features/REACT_ENHANCEMENTS.md` for proposed improvements.

### Output Format

```json
{
  "month_1": [
    { "title": "Maintain a small number of core/active developers.", "importance": 7, "refs": [...] },
    { "title": "Maintain concise, updated, accessible documentation.", "importance": 6, "refs": [...] }
  ]
}
```

---

## MongoDB Schema

**Database:** `decal-db`

### Core Collections (from Zenodo dataset)

| Collection | Documents | Contents |
|---|---|---|
| `grad_forecast` | ~260 | Apache project graduation forecasts (monthly probabilities) |
| `eclipse_grad_forecast` | ~180 | Eclipse project graduation forecasts |
| `github_repositories` | ~2,800 | Repository metadata snapshots |
| `commit_links` | ~1,500 | Commit relationship data |
| `issue_links` | ~1,400 | Issue relationship data |
| `users` | varies | Registered user accounts |

### User Document

```json
{
  "_id": "ObjectId",
  "full_name": "string",
  "email": "string",
  "affiliation": "string",
  "password_hash": "scrypt:...",
  "referral": "string",
  "registered_at": "ISODate"
}
```

### Forecast Document

```json
{
  "project_id": "beam",
  "project_name": "Beam",
  "forecast": {
    "1": { "close": 0.85, "prediction": "graduated" },
    "2": { "close": 0.87, "prediction": "graduated" },
    ...
  }
}
```

---

## Docker Compose Topology

| Service | Image | Port Mapping | Volumes |
|---|---|---|---|
| `mongodb` | `mongo:6.0` | `27017:27017` | `ossprey_mongo_data` (named volume) |
| `backend` | Custom (`backend.Dockerfile`) | `5001:5000` | Bind mounts: backend source, pex-forecaster, scraper, react-api |
| `frontend` | Custom (`frontend.Dockerfile`) | `3000:3000` | Bind mount: frontend source; named volume: `node_modules` |

### Backend Dockerfile

The backend image is based on `python:3.10-slim` and additionally installs:
- **Rust toolchain** (for compiling the OSS-Scraper miner binary)
- **Build essentials** (gcc, git, libssl-dev)
- All Python dependencies from `requirements.txt`

### Environment Variables

See `.env.example` for the full list. Key variables:

| Variable | Used By | Purpose |
|---|---|---|
| `GITHUB_TOKEN_1..4` | Backend (Python) | API rate-limit rotation for GitHub REST/GraphQL |
| `GITHUB_TOKEN` | Rust Scraper | GitHub API authentication |
| `MONGODB_URI` | Backend | Database connection string |
| `JWT_SECRET_KEY` | Backend | Signing key for JWT access tokens |
| `PEX_GENERATOR_DIR` | Backend | Path to mounted Pex-Forecaster volume |
| `OSS_SCRAPER_DIR` | Backend | Path to mounted Rust scraper volume |
| `VITE_API_BASE_URL` | Frontend | Backend API URL (build-time substitution) |

---

## Data Sources

### Zenodo Dataset (Training Corpus)

The [Zenodo dataset](https://zenodo.org/records/15307373) is a **static research artifact** published by the UC Davis DECAL Lab (Nafiz Imtiaz Khan, Vladimir Filkov). It contains pre-computed socio-technical metrics for **260 Apache** and **272 Eclipse** Foundation projects.

**Primary purpose:** These projects went through a known incubation lifecycle with labeled outcomes (graduated, retired, incubating), providing the **ground truth training data** for the Pex-Forecaster neural network. The model learned what "sustainable" vs "abandoned" projects look like from this corpus.

**Secondary purposes:**
- Instant demo access to 532 projects without running the scraper
- Benchmark population for comparative analysis

**Limitations:** The data is frozen at the time of publication and is not automatically updated. There is no pipeline or cron job keeping it current. Projects that have changed significantly since publication will show stale metrics.

See `docs/features/DESIGN_LIVE_REFRESH.md` for the proposed solution.

### Live Pipeline Sources

| Source | What It Provides | Access |
|---|---|---|
| GitHub REST API | Repository metadata, issues | Requires PAT |
| GitHub GraphQL API | Commit details, file changes | Requires PAT |
| Git clone (via Rust) | Full commit history analysis | Public repos only |

---

## Authentication

| Method | Status | Notes |
|---|---|---|
| Email/password | ✅ Working | scrypt-hashed, JWT-based sessions |
| Google OAuth | ⚠️ Requires config | Needs `GOOGLE_CLIENT_ID` in `.env` |

JWT tokens are returned on login and must be included in `Authorization: Bearer <token>` headers for protected endpoints.

---

## Testing

| Layer | Framework | Location | Run Command |
|---|---|---|---|
| Backend unit tests | pytest (mongomock) | `OSSPREY-BackEnd-Server/tests/` | `docker exec ossprey-backend python -m pytest tests/ -v` |
| Frontend unit tests | Node test runner | `OSSPREY-FrontEnd-Server/tests/` | `docker exec ossprey-frontend npm test` |
| Pex-Forecaster tests | pytest | `OSSPREY-Pex-Forecaster/tests/` | `cd OSSPREY-Pex-Forecaster && pytest` |
| Smoke tests | bash | `./smoke_test.sh` | `./smoke_test.sh` |
| E2E / Integration | Not yet implemented | — | — |

---

## Known Limitations

### Social Network Empty for GitHub Projects

The social network builder was designed for Apache/Eclipse **mailing list data** where reply chains are explicit (`In-Reply-To` headers). GitHub issues use a flat comment model without threading. When processing GitHub-hosted projects, the social network panel will be empty and email-related stats will show zero.

**Affected panels:** Social Network, Social Network Node, Number of Emails, Senders, Emails per Sender.

### Fork History Contamination

The Rust scraper clones the full git history, which for forked repos includes all upstream commits. For example, processing OpenCloud (forked from ownCloud Infinite Scale in January 2025) returns 157 developers and 104,750 rows going back to 2019 — the vast majority from ownCloud.

See `docs/features/DESIGN_DEVELOPER_ACTIVITY.md` for the proposed fork detection and toggle solution.

### GPU Acceleration

PyTorch inside Docker on macOS runs on **CPU only**. Apple Metal/MPS is not available through Docker's Linux VM. Performance is sufficient for current models but slower than native execution.

### Frontend Timeout on Long Processing

The frontend HTTP request may time out during long-running pipeline processing (e.g., large repos with 60K+ issues). The backend continues processing and caches the results, so resubmitting the same URL returns immediately.
