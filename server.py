"""
TAX AI - Unified Webhook Server
Chạy trên GreenNode AgentBase (port 8080).

Endpoints:
  - GET  /                    → Web chat UI
  - POST /chat                → Web chat API
  - GET  /health              → GreenNode health check
  - POST /telegram/webhook    → Telegram updates
  - POST /zalo/webhook        → Zalo Bot Chat events
"""
import asyncio
import logging
import os
import threading
import uuid
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import requests

from config import TELEGRAM_BOT_TOKEN, ZALO_BOT_TOKEN, ENDPOINT_URL, MEMORY_ID
import memory_client as mem
from mst_lookup import lookup_mst, search_company, is_valid_mst
from invoice_parser import verify_invoice, format_verify_result
from ai_handler import (
    extract_intent,
    INTENT_LOOKUP_MST,
    INTENT_SEARCH_NAME,
    INTENT_CHECK_STATUS,
    INTENT_GREETING,
    INTENT_HELP,
    _help_text,
)

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app, resources={r"/chat": {"origins": "*"}, r"/health": {"origins": "*"}})

# ── Batch job store (in-memory) ──
_batch_jobs: dict = {}  # job_id → {status, progress, total, results, error}

TELEGRAM_API = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}"

# ─────────────────────────────────────────────
# Health check (bắt buộc cho GreenNode)
# ─────────────────────────────────────────────

@app.route("/", methods=["GET"])
def index():
    base = os.path.dirname(os.path.abspath(__file__))
    return send_from_directory(base, "webchat.html")


@app.route("/chat", methods=["POST"])
def webchat():
    data = request.get_json(silent=True) or {}
    text = data.get("message", "").strip()
    if not text:
        return jsonify({"reply": "Vui long nhap noi dung."})
    if text.startswith("/start"):
        return jsonify({"reply": "Xin chao! Gui MST (10 so) hoac ten doanh nghiep de tra cuu."})
    if text.startswith("/help"):
        return jsonify({"reply": _help_text()})
    # Strip command prefixes
    for _prefix in ("/tracuu ", "/tim ", "/search ", "/find "):
        if text.lower().startswith(_prefix):
            text = text[len(_prefix):].strip()
            break

    from mst_lookup import is_valid_cccd, lookup_by_cccd
    intent_data = extract_intent(text)
    intent = intent_data.get("intent", "unknown")

    if intent == INTENT_LOOKUP_MST:
        result = lookup_mst(intent_data["mst"])
        return jsonify({"reply": result.to_message()})
    elif intent in (INTENT_SEARCH_NAME, INTENT_CHECK_STATUS):
        company = intent_data.get("company_name", "").strip()
        if company:
            return jsonify({"reply": _resolve_search(company)})
        return jsonify({"reply": "Bạn muốn tìm doanh nghiệp nào?"})
    elif intent in (INTENT_GREETING, INTENT_HELP):
        return jsonify({"reply": intent_data.get("response", "Xin chao!")})
    else:
        if is_valid_cccd(text):
            return jsonify({"reply": lookup_by_cccd(text).to_message()})
        if is_valid_mst(text):
            return jsonify({"reply": lookup_mst(text).to_message()})
        return jsonify({"reply": intent_data.get("response", "Gui MST (10 so) hoac ten DN de tra cuu.")})


