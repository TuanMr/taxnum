# ── TAX AI - Dockerfile ──────────────────────────────────────────────────────
# Build: docker build --platform linux/amd64 -t tax-ai:latest .
# Run:   docker run -p 8080:8080 --env-file .env tax-ai:latest
# ─────────────────────────────────────────────────────────────────────────────

FROM python:3.11-slim

LABEL maintainer="TAX AI" \
      description="AI chatbot tra cuu Ma So Thue Viet Nam"

# System deps cho Playwright Chromium
RUN apt-get update && apt-get install -y \
    wget gnupg ca-certificates \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2 libpango-1.0-0 libpangocairo-1.0-0 \
    libcairo2 libx11-6 libx11-xcb1 libxcb1 libxext6 \
    fonts-liberation libappindicator3-1 libdbus-1-3 \
    --no-install-recommends && rm -rf /var/lib/apt/lists/*

RUN groupadd -r taxai && useradd -r -g taxai taxai

WORKDIR /app

# Playwright browsers path - dat trong /app de chown duoc cho taxai
ENV PLAYWRIGHT_BROWSERS_PATH=/app/playwright-browsers

# Cai Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Cai Chromium vao /app/playwright-browsers/ (duoi root, truoc khi chown)
RUN playwright install chromium

# Copy source code
COPY config.py mst_lookup.py ai_handler.py memory_client.py memory_client.py server.py webchat.html ./

# Chown toan bo /app sang taxai (bao gom ca playwright-browsers/)
RUN chown -R taxai:taxai /app

USER taxai

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["python3", "server.py"]
