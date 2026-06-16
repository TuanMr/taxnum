"""
TAX AI - Zalo OA Webhook Server
Nhận và xử lý tin nhắn từ Zalo Official Account.

Cách triển khai:
1. Tạo Zalo OA tại: https://oa.zalo.me/
2. Vào Cài đặt → Webhook → nhập URL: https://yourdomain.com/zalo/webhook
3. Điền ZALO_OA_ACCESS_TOKEN và ZALO_APP_SECRET vào .env

Docs: https://developers.zalo.me/docs/official-account
"""
import hashlib
import hmac
import logging
import json
import requests
from flask import Flask, request, jsonify

from config import (
    ZALO_OA_ACCESS_TOKEN,
    ZALO_APP_SECRET,
    ZALO_WEBHOOK_PORT,
)
from mst_lookup import lookup_mst, search_company, is_valid_mst
from ai_handler import (
    extract_intent,
    INTENT_LOOKUP_MST,
    INTENT_SEARCH_NAME,
    INTENT_CHECK_STATUS,
    INTENT_GREETING,
    INTENT_HELP,
    _help_text,
)

logger = logging.getLogger(__name__)
app = Flask(__name__)

ZALO_API_BASE = "https://openapi.zalo.me/v2.0/oa"


# ─────────────────────────────────────────────
# Zalo API helpers
# ─────────────────────────────────────────────

def _send_message(user_id: str, text: str) -> dict:
    """Gửi tin nhắn văn bản đến người dùng Zalo."""
    url = f"{ZALO_API_BASE}/message"
    headers = {
        "access_token": ZALO_OA_ACCESS_TOKEN,
        "Content-Type": "application/json",
    }
    payload = {
        "recipient": {"user_id": user_id},
        "message": {"text": _strip_markdown(text)},
    }
    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=10)
        return resp.json()
    except Exception as e:
        logger.error("Zalo send_message failed: %s", e)
        return {}


def _send_list_message(user_id: str, title: str, results: list) -> dict:
    """Gửi danh sách kết quả tìm kiếm dạng list message."""
    if not results:
        return _send_message(user_id, "❌ Không tìm thấy kết quả.")

    # Zalo list message format
    elements = []
    for biz in results[:6]:  # Zalo giới hạn 6 item
        elements.append({
            "title": biz.name or biz.mst,
            "subtitle": f"MST: {biz.mst}" if biz.mst else "",
            "image_url": "https://via.placeholder.com/100x100?text=DN",
            "default_action": {
                "type": "oa.open.url",
                "url": f"https://masothue.com/{biz.mst}",
            },
        })

    url = f"{ZALO_API_BASE}/message"
    headers = {
        "access_token": ZALO_OA_ACCESS_TOKEN,
        "Content-Type": "application/json",
    }
    payload = {
        "recipient": {"user_id": user_id},
        "message": {
            "attachment": {
                "type": "template",
                "payload": {
                    "template_type": "list",
                    "elements": elements,
                    "buttons": [],
                },
            }
        },
    }
    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=10)
        return resp.json()
    except Exception as e:
        logger.error("Zalo list message failed: %s", e)
        # Fallback: text message
        text = title + "\n\n"
        for biz in results:
            text += f"• {biz.name} - MST: {biz.mst}\n"
        return _send_message(user_id, text)


def _strip_markdown(text: str) -> str:
    """Zalo không hỗ trợ Markdown, loại bỏ ký tự đặc biệt."""
    return (
        text.replace("*", "")
            .replace("`", "")
            .replace("_", "")
            .replace("[", "")
            .replace("]", "")
    )


def _verify_signature(raw_body: bytes, mac_token: str) -> bool:
    """Xác thực chữ ký webhook từ Zalo."""
    if not ZALO_APP_SECRET:
        return True  # Skip nếu chưa cấu hình
    expected = hmac.new(
        ZALO_APP_SECRET.encode(),
        raw_body,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, mac_token)


