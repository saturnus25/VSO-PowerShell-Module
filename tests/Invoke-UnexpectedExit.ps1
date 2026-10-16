[CmdletBinding()]
param([switch]$IsolatedLab)
$ErrorActionPreference='Stop'
if(-not $IsolatedLab -or $env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path 'C:\VSO-Lab\ISOLATED-LAB.json')){throw 'Dedicated disposable VM only.'}
$ui=Get-Content C:\VSO-Lab\Evidence\ui-MtaCustom.json -Raw|ConvertFrom-Json
$target='C:\VSO-Lab\MTA selected á'
if($ui.Phase -cne 'Completed' -or $ui.InstallationPath -ine $target){throw 'Exact successful MTA campaign installation required.'}
Import-Module C:\VSO-Lab\VSO_PS_module\src\VSO\VSO.psd1 -Force
$r=@{Name='Unexpected official payload exit followed by safe forced stop';Result='FAIL';Edition=$PSVersionTable.PSEdition;PowerShell=$PSVersionTable.PSVersion.ToString()};$decoys=@()
try{
 if((Get-VSOStatus -Path $target -Quiet).ProcessIds.Count){throw 'Test installation already active.'}
 $outside='C:\VSO-Lab\symlink-outside.txt';[IO.File]::WriteAllText($outside,'FOREIGN OUTSIDE')
 $link=Join-Path $target 'foreign-symlink.txt';New-Item -ItemType SymbolicLink -Path $link -Target $outside|Out-Null
 try{
  $rejected=$false;try{Reset-VSO -Path $target -Full -Quiet -WhatIf}catch{$rejected=$true}
  if(-not $rejected -or [IO.File]::ReadAllText($outside) -cne 'FOREIGN OUTSIDE' -or -not(Test-Path (Join-Path $target 'VSO7\VSO7.ps1'))){throw 'Symlink preflight or foreign preservation failed.'}
  $r.SymbolicLinkRejected=$true
 }finally{[IO.File]::Delete($link)}
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$cmd=Join-Path $env:SystemRoot 'System32\cmd.exe'
 $decoys=@(Start-Process $ps -ArgumentList '-NoProfile -NoExit -Command "Start-Sleep -Seconds 3600"' -PassThru;Start-Process $cmd -ArgumentList '/d /k "title VSO LAB FOREIGN EXIT TEST"' -PassThru)
 $launch=Start-VSO -Path $target -Confirm:$false -PassThru
 $limit=[DateTime]::UtcNow.AddSeconds(120)
 do{
  Start-Sleep -Seconds 1
  $payload=@(& (Get-Module VSO) {param($p)
   $c=New-VSOContext en -Quiet;$i=@(Get-VSOInstallationsInternal $c $p)[0]
   (Get-VSOProcesses $i.ApplicationPath $c $i.Receipt).Processes|Where-Object Evidence -in @('ProtectedMemorySourceAndHash','ExactScriptPath')
  } $target)
 }while(-not $payload.Count -and [DateTime]::UtcNow -lt $limit)
 if(-not $payload.Count){throw 'No real official payload observed.'}
 Start-Sleep -Seconds 3
 & (Get-Module VSO) {param($attributed) Stop-VSOAttributedProcess $attributed (New-VSOContext en -Quiet)} $payload[0]
 Start-Sleep -Seconds 1
 $before=Get-VSOStatus -Path $target -Quiet
 $stop=Stop-VSO -Path $target -Force -Quiet -PassThru
 $after=Get-VSOStatus -Path $target -Quiet
 if($after.ProcessIds.Count){throw 'Owned hosts remain.'}
 foreach($p in $decoys){$p.Refresh();if($p.HasExited){throw 'Foreign decoy exited.'}}
 $r.Result='PASS';$r.Evidence=@{TerminatedPayload=$payload[0].ProcessId;OwnedBeforeFinalStop=$before.ProcessIds;OwnedAfterStop=$after.ProcessIds;ForeignPIDs=$decoys.Id;ForeignSurvived=$true;Removed=(Reset-VSO -Path $target -Full -Force -Quiet -PassThru).Removed.Count}
}catch{$r.Error=$_.Exception.Message}
finally{
 foreach($p in $decoys){$p.Refresh();if(-not $p.HasExited){$p.Kill();$null=$p.WaitForExit(10000)};$p.Dispose()}
 $r|ConvertTo-Json -Depth 8|Set-Content C:\VSO-Lab\Evidence\unexpected-exit.json -Encoding UTF8
}
if($r.Result -ne 'PASS'){throw 'Inspect unexpected exit evidence.'}
