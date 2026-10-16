function Get-VSOProcessSnapshot {
    return @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate)
}

function Split-VSOCommandLine {
    param([string]$CommandLine)
    if (-not ('VSOManager.NativeArguments' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace VSOManager {
  public static class NativeArguments {
    [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern IntPtr CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
    public static string[] Split(string command) {
      int count; IntPtr memory=CommandLineToArgvW(command,out count);
      if(memory==IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
      try { string[] result=new string[count];
        for(int i=0;i<count;i++) result[i]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory,i*IntPtr.Size));
        return result;
      } finally { LocalFree(memory); }
    }
  }
}
'@ -ErrorAction Stop
    }
    return [VSOManager.NativeArguments]::Split($CommandLine)
}

function Test-VSOProtectedWrapperShape {
    param($Ast)
    $decoders=@($Ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'D'},$false))
    if ($decoders.Count -ne 1 -or ($decoders[0].Extent.Text -replace '\s','') -cne 'functionD([string]$v){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($v))}') { return $false }
    $assignments=@($Ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst]},$false))
    $required=@('$source','$expected','$text','$h','$actual','$sb','$invoke')
    $parts=@{}
    foreach ($name in $required) {
        $items=@($assignments|Where-Object {$_.Left.Extent.Text -ceq $name})
        if ($items.Count -ne 1) { return $false }; $parts[$name]=$items[0]
    }
    if (($parts['$text'].Right.Extent.Text -replace '\s','') -cne '[IO.File]::ReadAllText($stage,[Text.Encoding]::UTF8)') { return $false }
    if (($parts['$h'].Right.Extent.Text -replace '\s','') -cne '[Security.Cryptography.SHA256]::Create()') { return $false }
    if (($parts['$actual'].Right.Extent.Text -replace '\s','') -notmatch '\.ComputeHash\(\$enc\.GetBytes\(\$text\)\)') { return $false }
    if (($parts['$sb'].Right.Extent.Text -replace '\s','') -cne '[ScriptBlock]::Create($text)') { return $false }
    $guard=$false
    foreach ($condition in @($Ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst]},$false))) {
        foreach ($clause in $condition.Clauses) {
            if (($clause.Item1.Extent.Text -replace '\s','') -ceq '$actual-cne$expected' -and $condition.Extent.StartOffset -lt $parts['$sb'].Extent.StartOffset -and $clause.Item2.Find({param($n) $n -is [Management.Automation.Language.ThrowStatementAst]},$false)) { $guard=$true }
        }
    }
    if (-not $guard) { return $false }
    $tables=@($parts['$invoke'].Right.FindAll({param($n) $n -is [Management.Automation.Language.HashtableAst]},$false))
    if ($tables.Count -ne 1) { return $false }
    $expected=@{VSOTrustedHost='$true';VSOTrustedMemoryHost='$true';VSOOriginalSourcePath='$source';VSOExpectedSourceSha256='$expected';VSOExpectedUserSid='$sid';DirectAction='$action';StartupProbe='$probe'}
    if ($tables[0].KeyValuePairs.Count -ne $expected.Count) { return $false }
    foreach ($pair in $tables[0].KeyValuePairs) {
        $key=$pair.Item1.Extent.Text
        if (-not $expected.ContainsKey($key) -or ($pair.Item2.Extent.Text -replace '\s','').TrimEnd(';') -cne $expected[$key]) { return $false }
    }
    $calls=@($Ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and ($n.Extent.Text -replace '\s','') -ceq '&$sb@invoke'},$false))
    return ($calls.Count -eq 1)
}

function Test-VSOEncodedHost {
    param([string]$Text, [string]$Root, [string[]]$Hashes, [int]$Depth=0)
    if ($Depth -gt 2 -or $Text.Length -gt 131072) { return $false }
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { return $false }
    # These are data reads from the inspected official protected-memory wrapper.
    # Never invoke a decoded command or evaluate an AST from process data.
    $identityAssignments=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst]},$false))
    $sourceNodes=@($identityAssignments|Where-Object {$_.Left.Extent.Text -ceq '$source'})
    $hashNodes=@($identityAssignments|Where-Object {$_.Left.Extent.Text -ceq '$expected'})
    $sourceText=if ($sourceNodes.Count -eq 1) {$sourceNodes[0].Right.Extent.Text}else{''}
    $hashText=if ($hashNodes.Count -eq 1) {$hashNodes[0].Right.Extent.Text}else{''}
    $sourceMatch=[regex]::Matches($sourceText,'^D\(''([A-Za-z0-9+/=]+)''\)$')
    $hashMatch=[regex]::Matches($hashText,'^''([A-Fa-f0-9]{64})''$')
    if ($sourceMatch.Count -eq 1 -and $hashMatch.Count -eq 1 -and (Test-VSOProtectedWrapperShape $ast)) {
        try {
            $source=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($sourceMatch[0].Groups[1].Value))
            $full=[IO.Path]::GetFullPath($source)
            if ($full -iin @((Join-Path $Root 'VSO7.ps1'),(Join-Path $Root 'VSO7_7.0.0_RC_R80.ps1')) -and $hashMatch[0].Groups[1].Value.ToLowerInvariant() -cin $Hashes) { return $true }
        } catch { return $false }
    }
    # The VSO7 Windows Terminal broker embeds the exact wrapper in a literal payload.
    $pipeConstructors=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-Object' -and $node.Extent.Text.Contains('IO.Pipes.NamedPipeServerStream')},$false))
    $payloadConsumers=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and ($node.Extent.Text -replace '\s','') -ceq '[ScriptBlock]::Create($payload)'},$true))
    if ($pipeConstructors.Count -eq 0 -or $payloadConsumers.Count -eq 0 -or -not $Text.Contains('VSO7.Terminal.')) { return $false }
    foreach ($assignment in @($ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$payload'},$false))) {
        $values=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst]},$true))
        if ($values.Count -eq 1 -and (Test-VSOEncodedHost $values[0].Value $Root $Hashes ($Depth+1))) { return $true }
    }
    return $false
}

