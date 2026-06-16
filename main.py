"""
TAX AI - Entry Point
Chạy Telegram bot, Zalo bot, hoặc cả hai.

Usage:
  python main.py telegram     # Chỉ chạy Telegram
  python main.py zalo         # Chỉ chạy Zalo webhook
  python main.py both         # Chạy cả hai (threading)
  python main.py test         # Test tra cứu MST ngay trên terminal
"""
import sys
import logging

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    level=logging.INFO,
)


def run_telegram():
    from telegram_bot import run_telegram_bot
    run_telegram_bot()


def run_zalo():
    from zalo_bot import run_zalo_bot
    run_zalo_bot()


def run_both():
    import threading
    t_zalo = threading.Thread(target=run_zalo, daemon=True)
    t_zalo.start()
    run_telegram()  # Telegram chạy main thread


def run_test():
    """Test nhanh mà không cần token bot."""
    from mst_lookup import lookup_mst, search_company
    from ai_handler import extract_intent

    print("=" * 50)
    print("TAX AI - Test Mode")
    print("=" * 50)

    # Test MST lookup
    test_mst = "0101243150"
    print(f"\n📌 Tra cứu MST: {test_mst}")
    result = lookup_mst(test_mst)
    print(result.to_message())

    # Test intent extraction
    print("\n📌 Test NLP:")
    test_messages = [
        "xin chào",
        "tra cứu mst 0101243150",
        "tìm công ty MISA",
        "0305658735",
    ]
    for msg in test_messages:
        intent = extract_intent(msg)
        print(f"  '{msg}' → intent: {intent['intent']}, mst: {intent.get('mst')}, name: {intent.get('company_name')}")


def main():
    mode = sys.argv[1].lower() if len(sys.argv) > 1 else "telegram"

    modes = {
        "telegram": run_telegram,
        "zalo": run_zalo,
        "both": run_both,
        "test": run_test,
    }

    if mode not in modes:
        print(f"❌ Mode không hợp lệ: {mode}")
        print(f"   Các mode hợp lệ: {', '.join(modes.keys())}")
        sys.exit(1)

    modes[mode]()


if __name__ == "__main__":
    main()
