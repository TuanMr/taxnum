# TAX AI - Deploy Zalo + Telegram via GreenNode OpenClaw
# Run: powershell -ExecutionPolicy Bypass -File deploy_zalo.ps1

$ErrorActionPreference = "Stop"
$IAM_URL      = "https://iam.api.vngcloud.vn/accounts-api/v2/auth/token"
$OPENCLAW_URL = "https://agentbase.api.vngcloud.vn/runtime/openclaws"
$OC_VER_URL   = "https://agentbase.api.vngcloud.vn/runtime/openclaw-versions"
$FLAVOR_URL   = "https://agentbase.api.vngcloud.vn/runtime/flavors"

function OK($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Info($t) { Write-Host "  --> $t"  -ForegroundColor Gray }
function Fail($t) { Write-Host " [ERR] $t" -ForegroundColor Red; exit 1 }

function Load-Token($file, $label) {
    if (Test-Path $file) {
        $raw = Get-Content $file -Raw
        try {
            $ss = $raw.Trim() | ConvertTo-SecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
            $t = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            OK "Loaded $label from $file"; return $t
        } catch { $t = $raw.Trim(); OK "Loaded $label (plain) from $file"; return $t }
    }
    Write-Host "  Enter ${label}:" -ForegroundColor Yellow
    $ss = Read-Host "  Token" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    $t = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $ss | ConvertFrom-SecureString | Set-Content $file -Encoding ASCII
    OK "Saved $label to $file"; return $t
}

# -- 1. IAM Token --------------------------------------------------------------
Write-Host "`n[1/5] IAM Token" -ForegroundColor Cyan
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

# -- 2. Delete old OpenClaw if exists ------------------------------------------
Write-Host "`n[2/5] Cleanup old OpenClaw" -ForegroundColor Cyan
if (Test-Path ".agentbase-zalo.json") {
    $old = Get-Content ".agentbase-zalo.json" | ConvertFrom-Json
    if ($old.openclaw_id) {
        Info "Deleting: $($old.openclaw_id)"
        try { Invoke-RestMethod -Method Delete -Uri "$OPENCLAW_URL/$($old.openclaw_id)" -Headers $H | Out-Null; OK "Deleted" }
        catch { Info "Could not delete: $_" }
    }
} else { Info "No old OpenClaw found" }

# -- 3. Load tokens ------------------------------------------------------------
Write-Host "`n[3/5] Bot Tokens" -ForegroundColor Cyan
$zaloToken = Load-Token ".zalo-token.txt" "Zalo Bot Token"
$teleToken = Load-Token ".telegram-token.txt" "Telegram Bot Token"
if (-not $zaloToken) { Fail "Zalo token empty" }
if (-not $teleToken) { Fail "Telegram token empty" }

# -- 4. Pick flavor + version --------------------------------------------------
Write-Host "`n[4/5] Config" -ForegroundColor Cyan
$flavorId = $null
try {
    $flavorResp = Invoke-RestMethod -Uri $FLAVOR_URL -Headers $H
    $flavors = if ($flavorResp.listData) { $flavorResp.listData } else { $flavorResp }
    $picked = $flavors | Select-Object -First 1
    if ($picked.id) { $flavorId = $picked.id; OK "Flavor: $flavorId" }
} catch { Info "Using server default flavor" }

$verId = $null
try {
    $versResp = Invoke-RestMethod -Uri $OC_VER_URL -Headers $H
    $vers = if ($versResp.listData) { $versResp.listData } else { $versResp }
    $defVer = $vers | Where-Object { $_.defaultVersion -eq $true } | Select-Object -First 1
    if (-not $defVer) { $defVer = $vers | Select-Object -First 1 }
    if ($defVer) { $verId = $defVer.id; OK "Version: $($defVer.name)" }
} catch { Info "Using server default version" }

# -- 5. Create OpenClaw with Zalo + Telegram -----------------------------------
Write-Host "`n[5/5] Create OpenClaw (Zalo + Telegram)" -ForegroundColor Cyan

$bodyObj = @{
    name                   = "tax-ai"
    greenNodeModelProvider = @{ enabled = $true }
    channels               = @{
        zalo     = @{ botToken = $zaloToken;  dmPolicy = "pairing"; dmAllowedUserIds = @() }
        telegram = @{ botToken = $teleToken;  dmPolicy = "pairing"; dmAllowedUserIds = @() }
    }
}
if ($verId)    { $bodyObj.versionId = $verId }
if ($flavorId) { $bodyObj.flavorId  = $flavorId }

# Try dmPolicy "open" first, fall back to "pairing"
foreach ($policy in @("open", "pairing")) {
    $bodyObj.channels.zalo.dmPolicy     = $policy
    $bodyObj.channels.telegram.dmPolicy = $policy
    $body = $bodyObj | ConvertTo-Json -Depth 10
    Info "Trying dmPolicy=$policy ..."
    try {
        $res = Invoke-RestMethod -Method Post -Uri $OPENCLAW_URL `
            -Headers $H -ContentType "application/json" -Body $body
        OK "Created with dmPolicy=$policy"
        break
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
        if ($policy -eq "open") { Info "dmPolicy 'open' rejected ($errMsg), trying 'pairing'..." }
        else { Fail "Create failed: $_ | $errMsg" }
    }
}

$ocId  = $res.id
$ocUrl = $res.url
OK "OpenClaw ID: $ocId"
Write-Host ""
Write-Host ("=" * 58) -ForegroundColor Green
Write-Host "  TAX AI deployed on Zalo + Telegram!" -ForegroundColor Green
Write-Host ("=" * 58) -ForegroundColor Green
Write-Host "  Status  : $($res.status)"
Write-Host "  URL     : $ocUrl"
Write-Host "  Console : https://aiplatform.console.vngcloud.vn/agent-runtime?tab=openclaw"

@{ openclaw_id = $ocId; url = $ocUrl; deployed_at = (Get-Date -Format "o") } |
    ConvertTo-Json | Set-Content ".agentbase-zalo.json" -Encoding ASCII
OK "Saved to .agentbase-zalo.json"
