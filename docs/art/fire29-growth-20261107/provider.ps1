param([ValidateSet('Submit','Poll','Balance')][string]$Action='Submit',[ValidatePattern('^(growth-keypose|growth-motion)0[1-3]$')][string]$Variant='growth-keypose01')
$ErrorActionPreference='Stop'
$pxExternal='C:/Users/Aston/.codex/generated_images/fire29-growth-20261107'
$pxPackage='D:/Games/into-de-dung/docs/art/fire29-growth-20261107'
$pxDir=Join-Path $pxExternal ('pixellab/'+$Variant)
$pxSecure=ConvertTo-SecureString ([IO.File]::ReadAllText('C:/Users/Aston/.codex/secrets/pixellab.dpapi').Trim())
$pxPtr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($pxSecure)
try {
 $pxHeaders=@{Authorization=('Bearer '+[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pxPtr))}
 if($Action -eq 'Balance'){
  $pxPath=Join-Path $pxExternal ('balance-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.json')
  Invoke-WebRequest -Uri 'https://api.pixellab.ai/v2/balance' -Headers $pxHeaders -Method Get -TimeoutSec 20 -MaximumRedirection 0 -OutFile $pxPath | Out-Null
  $pxResult=Get-Content -LiteralPath $pxPath -Raw | ConvertFrom-Json
  $pxResult | ConvertTo-Json -Depth 6 -Compress
  exit 0
 }
 if($Action -eq 'Submit'){
  $pxBarrier=Join-Path $pxDir 'submit-started.json'
  if(Test-Path -LiteralPath $pxBarrier){throw 'Already attempted; GET recovery only'}
  $pxMeta=Get-Content -LiteralPath (Join-Path $pxPackage ('requests/'+$Variant+'/metadata.json')) -Raw | ConvertFrom-Json
  $pxRequestPath=Join-Path $pxDir 'request.json'
  if((Get-FileHash -LiteralPath $pxRequestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pxMeta.request_sha256){throw 'Request hash mismatch'}
  $pxBytes=[IO.File]::ReadAllBytes($pxRequestPath)
  $pxRequest=[Text.Encoding]::UTF8.GetString($pxBytes) | ConvertFrom-Json
  if($pxMeta.endpoint -notin @('inpaint-v3','animate-pixminimax')){throw 'Endpoint not allowed'}
  $pxSchemaPath=Join-Path $pxExternal ('openapi-before-'+$Variant+'.json')
  Invoke-WebRequest -Uri 'https://api.pixellab.ai/v2/openapi.json' -Method Get -TimeoutSec 35 -MaximumRedirection 0 -OutFile $pxSchemaPath | Out-Null
  $pxSchema=Get-Content -LiteralPath $pxSchemaPath -Raw | ConvertFrom-Json
  $pxRef=($pxSchema.paths.PSObject.Properties['/'+$pxMeta.endpoint].Value.post.requestBody.content.'application/json'.schema.'$ref' -split '/')[-1]
  $pxContract=$pxSchema.components.schemas.$pxRef
  if($pxContract.additionalProperties -ne $false){throw 'Schema contract changed'}
  foreach($pxKey in $pxRequest.PSObject.Properties.Name){if(-not $pxContract.properties.PSObject.Properties[$pxKey]){throw 'Unexpected property'}}
  foreach($pxKey in $pxContract.required){if(-not $pxRequest.PSObject.Properties[$pxKey]){throw 'Required property absent'}}
  $pxStream=[IO.File]::Open($pxBarrier,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$pxStamp=[Text.Encoding]::UTF8.GetBytes([DateTime]::UtcNow.ToString('o'));$pxStream.Write($pxStamp,0,$pxStamp.Length)}finally{$pxStream.Dispose()}
  $pxPath=Join-Path $pxDir 'response-raw.json'
  Invoke-WebRequest -Uri ('https://api.pixellab.ai/v2/'+$pxMeta.endpoint) -Headers $pxHeaders -Method Post -ContentType 'application/json' -Body $pxBytes -TimeoutSec 300 -MaximumRedirection 0 -OutFile $pxPath | Out-Null
  $pxResult=Get-Content -LiteralPath $pxPath -Raw | ConvertFrom-Json
  if($pxResult.background_job_id){Copy-Item -LiteralPath $pxPath -Destination (Join-Path $pxDir 'admission.json')}
 }else{
  $pxAdmission=Get-Content -LiteralPath (Join-Path $pxDir 'admission.json') -Raw | ConvertFrom-Json
  if(-not $pxAdmission.background_job_id){throw 'No job ID'}
  $pxPath=Join-Path $pxDir ('poll-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.json')
  Invoke-WebRequest -Uri ('https://api.pixellab.ai/v2/background-jobs/'+$pxAdmission.background_job_id) -Headers $pxHeaders -Method Get -TimeoutSec 20 -MaximumRedirection 0 -OutFile $pxPath | Out-Null
  $pxResult=Get-Content -LiteralPath $pxPath -Raw | ConvertFrom-Json
  Copy-Item -LiteralPath $pxPath -Destination (Join-Path $pxDir 'job-latest.json')
 }
 @{variant=$Variant;status=$pxResult.status;job_id=$pxResult.background_job_id;usage=$pxResult.usage;last_fields=@($pxResult.last_response.PSObject.Properties.Name);fields=@($pxResult.PSObject.Properties.Name)}|ConvertTo-Json -Depth 6 -Compress
}catch{
 $pxStatus=$null;if($_.Exception.Response){$pxStatus=[int]$_.Exception.Response.StatusCode}
 if($_.ErrorDetails.Message){[IO.File]::WriteAllText((Join-Path $pxDir 'rejected-response.json'),$_.ErrorDetails.Message,[Text.UTF8Encoding]::new($false))}
 @{failed=$true;http_status=$pxStatus;exception=$_.Exception.GetType().Name;variant=$Variant;barrier=(Test-Path -LiteralPath (Join-Path $pxDir 'submit-started.json'))}|ConvertTo-Json -Compress
 exit 1
}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pxPtr);if($pxHeaders){$pxHeaders.Clear()}}
