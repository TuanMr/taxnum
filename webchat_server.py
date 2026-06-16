
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

from flask import Flask, request, jsonify, send_from_directory
from mst_lookup import lookup_mst, search_company, is_valid_mst, is_valid_cccd, lookup_by_cccd
from ai_handler import extract_intent, INTENT_LOOKUP_MST, INTENT_SEARCH_NAME, INTENT_CHECK_STATUS, INTENT_GREETING, INTENT_HELP, _help_text

app = Flask(__name__)

@app.route('/')
def index():
    return send_from_directory('.', 'webchat.html')

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/chat', methods=['POST'])
def chat():
    data = request.get_json(silent=True) or {}
    text = data.get('message', '').strip()
    if not text:
        return jsonify({'reply': 'Vui long nhap noi dung.'})

    if text.startswith('/start'):
        return jsonify({'reply': 'Xin chao! Gui MST (10 so) hoac ten doanh nghiep de tra cuu.'})
    if text.startswith('/help'):
        return jsonify({'reply': _help_text()})
    if text.startswith('/tracuu '):
        text = text[8:].strip()

    intent_data = extract_intent(text)
    intent = intent_data.get('intent', 'unknown')

    if intent == INTENT_LOOKUP_MST:
        result = lookup_mst(intent_data['mst'])
        return jsonify({'reply': result.to_message()})

    elif intent in (INTENT_SEARCH_NAME, INTENT_CHECK_STATUS):
        company = intent_data.get('company_name', '').strip()
        if company:
            results = search_company(company)
            if not results:
                return jsonify({'reply': f'Khong tim thay: {company}'})
            elif len(results) == 1 and results[0].address:
                return jsonify({'reply': results[0].to_message()})
            else:
                lines = [f'Tim thay {len(results)} ket qua cho {company}:\n']
                for i, biz in enumerate(results[:8], 1):
                    lines.append(f'{i}. {biz.name} - MST: {biz.mst}')
                lines.append('\nGui MST de xem chi tiet.')
                return jsonify({'reply': '\n'.join(lines)})
        return jsonify({'reply': 'Ban muon tim doanh nghiep nao?'})

    elif intent in (INTENT_GREETING, INTENT_HELP):
        return jsonify({'reply': intent_data.get('response', 'Xin chao!')})

    else:
        if is_valid_cccd(text):
            result = lookup_by_cccd(text)
            return jsonify({'reply': result.to_message()})
        if is_valid_mst(text):
            result = lookup_mst(text)
            return jsonify({'reply': result.to_message()})
        return jsonify({'reply': intent_data.get('response', 'Gui MST (10 so), CCCD (12 so) hoac ten doanh nghiep de tra cuu.')})

if __name__ == '__main__':
    print('TAX AI Web Chat: http://localhost:5000')
    app.run(host='0.0.0.0', port=5000, debug=True)