def _resolve_search(company: str) -> str:
    """
    Xử lý kết quả tìm kiếm theo tên:
    - 1 kết quả có MST hợp lệ → tự động tra MST luôn
    - 1 kết quả không có MST / có lỗi → hiển thị info sẵn có
    - Nhiều kết quả → liệt kê, chỉ gợi ý gửi MST nếu thực sự có MST
    """
    results = search_company(company)

    if not results:
        return f"❌ Không tìm thấy doanh nghiệp nào với tên *{company}*."

    if len(results) == 1:
        r = results[0]
        if r.error:
            return r.to_message()
        # Có MST hợp lệ → tra luôn để lấy đầy đủ thông tin
        if r.mst and is_valid_mst(r.mst):
            full = lookup_mst(r.mst)
            if full.name:
                return full.to_message()
        # Không có MST nhưng có tên → hiển thị những gì có
        if r.name:
            return r.to_message()
        return f"❌ Không tìm thấy thông tin chi tiết cho *{company}*."

    # Nhiều kết quả
    lines = [f"🔎 Tìm thấy {len(results)} kết quả cho *{company}*:\n"]
    has_mst = False
    for i, biz in enumerate(results[:8], 1):
        if biz.error:
            lines.append(biz.to_message())
            continue
        mst_str = f" — MST: `{biz.mst}`" if biz.mst else ""
        lines.append(f"{i}. {biz.name}{mst_str}")
        if biz.mst:
            has_mst = True
    if has_mst:
        lines.append("\nGửi MST để xem chi tiết.")
    return "\n".join(lines)


@app.route("/invoice", methods=["POST"])
def invoice_upload():
    """
    Upload file hóa đơn điện tử (.xml hoặc .pdf).
    Form-data: file=<binary>
    Trả về kết quả kiểm tra MST bên bán/mua + đối chiếu địa chỉ.
    """
    if "file" not in request.files:
        return jsonify({"error": "Thiếu field 'file' trong form-data"}), 400

    f = request.files["file"]
    filename = f.filename or "invoice"
    ext = filename.lower().rsplit(".", 1)[-1] if "." in filename else ""

    if ext not in ("xml", "pdf"):
        return jsonify({
            "error": f"Định dạng không hỗ trợ: .{ext}. Chỉ chấp nhận .xml và .pdf"
        }), 400

    content = f.read()
    if len(content) > 10 * 1024 * 1024:  # 10MB
        return jsonify({"error": "File quá lớn (tối đa 10MB)"}), 400

    try:
        result  = verify_invoice(content, filename)
        message = format_verify_result(result)
        return jsonify({"reply": message, "ok": True})
    except Exception as e:
        logger.exception("invoice_upload error")
        return jsonify({"error": str(e)}), 500


@app.route("/invoice/batch", methods=["POST"])
def invoice_batch_start():
    """
    Upload nhiều file .xml để kiểm tra hàng loạt.
    Form-data: files=<file1>,<file2>,...
    Trả về job_id để poll trạng thái.
    """
    files = request.files.getlist("files")
    if not files:
        return jsonify({"error": "Thiếu field 'files' trong form-data"}), 400

    # Read file content trong request context (trước khi thread bắt đầu)
    file_data = []
    for f in files:
        name = f.filename or "invoice.xml"
        ext  = name.lower().rsplit(".", 1)[-1] if "." in name else ""
        if ext != "xml":
            continue
        content = f.read()
        if len(content) > 10 * 1024 * 1024:
            continue
        file_data.append((name, content))

    if not file_data:
        return jsonify({"error": "Không có file .xml hợp lệ (tối đa 10MB/file)"}), 400

    job_id = str(uuid.uuid4())[:8]
    _batch_jobs[job_id] = {
        "status":   "processing",
        "progress": 0,
        "total":    len(file_data),
        "results":  [],
        "error":    None,
    }

    def _process():
        from invoice_parser import verify_invoice, _extract_batch_row
        rows = []
        try:
            for i, (fname, content) in enumerate(file_data):
                try:
                    result = verify_invoice(content, fname)
                    rows.append(_extract_batch_row(fname, result))
                except Exception as e:
                    rows.append({"filename": fname, "parse_error": str(e),
                                 "invoice_no": "", "invoice_date": "", "signing_time": "",
                                 "seller_mst": "", "buyer_mst": "",
                                 "seller_is_active": None, "buyer_is_active": None,
                                 "signing_delay_hours": None, "signing_delay_str": ""})
                _batch_jobs[job_id]["progress"] = i + 1
                _batch_jobs[job_id]["results"]  = list(rows)
            _batch_jobs[job_id]["status"] = "done"
        except Exception as e:
            logger.exception("batch processing error")
            _batch_jobs[job_id]["status"] = "error"
            _batch_jobs[job_id]["error"]  = str(e)

    threading.Thread(target=_process, daemon=True).start()
    return jsonify({"job_id": job_id, "total": len(file_data)})


