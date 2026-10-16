[CmdletBinding()]
param([switch]$IsolatedLab,[Parameter(Mandatory)][string]$ModulePath,[int]$Attempt=1)
$ErrorActionPreference='Stop'
if(-not $IsolatedLab -or $env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path 'C:\VSO-Lab\ISOLATED-LAB.json') -or (Get-CimInstance Win32_ComputerSystem).Model -notmatch 'VMware'){throw 'Dedicated disposable VM only.'}
Import-Module $ModulePath -Force
$root='C:\VSO-Lab\Faults-'+$PSVersionTable.PSEdition+'-'+$Attempt
if(Test-Path $root){throw 'Fresh fault campaign directory required.'}
[void][IO.Directory]::CreateDirectory($root)
$target=Join-Path $root 'VSO';$results=New-Object 'Collections.Generic.List[object]'
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Case([string]$Name,[scriptblock]$Body){
 $state='PASS';try{$detail=& $Body}catch{$state='FAIL';$detail=$_.Exception.Message}
 $results.Add([pscustomobject]@{Name=$Name;Result=$state;Evidence=$detail})
 @{Edition=$PSVersionTable.PSEdition;PowerShell=$PSVersionTable.PSVersion.ToString();Attempt=$Attempt;Cases=$results.ToArray()}|ConvertTo-Json -Depth 8|Set-Content ('C:\VSO-Lab\Evidence\faults-'+$PSVersionTable.PSEdition+'-'+$Attempt+'.json') -Encoding UTF8
}
function Integrity([string]$Version){
 $r=Get-Content (Join-Path $target '.vso-manager.json') -Raw|ConvertFrom-Json
 Check ($r.Version -ceq $Version) 'Wrong receipt version.'
 foreach($f in $r.Files){Check (((Get-FileHash (Join-Path $target $f.Path)).Hash.ToLowerInvariant()) -ceq $f.Sha256) 'Owned hash differs.'}
 Check ((Get-VSOInstallation -Path $target -Quiet).State -ceq 'Ready') 'Registration not Ready.'
 Check ([IO.File]::ReadAllText((Join-Path $target 'foreign.txt')) -ceq 'KEEP') 'Foreign sentinel changed.'
}
Case 'Real official installation for fault campaign' {
 $null=Install-VSO -Path $target -Version 1.2.1 -Quiet -PassThru
 [IO.File]::WriteAllText((Join-Path $target 'foreign.txt'),'KEEP');Integrity '1.2.1'
}
Case 'Real official update rolls back after injected registration failure' {
 # Instrument only the registration boundary. Payload and filesystem writes remain real.
 & (Get-Module VSO) {
  $script:LabOriginalRegister=${function:Register-VSOReceipt};$script:LabFailOnce=$true
  function script:Register-VSOReceipt {param($Receipt,$Context)
   if($script:LabFailOnce){$script:LabFailOnce=$false;throw 'LAB injected registration fault'}
   & $script:LabOriginalRegister $Receipt $Context
  }
 }
 $rejected=$false
 try{Update-VSO -Path $target -Version 1.2.2 -Quiet}catch{$rejected=$true}finally{& (Get-Module VSO) {Set-Item Function:Register-VSOReceipt $script:LabOriginalRegister}}
 Check $rejected 'Fault did not interrupt update.';Integrity '1.2.1'
 $j=@(Get-ChildItem $root -Filter '.vso-txn-*' -Directory|ForEach-Object {Get-Content (Join-Path $_.FullName 'transaction.json') -Raw|ConvertFrom-Json})
 Check (@($j|Where-Object State -eq 'RolledBack').Count -ge 1) 'Rollback journal missing.'
 @{OriginalVersionRestored='1.2.1';ForeignSentinelPreserved=$true}
}
Case 'Hard-killed update restores interrupted rename and retries through public Update' {
 $pause=Join-Path $root 'paused.txt';$childScript=Join-Path $root 'child.ps1'
 $childCode=@'
param($ModulePath,$Target,$Pause)
$ErrorActionPreference='Stop'
Import-Module $ModulePath -Force
$global:LabPause=$Pause
& (Get-Module VSO) {
 # The module loads reviewed strings, so file debugger breakpoints do not bind.
 # Insert exactly one deterministic pause into this child's in-memory function.
 $body=${function:Invoke-VSOInstallTransaction}.ToString()
 $needle='[IO.Directory]::Move($stage,$target); $promoted=$true'
 if(($body.Split([string[]]@($needle),[StringSplitOptions]::None)).Count -ne 2){throw 'Unique real promotion statement missing.'}
 $pauseCode='[IO.File]::WriteAllText($global:LabPause,''Paused after old rename'');Start-Sleep -Seconds 3600;'
 Set-Item Function:Invoke-VSOInstallTransaction ([scriptblock]::Create($body.Replace($needle,$pauseCode+$needle)))
}
Update-VSO -Path $Target -Version 1.2.2 -Quiet -PassThru
'@
 [IO.File]::WriteAllText($childScript,$childCode,[Text.UTF8Encoding]::new($true))
 $binary=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Desktop'){'powershell.exe'}else{'pwsh.exe'})
 $args='-NoProfile -ExecutionPolicy Bypass -File "'+$childScript+'" -ModulePath "'+$ModulePath+'" -Target "'+$target+'" -Pause "'+$pause+'"'
 $child=Start-Process $binary -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'child-stdout.txt') -RedirectStandardError (Join-Path $root 'child-stderr.txt')
 try{
  $limit=[DateTime]::UtcNow.AddSeconds(120)
  while(-not(Test-Path $pause) -and -not $child.HasExited -and [DateTime]::UtcNow -lt $limit){Start-Sleep -Milliseconds 100}
  Check (Test-Path $pause) ('Debugger pause was not reached. ChildExited='+$child.HasExited+'; inspect '+(Join-Path $root 'child-stderr.txt'))
  Check (-not(Test-Path $target)) 'Old directory had not been renamed at interruption.'
  $child.Kill();Check ($child.WaitForExit(10000)) 'Child did not exit.'
  $r=Update-VSO -Path $target -Version 1.2.2 -Quiet -PassThru
  Check $r.Changed 'Retry did not finish.';Integrity '1.2.2'
  @{KilledOnlyCreatedChild=$child.Id;RecoveredAndUpdated=$true;Version='1.2.2'}
 }finally{if(-not $child.HasExited){$child.Kill();$null=$child.WaitForExit(10000)};$child.Dispose()}
}
Case 'Backup removal needs explicit intent and WhatIf preserves all files' {
 $rejected=$false;try{Reset-VSO -Path $target -Full -RemoveBackups -Force -Quiet}catch{$rejected=$true};Check $rejected 'Backup intent was not required.'
 $before=@(Get-ChildItem $root -File -Recurse|Get-FileHash|ForEach-Object {$_.Path+$_.Hash}) -join '|'
 $null=Reset-VSO -Path $target -Full -RemoveBackups -AcknowledgeBackupLoss -Quiet -WhatIf -PassThru
 $after=@(Get-ChildItem $root -File -Recurse|Get-FileHash|ForEach-Object {$_.Path+$_.Hash}) -join '|';Check ($before -ceq $after) 'WhatIf altered backup files.'
}
Case 'Full acknowledged removal deletes attributable backups and preserves foreign copies' {
 $receipt=Get-Content (Join-Path $target '.vso-manager.json') -Raw|ConvertFrom-Json
 $previous=@($receipt.Backups|ForEach-Object {Join-Path (Join-Path $root $_) 'previous'})
 $r=Reset-VSO -Path $target -Full -RemoveBackups -AcknowledgeBackupLoss -Force -Quiet -PassThru
 Check (-not(Test-Path (Join-Path $target '.vso-manager.json'))) 'Receipt remains.'
 Check ([IO.File]::ReadAllText((Join-Path $target 'foreign.txt')) -ceq 'KEEP') 'Main sentinel removed.'
 foreach($p in $previous){Check (-not(Test-Path (Join-Path $p 'VSO7\VSO7.ps1'))) 'Owned previous file remains.';Check ([IO.File]::ReadAllText((Join-Path $p 'foreign.txt')) -ceq 'KEEP') 'Backup foreign sentinel removed.'}
 @{Removed=$r.Removed.Count;PreviousCopies=$previous.Count;ForeignCopiesPreserved=($previous.Count+1)}
}
if(@($results|Where-Object Result -eq 'FAIL').Count){throw 'Inspect real fault campaign evidence.'}
