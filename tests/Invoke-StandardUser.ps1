[CmdletBinding()]
param([switch]$IsolatedLab)
$ErrorActionPreference='Stop'
if(-not $IsolatedLab -or $env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path 'C:\VSO-Lab\ISOLATED-LAB.json')){throw 'Dedicated disposable VM only.'}
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($admin){throw 'A genuine standard account is required.'}
Import-Module C:\VSO-Lab\VSO_PS_module\src\VSO\VSO.psd1
$root='C:\VSO-Lab\StandardUser';$target=Join-Path $root 'VSO espacio á';$cases=New-Object 'Collections.Generic.List[object]'
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Case([string]$Name,[scriptblock]$Body){$s='PASS';try{$d=& $Body}catch{$s='FAIL';$d=$_.Exception.Message};$cases.Add([pscustomobject]@{Name=$Name;Result=$s;Evidence=$d});@{IsAdministrator=$admin;PowerShell=$PSVersionTable.PSVersion.ToString();Cases=$cases.ToArray()}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $root 'standard-user.json') -Encoding UTF8}
Case 'Quiet AllUsers fails without invoking consent from a standard account' {
 $id=$null;try{Install-VSO -Path 'C:\Program Files\VSO Standard Forbidden' -AllUsers -Version 1.2.2 -Quiet}catch{$id=$_.FullyQualifiedErrorId}
 Check ($id -like 'VSO.Admin*') ('Unexpected rejection: '+$id)
 Check (-not(Test-Path 'C:\Program Files\VSO Standard Forbidden')) 'Forbidden target created.'
}
Case 'Genuine standard account installs and verifies official CurrentUser payload' {
 $r=Install-VSO -Path $target -Scope CurrentUser -Version 1.2.2 -Quiet -PassThru
 Check $r.Changed 'Installation unchanged.';$receipt=Get-Content (Join-Path $target '.vso-manager.json') -Raw|ConvertFrom-Json
 foreach($f in $receipt.Files){Check (((Get-FileHash (Join-Path $target $f.Path)).Hash.ToLowerInvariant()) -ceq $f.Sha256) 'Owned file hash differs.'}
 Check ((Get-VSOInstallation -Path $target -Quiet).State -ceq 'Ready') 'Registration not Ready.'
 @{OwnedFiles=$receipt.Files.Count;Scope=$receipt.Scope}
}
Case 'Standard account removes its own installation and preserves foreign data' {
 [IO.File]::WriteAllText((Join-Path $target 'foreign.txt'),'KEEP')
 $r=Reset-VSO -Path $target -Full -Force -Quiet -PassThru
 Check (-not(Test-Path (Join-Path $target '.vso-manager.json'))) 'Owned receipt remains.'
 Check ([IO.File]::ReadAllText((Join-Path $target 'foreign.txt')) -ceq 'KEEP') 'Foreign sentinel removed.'
 @{Removed=$r.Removed.Count;ForeignPreserved=$true}
}
