# ── OSSPREY Frontend (Vue 3 + Vite Dev Server) ──────────────
FROM node:18-slim

WORKDIR /app

# Copy the full source first because the postinstall script
# (build:icons) requires src/plugins/iconify/build-icons.js
COPY . .

# Install all dependencies (postinstall will now find the source files)
RUN npm ci

EXPOSE 3000

# Run Vite dev server on all interfaces so Docker can expose it
CMD ["npx", "vite", "--host", "0.0.0.0", "--port", "3000"]
