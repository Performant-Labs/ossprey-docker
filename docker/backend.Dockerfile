# ── OSSPREY Backend (Flask + Gunicorn + Rust Scraper) ────────
FROM python:3.10-slim

# System deps for building native wheels (pymongo, scipy, torch, etc.)
# plus Rust toolchain for the OSS-Scraper
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc git curl pkg-config libssl-dev && \
    rm -rf /var/lib/apt/lists/*

# Install Rust (needed to compile the OSS-Scraper tool)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Install Python deps first (layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY . .

# Create output directories the app expects
RUN mkdir -p out/apache/partial

EXPOSE 5000

# Start with Gunicorn in dev-friendly mode (auto-reload, 1 worker)
CMD ["gunicorn", "--config", "gunicorn.conf.py", "--bind", "0.0.0.0:5000", "run:app"]
