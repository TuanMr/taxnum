$ErrorActionPreference = "Stop"

$IAM_URL      = "https://iam.api.vngcloud.vn/accounts-api/v2/auth/token"
$CR_URL       = "https://agentbase.api.vngcloud.vn/cr/api/v1"
$RT_URL       = "https://agentbase.api.vngcloud.vn/runtime/agent-runtimes"
$IMAGE_NAME   = "tax-ai"
$RUNTIME_NAME = "tax-ai"
$FLAVOR       = "1x1-general"

function Step($n,$t){ Write-Host "`n[$n/8] $t" -ForegroundColor Cyan }
function OK($t)     { Write-Host "  [OK] $t"  -ForegroundColor Green }
function Info($t)   { Write-Host "  --> $t"   -ForegroundColor Gray }
function Fail($t)   { Write-Host " [ERR] $t"  -ForegroundColor Red; exit 1 }

Step 1 "IAM Credentials"
$cf = ".greennode.json"
$cid = ""; $csec = ""
if (Test-Path $cf) {
    $s = Get-Content $cf -Raw | ConvertFrom-Json
    $cid = $s.client_id; $csec = $s.client_secret
    OK "Loaded from $cf"
} elseif ($env:GREENNODE_CLIENT_ID) {
    $cid = $env:GREENNODE_CLIENT_ID; $csec = $env:GREENNODE_CLIENT_SECRET
    OK "Loaded from env"
} else {
    Write-Host "  Enter GreenNode IAM credentials" -ForegroundColor Yellow
    Write-Host "  https://iam.console.vngcloud.vn/service-accounts" -ForegroundColor DarkGray
    $cid = Read-Host "  Client ID"
    $ss = Read-Host "  Client Secret" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    $csec = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    [PSCustomObject]@{ client_id = $cid; client_secret = $csec } | ConvertTo-Json | Set-Content $cf -Encoding UTF8
    OK "Saved to $cf"
}

Step 2 "IAM Token"
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${cid}:${csec}"))
try {
    $tok = Invoke-RestMethod -Method Post -Uri $IAM_URL `
        -Headers @{ Authorization = "Basic $b64" } `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "grant_type=client_credentials"
} catch { Fail "Token failed: $_" }
$TOKEN = $tok.access_token
if (-not $TOKEN) { Fail "Empty token. Check credentials." }
$H = @{ Authorization = "Bearer $TOKEN" }
OK "Token OK"

Step 3 "Container Registry"
try { $repo = Invoke-RestMethod -Uri "$CR_URL/repository" -Headers $H }
catch { Fail "CR repo failed: $_" }
$regUrl  = $repo.registryUrl
$repName = $repo.name
if (-not $regUrl)  { Fail "No registryUrl. Response: $($repo | ConvertTo-Json)" }
if (-not $repName) { Fail "No name field.   Response: $($repo | ConvertTo-Json)" }
OK "registryUrl = $regUrl"
OK "repoName    = $repName"

try { $cred = Invoke-RestMethod -Uri "$CR_URL/registry-credential" -Headers $H }
catch { Fail "CR cred failed: $_" }
$crUser = $cred.username; $crSec = $cred.secret
if (-not $crUser -or -not $crSec) { Fail "CR credentials missing." }
OK "CR user: $crUser"

Step 4 "Docker login"
$crSec | docker login $regUrl --username $crUser --password-stdin
if ($LASTEXITCODE -ne 0) { Fail "docker login failed." }
OK "Docker login OK"

Step 5 "Build image"
$tag   = "v$(Get-Date -Format 'yyyyMMddHHmmss')"
$img   = "$regUrl/$repName/$IMAGE_NAME`:$tag"
Info "Image: $img"
docker build --platform linux/amd64 -t $img .
if ($LASTEXITCODE -ne 0) { Fail "docker build failed." }
OK "Build OK"

Step 6 "Push image"
docker push $img
if ($LASTEXITCODE -ne 0) { Fail "docker push failed." }
OK "Push OK"

Step 7 "Deploy runtime"

# Verify flavor exists
try {
    $flavors = Invoke-RestMethod -Uri "https://agentbase.api.vngcloud.vn/runtime/flavors" -Headers $H
    $validFlavor = $flavors | Where-Object { $_.id -eq $FLAVOR } | Select-Object -First 1
    if (-not $validFlavor) {
        Info "Flavor '$FLAVOR' not found. Available flavors:"
        $flavors | ForEach-Object { Info "  $($_.id) - $($_.name)" }
        $FLAVOR = ($flavors | Select-Object -First 1).id
        Info "Using first available: $FLAVOR"
    } else {
        Info "Flavor OK: $FLAVOR"
    }
} catch { Info "Could not verify flavors, proceeding with $FLAVOR" }

