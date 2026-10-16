[CmdletBinding()]
param([Parameter(Mandatory)][int]$TargetPid,[switch]$Select)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path 'C:\VSO-Lab\ISOLATED-LAB.json')){throw 'Dedicated guest only'}
$process=Get-CimInstance Win32_Process -Filter ('ProcessId='+$TargetPid)
if(-not$process -or $process.CommandLine -notlike '*C:\VSO-Lab\UIProbe.ps1*FolderManual*'){throw 'Only the dedicated modern-folder probe is allowed'}
Add-Type @'
using System;using System.Collections.Generic;using System.Text;using System.Runtime.InteropServices;
public static class LabFolderSelect {
 public class Button {public long Handle;public string Text;public bool Enabled,Visible;}
 delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback cb,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr root,Callback cb,IntPtr p);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
 [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 static IntPtr Dialog(uint pid) {
  var list=new List<IntPtr>();EnumWindows(delegate(IntPtr h,IntPtr p){uint owner;GetWindowThreadProcessId(h,out owner);var b=new StringBuilder(256);GetClassName(h,b,256);if(owner==pid&&b.ToString()=="#32770"&&IsWindowVisible(h))list.Add(h);return true;},IntPtr.Zero);
  if(list.Count!=1)throw new Exception("One visible probe-owned folder dialog required.");return list[0];
 }
 public static Button[] Inspect(uint pid) {
  var list=new List<Button>();EnumChildWindows(Dialog(pid),delegate(IntPtr h,IntPtr p){var c=new StringBuilder(256);GetClassName(h,c,256);if(c.ToString()=="Button"){var t=new StringBuilder(512);GetWindowText(h,t,512);list.Add(new Button{Handle=h.ToInt64(),Text=t.ToString(),Visible=IsWindowVisible(h),Enabled=IsWindowEnabled(h)});}return true;},IntPtr.Zero);return list.ToArray();
 }
 public static void Select(uint pid) {
  var dialog=Dialog(pid);var list=new List<Button>();foreach(var b in Inspect(pid))if(b.Text.Replace("&","")=="Select Folder"&&b.Enabled&&b.Visible)list.Add(b);
  if(list.Count!=1)throw new Exception("One enabled native Select Folder button required.");
  SetForegroundWindow(dialog);System.Threading.Thread.Sleep(50);if(GetForegroundWindow()!=dialog)throw new Exception("Folder dialog must have focus.");
  SendMessage(new IntPtr(list[0].Handle),0xF5,IntPtr.Zero,IntPtr.Zero);
 }
}
'@
$buttons=[LabFolderSelect]::Inspect([uint32]$TargetPid)
@{TargetPid=$TargetPid;Buttons=@($buttons);SelectRequested=[bool]$Select}|ConvertTo-Json -Depth 6|Set-Content ('C:\VSO-Lab\Evidence\folder-native-buttons-'+$TargetPid+'.json') -Encoding UTF8
if($Select){[LabFolderSelect]::Select([uint32]$TargetPid)}
