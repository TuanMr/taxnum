# 🚀 Hướng dẫn Deploy TAX AI lên GreenNode AgentBase

## Kiến trúc deploy

```
Telegram / Zalo
     │
     ▼
GreenNode AgentBase Runtime (Custom Agent)
  ├── /health          → GreenNode health check
  ├── /telegram/webhook → Telegram updates
  └── /zalo/webhook    → Zalo OA events
     │
     ├── VietQR API (tra cứu MST)
     ├── masothue.com (tìm theo tên)
     ├── Claude API (NLP - optional)
     └── GreenNode Memory (lịch sử hội thoại - optional)
```

---

## Bước 0: Chuẩn bị

### Tài khoản & công cụ cần có

- ✅ Tài khoản [GreenNode / VNG Cloud](https://aiplatform.console.vngcloud.vn/)
- ✅ Docker Desktop cài đặt sẵn
- ✅ Token Telegram Bot (từ @BotFather)
- ✅ Token Zalo OA (từ [developers.zalo.me](https://developers.zalo.me/))

### Cài dependencies

```bash
cd TAX\ Search/
pip install -r requirements.txt
```

---

## Bước 1: Cấu hình IAM Credentials

Vào [IAM Console VNG Cloud](https://iam.console.vngcloud.vn/service-accounts) → tạo Service Account.

Cấu hình credentials (không bao giờ commit file này):

```bash
# Lưu credentials vào .greennode.json
echo '<client_secret>' | bash .claude/skills/agentbase/scripts/save_iam_credentials.sh \
  --client-id "<client_id>" --secret-stdin

# Kiểm tra
bash .claude/skills/agentbase/scripts/check_credentials.sh iam
```

---

## Bước 2: Tạo Memory Store (Tuỳ chọn)

Memory lưu lịch sử hội thoại của người dùng.

```bash
# Lấy IAM token
TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)

# Tạo memory store
curl -s -X POST "https://agentbase.api.vngcloud.vn/memory/memories" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "tax-ai-memory",
    "description": "Lịch sử hội thoại TAX AI",
    "eventExpiryDuration": 30,
    "longTermMemoryStrategies": [
      {
        "name": "user-preference",
        "type": "USER_PREFERENCE",
        "namespaceTemplate": "/strategies/{memoryStrategyId}/actors/{actorId}",
        "enableAutomaticMemoryRecordGeneration": true
      }
    ]
  }'
```

Lưu `memory_id` trả về vào `.env`:
```bash
bash .claude/skills/agentbase/scripts/save_env_var.sh \
  --key MEMORY_ID --value "<memory-id-từ-response>"
```

---

## Bước 3: Cấu hình file .env

```bash
cp .env.example .env
```

Chỉnh sửa `.env`:

```env
# Telegram
TELEGRAM_BOT_TOKEN=your_telegram_token

# Zalo
ZALO_OA_ACCESS_TOKEN=your_zalo_token
ZALO_APP_SECRET=your_zalo_secret

# Claude API (tuỳ chọn)
ANTHROPIC_API_KEY=your_claude_key
CLAUDE_MODEL=claude-haiku-4-5-20251001

# GreenNode Memory (nếu có)
MEMORY_ID=memory-xxxxxxxx
```

> ⚠️ KHÔNG để vào .env: `GREENNODE_CLIENT_ID`, `GREENNODE_CLIENT_SECRET`,
> `GREENNODE_AGENT_IDENTITY`, `GREENNODE_ENDPOINT_URL`
> — GreenNode tự inject các biến này vào container khi deploy.

---

## Bước 4: Build Docker Image

```bash
# Build cho linux/amd64 (bắt buộc cho GreenNode)
docker build --platform linux/amd64 -t tax-ai:latest .

# Test local trước khi push
docker run -p 8080:8080 --env-file .env tax-ai:latest

# Kiểm tra health endpoint
curl http://localhost:8080/health
# → {"status": "ok", "service": "TAX AI"}
```

---

## Bước 5: Push lên Container Registry

### 5a. Lấy thông tin Container Registry

```bash
TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)

# Lấy repo info
bash .claude/skills/agentbase/scripts/cr.sh repo-info
```

Kết quả trả về `repoUrl` dạng: `cr.vngcloud.vn/<namespace>/agentbase`

### 5b. Docker login vào CR

```bash
bash .claude/skills/agentbase/scripts/docker_login.sh
```

### 5c. Tag và push image

```bash
# Thay <namespace> bằng namespace thực tế từ bước 5a
CR_REPO="cr.vngcloud.vn/<namespace>/agentbase"
IMAGE_TAG="v$(date +%Y%m%d%H%M%S)"

docker tag tax-ai:latest $CR_REPO/tax-ai:$IMAGE_TAG
docker push $CR_REPO/tax-ai:$IMAGE_TAG

echo "Image: $CR_REPO/tax-ai:$IMAGE_TAG"
```

---

## Bước 6: Deploy Runtime

### 6a. Xem available flavors

```bash
bash .claude/skills/agentbase/scripts/runtime.sh flavors
```

Gợi ý: `1x1-general` (1 CPU, 1GB RAM) đủ cho TAX AI.

### 6b. Prepare imageAuth

```bash
bash .claude/skills/agentbase/scripts/prepare_image_auth.sh
# Tạo file .agentbase/imageauth.json
```

### 6c. Tạo Runtime

```bash
TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)
IMAGE_AUTH=$(cat .agentbase/imageauth.json)

curl -s -X POST "https://agentbase.api.vngcloud.vn/agent-runtimes" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"tax-ai\",
    \"description\": \"AI tra cứu Mã Số Thuế Việt Nam\",
    \"imageUrl\": \"$CR_REPO/tax-ai:$IMAGE_TAG\",
    \"imageAuth\": $IMAGE_AUTH,
    \"command\": [],
    \"args\": [],
    \"environmentVariables\": {},
    \"flavorId\": \"1x1-general\",
    \"autoscaling\": {
      \"minReplicas\": 1,
      \"maxReplicas\": 2,
      \"cpuUtilization\": 70,
      \"memoryUtilization\": 80
    }
  }" | bash .claude/skills/agentbase/scripts/redact_response.sh
```

> **Lưu ý**: Biến môi trường được inject qua field `environmentVariables` ở trên,
> HOẶC bạn có thể dùng `--env-file .env` nếu dùng script wrapper của skills.

### Dùng script thay thế (đơn giản hơn):

```bash
bash .claude/skills/agentbase/scripts/runtime.sh create \
  --name tax-ai \
  --image "$CR_REPO/tax-ai:$IMAGE_TAG" \
  --flavor 1x1-general \
  --env-file .env \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu-scale 70 \
  --mem-scale 80
```

### 6d. Theo dõi trạng thái

```bash
# Lấy RUNTIME_ID từ response bước trên
RUNTIME_ID="agent-runtime-xxxxxxxx"

# Poll cho đến khi ACTIVE
watch -n 5 "bash .claude/skills/agentbase/scripts/runtime.sh get $RUNTIME_ID"

# Xem endpoint URL
bash .claude/skills/agentbase/scripts/runtime.sh endpoints list $RUNTIME_ID
```

---

## Bước 7: Đăng ký Webhook

Sau khi có `ENDPOINT_URL` từ bước 6d:

### Telegram Webhook

```bash
ENDPOINT_URL="https://your-runtime-endpoint.vngcloud.vn"
BOT_TOKEN="your_telegram_token"

curl "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook" \
  -d "url=${ENDPOINT_URL}/telegram/webhook"

# Kiểm tra
curl "https://api.telegram.org/bot${BOT_TOKEN}/getWebhookInfo"
```

### Zalo OA Webhook

Vào [Zalo OA Admin](https://oa.zalo.me/) → Cài đặt → Webhook:
- URL: `https://your-runtime-endpoint.vngcloud.vn/zalo/webhook`
- Chọn events: `user_send_text`, `follow`

---

## Bước 8: Kiểm tra & Monitor

```bash
# Health check
curl https://your-runtime-endpoint.vngcloud.vn/health

# Xem logs
bash .claude/skills/agentbase/scripts/runtime.sh logs $RUNTIME_ID

# Hoặc dùng skill
# /agentbase-monitor runtime-logs $RUNTIME_ID
```

Console: https://aiplatform.console.vngcloud.vn/agent-runtime?tab=runtime

---

## Bước 9: Update / Redeploy

Khi thay đổi code:

```bash
# Build image mới
IMAGE_TAG="v$(date +%Y%m%d%H%M%S)"
docker build --platform linux/amd64 -t $CR_REPO/tax-ai:$IMAGE_TAG .
docker push $CR_REPO/tax-ai:$IMAGE_TAG

# Update runtime
bash .claude/skills/agentbase/scripts/runtime.sh update $RUNTIME_ID \
  --image "$CR_REPO/tax-ai:$IMAGE_TAG"
```

---

## Tóm tắt nhanh (Checklist)

```
[ ] 0. Cài Docker, có GreenNode account
[ ] 1. Tạo IAM Service Account → save credentials
[ ] 2. (Optional) Tạo Memory Store → save MEMORY_ID
[ ] 3. Tạo .env với Telegram/Zalo tokens
[ ] 4. docker build --platform linux/amd64 -t tax-ai:latest .
[ ] 5. docker login CR → docker tag → docker push
[ ] 6. runtime.sh create → đợi ACTIVE
[ ] 7. setWebhook Telegram + Zalo OA config
[ ] 8. Test chat → monitor logs
```

---

## Troubleshooting

| Lỗi | Nguyên nhân | Fix |
|-----|-------------|-----|
| Runtime status ERROR | Image pull failed | Kiểm tra imageAuth credentials |
| `/health` timeout | Server bind sai | Đảm bảo `host="0.0.0.0"`, port 8080 |
| Telegram không nhận tin | Webhook chưa set | Chạy lại `setWebhook` |
| 401 từ GreenNode API | Token hết hạn | `get_token.sh --force` |
| Zalo 403 | App Secret sai | Kiểm tra `ZALO_APP_SECRET` |
| Memory not found | MEMORY_ID sai | Kiểm tra `GET /memory/memories` |
