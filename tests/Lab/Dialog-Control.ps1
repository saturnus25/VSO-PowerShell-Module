[CmdletBinding()]
param([Parameter(Mandatory)][int]$TargetPid)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path 'C:\VSO-Lab\ISOLATED-LAB.json')){throw 'Dedicated disposable guest only.'}
$target=Get-CimInstance Win32_Process -Filter ('ProcessId='+$TargetPid)
if(-not $target -or -not $target.CommandLine.Contains('C:\VSO-Lab\UIProbe.ps1')){throw 'Only this lab folder dialog may be controlled.'}
Add-Type @'
using System;using System.Collections.Generic;using System.Runtime.InteropServices;using System.Text;
public static class LabFolderCancel {
 delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")]static extern bool EnumWindows(Callback cb,IntPtr p);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassNameW(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll")]static extern bool PostMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static IntPtr[] Find(uint pid){var a=new List<IntPtr>();EnumWindows(delegate(IntPtr h,IntPtr p){uint owner;GetWindowThreadProcessId(h,out owner);var b=new StringBuilder(256);GetClassNameW(h,b,256);if(owner==pid&&b.ToString()=="#32770")a.Add(h);return true;},IntPtr.Zero);return a.ToArray();}
 public static bool Close(IntPtr h){return PostMessageW(h,0x10,IntPtr.Zero,IntPtr.Zero);}
}
'@
$windows=@([LabFolderCancel]::Find($TargetPid))
if($windows.Count -ne 1){throw 'Exactly one owned native dialog required.'}
@{TargetPid=$TargetPid;OwnedNativeDialogs=$windows.Count;Cancelled=$true;Sent=[LabFolderCancel]::Close($windows[0])}|ConvertTo-Json|Set-Content ('C:\VSO-Lab\Evidence\dialog-'+$TargetPid+'.json') -Encoding UTF8