$skip = "GREENNODE_CLIENT_ID","GREENNODE_CLIENT_SECRET","GREENNODE_AGENT_IDENTITY","GREENNODE_ENDPOINT_URL"
$ev = @{}
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^\s*([^#=][^=]*)=(.*)$") {
            $k = $Matches[1].Trim(); $v = $Matches[2].Trim()
            if ($k -notin $skip) { $ev[$k] = $v }
        }
    }
    Info "Loaded $($ev.Count) env vars"
}

$body = @{
    name = $RUNTIME_NAME
    description = "TAX AI bot"
    imageUrl = $img
    imageAuth = @{ enabled = $true; username = $crUser; password = $crSec }
    command = @(); args = @()
    environmentVariables = $ev
    flavorId = $FLAVOR
    autoscaling = @{ minReplicas = 1; maxReplicas = 2; cpuUtilization = 70; memoryUtilization = 80 }
} | ConvertTo-Json -Depth 10

$rid = $null
try {
    $lst = Invoke-RestMethod -Uri "${RT_URL}?page=1&size=100" -Headers $H
    $ex  = $lst.listData | Where-Object { $_.name -eq $RUNTIME_NAME } | Select-Object -First 1
    if ($ex) { $rid = $ex.id }
} catch {}

if ($rid) {
    Info "Updating existing runtime $rid..."
    $ub = @{
        description = "TAX AI bot"
        imageUrl    = $img
        imageAuth   = @{ enabled = $true; username = $crUser; password = $crSec }
        command     = @()
        args        = @()
        environmentVariables = $ev
        flavorId    = $FLAVOR
        autoscaling = @{ minReplicas = 1; maxReplicas = 2; cpuUtilization = 70; memoryUtilization = 80 }
    } | ConvertTo-Json -Depth 10
    try { Invoke-RestMethod -Method Patch -Uri "$RT_URL/$rid" -Headers $H -ContentType "application/json" -Body $ub | Out-Null }
    catch { Fail "Update failed: $_" }
    OK "Updated"
} else {
    Info "Creating runtime..."
    try { $cr2 = Invoke-RestMethod -Method Post -Uri $RT_URL -Headers $H -ContentType "application/json" -Body $body }
    catch {
        $errBody = ""
        try { $errBody = $_.ErrorDetails.Message } catch {}
        if (-not $errBody) { try { $errBody = $_.Exception.Response | ConvertTo-Json } catch {} }
        Fail "Create failed: $_ | API response: $errBody"
    }
    $rid = $cr2.id
    if (-not $rid) { Fail "No runtime ID returned." }
    OK "Created: $rid"
}

Step 8 "Waiting for ACTIVE"
$max = 300; $el = 0; $st = ""
while ($el -lt $max) {
    Start-Sleep 10; $el += 10
    try { $r = Invoke-RestMethod -Uri "$RT_URL/$rid" -Headers $H; $st = $r.status }
    catch { $st = "UNKNOWN" }
    Write-Host "  [$el s] $st" -ForegroundColor Yellow
    if ($st -eq "ACTIVE") { break }
    if ($st -in @("ERROR","FAILED","ERROR_DELETING")) { Fail "Runtime error: $st" }
}
if ($st -ne "ACTIVE") { Fail "Timeout. Last status: $st" }
OK "ACTIVE"

$epUrl = ""
try {
    $eps = Invoke-RestMethod -Uri "$RT_URL/$rid/endpoints" -Headers $H
    $ep  = $eps.listData | Where-Object { $_.type -eq "DEFAULT" } | Select-Object -First 1
    if (-not $ep) { $ep = $eps.listData | Select-Object -First 1 }
    $epUrl = $ep.url
} catch {}

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  TAX AI deployed!" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  Runtime  : $rid"
Write-Host "  Image    : $img"
Write-Host "  Endpoint : $epUrl"
Write-Host ""
$tgTok = $ev["TELEGRAM_BOT_TOKEN"]
if ($tgTok) {
    Write-Host "  Set Telegram webhook:" -ForegroundColor Yellow
    Write-Host "  Invoke-RestMethod 'https://api.telegram.org/bot$tgTok/setWebhook?url=$epUrl/telegram/webhook'"
} else {
    Write-Host "  Set Telegram webhook:" -ForegroundColor Yellow
    Write-Host "  Invoke-RestMethod 'https://api.telegram.org/bot<TOKEN>/setWebhook?url=$epUrl/telegram/webhook'"
}
Write-Host "  Zalo webhook: $epUrl/zalo/webhook" -ForegroundColor Yellow

@{ runtime_id = $rid; image = $img; endpoint = $epUrl; deployed_at = (Get-Date -Format "o") } |
    ConvertTo-Json | Set-Content ".agentbase-state.json" -Encoding ASCII
OK "Done. State saved to .agentbase-state.json"