function Get-VSOProcesses {
    param([string]$Root, $Context, $Receipt, [object[]]$Snapshot)
    if (-not $PSBoundParameters.ContainsKey('Snapshot')) {
        try { $Snapshot=@(Get-VSOProcessSnapshot) }
        catch { return [pscustomobject]@{ Reliable=$false; Processes=@(); Diagnostic=$_.Exception.Message } }
    }
    $hashes=@()
    try {
        if ($Receipt) {
            $hashes=@([string](Get-VSOProperty $Receipt MemorySourceSha256 ''))
        } elseif ([IO.File]::Exists((Join-Path $Root 'VSO7.ps1'))) { $hashes=@(Get-VSOSourceTextHash (Join-Path $Root 'VSO7.ps1') $Context) }
    } catch { return [pscustomobject]@{Reliable=$false;Processes=@();Diagnostic=$_.Exception.Message} }
    $owned=[Collections.Generic.List[object]]::new(); $reliable=$true
    $system=Get-VSOSystemDirectory $Context
    $windowsPS=Join-Path $system 'WindowsPowerShell\v1.0\powershell.exe'
    $windowsCmd=Join-Path $system 'cmd.exe'
    foreach ($process in $Snapshot) {
        if ($process.Name -notin @('powershell.exe','cmd.exe')) { continue }
        if (-not $process.CommandLine -or -not $process.ExecutablePath -or -not $process.CreationDate) { $reliable=$false; continue }
        $evidence=$null
        if ($process.Name -ieq 'powershell.exe' -and $process.ExecutablePath -ieq $windowsPS) {
            try { $arguments=@(Split-VSOCommandLine $process.CommandLine) } catch { $reliable=$false; continue }
            for ($i=1; $i -lt $arguments.Count-1; $i++) {
                if ($arguments[$i] -in @('-Command','-c','-CommandWithArgs','-EncodedArguments')) { break }
                if ($arguments[$i] -ieq '-File') {
                    $file=$arguments[$i+1]
                    if ($file -iin @((Join-Path $Root 'VSO7.ps1'),(Join-Path $Root 'VSO7_7.0.0_RC_R80.ps1'))) { $evidence='ExactScriptPath' }
                    if ($file -ieq (Join-Path $Root 'Tools\VSO7_STARTUP_GATE.ps1')) {
                        for ($j=$i+2; $j -lt $arguments.Count-1; $j++) { if ($arguments[$j] -ieq '-Root' -and $arguments[$j+1].TrimEnd('\','.') -ieq $Root.TrimEnd('\')) { $evidence='ExactStartupGate' } }
                    }
                    break
                }
                if ($arguments[$i] -ieq '-EncodedCommand') {
                    try {
                        $decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($arguments[$i+1]))
                        if (Test-VSOEncodedHost $decoded $Root $hashes) { $evidence='ProtectedMemorySourceAndHash' }
                        elseif ($decoded -match 'VSO7|VSOTrustedMemoryHost') { $reliable=$false }
                    } catch { $reliable=$false }
                    break
                }
            }
        }
        if ($process.Name -ieq 'cmd.exe' -and $process.ExecutablePath -ieq $windowsCmd) {
            $launcher=[regex]::Escape((Join-Path $Root 'START VSO7.bat'))
            if ($process.CommandLine -match ('(?i)^"?'+[regex]::Escape($windowsCmd)+'"?\s+/d\s+/s\s+/c\s+""'+$launcher+'""\s*$')) { $evidence='ExactOfficialLauncher' }
            $managedArguments='/d /s /c "set "PSModulePath=" & call "'+(Join-Path $Root 'START VSO7.bat')+'""'
            if ($process.CommandLine -match ('(?i)^"?'+[regex]::Escape($windowsCmd)+'"?\s+'+[regex]::Escape($managedArguments)+'\s*$')) { $evidence='ExactOfficialLauncher' }
        }
        # Shared terminals, arbitrary descendants and unrelated PowerShell processes are excluded.
        if ($evidence) { $owned.Add([pscustomobject]@{ ProcessId=[int]$process.ProcessId; ParentProcessId=[int]$process.ParentProcessId; CreationDate=$process.CreationDate; ExecutablePath=$process.ExecutablePath; CommandLine=$process.CommandLine; Evidence=$evidence }) }
    }
    return [pscustomobject]@{ Reliable=$reliable; Processes=@($owned.ToArray()); Diagnostic=$(if ($reliable) {$null}else{$Context.Text.ProcessVisibility}) }
}

function New-VSOLaunchInfo {
    param([string]$ApplicationPath, $Context)
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Join-Path (Get-VSOSystemDirectory $Context) 'cmd.exe'
    $info.Arguments='/d /s /c "set "PSModulePath=" & call "'+(Join-Path $ApplicationPath 'START VSO7.bat')+'""'
    $info.WorkingDirectory=$ApplicationPath
    # cmd is an intermediate process: it otherwise passes Core's module paths
    # to the official Windows PowerShell launcher. Let Desktop construct its own
    # paths. This changes only the child's environment, never the caller's.
    # Keep ShellExecute's separate application window. Clear the variable in
    # the child cmd with a constant prefix; validated paths forbid cmd expansion.
    $info.UseShellExecute=$true
    $info.CreateNoWindow=$false
    $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Normal
    return $info
}

function Invoke-VSOLauncher {
    param($Installation, $Context)
    $root=Resolve-VSOPath $Installation.Path $Context -Installation
    $app=Resolve-VSOPath $Installation.ApplicationPath $Context
    if (-not (Test-VSOWithin $app $root -AllowEqual)) { Throw-VSOError $Context Path @($app) }
    if ([IO.Path]::GetFileName($app) -ine 'VSO7') { Throw-VSOError $Context Vso7Folder }
    if ($Installation.Receipt) { Test-VSOInstalledFiles $Installation.Receipt $Context }
    $null=Get-VSODistribution $app $Context -ExpectedVersion $Installation.Version
    $info=New-VSOLaunchInfo $app $Context
    $child=[Diagnostics.Process]::Start($info)
    if (-not $child) { Throw-VSOError $Context Failure }
    try { return [pscustomobject]@{ PSTypeName='VSO.LaunchResult'; Path=$root; ApplicationPath=$app; Version=$Installation.Version; Launcher='START VSO7.bat'; LauncherProcessId=$child.Id; StartupVerified=$false; Message=$Context.Text.Started } }
    finally { $child.Dispose(); Write-VSOProgress $Context Verify -Completed }
}

function Stop-VSOAttributedProcess {
    param($Attributed, $Context)
    $live=@(Get-VSOProcessSnapshot | Where-Object ProcessId -EQ $Attributed.ProcessId)
    # Stopping one owned host can let its sibling exit before this turn. Absence
    # needs no termination; an occupied/reused PID still requires exact identity.
    if ($live.Count -eq 0) { return }
    if ($live.Count -ne 1 -or $live[0].CreationDate -ne $Attributed.CreationDate -or $live[0].CommandLine -cne $Attributed.CommandLine -or $live[0].ExecutablePath -ine $Attributed.ExecutablePath) { Throw-VSOError $Context ProcessUnknown }
    try { $process=Get-Process -Id $Attributed.ProcessId -ErrorAction Stop }
    catch {
        # Win32_Process may briefly retain a terminating host after Get-Process
        # no longer finds it. Wait only for absence; never acquire/kill another PID
        # from this branch. Any occupied identity change still fails immediately.
        for ($attempt=0; $attempt -lt 4; $attempt++) {
            $remaining=@(Get-VSOProcessSnapshot | Where-Object ProcessId -EQ $Attributed.ProcessId)
            if ($remaining.Count -eq 0) { return }
            if ($remaining.Count -ne 1 -or $remaining[0].CreationDate -ne $Attributed.CreationDate -or $remaining[0].CommandLine -cne $Attributed.CommandLine -or $remaining[0].ExecutablePath -ine $Attributed.ExecutablePath) { Throw-VSOError $Context ProcessUnknown }
            if ($attempt -lt 3) { Start-Sleep -Milliseconds 250 }
        }
        Throw-VSOError $Context ProcessUnknown
    }
    try {
        $null=$process.Handle
        if ($process.HasExited) { return }
        # CIM's DMTF timestamp has microsecond precision; Process.StartTime can
        # retain sub-microsecond FILETIME ticks. Preserve identity without requiring
        # an impossible equality at a finer precision than the snapshot.
        $difference=[Math]::Abs($process.StartTime.ToUniversalTime().Ticks-([DateTime]$Attributed.CreationDate).ToUniversalTime().Ticks)
        if ($difference -ge 10) { Throw-VSOError $Context ProcessUnknown }
        $process.Kill()
        if (-not $process.WaitForExit(10000)) { Throw-VSOError $Context Failure }
    } catch {
        if (-not $process.HasExited) { throw }
    } finally { $process.Dispose() }
}
