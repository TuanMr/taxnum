"""
TAX AI - Telegram Bot
Chạy bằng python-telegram-bot v20+ (asyncio)
"""
import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    filters,
    ContextTypes,
)
from telegram.constants import ParseMode

from config import TELEGRAM_BOT_TOKEN
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

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

async def _send_typing(update: Update):
    await update.message.chat.send_action("typing")


def _search_result_keyboard(results: list) -> InlineKeyboardMarkup:
    """Tạo inline keyboard từ kết quả tìm kiếm."""
    buttons = []
    for biz in results:
        if biz.mst:
            label = f"{biz.name[:30]}... [{biz.mst}]" if len(biz.name) > 30 else f"{biz.name} [{biz.mst}]"
            buttons.append([InlineKeyboardButton(label, callback_data=f"mst:{biz.mst}")])
    return InlineKeyboardMarkup(buttons)


# ─────────────────────────────────────────────
# Command handlers
# ─────────────────────────────────────────────

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler lệnh /start"""
    text = (
        "👋 Xin chào! Tôi là *TAX AI*\n"
        "Trợ lý tra cứu thông tin doanh nghiệp Việt Nam 🇻🇳\n\n"
        "Gửi *MST* (10 số) hoặc *tên doanh nghiệp* để bắt đầu.\n\n"
        "Gõ /help để xem hướng dẫn chi tiết."
    )
    await update.message.reply_text(text, parse_mode=ParseMode.MARKDOWN)


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler lệnh /help"""
    await update.message.reply_text(_help_text(), parse_mode=ParseMode.MARKDOWN)


async def cmd_tracuu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/tracuu <MST> - Tra cứu MST trực tiếp"""
    if not context.args:
        await update.message.reply_text(
            "❗ Cú pháp: `/tracuu <MST>`\nVí dụ: `/tracuu 0101243150`",
            parse_mode=ParseMode.MARKDOWN,
        )
        return

    mst = context.args[0].strip()
    await _handle_mst_lookup(update, mst)


async def cmd_tim(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/tim <tên> - Tìm kiếm doanh nghiệp"""
    if not context.args:
        await update.message.reply_text(
            "❗ Cú pháp: `/tim <tên doanh nghiệp>`\nVí dụ: `/tim MISA`",
            parse_mode=ParseMode.MARKDOWN,
        )
        return

    name = " ".join(context.args)
    await _handle_name_search(update, name)


# ─────────────────────────────────────────────
# Core logic
# ─────────────────────────────────────────────

async def _handle_mst_lookup(update: Update, mst: str):
    """Tra cứu MST và gửi kết quả."""
    msg = await update.message.reply_text("🔍 Đang tra cứu...")
    result = lookup_mst(mst)
    await msg.edit_text(
        result.to_message(),
        parse_mode=ParseMode.MARKDOWN,
    )


async def _handle_name_search(update: Update, name: str):
    """Tìm kiếm doanh nghiệp theo tên."""
    msg = await update.message.reply_text(f"🔍 Đang tìm kiếm *{name}*...", parse_mode=ParseMode.MARKDOWN)
    results = search_company(name)

    if not results:
        await msg.edit_text(
            f"❌ Không tìm thấy doanh nghiệp nào với tên *{name}*.\n\n"
            "Thử tìm bằng MST (10 số) nếu bạn đã biết.",
            parse_mode=ParseMode.MARKDOWN,
        )
        return

    if len(results) == 1 and results[0].address:
        # Chỉ 1 kết quả đầy đủ thông tin - hiển thị luôn
        await msg.edit_text(results[0].to_message(), parse_mode=ParseMode.MARKDOWN)
        return

    # Nhiều kết quả - hiển thị danh sách
    text = f"🔎 Tìm thấy {len(results)} kết quả cho *{name}*:\nChọn doanh nghiệp bạn muốn xem:"
    keyboard = _search_result_keyboard(results)
    await msg.edit_text(text, parse_mode=ParseMode.MARKDOWN, reply_markup=keyboard)


# ─────────────────────────────────────────────
# Message handler (natural language)
# ─────────────────────────────────────────────

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Xử lý tin nhắn văn bản tự nhiên."""
    text = update.message.text.strip()
    await _send_typing(update)

    intent_data = extract_intent(text)
    intent = intent_data.get("intent", "unknown")

    if intent == INTENT_LOOKUP_MST:
        await _handle_mst_lookup(update, intent_data["mst"])

    elif intent in (INTENT_SEARCH_NAME, INTENT_CHECK_STATUS):
        company_name = intent_data.get("company_name", "").strip()
        if company_name:
            await _handle_name_search(update, company_name)
        else:
            await update.message.reply_text(
                "Bạn muốn tìm doanh nghiệp nào? Vui lòng cung cấp tên hoặc MST.",
                parse_mode=ParseMode.MARKDOWN,
            )

    elif intent in (INTENT_GREETING, INTENT_HELP):
        await update.message.reply_text(
            intent_data.get("response", "Xin chào!"),
            parse_mode=ParseMode.MARKDOWN,
        )

    else:
        # Unknown - nếu là số 10 chữ số, thử tra cứu MST
        if is_valid_mst(text):
            await _handle_mst_lookup(update, text)
        else:
            await update.message.reply_text(
                intent_data.get("response", "🤔 Tôi chưa hiểu. Gõ /help để xem hướng dẫn."),
                parse_mode=ParseMode.MARKDOWN,
            )


# ─────────────────────────────────────────────
# Callback query (inline keyboard)
# ─────────────────────────────────────────────

async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Xử lý khi người dùng bấm vào kết quả tìm kiếm."""
    query = update.callback_query
    await query.answer()

    data = query.data
    if data.startswith("mst:"):
        mst = data[4:]
        await query.edit_message_text("🔍 Đang tra cứu...")
        result = lookup_mst(mst)
        await query.edit_message_text(
            result.to_message(),
            parse_mode=ParseMode.MARKDOWN,
        )


# ─────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────

def run_telegram_bot():
    if not TELEGRAM_BOT_TOKEN:
        raise ValueError("TELEGRAM_BOT_TOKEN chưa được cấu hình trong file .env")

    app = Application.builder().token(TELEGRAM_BOT_TOKEN).build()

    # Commands
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("tracuu", cmd_tracuu))
    app.add_handler(CommandHandler("tim", cmd_tim))

    # Callback
    app.add_handler(CallbackQueryHandler(handle_callback))

    # Text messages
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    logger.info("🤖 TAX AI Telegram Bot đang chạy...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    run_telegram_bot()
