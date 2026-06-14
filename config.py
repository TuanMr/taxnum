"""
TAX AI - Configuration
"""
import os
from dotenv import load_dotenv

load_dotenv()

# ===== TELEGRAM =====
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")

# ===== ZALO BOT CHAT =====
ZALO_BOT_TOKEN = os.getenv("ZALO_BOT_TOKEN", "")
ENDPOINT_URL = os.getenv("ENDPOINT_URL", "")

# ===== CLAUDE API (NLP) =====
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
CLAUDE_MODEL = os.getenv("CLAUDE_MODEL", "claude-haiku-4-5-20251001")

# ===== VIETQR API =====
VIETQR_API_BASE = "https://api.vietqr.io/v2"

# ===== MASOTHUE SCRAPER =====
MASOTHUE_BASE = "https://masothue.com"
SCRAPER_TIMEOUT = 15
SCRAPER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "vi-VN,vi;q=0.9,en;q=0.8",
    "Referer": "https://masothue.com/",
}

# ===== SEARCH APIs (optional - cho name search) =====
# Bing Search API v7 (Azure): 1000 queries/month free
# Tao tai: https://portal.azure.com -> Cognitive Services -> Bing Search v7
BING_SEARCH_KEY = os.getenv("BING_SEARCH_KEY", "")

# Google Custom Search Engine: 100 queries/day free
# Tao CSE tai: https://cse.google.com (target masothue.com)
# Lay API key tai: https://console.cloud.google.com -> Custom Search JSON API
GOOGLE_SEARCH_KEY = os.getenv("GOOGLE_SEARCH_KEY", "")
GOOGLE_SEARCH_CX  = os.getenv("GOOGLE_SEARCH_CX", "")

# ===== GREENNODE MEMORY =====
MEMORY_ID = os.getenv("MEMORY_ID", "")
MEMORY_API_BASE = "https://agentbase.api.vngcloud.vn/memory"

# ===== APP =====
MAX_SEARCH_RESULTS = 10
CACHE_TTL_SECONDS = 3600  # 1 gio