# ─────────────────────────────────────────────
# Core message processing
# ─────────────────────────────────────────────

def _process_message(user_id: str, text: str):
    """Xử lý tin nhắn và gửi phản hồi."""
    text = text.strip()
    intent_data = extract_intent(text)
    intent = intent_data.get("intent", "unknown")

    if intent == INTENT_LOOKUP_MST:
        mst = intent_data["mst"]
        _send_message(user_id, "🔍 Đang tra cứu MST " + mst + "...")
        result = lookup_mst(mst)
        _send_message(user_id, result.to_message())

    elif intent in (INTENT_SEARCH_NAME, INTENT_CHECK_STATUS):
        company_name = intent_data.get("company_name", "").strip()
        if company_name:
            _send_message(user_id, f"🔍 Đang tìm kiếm: {company_name}...")
            results = search_company(company_name)
            if not results:
                _send_message(user_id, f"❌ Không tìm thấy doanh nghiệp nào với tên {company_name}.")
            elif len(results) == 1 and results[0].address:
                _send_message(user_id, results[0].to_message())
            else:
                _send_list_message(user_id, f"Tìm thấy {len(results)} kết quả:", results)
        else:
            _send_message(user_id, "Bạn muốn tìm doanh nghiệp nào? Vui lòng cung cấp tên hoặc MST.")

    elif intent in (INTENT_GREETING, INTENT_HELP):
        _send_message(user_id, intent_data.get("response", "Xin chào!"))

    else:
        if is_valid_mst(text):
            result = lookup_mst(text)
            _send_message(user_id, result.to_message())
        else:
            _send_message(user_id, intent_data.get("response", "🤔 Tôi chưa hiểu. Gửi /help để xem hướng dẫn."))


# ─────────────────────────────────────────────
# Webhook routes
# ─────────────────────────────────────────────

@app.route("/zalo/webhook", methods=["GET"])
def zalo_verify():
    """Zalo webhook verification (OA đặt URL lần đầu)."""
    return jsonify({"status": "ok"})


@app.route("/zalo/webhook", methods=["POST"])
def zalo_webhook():
    """Nhận sự kiện từ Zalo OA."""
    raw_body = request.get_data()

    # Xác thực chữ ký
    mac_token = request.headers.get("X-ZEvent-Signature", "")
    if not _verify_signature(raw_body, mac_token):
        logger.warning("Invalid Zalo webhook signature")
        return jsonify({"error": "Invalid signature"}), 403

    try:
        data = json.loads(raw_body)
    except json.JSONDecodeError:
        return jsonify({"error": "Invalid JSON"}), 400

    event_type = data.get("event_name", "")
    logger.info("Zalo event: %s", event_type)

    # Chỉ xử lý tin nhắn text
    if event_type == "user_send_text":
        user_id = data.get("sender", {}).get("id", "")
        message = data.get("message", {}).get("text", "")
        if user_id and message:
            _process_message(user_id, message)

    # Sự kiện follow OA
    elif event_type == "follow":
        user_id = data.get("follower", {}).get("id", "")
        if user_id:
            _send_message(
                user_id,
                "👋 Xin chào! Tôi là TAX AI - trợ lý tra cứu thông tin doanh nghiệp Việt Nam.\n\n"
                "Gửi MST (10 số) hoặc tên doanh nghiệp để bắt đầu tra cứu.",
            )

    return jsonify({"status": "ok"})


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy", "service": "TAX AI Zalo Bot"})


# ─────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────

def run_zalo_bot():
    if not ZALO_OA_ACCESS_TOKEN:
        logger.warning("ZALO_OA_ACCESS_TOKEN chưa cấu hình - bot sẽ không gửi được tin nhắn")
    logger.info("🤖 TAX AI Zalo Bot đang chạy trên port %d...", ZALO_WEBHOOK_PORT)
    app.run(host="0.0.0.0", port=ZALO_WEBHOOK_PORT, debug=False)


if __name__ == "__main__":
    run_zalo_bot()
