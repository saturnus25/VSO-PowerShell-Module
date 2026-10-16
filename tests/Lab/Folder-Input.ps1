[CmdletBinding()]
param([Parameter(Mandatory)][int]$TargetPid)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path 'C:\VSO-Lab\ISOLATED-LAB.json')){throw 'Dedicated guest only'}
$process=Get-CimInstance Win32_Process -Filter ('ProcessId='+$TargetPid)
if(-not$process -or $process.CommandLine -notlike '*C:\VSO-Lab\UIProbe.ps1*FolderManual*'){throw 'Only the dedicated modern-folder probe is allowed'}
Add-Type @'
using System;using System.Collections.Generic;using System.Text;using System.Runtime.InteropServices;
public static class LabFolderInput {
 delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback cb,IntPtr p);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] struct Key {public ushort Vk,Scan;public uint Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Explicit,Size=40)] struct Input {[FieldOffset(0)]public uint Type;[FieldOffset(8)]public Key Key;}
 [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,Input[] input,int size);
 public static void TypePath(uint pid,string path) {
  var windows=new List<IntPtr>();EnumWindows(delegate(IntPtr h,IntPtr p){uint owner;GetWindowThreadProcessId(h,out owner);var b=new StringBuilder(256);GetClassName(h,b,256);if(owner==pid&&b.ToString()=="#32770"&&IsWindowVisible(h))windows.Add(h);return true;},IntPtr.Zero);
  if(windows.Count!=1)throw new Exception("One visible probe-owned folder dialog is required; found "+windows.Count);
  SetForegroundWindow(windows[0]);System.Threading.Thread.Sleep(50);
  if(GetForegroundWindow()!=windows[0])throw new Exception("Probe folder dialog must have focus.");
  var keys=new List<Input>();Action<ushort,uint> vk=(v,f)=>keys.Add(new Input{Type=1,Key=new Key{Vk=v,Flags=f}});
  vk(18,0);vk(68,0);vk(68,2);vk(18,2);
  vk(17,0);vk(65,0);vk(65,2);vk(17,2);
  foreach(char c in path){keys.Add(new Input{Type=1,Key=new Key{Scan=c,Flags=4}});keys.Add(new Input{Type=1,Key=new Key{Scan=c,Flags=6}});}
  vk(13,0);vk(13,2);
  if(SendInput((uint)keys.Count,keys.ToArray(),40)!=(uint)keys.Count)throw new System.ComponentModel.Win32Exception();
 }
}
'@
try {[LabFolderInput]::TypePath([uint32]$TargetPid,'C:\VSO-Lab\UI selected á')}
catch {@{TargetPid=$TargetPid;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content ('C:\VSO-Lab\Evidence\folder-input-error-'+$TargetPid+'.json') -Encoding UTF8;throw}
@{TargetPid=$TargetPid;Path='C:\VSO-Lab\UI selected á';Method='Native Unicode keyboard input; probe-owned active dialog only'}|ConvertTo-Json|Set-Content ('C:\VSO-Lab\Evidence\folder-input-'+$TargetPid+'.json') -Encoding UTF8
