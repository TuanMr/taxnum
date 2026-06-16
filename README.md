# 🏛️ TAX AI — Tra cứu Mã Số Thuế & Kiểm tra Hóa đơn Điện tử

<div align="center">

[![Live Demo](https://img.shields.io/badge/🌐_Live_Demo-Online-brightgreen?style=for-the-badge)](https://endpoint-a8fb1754-4339-4474-85cf-3a43d3e3c5b2.agentbase-runtime.aiplatform.vngcloud.vn)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=for-the-badge&logo=python)](https://python.org)
[![Flask](https://img.shields.io/badge/Flask-3.0-000000?style=for-the-badge&logo=flask)](https://flask.palletsprojects.com)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=for-the-badge&logo=docker)](https://docker.com)

**Chatbot AI tra cứu thông tin doanh nghiệp · Kiểm tra hóa đơn điện tử · Xuất Excel hàng loạt**  
Hỗ trợ Telegram · Zalo · Web Chat · REST API

</div>

---

## 🌐 Dùng ngay — Không cần cài đặt

| Kênh | Link |
|------|------|
| 🌐 Web Chat | [https://endpoint-a8fb1754-4339-4474-85cf-3a43d3e3c5b2.agentbase-runtime.aiplatform.vngcloud.vn](https://endpoint-a8fb1754-4339-4474-85cf-3a43d3e3c5b2.agentbase-runtime.aiplatform.vngcloud.vn) |
| 💬 Telegram | Tìm bot theo token đã cấu hình |
| 📱 Zalo | Qua Zalo OA đã tích hợp |

---

## ✨ Tính năng

### 🔍 Tra cứu thông tin doanh nghiệp
- **Tra theo MST** — nhập 10 chữ số, nhận đầy đủ thông tin ngay lập tức
- **Tìm theo tên** — nhập tên công ty, AI tự động tìm và trả kết quả
- **Tra theo CCCD** — tra cứu MST cá nhân từ số CCCD 12 chữ số
- **Cảnh báo trạng thái** ❌ — tự động bôi đỏ khi NNT không đang hoạt động (áp dụng cho cả tra MST, tìm tên và kiểm tra hóa đơn)

### 📄 Kiểm tra hóa đơn điện tử (1 file)
Upload file `.xml` hoặc `.pdf`, hệ thống tự động:
- Trích xuất MST bên bán / bên mua từ file
- Đối chiếu **tên công ty** trên HĐ với dữ liệu GDT — bôi đỏ nếu sai lệch đáng kể
- So sánh **địa chỉ** trên HĐ vs địa chỉ GDT — bôi đỏ cả 2 dòng nếu không khớp
- Cảnh báo **trạng thái hoạt động** của bên bán và bên mua
- Phát hiện **ký số trễ >24h** so với ngày lập hóa đơn
- Tổng hợp tất cả cảnh báo cuối kết quả

### 📋 Kiểm tra hàng loạt hóa đơn XML *(tính năng mới)*
Upload nhiều file `.xml` cùng lúc:
- **Thanh tiến trình realtime** — hiển thị X/N file đang xử lý
- Tự động đối chiếu từng hóa đơn với GDT
- **Xuất file Excel (.xlsx)** khi hoàn thành, gồm 2 sheet:

| Sheet | Nội dung |
|-------|----------|
| **Tổng hợp** | Tổng số HĐ kiểm tra · Danh sách HĐ có MST không hoạt động · Danh sách HĐ ký số trễ >24h |
| **Chi tiết** | STT · Tên file · Số HĐ · Bên bán/MST/Trạng thái · Bên mua/MST/Trạng thái · Độ khớp địa chỉ · Chênh lệch ngày ký |

Hàng có vấn đề được **tô màu đỏ** tự động trong Excel.

### 🧠 AI tìm kiếm theo tên thông minh
Khi tìm theo tên, hệ thống chạy pipeline tự động:
```
1. xinvoice.vn API (name search)
        ↓ không có kết quả
2. Playwright Chromium → Google Search (headless, stealth mode)
   - Tìm "{tên} mã số thuế", extract số 10 chữ số, verify qua GDT
        ↓ không có kết quả
3. DuckDuckGo HTML scraping (fallback)
        ↓ không có kết quả
4. Bing HTML scraping (last resort)
```

### 📊 Thông tin trả về
- Tên đầy đủ, tên quốc tế, tên ngắn
- Mã số thuế · Trạng thái hoạt động (✅ / ❌)
- Địa chỉ trụ sở · Cơ quan thuế quản lý
- Người đại diện pháp luật · Loại hình DN · Ngày bắt đầu

### 🤖 Xử lý ngôn ngữ tự nhiên
- Nhận diện intent: tra MST, tìm tên, hỏi trạng thái, chào hỏi
- Hỗ trợ tiếng Việt có dấu và không dấu
- Tích hợp Claude AI (Anthropic) để xử lý câu hỏi phức tạp

---

## 🚀 Hướng dẫn sử dụng

### Người dùng cuối

**Tra theo MST (10 hoặc 13 số):**
```
0302654173
0302654173-001
```

**Tìm theo tên công ty:**
```
VNG
Viettel
FPT Software
MISA
```

**Tra theo CCCD:**
```
079201012345
```

**Lệnh:**
```
/start  — Chào hỏi, hướng dẫn
/help   — Danh sách lệnh
```

### REST API

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| `GET` | `/` | Web Chat UI |
| `POST` | `/chat` | Chat API — `{"message": "VNG"}` |
| `POST` | `/invoice` | Upload 1 hóa đơn `.xml` / `.pdf` |
| `POST` | `/invoice/batch` | Upload nhiều `.xml` → trả `job_id` |
| `GET` | `/invoice/batch/status/<id>` | Trạng thái xử lý batch |
| `GET` | `/invoice/batch/result/<id>` | Download file Excel kết quả |
| `GET` | `/health` | Health check (GreenNode) |
| `POST` | `/telegram/webhook` | Telegram webhook |
| `POST` | `/zalo/webhook` | Zalo webhook |
| `GET` | `/debug/search?q=VNG` | Debug tìm kiếm (dev only) |

---

## 🛠 Hướng dẫn cho Developer

### Yêu cầu hệ thống

| Công nghệ | Phiên bản |
|-----------|-----------|
| Python | 3.11+ |
| Docker | 24+ |
| Chromium (Playwright) | Tự động cài |

### Cài đặt local

```bash
# 1. Clone repo
git clone https://github.com/TuanMr/taxnum.git
cd taxnum

# 2. Tạo môi trường ảo
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 3. Cài dependencies
pip install -r requirements.txt

# 4. Cài Playwright Chromium
playwright install chromium

# 5. Cấu hình môi trường
cp .env.example .env
# Chỉnh sửa .env với các key thực

# 6. Chạy server
python server.py
```

Server chạy tại: `http://localhost:8080`

### Cấu trúc dự án

```
taxnum/
├── server.py           # Flask server, tất cả endpoints
├── invoice_parser.py   # Parser hóa đơn XML/PDF + batch Excel export
├── mst_lookup.py       # Core: tra cứu MST, tìm theo tên công ty
├── ai_handler.py       # NLP: phân tích intent với Claude AI
├── config.py           # Cấu hình từ biến môi trường
├── memory_client.py    # GreenNode Memory Store client
├── webchat.html        # Web Chat UI (single-file, no build step)
├── Dockerfile          # Docker image (python:3.11-slim + Playwright)
├── requirements.txt    # Python dependencies
└── .env.example        # Template biến môi trường
```

### Biến môi trường

| Biến | Bắt buộc | Mô tả |
|------|----------|-------|
| `TELEGRAM_BOT_TOKEN` | ✅ | Token từ @BotFather |
| `ZALO_BOT_TOKEN` | ⬜ | Token Zalo OA |
| `ENDPOINT_URL` | ✅ | URL public của server (để set webhook) |
| `ANTHROPIC_API_KEY` | ⬜ | Claude API key (NLP nâng cao) |
| `CLAUDE_MODEL` | ⬜ | Model Claude (default: claude-haiku-4-5-20251001) |
| `BING_SEARCH_KEY` | ⬜ | Azure Bing Search v7 API key |
| `GOOGLE_SEARCH_KEY` | ⬜ | Google Custom Search API key |
| `GOOGLE_SEARCH_CX` | ⬜ | Google CSE ID |
| `MEMORY_ID` | ⬜ | GreenNode Memory Store ID |

### Deploy lên GreenNode AgentBase

```bash
# Build Docker image
docker build --platform linux/amd64 -t tax-ai:latest .

# Push lên GreenNode Container Registry
docker tag tax-ai:latest vcr.vngcloud.vn/YOUR_PROJECT/tax-ai:latest
docker push vcr.vngcloud.vn/YOUR_PROJECT/tax-ai:latest
```

Cấu hình AgentBase:
- **Port:** 8080
- **Health check:** `GET /health`
- **Env vars:** Điền trong giao diện AgentBase

### Stack công nghệ

| Layer | Thư viện |
|-------|----------|
| Web server | Flask 3.0, flask-cors |
| Scraping | Playwright (Chromium), BeautifulSoup, Requests |
| PDF | PyMuPDF (fitz) |
| Excel | **openpyxl 3.1** |
| Bot | python-telegram-bot v20, python-zalo-bot |
| AI / NLP | Anthropic Claude API |
| Deploy | Docker, GreenNode AgentBase |

### Nguồn dữ liệu

| Nguồn | Dùng cho |
|-------|---------|
| xinvoice.vn / GDT API | Tra MST chính |
| VietQR | Tên quốc tế, tên ngắn |
| Google Search (Playwright) | Tìm theo tên công ty |
| DuckDuckGo HTML | Fallback tìm tên |

---

## 🔧 Kiến trúc hệ thống

```
User (Telegram/Zalo/Web)
         │
         ▼
   Flask Server (port 8080)
         │
    ┌────┴────┐
    │ NLP     │  ← Claude AI (intent detection)
    │ Handler │
    └────┬────┘
         │
    ┌────┴────────────────┐
    │   MST Lookup Engine │
    │                     │
    │  [Tra theo MST]     │
    │   xinvoice.vn ──────┼─→ GDT API
    │   VietQR ───────────┼─→ GDT API
    │                     │
    │  [Tìm theo tên]     │
    │   Google/Playwright ┼─→ Chromium headless
    │   DuckDuckGo HTML ──┼─→ HTTP scraping
    │   Bing API ─────────┼─→ Azure (optional)
    └─────────────────────┘
         │
    GreenNode Memory Store (hội thoại)
```

---

## 📝 Giấy phép

MIT License — Tự do sử dụng, chỉnh sửa, phân phối.

---

<div align="center">
Made with ❤️ for Vietnam business lookup · Powered by GreenNode AgentBase
</div>