@app.route("/invoice/batch/status/<job_id>", methods=["GET"])
def invoice_batch_status(job_id):
    job = _batch_jobs.get(job_id)
    if not job:
        return jsonify({"error": "Không tìm thấy job"}), 404
    return jsonify({
        "status":   job["status"],
        "progress": job["progress"],
        "total":    job["total"],
        "error":    job.get("error"),
    })


@app.route("/invoice/batch/result/<job_id>", methods=["GET"])
def invoice_batch_result(job_id):
    job = _batch_jobs.get(job_id)
    if not job:
        return jsonify({"error": "Không tìm thấy job"}), 404
    if job["status"] != "done":
        return jsonify({"error": "Chưa hoàn thành xử lý"}), 400

    try:
        from invoice_parser import batch_to_excel
        excel_bytes = batch_to_excel(job["results"])
        resp = app.make_response(excel_bytes)
        resp.headers["Content-Type"] = (
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )
        resp.headers["Content-Disposition"] = (
            'attachment; filename="kiem_tra_hoa_don.xlsx"'
        )
        resp.headers["Content-Length"] = len(excel_bytes)
        resp.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        return resp
    except Exception as e:
        logger.exception("batch_to_excel error")
        return jsonify({"error": str(e)}), 500


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "TAX AI"}), 200


