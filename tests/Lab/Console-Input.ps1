[CmdletBinding()]
param([Parameter(Mandatory)][int]$TargetPid,[string]$TextBase64,[switch]$Capture,[int]$MonitorSeconds=0)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'VSO-MODULE-LAB' -or -not(Test-Path 'C:\VSO-Lab\ISOLATED-LAB.json')){throw 'Dedicated disposable guest only.'}
$target=Get-CimInstance Win32_Process -Filter ('ProcessId='+$TargetPid)
if(-not $target -or -not $target.CommandLine.Contains('C:\VSO-Lab\UIProbe.ps1')){throw 'Only the specific lab console may receive input.'}
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class LabConsoleInput {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] public struct Key {public int Down;public ushort Repeat,Vk,Scan;public char Char;public uint State;}
 [StructLayout(LayoutKind.Explicit)] public struct Input {[FieldOffset(0)]public ushort Type;[FieldOffset(4)]public Key Key;}
 [StructLayout(LayoutKind.Sequential)] public struct Coord {public short X,Y;public Coord(short x,short y){X=x;Y=y;}}
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public short Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential)] public struct Info {public Coord Size,Cursor;public ushort Attributes;public Rect Window;public Coord Max;}
 [StructLayout(LayoutKind.Explicit,CharSet=CharSet.Unicode)] public struct Cell {[FieldOffset(0)]public char Character;[FieldOffset(2)]public ushort Attributes;}
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool FreeConsole();
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool AttachConsole(uint pid);
 [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool WriteConsoleInputW(IntPtr h,Input[] items,uint length,out uint written);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetConsoleScreenBufferInfo(IntPtr h,out Info info);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ReadConsoleOutputW(IntPtr h,[Out]Cell[] cells,Coord size,Coord origin,ref Rect rect);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern short VkKeyScanW(char ch);
 public static int Send(string text){
  var list=new List<Input>();
  foreach(char c in text){
   if(c=='\n')continue;short mapped=VkKeyScanW(c);ushort vk=(ushort)(c=='\r'?13:(mapped<0?0:mapped&255));uint state=0;
   if(mapped>=0){int modifiers=(mapped>>8)&255;if((modifiers&1)!=0)state|=0x10;if((modifiers&2)!=0)state|=0x08;if((modifiers&4)!=0)state|=0x02;}
   var k=new Key{Down=1,Repeat=1,Vk=vk,Char=c,State=state};list.Add(new Input{Type=1,Key=k});k.Down=0;list.Add(new Input{Type=1,Key=k});
  }
  uint n;if(!WriteConsoleInputW(GetStdHandle(-10),list.ToArray(),(uint)list.Count,out n))throw new System.ComponentModel.Win32Exception();return(int)n;
 }
 public static string[] Read(out int red){
  Info info;var h=GetStdHandle(-11);if(!GetConsoleScreenBufferInfo(h,out info))throw new System.ComponentModel.Win32Exception();
  var rect=info.Window;short width=(short)(rect.Right-rect.Left+1),height=(short)(rect.Bottom-rect.Top+1);var cells=new Cell[width*height];
  if(!ReadConsoleOutputW(h,cells,new Coord(width,height),new Coord(0,0),ref rect))throw new System.ComponentModel.Win32Exception();
  var lines=new string[height];red=0;for(int y=0;y<height;y++){var chars=new char[width];for(int x=0;x<width;x++){var cell=cells[y*width+x];chars[x]=cell.Character;if((cell.Attributes&7)==4&&cell.Character!=' '&&cell.Character!='\0')red++;}lines[y]=new string(chars).TrimEnd();}return lines;
 }
}
'@
$null=[LabConsoleInput]::FreeConsole()
if(-not[LabConsoleInput]::AttachConsole($TargetPid)){throw ('AttachConsole error '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
try{
 $r=@{TargetPid=$TargetPid}
 if($TextBase64){$text=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TextBase64));$r.InputRecordsWritten=[LabConsoleInput]::Send($text)}
 if($Capture){$red=0;$r.Lines=[LabConsoleInput]::Read([ref]$red);$r.RedCharacters=$red}
 if($MonitorSeconds -gt 0){
  $frames=New-Object 'Collections.Generic.List[object]';$watch=[Diagnostics.Stopwatch]::StartNew();$last=''
  do{$red=0;$lines=[LabConsoleInput]::Read([ref]$red);$joined=$lines -join "`n";if($joined -cne $last){$frames.Add(@{Milliseconds=$watch.ElapsedMilliseconds;Lines=$lines;RedCharacters=$red});$last=$joined;$r.Frames=@($frames.ToArray());$r|ConvertTo-Json -Depth 7|Set-Content ('C:\VSO-Lab\Evidence\console-'+$TargetPid+'.json') -Encoding UTF8};Start-Sleep -Milliseconds 25}while($watch.Elapsed.TotalSeconds -lt $MonitorSeconds)
 }
 $r|ConvertTo-Json -Depth 7|Set-Content ('C:\VSO-Lab\Evidence\console-'+$TargetPid+'.json') -Encoding UTF8
}finally{$null=[LabConsoleInput]::FreeConsole()}
