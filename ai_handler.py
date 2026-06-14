"""
TAX AI - NLP Handler
Dùng Claude API để hiểu câu hỏi tự nhiên và trích xuất intent/MST.
"""
import re
import json
import logging
from typing import Optional

try:
    import anthropic
    _ANTHROPIC_OK = True
except ImportError:
    anthropic = None
    _ANTHROPIC_OK = False

try:
    from config import ANTHROPIC_API_KEY, CLAUDE_MODEL
except Exception:
    ANTHROPIC_API_KEY = ""
    CLAUDE_MODEL = ""

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Intent types
# ─────────────────────────────────────────────

INTENT_LOOKUP_MST = "lookup_mst"        # Tra cứu theo MST
INTENT_SEARCH_NAME = "search_name"      # Tìm theo tên DN
INTENT_CHECK_STATUS = "check_status"    # Kiểm tra trạng thái
INTENT_GREETING = "greeting"            # Chào hỏi
INTENT_HELP = "help"                    # Hỏi cách dùng
INTENT_UNKNOWN = "unknown"              # Không xác định

SYSTEM_PROMPT = """Bạn là TAX AI - trợ lý tra cứu thông tin doanh nghiệp Việt Nam qua Mã Số Thuế (MST).

Nhiệm vụ của bạn là:
1. Phân tích tin nhắn người dùng
2. Trả về JSON với cấu trúc:
{
  "intent": "<intent>",
  "mst": "<mst nếu có>",
  "company_name": "<tên DN nếu có>",
  "response": "<câu trả lời ngắn gọn nếu là greeting/help/unknown>"
}

Các intent hợp lệ:
- "lookup_mst": người dùng cung cấp MST để tra cứu
- "search_name": người dùng cung cấp tên doanh nghiệp để tìm kiếm
- "check_status": hỏi về trạng thái hoạt động
- "greeting": chào hỏi thông thường
- "help": hỏi cách sử dụng
- "unknown": không xác định được yêu cầu

MST có định dạng 10 hoặc 13 chữ số (ví dụ: 0101243150 hoặc 0101243150-001).

Quy tắc:
- Chỉ trả về JSON, không giải thích thêm
- Nếu intent là greeting/help/unknown, điền trường "response" bằng tiếng Việt thân thiện
- Nếu MST kèm theo tên thì ưu tiên lookup_mst
"""


# ─────────────────────────────────────────────
# Rule-based fallback (không cần API)
# ─────────────────────────────────────────────

MST_RE = re.compile(r"\b(\d{10}(?:-\d{3})?)\b")


def _extract_intent_rulebased(text: str) -> dict:
    """Trích xuất intent bằng regex, không cần AI."""
    text_lower = text.lower().strip()

    # MST pattern
    mst_match = MST_RE.search(text)
    if mst_match:
        return {"intent": INTENT_LOOKUP_MST, "mst": mst_match.group(1), "company_name": ""}

    # Greeting
    greet_words = ["xin chào", "hello", "hi", "chào", "hey", "helo"]
    if any(w in text_lower for w in greet_words):
        return {
            "intent": INTENT_GREETING,
            "mst": "",
            "company_name": "",
            "response": (
                "Xin chào! 👋 Tôi là *TAX AI* - trợ lý tra cứu thông tin doanh nghiệp Việt Nam.\n\n"
                "Bạn có thể:\n"
                "• Gửi *MST* (10 số) để tra cứu thông tin\n"
                "• Gửi *tên doanh nghiệp* để tìm kiếm\n"
                "• Gõ /help để xem hướng dẫn chi tiết"
            ),
        }

    # Help
    help_words = ["help", "hướng dẫn", "giúp", "cách dùng", "cách sử dụng", "/help"]
    if any(w in text_lower for w in help_words):
        return {
            "intent": INTENT_HELP,
            "mst": "",
            "company_name": "",
            "response": _help_text(),
        }

    # Search by name keywords
    search_keywords = ["tìm", "tìm kiếm", "search", "công ty", "doanh nghiệp"]
    if any(w in text_lower for w in search_keywords):
        # Remove keywords to get company name
        company = text
        for kw in ["tìm kiếm", "tìm công ty", "tìm doanh nghiệp", "tìm", "search"]:
            company = re.sub(rf"\b{re.escape(kw)}\b", "", company, flags=re.IGNORECASE).strip()
        return {"intent": INTENT_SEARCH_NAME, "mst": "", "company_name": company}

    # Nếu text ngắn và không có số, có thể là tên DN
    if len(text) > 3 and not re.search(r"\d{5,}", text):
        return {"intent": INTENT_SEARCH_NAME, "mst": "", "company_name": text}

    return {"intent": INTENT_UNKNOWN, "mst": "", "company_name": "", "response": _unknown_text()}


