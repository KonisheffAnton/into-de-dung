param([Parameter(Mandatory=$true)][ValidateSet('Balance','Submit','Poll')][string]$Action,[ValidatePattern('^(idle|death|ability)-[1-5]$')][string]$Variant='idle-1',[string]$BalanceFile='balance-before.json')
$ErrorActionPreference='Stop'
function Save-PxJson([string]$Path,[object]$Value,[int]$Depth) {
 $pxTemp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($pxTemp,($Value|ConvertTo-Json -Depth $Depth),[Text.UTF8Encoding]::new($false))
 [IO.File]::Move($pxTemp,$Path,$true)
}
$pxDir=Join-Path $PSScriptRoot ('pixellab/'+$Variant)
$pxSecure=ConvertTo-SecureString ([IO.File]::ReadAllText('C:/Users/Aston/.codex/secrets/pixellab.dpapi').Trim())
$pxPtr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($pxSecure)
try {
 $pxHeaders=@{Authorization=('Bearer '+[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pxPtr))}
 if($Action -eq 'Balance'){
  $pxResult=Invoke-RestMethod -Uri 'https://api.pixellab.ai/v2/balance' -Headers $pxHeaders -Method Get -TimeoutSec 35 -MaximumRedirection 0
  Save-PxJson (Join-Path $PSScriptRoot $BalanceFile) $pxResult 25
  $pxResult|ConvertTo-Json -Depth 8 -Compress
 } else {
  if($Action -eq 'Submit'){
   # CreateNew резервирует единственный POST атомарно даже при двух процессах.
   $pxMarker=[IO.File]::Open((Join-Path $pxDir 'submit-started.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
   try {
    $pxMarkerBytes=[Text.UTF8Encoding]::new($false).GetBytes(('{"attemptedUtc":"'+[DateTime]::UtcNow.ToString('o')+'"}'))
    $pxMarker.Write($pxMarkerBytes,0,$pxMarkerBytes.Length)
    $pxMarker.Flush($true)
   } finally { $pxMarker.Dispose() }
   $pxBytes=[IO.File]::ReadAllBytes((Join-Path $pxDir 'request.json'))
   $pxResult=Invoke-RestMethod -Uri 'https://api.pixellab.ai/v2/animate-pixminimax' -Headers $pxHeaders -Method Post -ContentType 'application/json' -Body $pxBytes -TimeoutSec 55 -MaximumRedirection 0
   $pxSave='admission.json'
  } else {
   $pxAdmission=Get-Content -LiteralPath (Join-Path $pxDir 'admission.json') -Raw|ConvertFrom-Json
   if(-not $pxAdmission.background_job_id){throw 'Missing job id'}
   $pxResult=Invoke-RestMethod -Uri ('https://api.pixellab.ai/v2/background-jobs/'+$pxAdmission.background_job_id) -Headers $pxHeaders -Method Get -TimeoutSec 35 -MaximumRedirection 0
   $pxSave='job-latest.json'
  }
  Save-PxJson (Join-Path $pxDir $pxSave) $pxResult 60
  @{variant=$Variant;status=$pxResult.status;job_id=$pxResult.background_job_id;id=$pxResult.id;usage=$pxResult.usage;billing_usage=$pxResult.last_response.billing_usage;last_usage=$pxResult.last_response.usage;error=$pxResult.error} | ConvertTo-Json -Depth 8 -Compress
 }
} catch {
 $pxStatus=$null;if($_.Exception.Response){$pxStatus=[int]$_.Exception.Response.StatusCode}
 @{failed=$true;http_status=$pxStatus;exception=$_.Exception.GetType().Name;action=$Action;variant=$Variant}|ConvertTo-Json -Compress
 if($_.ErrorDetails.Message){[IO.File]::WriteAllText((Join-Path $pxDir 'rejected-response.json'),$_.ErrorDetails.Message);try{$pxError=$_.ErrorDetails.Message|ConvertFrom-Json;$pxError.detail|Select-Object loc,msg,type|ConvertTo-Json -Depth 5 -Compress}catch{}}
 exit 1
} finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pxPtr);if($pxHeaders){$pxHeaders.Clear()}}