@app.route("/debug/search", methods=["GET"])
def debug_search():
    """
    Chẩn đoán tìm kiếm theo tên từ GreenNode.
    Dùng: GET /debug/search?q=VNG
    """
    import logging as _log
    import urllib.parse as _up

    q = request.args.get("q", "").strip()
    if not q:
        return jsonify({"error": "Thiếu param ?q="}), 400

    log_records: list[str] = []

    class _ListHandler(_log.Handler):
        def emit(self, record):
            log_records.append(self.format(record))

    h = _ListHandler()
    h.setFormatter(_log.Formatter("%(name)s [%(levelname)s] %(message)s"))
    root = _log.getLogger()
    root.addHandler(h)

    out: dict = {"query": q, "steps": []}

    try:
        from mst_lookup import (
            _search_xinvoice_by_name,
            _make_scraper,
            _extract_msts_from_html,
            search_company,
        )

        # Step 1: xinvoice name search
        xr = _search_xinvoice_by_name(q)
        out["steps"].append({
            "step": "xinvoice_name_search",
            "results": len(xr),
            "names": [r.name for r in xr],
        })

        # Step 2: Bing HTML — xem tất cả masothue context để biết URL format
        from mst_lookup import _make_scraper
        import re as _re
        bing_session = _make_scraper()
        bing_url = f"https://www.bing.com/search?q={_up.quote(q + ' site:masothue.com')}&cc=vn&setlang=vi&count=10"
        try:
            br = bing_session.get(bing_url, timeout=12)
            bhtml = br.text
            # Tất cả masothue contexts
            all_ctx = []
            i = 0
            bhtml_lower = bhtml.lower()
            while True:
                p = bhtml_lower.find("masothue", i)
                if p == -1:
                    break
                all_ctx.append(bhtml[max(0, p-150): p+350])
                i = p + 1
            all_10d = list(set(_re.findall(r'\b\d{10}\b', bhtml)))
            out["steps"].append({
                "step": "bing_masothue_contexts",
                "status": br.status_code,
                "html_len": len(bhtml),
                "masothue_count": len(all_ctx),
                "all_10digit_in_bing": all_10d[:20],
                "contexts": all_ctx,
            })
        except Exception as e:
            out["steps"].append({"step": "bing_masothue_contexts", "error": str(e)})

        # Step 3: DDG HTML + cac site khac
        import re as _re2
        search_tests = []
        br_s = requests.Session()
        br_s.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
            "Accept": "text/html,*/*",
            "Accept-Language": "vi-VN,vi;q=0.9,en;q=0.8",
        })
        search_urls = [
            ("ddg-html",      f"https://html.duckduckgo.com/html/?q={_up.quote(q + ' site:masothue.com')}", "GET"),
            ("ddg-lite",      f"https://lite.duckduckgo.com/lite/?q={_up.quote(q + ' ma so thue masothue')}", "GET"),
            ("tracumst",      f"https://tracumst.vn/search?q={_up.quote(q)}", "GET"),
            ("masothue-info", f"https://masothue.info/search?q={_up.quote(q)}", "GET"),
            ("thue-vn",       f"https://thue.vn/tra-cuu?q={_up.quote(q)}", "GET"),
        ]
        for label, url, method in search_urls:
            try:
                r2 = br_s.request(method, url, timeout=8, allow_redirects=True)
                html2 = r2.text
                msts_found = list(set(_re2.findall(r"masothue[^/]*/(\d{10})", html2)))
                msts_found = list(set(msts_found))[:10]
                search_tests.append({
                    "label": label,
                    "status": r2.status_code,
                    "len": len(html2),
                    "content_type": r2.headers.get("Content-Type", ""),
                    "msts_extracted": msts_found,
                    "snippet": html2[:500],
                })
            except Exception as e:
                search_tests.append({"label": label, "error": str(e)})
        out["steps"].append({"step": "search_engine_tests", "results": search_tests})

        # Step 4: Playwright/Google test (direct)
        try:
            from mst_lookup import _search_by_playwright
            pw_results = _search_by_playwright(q)
            out["steps"].append({
                "step": "playwright_google",
                "count": len(pw_results),
                "results": [{"mst": r.mst, "name": r.name} for r in pw_results],
            })
        except Exception as e:
            import traceback as _tb2
            out["steps"].append({"step": "playwright_google", "error": str(e), "tb": _tb2.format_exc()})

        # Step 5: full search
        final = search_company(q)
        out["steps"].append({
            "step": "search_company",
            "count": len(final),
            "results": [{"mst": r.mst, "name": r.name, "error": r.error} for r in final],
        })

        out["logs"] = log_records[-60:]
        import json as _json
        return app.response_class(
            _json.dumps(out, ensure_ascii=False, indent=2),
            mimetype="application/json"
        )

    except Exception as ex:
        out["fatal_error"] = str(ex)
        import traceback as _tb
        out["traceback"] = _tb.format_exc()
        out["logs"] = log_records[-60:]
        import json as _json
        return app.response_class(
            _json.dumps(out, ensure_ascii=False, indent=2),
            status=500, mimetype="application/json"
        )
    finally:
        root.removeHandler(h)


# ─────────────────────────────────────────────
# Telegram Webhook
# ─────────────────────────────────────────────

def tg_send(chat_id: int, text: str, parse_mode: str = "Markdown"):
    try:
        requests.post(
            f"{TELEGRAM_API}/sendMessage",
            json={"chat_id": chat_id, "text": text, "parse_mode": parse_mode},
            timeout=10,
        )
    except Exception as e:
        logger.error("Telegram send error: %s", e)


def tg_send_temp(chat_id: int, text: str) -> int:
    """Gửi tin nhắn tạm, trả về message_id để edit sau."""
    try:
        r = requests.post(
            f"{TELEGRAM_API}/sendMessage",
            json={"chat_id": chat_id, "text": text},
            timeout=10,
        ).json()
        return r.get("result", {}).get("message_id", 0)
    except Exception:
        return 0


def tg_edit(chat_id: int, msg_id: int, text: str):
    try:
        requests.post(
            f"{TELEGRAM_API}/editMessageText",
            json={"chat_id": chat_id, "message_id": msg_id, "text": text, "parse_mode": "Markdown"},
            timeout=10,
        )
    except Exception as e:
        logger.error("Telegram edit error: %s", e)


