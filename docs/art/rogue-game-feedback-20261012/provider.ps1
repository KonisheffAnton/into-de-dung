param(
    [ValidateSet('balance','submit','poll')][string]$Mode,
    [ValidatePattern('^[a-z0-9-]+$')][string]$Name = 'account',
    [ValidateSet('edit-images-v2','edit-animation-v2','animate-with-text-v3','animate-pixminimax')][string]$Endpoint = 'edit-images-v2'
)
$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot $Name
[IO.Directory]::CreateDirectory($dir) | Out-Null
$secret = (Get-Content -Raw -LiteralPath 'C:/Users/Aston/.codex/secrets/pixellab.dpapi').Trim() | ConvertTo-SecureString
$headers = @{ Authorization = 'Bearer ' + ([Net.NetworkCredential]::new('', $secret).Password) }
$baseUri = 'https://api.pixellab.ai/v2'
try {
    if ($Mode -eq 'balance') {
        $result = Invoke-RestMethod -Uri "$baseUri/balance" -Headers $headers -TimeoutSec 60
        $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'balance-before.json') -Encoding utf8
        Write-Output 'Balance saved without authentication data.'
    } elseif ($Mode -eq 'submit') {
        $attempt = Join-Path $dir 'submission-attempt.json'
        if (Test-Path -LiteralPath $attempt) { throw 'Submission already attempted; recover its job instead of posting twice.' }
        $request = Join-Path $dir 'request.json'
        $idempotency = [guid]::NewGuid().ToString()
        @{endpoint=$Endpoint; started_utc=[DateTime]::UtcNow.ToString('o'); idempotency_key=$idempotency; request_sha256=(Get-FileHash -LiteralPath $request -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content -LiteralPath $attempt -Encoding utf8
        $headers['Idempotency-Key'] = $idempotency
        $result = Invoke-RestMethod -Uri "$baseUri/$Endpoint" -Method Post -Headers $headers -ContentType 'application/json' -Body ([IO.File]::ReadAllBytes($request)) -TimeoutSec 60
        $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $dir 'response.json') -Encoding utf8
        @{name=$Name; job=$result.background_job_id; status=$result.status} | ConvertTo-Json -Compress
    } else {
        $submission = Get-Content -Raw -LiteralPath (Join-Path $dir 'response.json') | ConvertFrom-Json
        $jobId = $submission.background_job_id
        if (-not $jobId) { throw 'No recoverable background_job_id.' }
        $result = Invoke-RestMethod -Uri "$baseUri/background-jobs/$jobId" -Headers $headers -TimeoutSec 60
        $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $dir 'job-status.json') -Encoding utf8
        if ($result.status -eq 'completed') {
            $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $dir 'result.json') -Encoding utf8
        }
        @{name=$Name; job=$jobId; status=$result.status; progress=$result.last_response.progress; usage=$result.last_response.billing_usage} | ConvertTo-Json -Depth 5 -Compress
    }
} finally {
    $headers.Clear()
    $secret.Dispose()
}
