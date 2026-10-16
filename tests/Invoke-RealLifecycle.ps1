[CmdletBinding()]
param([switch]$IsolatedLab,[Parameter(Mandatory)][string]$ModulePath,[ValidateSet('src','dist','package')][string]$Label='src',[switch]$SkipLaunch,[int]$Attempt=1)
$ErrorActionPreference='Stop'
$lab='C:\VSO-Lab'
if(-not $IsolatedLab -or $env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path -LiteralPath "$lab\ISOLATED-LAB.json") -or (Get-CimInstance Win32_ComputerSystem).Model -notmatch 'VMware') {throw 'Only the dedicated fresh disposable campaign VM is authorized.'}
Import-Module $ModulePath -Force -ErrorAction Stop
$edition=$PSVersionTable.PSEdition
$campaign=Join-Path $lab ('Real-'+$edition+'-'+$Label+'-'+$Attempt)
[void][IO.Directory]::CreateDirectory($campaign)
$target=Join-Path $campaign 'VSO espacio á'
$allTarget=Join-Path $env:ProgramFiles ('VSO Lab '+$edition+' '+$Label)
if(Test-Path -LiteralPath $target){throw 'A new campaign target is required; preserve earlier evidence.'}
$script:results=New-Object 'Collections.Generic.List[object]'
$script:installed=$false
$script:started=$false
$script:decoys=@()
$report=Join-Path $lab ('Evidence\real-'+$edition+'-'+$Label+'-'+$Attempt+'.json')
function Assert-Lab([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Save-LabResults {
 $os=Get-CimInstance Win32_OperatingSystem
 @{OS=$os.Caption;Build=$os.BuildNumber;PowerShell=$PSVersionTable.PSVersion.ToString();Edition=$edition;Artifact=$Label;Attempt=$Attempt;InteractiveSessionId=(Get-Process -Id $PID).SessionId;IsAdministrator=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);Cases=@($script:results.ToArray())}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $report -Encoding UTF8
}
function Invoke-LabCase([string]$Name,[scriptblock]$Body,[bool]$Skip=$false) {
 $watch=[Diagnostics.Stopwatch]::StartNew();$detail=$null;$state='PASS'
 if($Skip){$state='SKIP';$detail='Required preceding operation did not complete.'}
 else{try{$detail=& $Body}catch{$state='FAIL';$detail=$_.Exception.Message}}
 $script:results.Add([pscustomobject]@{Name=$Name;Result=$state;Seconds=[math]::Round($watch.Elapsed.TotalSeconds,3);Evidence=$detail})
 Save-LabResults
 Write-Host ($state+' '+$Name)
}
function Assert-LabIntegrity([string]$Path,[string]$Version) {
 $receipt=Get-Content -LiteralPath (Join-Path $Path '.vso-manager.json') -Raw|ConvertFrom-Json
 Assert-Lab ($receipt.Version -ceq $Version) 'Receipt version differs.'
 foreach($file in $receipt.Files){Assert-Lab (((Get-FileHash -LiteralPath (Join-Path $Path $file.Path)).Hash.ToLowerInvariant()) -ceq $file.Sha256) ('File hash differs: '+$file.Path)}
 $found=@(Get-VSOInstallation -Path $Path -Quiet)
 Assert-Lab ($found.Count -eq 1 -and $found[0].Managed -and $found[0].State -ceq 'Ready') 'Registration or installation integrity failed.'
 return @{Version=$receipt.Version;OwnedFiles=$receipt.Files.Count;ArchiveSha256=$receipt.ArchiveSha256;Id=$receipt.Id}
}
[void][IO.Directory]::CreateDirectory((Split-Path $report -Parent))
Invoke-LabCase 'Import and both native/custom help interfaces' {
 Assert-Lab (@(Get-Command -Module VSO).Count -eq 8) 'Eight exports required.'
 foreach($name in @(Get-Command -Module VSO).Name){Assert-Lab ($null -ne (Get-Help $name -Full).Description) ('Help missing: '+$name)}
 Assert-Lab ((Help-VSO -Command Install-VSO -Language es -PassThru).Language -ceq 'es-ES') 'Spanish help missing.'
 Assert-Lab ((Help-VSO -Command Install-VSO -Language en -PassThru).Language -ceq 'en-US') 'English help missing.'
}
Invoke-LabCase 'Install WhatIf creates no target or staging' {
 $before=@(Get-ChildItem -LiteralPath $campaign -Force).Name -join '|'
 Install-VSO -Path $target -Scope CurrentUser -Quiet -WhatIf
 Assert-Lab (-not(Test-Path -LiteralPath $target)) 'WhatIf created target.'
 Assert-Lab ((@(Get-ChildItem -LiteralPath $campaign -Force).Name -join '|') -ceq $before) 'WhatIf changed parent.'
}
Invoke-LabCase 'Official 1.0.0 CurrentUser installation from System32 with Unicode' {
 Push-Location "$env:SystemRoot\System32"
 try{$r=@(Install-VSO -Path $target -Scope CurrentUser -Version 1.0.0 -Quiet -PassThru)}finally{Pop-Location}
 $script:installed=Test-Path -LiteralPath (Join-Path $target '.vso-manager.json')
 Assert-Lab ($r.Count -eq 1 -and $r[0].Changed) 'Install must emit exactly one successful result.'
 Assert-LabIntegrity $target '1.0.0'
}
Invoke-LabCase 'Repeated installation refuses replacement and preserves receipt' {
 $before=(Get-FileHash (Join-Path $target '.vso-manager.json')).Hash;$rejected=$false
 try{Install-VSO -Path $target -Version 1.0.0 -Quiet}catch{$rejected=$true}
 Assert-Lab $rejected 'Repeated installation accepted.'
 Assert-Lab (((Get-FileHash (Join-Path $target '.vso-manager.json')).Hash) -ceq $before) 'Receipt changed.'
} (-not $script:installed)
Invoke-LabCase 'Runtime configuration, backup and foreign sentinels prepared' {
 foreach($relative in @('foreign.txt','VSO7/config/user.json','VSO7/Recuperacion/backup.json','VSO7/logs/session.log')){
  $file=Join-Path $target $relative;[void][IO.Directory]::CreateDirectory((Split-Path $file -Parent));[IO.File]::WriteAllText($file,'VSO LAB SENTINEL '+$relative)
 }
} (-not $script:installed)
foreach($version in @('1.1.0','1.1.1','1.2.0','1.2.1','1.2.2')){
 Invoke-LabCase ('Real official update to '+$version+' preserves configuration and backups') {
  $r=@(Update-VSO -Path $target -Version $version -Quiet -PassThru)
  Assert-Lab ($r.Count -eq 1 -and $r[0].Changed) 'Update must emit exactly one successful result.'
  foreach($relative in @('foreign.txt','VSO7/config/user.json','VSO7/Recuperacion/backup.json','VSO7/logs/session.log')){Assert-Lab ([IO.File]::ReadAllText((Join-Path $target $relative)) -ceq ('VSO LAB SENTINEL '+$relative)) ('Sentinel changed: '+$relative)}
  Assert-Lab (Test-Path -LiteralPath (Join-Path $r[0].BackupPath 'VSO7/VSO7.ps1')) 'Previous official application was not retained.'
  Assert-LabIntegrity $target $version
 } (-not $script:installed)
}
Invoke-LabCase 'Equal official version is unchanged' {
 $before=(Get-FileHash (Join-Path $target '.vso-manager.json')).Hash
 Assert-Lab (-not(Update-VSO -Path $target -Version 1.2.2 -Quiet -PassThru).Changed) 'Equal version was replaced.'
 Assert-Lab (((Get-FileHash (Join-Path $target '.vso-manager.json')).Hash) -ceq $before) 'Receipt changed.'
} (-not $script:installed)
Invoke-LabCase 'Full WhatIf preserves every installation file' {
 $before=@(Get-ChildItem -LiteralPath $target -Recurse -File -Force|Get-FileHash|ForEach-Object {$_.Path+' '+$_.Hash}) -join "`n"
 $plan=Reset-VSO -Path $target -Full -WhatIf -Quiet -PassThru
 Assert-Lab ($plan.Remove.Count -gt 10) 'No exact removal plan.'
 $after=@(Get-ChildItem -LiteralPath $target -Recurse -File -Force|Get-FileHash|ForEach-Object {$_.Path+' '+$_.Hash}) -join "`n"
 Assert-Lab ($before -ceq $after) 'WhatIf altered files.'
 @{PlannedRemove=$plan.Remove.Count;PlannedPreserve=$plan.Preserve.Count}
} (-not $script:installed)
Invoke-LabCase 'Junction attack cannot escape Reset' {
 $outside=Join-Path $campaign 'outside';[void][IO.Directory]::CreateDirectory($outside);[IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'FOREIGN OUTSIDE')
 $link=Join-Path $target 'foreign-junction';New-Item -ItemType Junction -Path $link -Target $outside|Out-Null
 try{$rejected=$false;try{Reset-VSO -Path $target -Full -Force -Quiet}catch{$rejected=$true};Assert-Lab $rejected 'Junction was followed.';Assert-Lab ([IO.File]::ReadAllText((Join-Path $outside 'keep.txt')) -ceq 'FOREIGN OUTSIDE') 'Outside sentinel changed.'}
 finally{[IO.Directory]::Delete($link,$false)}
} (-not $script:installed)
Invoke-LabCase 'Manipulated metadata fails before deletion' {
 $marker=Join-Path $target '.vso-manager.json';$original=[IO.File]::ReadAllBytes($marker)
 try{$r=Get-Content $marker -Raw|ConvertFrom-Json;$r.Files[0].Path='../outside/keep.txt';[IO.File]::WriteAllText($marker,($r|ConvertTo-Json -Depth 10));$rejected=$false;try{Reset-VSO -Path $target -Full -Force -Quiet}catch{$rejected=$true};Assert-Lab $rejected 'Tampered metadata accepted.';Assert-Lab (Test-Path (Join-Path $target 'VSO7/VSO7.ps1')) 'An owned file was removed before rejection.'}
 finally{[IO.File]::WriteAllBytes($marker,$original)}
} (-not $script:installed)
Invoke-LabCase 'Locked owned file fails without deleting other files' {
 $file=Join-Path $target 'VSO7/VSO7.ps1';$handle=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try{$rejected=$false;try{Reset-VSO -Path $target -Full -Force -Quiet}catch{$rejected=$true};Assert-Lab $rejected 'Locked file not rejected.';Assert-Lab (Test-Path (Join-Path $target 'VSO7/START VSO7.bat')) 'Earlier owned file deleted.'}
 finally{$handle.Dispose()}
} (-not $script:installed)
Invoke-LabCase 'Official launch, forced stop and real foreign process survival' {
 $ps=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe';$cmd=Join-Path $env:SystemRoot 'System32/cmd.exe'
 $script:decoys=@(Start-Process $ps -ArgumentList '-NoProfile -NoExit -Command "Start-Sleep -Seconds 3600"' -PassThru;Start-Process $cmd -ArgumentList '/d /k "title VSO LAB FOREIGN CMD"' -PassThru)
 try{
  foreach($p in $script:decoys){Assert-Lab (-not $p.HasExited) 'Decoy exited before test.'}
  $launch=Start-VSO -Path $target -PassThru -Confirm:$false
  $limit=[DateTime]::UtcNow.AddSeconds(120)
  do{
   Start-Sleep -Seconds 2;$status=Get-VSOStatus -Path $target -Quiet
   $activity=& (Get-Module VSO) {param($path) $ctx=New-VSOContext en -Quiet;$i=@(Get-VSOInstallationsInternal $ctx $path)[0];Get-VSOProcesses $i.ApplicationPath $ctx $i.Receipt} $target
   $payload=@($activity.Processes|Where-Object Evidence -in @('ProtectedMemorySourceAndHash','ExactScriptPath'))
  }while(($payload.Count -eq 0 -or -not $status.ProcessVisibilityReliable -or -not $activity.Reliable) -and [DateTime]::UtcNow -lt $limit)
  Assert-Lab ($status.ProcessVisibilityReliable -and $status.ProcessIds.Count -gt 0) 'Official VSO launch was not observable.'
  Assert-Lab ($payload.Count -gt 0) 'Only the startup gate or launcher was observed; no official payload host.'
  Start-Sleep -Seconds 15
  $status=Get-VSOStatus -Path $target -Quiet
  Assert-Lab (@($payload|Where-Object ProcessId -in $status.ProcessIds).Count -gt 0) 'The official payload host did not remain running.'
  $script:started=$true
  $duplicate=Start-VSO -Path $target -PassThru -Confirm:$false;Assert-Lab ($duplicate.AlreadyRunning) 'Duplicate instance was started.'
  $blocked=$false;try{Update-VSO -Path $target -Version 1.2.2 -Force -Quiet}catch{$blocked=$true};Assert-Lab $blocked 'Update accepted a running application.'
  $owned=@($status.ProcessIds);$foreign=@($script:decoys.Id)
  $stop=Stop-VSO -Path $target -Force -Quiet -PassThru
  foreach($p in $script:decoys){$p.Refresh();Assert-Lab (-not $p.HasExited) ('Foreign process was stopped: '+$p.Id)}
  Assert-Lab (@(Get-VSOStatus -Path $target -Quiet).ProcessIds.Count -eq 0) 'An attributed process remained.'
  foreach($pidValue in $stop.ProcessIds){Assert-Lab ($pidValue -notin $foreign) 'Foreign PID appeared in stop result.'}
  @{OfficialLauncherPID=$launch.LauncherProcessId;ObservedOwnedPIDs=$owned;StoppedPIDs=$stop.ProcessIds;ForeignPIDs=$foreign;ForeignSurvived=$true}
 }finally{foreach($p in $script:decoys){$p.Refresh();if(-not $p.HasExited){$p.Kill();$null=$p.WaitForExit(10000)};$p.Dispose()}}
} (-not $script:installed -or [bool]$SkipLaunch)
Invoke-LabCase 'Quiet AllUsers real installation, integrity and removal' {
 Assert-Lab (-not(Test-Path -LiteralPath $allTarget)) 'AllUsers test destination already exists.'
 $r=@(Install-VSO -Path $allTarget -AllUsers -Version 1.2.2 -Quiet -PassThru);Assert-Lab ($r.Count -eq 1) 'AllUsers emitted extra objects.'
 $proof=Assert-LabIntegrity $allTarget '1.2.2'
 $removed=Reset-VSO -Path $allTarget -Force -Quiet -PassThru
 Assert-Lab (-not(Test-Path -LiteralPath $allTarget)) 'Empty AllUsers installation remains.'
 $proof
}
Invoke-LabCase 'Full Reset removes owned files and preserves every unknown sentinel' {
 $result=Reset-VSO -Path $target -Full -Force -Quiet -PassThru
 Assert-Lab ($result.Changed -and -not $result.RestoredWindowsTweaks) 'Reset result invalid.'
 Assert-Lab (-not(Test-Path (Join-Path $target 'VSO7/VSO7.ps1'))) 'Owned application remains.'
 foreach($relative in @('foreign.txt','VSO7/config/user.json','VSO7/Recuperacion/backup.json','VSO7/logs/session.log')){Assert-Lab ([IO.File]::ReadAllText((Join-Path $target $relative)) -ceq ('VSO LAB SENTINEL '+$relative)) ('Sentinel changed: '+$relative)}
 Assert-Lab (-not(Test-Path (Join-Path $target '.vso-manager.json'))) 'Receipt remains.'
 @{RemovedFiles=$result.Removed.Count;PreservedFiles=$result.Preserved.Count;ForeignSentinelsPreserved=4}
} (-not $script:installed)
Save-LabResults
@($script:results.ToArray())|Group-Object Result|Select-Object Name,Count
if(@($script:results|Where-Object Result -eq 'FAIL').Count){throw 'Real lifecycle campaign contains failures; inspect JSON evidence.'}