def _help_text() -> str:
    return (
        "📖 *Hướng dẫn sử dụng TAX AI*\n\n"
        "*Tra cứu theo MST:*\n"
        "Gửi MST 10 số, ví dụ: `0101243150`\n\n"
        "*Tìm kiếm theo tên:*\n"
        "Gửi tên DN, ví dụ: `MISA` hoặc `tìm công ty MISA`\n\n"
        "*Lệnh nhanh:*\n"
        "/tracuu `<MST>` - Tra cứu MST\n"
        "/tim `<tên>` - Tìm kiếm doanh nghiệp\n"
        "/help - Xem hướng dẫn\n\n"
        "Dữ liệu từ: GDT (Tổng cục Thuế) & masothue.com"
    )


def _unknown_text() -> str:
    return (
        "🤔 Tôi chưa hiểu yêu cầu của bạn.\n\n"
        "Bạn có thể:\n"
        "• Gửi *MST* (10 số): `0101243150`\n"
        "• Gửi *tên doanh nghiệp*: `MISA`\n"
        "• Gõ /help để xem hướng dẫn"
    )


# ─────────────────────────────────────────────
# Claude API handler
# ─────────────────────────────────────────────

_client = None


def _get_client():
    global _client
    if not _ANTHROPIC_OK or not ANTHROPIC_API_KEY:
        return None
    if _client is None:
        _client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    return _client


def extract_intent(user_message: str) -> dict:
    """
    Phân tích intent từ tin nhắn người dùng.
    Dùng rule-based trước, Claude API nếu cần.
    """
    # Rule-based (nhanh, offline)
    rb = _extract_intent_rulebased(user_message)
    if rb["intent"] != INTENT_UNKNOWN:
        return rb

    # Claude API (cho câu hỏi phức tạp)
    client = _get_client()
    if not client:
        return rb  # No API key, return unknown

    try:
        msg = client.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=256,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_message}],
        )
        raw = msg.content[0].text.strip()
        # Parse JSON
        raw = re.sub(r"```json\s*|\s*```", "", raw).strip()
        data = json.loads(raw)
        return {
            "intent": data.get("intent", INTENT_UNKNOWN),
            "mst": data.get("mst", ""),
            "company_name": data.get("company_name", ""),
            "response": data.get("response", ""),
        }
    except Exception as e:
        logger.warning("Claude API intent extraction failed: %s", e)
        return rb


def generate_summary(business_info) -> str:
    """
    Tóm tắt thông tin doanh nghiệp bằng ngôn ngữ tự nhiên (nếu có Claude API).
    Fallback về format mặc định nếu không có API.
    """
    if not ANTHROPIC_API_KEY:
        return business_info.to_message()

    client = _get_client()
    if not client:
        return business_info.to_message()

    prompt = f"""Tóm tắt ngắn gọn thông tin doanh nghiệp sau bằng tiếng Việt thân thiện (dưới 100 từ):
Tên: {business_info.name}
MST: {business_info.mst}
Địa chỉ: {business_info.address}
Trạng thái: {business_info.status}
Người đại diện: {business_info.representative}
"""
    try:
        msg = client.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=200,
            messages=[{"role": "user", "content": prompt}],
        )
        return msg.content[0].text.strip()
    except Exception as e:
        logger.warning("Claude summary failed: %s", e)
        return business_info.to_message()
