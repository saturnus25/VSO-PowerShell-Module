[CmdletBinding()]
param([ValidateSet('Cancel','DefaultInstall','FolderCancel','FolderSelect','FolderManual','UacCancel','UacAccept','AutoSpanish','AutoEnglish','Quiet','MtaCustom','DestinationAllUsers','ScopeCurrentUser','CrossAccept','CrossCancel')][string]$Scenario='Cancel',[string]$Language='en',[string]$EvidenceRoot='C:\VSO-Lab\Evidence',[string]$Suffix='')
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path 'C:\VSO-Lab\ISOLATED-LAB.json')){throw 'Dedicated disposable guest only.'}
$path=Join-Path $EvidenceRoot ('ui-'+$Scenario+$Suffix+'.json')
$r=@{Scenario=$Scenario;ProcessId=$PID;Apartment=[Threading.Thread]::CurrentThread.GetApartmentState().ToString();InputRedirected=[Console]::IsInputRedirected;Language=$Language;SessionUICulture=$PSUICulture;IsAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);Phase='Starting'}
$r.TerminalSession=$env:WT_SESSION;$r.SessionId=(Get-Process -Id $PID).SessionId;$r.PowerShell=$PSVersionTable.PSVersion.ToString()
$r.Caller=[Security.Principal.WindowsIdentity]::GetCurrent().Name
if($Scenario -eq 'AutoSpanish' -and $PSUICulture -notmatch '^es'){$r.Phase='SKIP';$r.Reason='A real Spanish PowerShell UI culture is required.';$r|ConvertTo-Json|Set-Content $path -Encoding UTF8;return}
$r|ConvertTo-Json|Set-Content $path -Encoding UTF8
Import-Module C:\VSO-Lab\VSO_PS_module\src\VSO\VSO.psd1 -Force
$timer=$null
try{
 if($Scenario -eq 'FolderSelect'){
  if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'){throw 'Native selection case requires STA.'}
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type @"
using System;using System.Collections.Generic;using System.Runtime.InteropServices;using System.Text;
public static class LabOwnFolder {
 delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")]static extern bool EnumWindows(Callback cb,IntPtr p);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassNameW(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,string path);
 [DllImport("user32.dll")]static extern bool PostMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static bool SelectOwn(string path){
  uint self=(uint)System.Diagnostics.Process.GetCurrentProcess().Id;var list=new List<IntPtr>();
  EnumWindows(delegate(IntPtr h,IntPtr p){uint owner;GetWindowThreadProcessId(h,out owner);var b=new StringBuilder(256);GetClassNameW(h,b,256);if(owner==self&&b.ToString()=="#32770")list.Add(h);return true;},IntPtr.Zero);
  if(list.Count!=1)return false;
  // WM_USER string pointers must stay inside the dialog owner's STA process.
  SendMessageW(list[0],0x467,new IntPtr(1),path);
  return PostMessageW(list[0],0x111,new IntPtr(1),IntPtr.Zero);
 }
}
"@
  [void][IO.Directory]::CreateDirectory('C:\VSO-Lab\UI selected á')
  $timer=New-Object Windows.Forms.Timer;$timer.Interval=500
  $timer.add_Tick({if([LabOwnFolder]::SelectOwn('C:\VSO-Lab\UI selected á')){$timer.Stop();$r.NativeFolderSelectionRequestedInOwner=$true}})
  $timer.Start()
 }
 $r.Phase='Prompting';$r|ConvertTo-Json|Set-Content $path -Encoding UTF8
 if($Scenario -eq 'Quiet'){$null=Read-Host 'LAB START QUIET - Enter to begin capture'}
 if($Scenario -in @('CrossAccept','CrossCancel')){$result=Install-VSO -AllUsers -Path (Join-Path $env:ProgramFiles 'VSO Cross á') -Language $Language -Version 1.2.2 -PassThru}
 elseif($Scenario -eq 'DestinationAllUsers'){$result=Install-VSO -AllUsers -Language $Language -Version 1.2.2 -PassThru}
 elseif($Scenario -eq 'ScopeCurrentUser'){$result=Install-VSO -Scope CurrentUser -Language $Language -Version 1.2.2 -PassThru}
 elseif($Language -like 'auto-*'){$result=Install-VSO -Version 1.2.2 -PassThru}
 elseif($Scenario -eq 'Quiet'){$result=Install-VSO -Version 1.2.2 -Quiet -PassThru}
 else{$result=Install-VSO -Language $Language -Version 1.2.2 -PassThru}
 $r.Phase='Completed';$r.Changed=$result.Changed;$r.InstallationPath=$result.Path
 if($Scenario -in @('FolderSelect','FolderManual')){$r.NativeFolderSelected=($result.Path -ceq 'C:\VSO-Lab\UI selected á')}
 $r.Result=@($result);$r.VisibleInstallation=@(Get-VSOInstallation -Path $result.Path -Quiet|Select-Object Path,Scope,State,Managed)
}catch{
 $r.Phase='CancelledOrFailed';$r.ErrorId=$_.FullyQualifiedErrorId;$r.Message=$_.Exception.Message
 if($Scenario -eq 'CrossCancel'){$r.TargetExistsAtCancellation=Test-Path (Join-Path $env:ProgramFiles 'VSO Cross á');$r.TemporaryRequestsRemaining=@(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter '.vso-work-*' -ErrorAction SilentlyContinue).Count}
 Write-Error -ErrorRecord $_ -ErrorAction Continue
}finally{if($timer){$timer.Stop();$timer.Dispose()};$r|ConvertTo-Json -Depth 5|Set-Content $path -Encoding UTF8}
$null=Read-Host 'LAB CAPTURE - Enter to finish'
