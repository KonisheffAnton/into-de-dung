param([Parameter(Mandatory=$true)][string[]]$Keys,[string[]]$ExistingKeys=@())
# Одна очередь и один POST на отдельный исходный мазок. Не повторяем неопределённые POST.
$ErrorActionPreference='Stop'
$pxExternal='C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106'
$pxBridge=Join-Path $pxExternal 'invoke-pixellab.ps1'
$pxTodo=[Collections.Generic.Queue[string]]::new()
$pxActive=[Collections.Generic.List[string]]::new()
$pxDone=[Collections.Generic.List[string]]::new()
$pxUncertain=[Collections.Generic.List[string]]::new()
$pxLockPath=Join-Path $pxExternal 'field-queue.lock.json'
$pxQueueToken=[guid]::NewGuid().ToString()
foreach($pxKey in $Keys){
 if($pxKey -notmatch '^fire(24|29)-(field[0-9]{2}(r1)?|drift01|alpha01|short0[12]|palette01)$'){throw 'Invalid field key'}
 if($pxTodo.Contains($pxKey)){throw 'Duplicate queue key'}
 $pxJob=Join-Path $pxExternal ('pixellab/'+$pxKey)
 if(Test-Path -LiteralPath (Join-Path $pxJob 'submit-started.json')){throw 'Key already attempted; inspect its admission separately'}
 if(-not(Test-Path -LiteralPath (Join-Path $pxJob 'request.json'))){throw 'Missing prepared request'}
 $pxTodo.Enqueue($pxKey)
}
foreach($pxKey in $ExistingKeys){
 if($pxKey -notmatch '^fire(24|29)-(field[0-9]{2}(r1)?|drift01|alpha01|short0[12]|palette01)$'){throw 'Invalid existing key'}
 if($pxTodo.Contains($pxKey) -or $pxActive.Contains($pxKey)){throw 'Duplicate existing key'}
 if(-not(Test-Path -LiteralPath (Join-Path $pxExternal ('pixellab/'+$pxKey+'/admission.json')))){throw 'Existing job has no admission'}
 $pxActive.Add($pxKey)
}
if($pxActive.Count -gt 3){throw 'Too many existing jobs'}
function Write-QueueSnapshot {
 $pxSnapshot=@{utc=[DateTime]::UtcNow.ToString('o');pending=@($pxTodo.ToArray());active=@($pxActive.ToArray());done=@($pxDone.ToArray());uncertain=@($pxUncertain.ToArray());max_active=3}
 [IO.File]::WriteAllText((Join-Path $pxExternal 'field-queue-latest.json'),($pxSnapshot|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
$pxLock=[IO.File]::Open($pxLockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try {
 $pxLockBytes=[Text.Encoding]::UTF8.GetBytes((@{token=$pxQueueToken;pid=$PID;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress))
 $pxLock.Write($pxLockBytes,0,$pxLockBytes.Length);$pxLock.Flush()
 # Не запускаем новую очередь поверх ранее принятых или неопределённых запросов.
 foreach($pxExisting in Get-ChildItem -LiteralPath (Join-Path $pxExternal 'pixellab') -Directory){
  if(-not(Test-Path -LiteralPath (Join-Path $pxExisting.FullName 'submit-started.json'))){continue}
  $pxExistingAdmission=Join-Path $pxExisting.FullName 'admission.json'
  $pxExistingState=Join-Path $pxExisting.FullName 'job-latest.json'
  if(-not(Test-Path -LiteralPath $pxExistingAdmission) -or -not(Test-Path -LiteralPath $pxExistingState)){throw ('Unresolved prior POST: '+$pxExisting.Name)}
  $pxOldAdmission=Get-Content -LiteralPath $pxExistingAdmission -Raw|ConvertFrom-Json
  $pxOldState=Get-Content -LiteralPath $pxExistingState -Raw|ConvertFrom-Json
  if($pxOldState.id -ne $pxOldAdmission.background_job_id){throw 'Prior job identity mismatch'}
  # Явно переданные незавершённые jobs занимают слоты и читаются только через GET.
  if($pxExisting.Name -in $ExistingKeys){continue}
  if($pxOldState.status -eq 'failed' -and $pxOldState.last_response.error -like 'GPU worker dropped this*'){throw ('Prior soft failure may still finish; poll it first: '+$pxExisting.Name)}
  if($pxOldState.status -notin @('completed','failed','cancelled')){
   $pxResolutionPath=Join-Path $pxExisting.FullName 'resolution.json'
   if(-not(Test-Path -LiteralPath $pxResolutionPath)){throw ('Prior job is not terminal: '+$pxExisting.Name)}
   $pxResolution=Get-Content -LiteralPath $pxResolutionPath -Raw|ConvertFrom-Json
   if($pxResolution.kind -ne 'unavailable_after_404' -or $pxResolution.http_status -ne 404 -or $pxResolution.job_id -ne $pxOldAdmission.background_job_id){throw 'Unresolved prior job'}
  }
 }
 while($pxTodo.Count -gt 0 -or $pxActive.Count -gt 0){
 while($pxTodo.Count -gt 0 -and $pxActive.Count -lt 3){
  $pxKey=$pxTodo.Peek()
  Write-QueueSnapshot
  # Bridge проверяет SHA, свежую схему и CreateNew barrier до отправки.
  $pxOutput=& $pxBridge -Action Submit -Variant $pxKey -QueueToken $pxQueueToken
  Write-Output $pxOutput
  $pxSubmitted=$pxOutput|ConvertFrom-Json
  if($pxSubmitted.failed -or -not $pxSubmitted.job_id){$pxUncertain.Add($pxKey);Write-QueueSnapshot;throw ('Submission stopped; inspect barrier for '+$pxKey)}
  $pxAdmission=Get-Content -LiteralPath (Join-Path $pxExternal ('pixellab/'+$pxKey+'/admission.json')) -Raw|ConvertFrom-Json
  if(-not $pxAdmission.background_job_id){throw 'Missing confirmed admission'}
  $pxTodo.Dequeue()|Out-Null;$pxActive.Add($pxKey);Write-QueueSnapshot
 }
 Start-Sleep -Seconds 5
 foreach($pxKey in $pxActive.ToArray()){
  $pxOutput=& $pxBridge -Action Poll -Variant $pxKey
  $pxState=$pxOutput|ConvertFrom-Json
  if($pxState.failed){Write-QueueSnapshot;throw ('Poll stopped; resume GET only for '+$pxKey)}
  if($pxState.status -eq 'completed'){
   Write-Output $pxOutput
   & python (Join-Path $PSScriptRoot 'field_pipeline.py') extract $pxKey
   if($LASTEXITCODE -ne 0){throw ('Extraction failed; raw response preserved for '+$pxKey)}
   $pxActive.Remove($pxKey)|Out-Null;$pxDone.Add($pxKey);Write-QueueSnapshot
  }elseif($pxState.status -eq 'failed'){
   $pxFailedBody=Get-Content -LiteralPath (Join-Path $pxExternal ('pixellab/'+$pxKey+'/job-latest.json')) -Raw|ConvertFrom-Json
   # Этот конкретный ответ сам предупреждает, что тот же job ещё может завершиться.
   if($pxFailedBody.last_response.error -like 'GPU worker dropped this*'){continue}
   Write-Output $pxOutput;Write-QueueSnapshot;throw 'Provider failure; preserve admission and inspect before retry'
  }elseif($pxState.status -notin @('processing','pending','queued')){
   Write-Output $pxOutput;Write-QueueSnapshot;throw 'Unexpected terminal provider state; stop admission'
  }
 }
 }
 Write-QueueSnapshot
 Write-Output ('Completed field clips: '+$pxDone.Count)
}finally{
 $pxLock.Dispose()
 $pxOwnedLock=Get-Content -LiteralPath $pxLockPath -Raw|ConvertFrom-Json
 if($pxOwnedLock.token -ne $pxQueueToken){throw 'Queue lock ownership changed'}
 Remove-Item -LiteralPath $pxLockPath
}
