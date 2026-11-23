param([ValidateSet('generate','generate-fragments','poll','poll-fragments','balance')][string]$Action='poll')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$secret=ConvertTo-SecureString ((Get-Content -LiteralPath 'C:/Users/Aston/.codex/secrets/pixellab.dpapi' -Raw).Trim())
$secretPointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try {
    $env:TASK_PIXELLAB_TOKEN=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    & python (Join-Path $taskRoot 'run.py') $Action
    if ($LASTEXITCODE -ne 0) { throw 'Inspect PixelLab receipt before retrying.' }
} finally {
    Remove-Item Env:TASK_PIXELLAB_TOKEN -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    $secret.Dispose()
}
