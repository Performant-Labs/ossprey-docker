# OSSPREY

[![Smoke Tests](https://img.shields.io/badge/smoke%20tests-21%20checks-brightgreen)](#smoke-tests)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

**OSSPREY** (Open Source Software PRojEct sustainabilitY tracker) is a web-based platform that predicts whether open source projects will remain sustainable. It collects socio-technical metrics from GitHub repositories, runs them through machine learning models, and presents forecasts with actionable recommendations.

---

## Quick Start

```bash
# 1. Clone this repo and all sub-repos
git clone git@github.com:Performant-Labs/ossprey-docker.git ~/Sites/OSSPREY
cd ~/Sites/OSSPREY

git clone https://github.com/OSS-PREY/OSSPREY-FrontEnd-Server.git
git clone https://github.com/OSS-PREY/OSSPREY-BackEnd-Server.git
git clone https://github.com/OSS-PREY/OSSPREY-ReACT-API.git
git clone https://github.com/OSS-PREY/OSSPREY-Pex-Forecaster.git
git clone https://github.com/OSS-PREY/OSSPREY-OSS-Scraper-Tool.git

# 2. Configure environment
cp .env.example .env
# Edit .env — add your GitHub token (see docs/TESTING_INSTRUCTIONS.md)

# 3. Start the stack
docker compose up -d --build

# 4. Build the Rust scraper (one-time)
docker exec ossprey-backend bash -c "cd /opt/ossprey/scraper && cargo build"

# 5. Import the Zenodo dataset
mkdir -p data
curl -L -o data/mongo_exports.zip \
  "https://zenodo.org/records/15307373/files/mongo_exports.zip?download=1"
cd data && unzip -o mongo_exports.zip && cd ..

for f in data/mongo_exports/*.json; do
  collection=$(basename "$f" .json)
  docker cp "$f" ossprey-mongodb:/tmp/
  docker exec ossprey-mongodb mongoimport \
    --uri "mongodb://ossprey:ossprey_dev_pw@localhost:27017/decal-db?authSource=admin" \
    --collection "$collection" \
    --file "/tmp/$(basename $f)" \
    --jsonArray --drop
done

# 6. Verify
./smoke_test.sh

# 7. Open the app
open http://localhost:3000
```

## Services

| Service | Port | Technology |
|---|---|---|
| **Frontend** | [localhost:3000](http://localhost:3000) | Vue 3, Vuetify 3, Plotly.js, Vite |
| **Backend API** | [localhost:5001](http://localhost:5001) | Flask 2, Gunicorn, PyMongo |
| **Database** | localhost:27017 | MongoDB 6.0 |

## Repositories

This is the **orchestration repository**. The application code lives in six sub-repos:

| Repository | Language | Purpose |
|---|---|---|
| [OSSPREY-FrontEnd-Server](https://github.com/OSS-PREY/OSSPREY-FrontEnd-Server) | Vue 3 / JS | Dashboard UI, data visualization |
| [OSSPREY-BackEnd-Server](https://github.com/OSS-PREY/OSSPREY-BackEnd-Server) | Python / Flask | REST API, pipeline orchestrator |
| [OSSPREY-OSS-Scraper-Tool](https://github.com/OSS-PREY/OSSPREY-OSS-Scraper-Tool) | Rust | GitHub data miner |
| [OSSPREY-Pex-Forecaster](https://github.com/OSS-PREY/OSSPREY-Pex-Forecaster) | Python / PyTorch | Sustainability ML forecaster |
| [OSSPREY-ReACT-API](https://github.com/OSS-PREY/OSSPREY-ReACT-API) | Python | Actionable recommendation engine |
| [OSSPREY-Website](https://github.com/OSS-PREY/OSSPREY-Website) | HTML | Public marketing site |

## Documentation

| Document | Description |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | System design, component breakdown, data flow, MongoDB schema |
| [Testing & Setup](docs/TESTING_INSTRUCTIONS.md) | Full setup guide, GitHub tokens, Zenodo import, troubleshooting |

## Smoke Tests

Run the automated smoke test suite after bringing the stack up:

```bash
./smoke_test.sh
```

Validates 21 checks across containers, networking, CORS, MongoDB data, GitHub tokens, authentication, API endpoints, and Gunicorn configuration. See the [test matrix](docs/TESTING_INSTRUCTIONS.md#test-matrix) for details.

## Prerequisites

- **Docker Desktop** (or OrbStack / Colima)
- **Git**
- A GitHub token — see [GitHub Tokens](docs/TESTING_INSTRUCTIONS.md#github-tokens) for setup options

## Contributing

1. Fork the relevant sub-repo (not this orchestration repo)
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes and add tests
4. Run `./smoke_test.sh` to verify the full stack
5. Submit a pull request

## License

This project is licensed under the [Apache License 2.0](LICENSE).

## Acknowledgments

- **UC Davis DECAL Lab** — Original research and dataset
- **Zenodo** — [Pre-computed foundation project data](https://zenodo.org/records/15307373)
- **Apache Software Foundation** & **Eclipse Foundation** — Project lifecycle data
