# TAX AI - Tao GreenNode Memory Store
# Run: powershell -ExecutionPolicy Bypass -File create_memory.ps1

$ErrorActionPreference = "Stop"
$IAM_URL = "https://iam.api.vngcloud.vn/accounts-api/v2/auth/token"
$MEM_URL = "https://agentbase.api.vngcloud.vn/memory/memories"

function OK($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Info($t) { Write-Host "  --> $t"  -ForegroundColor Gray }
function Fail($t) { Write-Host " [ERR] $t" -ForegroundColor Red; exit 1 }

Write-Host "`n[1/2] IAM Token" -ForegroundColor Cyan
$cf = ".greennode.json"
if (-not (Test-Path $cf)) { Fail ".greennode.json not found. Run deploy.ps1 first." }
$s   = Get-Content $cf -Raw | ConvertFrom-Json
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($s.client_id):$($s.client_secret)"))
try {
    $tok = Invoke-RestMethod -Method Post -Uri $IAM_URL `
        -Headers @{ Authorization = "Basic $b64" } `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "grant_type=client_credentials"
} catch { Fail "Token failed: $_" }
if (-not $tok.access_token) { Fail "Empty token." }
$H = @{ Authorization = "Bearer $($tok.access_token)" }
OK "Token OK"

Write-Host "`n[2/2] Create Memory Store" -ForegroundColor Cyan

$body = @{
    name                      = "tax-ai-memory"
    description               = "Lich su hoi thoai TAX AI"
    eventExpiryDuration       = 90
    longTermMemoryStrategies  = @(
        @{
            name                               = "user-history"
            type                               = "SEMANTIC"
            namespaceTemplate                  = "/strategies/{memoryStrategyId}/actors/{actorId}"
            enableAutomaticMemoryRecordGeneration = $true
        }
    )
} | ConvertTo-Json -Depth 10

try {
    $res = Invoke-RestMethod -Method Post -Uri $MEM_URL `
        -Headers $H -ContentType "application/json" -Body $body
} catch {
    $errMsg = ""
    try { $errMsg = $_.ErrorDetails.Message } catch {}
    if (-not $errMsg) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0; $reader.DiscardBufferedData()
            $errMsg = $reader.ReadToEnd()
        } catch {}
    }
    Fail "Create memory failed: $_ | $errMsg"
}

$memId = $res.id
OK "Memory created: $memId"

# Luu vao .env
if (Test-Path ".env") {
    $envContent = Get-Content ".env" -Raw
    if ($envContent -match "MEMORY_ID=") {
        $envContent = $envContent -replace "MEMORY_ID=.*", "MEMORY_ID=$memId"
    } else {
        $envContent += "`nMEMORY_ID=$memId"
    }
    $envContent | Set-Content ".env" -Encoding UTF8
    OK "MEMORY_ID saved to .env"
} else {
    "MEMORY_ID=$memId" | Set-Content ".env" -Encoding UTF8
    OK ".env created with MEMORY_ID"
}

# Luu state
@{ memory_id = $memId; created_at = (Get-Date -Format "o") } |
    ConvertTo-Json | Set-Content ".agentbase-memory.json" -Encoding ASCII
OK "Saved to .agentbase-memory.json"

Write-Host ""
Write-Host ("=" * 50) -ForegroundColor Green
Write-Host "  Memory Store ready!" -ForegroundColor Green
Write-Host "  ID: $memId" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Green