def _tg_handle_message(chat_id: int, text: str):
    text = text.strip()
    intent_data = extract_intent(text)
    intent = intent_data.get("intent", "unknown")

    if intent == INTENT_LOOKUP_MST:
        mst = intent_data["mst"]
        mid = tg_send_temp(chat_id, f"🔍 Đang tra cứu MST {mst}...")
        result = lookup_mst(mst)
        if mid:
            tg_edit(chat_id, mid, result.to_message())
        else:
            tg_send(chat_id, result.to_message())

    elif intent in (INTENT_SEARCH_NAME, INTENT_CHECK_STATUS):
        company = intent_data.get("company_name", "").strip()
        if company:
            mid = tg_send_temp(chat_id, f"🔍 Đang tìm *{company}*...")
            msg = _resolve_search(company)
            if mid:
                tg_edit(chat_id, mid, msg)
            else:
                tg_send(chat_id, msg)
        else:
            tg_send(chat_id, "Bạn muốn tìm doanh nghiệp nào? Cung cấp tên hoặc MST.")

    elif intent in (INTENT_GREETING, INTENT_HELP):
        tg_send(chat_id, intent_data.get("response", "Xin chào!"))

    else:
        if is_valid_mst(text):
            mid = tg_send_temp(chat_id, f"🔍 Đang tra cứu MST {text}...")
            result = lookup_mst(text)
            if mid:
                tg_edit(chat_id, mid, result.to_message())
            else:
                tg_send(chat_id, result.to_message())
        else:
            tg_send(chat_id, intent_data.get("response", "🤔 Gõ /help để xem hướng dẫn."))


@app.route("/telegram/webhook", methods=["POST"])
def telegram_webhook():
    data = request.get_json(silent=True) or {}
    message = data.get("message", {})
    if not message:
        return jsonify({"ok": True})

    chat_id = message.get("chat", {}).get("id")
    text = message.get("text", "")

    if not chat_id or not text:
        return jsonify({"ok": True})

    # Luu input vao memory
    actor = f"tg_{chat_id}"
    mem.save_local(actor, "user", text)
    if MEMORY_ID:
        mem.add_event(MEMORY_ID, actor, "user", text)

    # Xu ly lenh nhanh
    if text.startswith("/start"):
        tg_send(chat_id, "👋 Xin chào! Tôi là *TAX AI*\nGửi MST (10 số) hoặc tên DN để tra cứu.\nGõ /help xem hướng dẫn.")
    elif text.startswith("/help"):
        tg_send(chat_id, _help_text())
    elif text.startswith("/tracuu "):
        mst = text[8:].strip()
        mid = tg_send_temp(chat_id, f"🔍 Đang tra cứu MST {mst}...")
        result = lookup_mst(mst)
        if mid:
            tg_edit(chat_id, mid, result.to_message())
        else:
            tg_send(chat_id, result.to_message())
    elif text.startswith("/tim "):
        name = text[5:].strip()
        _tg_handle_message(chat_id, f"tìm {name}")
    else:
        _tg_handle_message(chat_id, text)

    # Luu response vao memory
    if MEMORY_ID:
        mem.add_event(MEMORY_ID, actor, "assistant", "OK")
    return jsonify({"ok": True})


# ─────────────────────────────────────────────
# Zalo Bot Chat (python-zalo-bot)
# ─────────────────────────────────────────────

try:
    from zalo_bot import Bot as ZaloBot, Update as ZaloUpdate
    from zalo_bot.ext import Dispatcher, CommandHandler, MessageHandler, filters as zf
    _ZALO_OK = True
except ImportError:
    logger.warning("python-zalo-bot not installed — Zalo disabled.")
    _ZALO_OK = False

_zalo_bot = None
_zalo_disp = None


async def _zalo_start(update, context):
    await update.message.reply_text(
        "👋 Xin chào! Tôi là TAX AI\n"
        "Gửi MST (10 số) hoặc tên DN để tra cứu.\n"
        "Gõ /help xem hướng dẫn."
    )


async def _zalo_help(update, context):
    await upda