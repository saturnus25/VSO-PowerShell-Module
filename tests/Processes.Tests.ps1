if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
InModuleScope VSO {
    BeforeAll { . (Join-Path $env:VSO_MODULE_LAB_PROJECT 'tests/Fixtures.ps1'); $script:ctx=New-VSOContext en -Quiet; $script:root=Join-Path $env:LOCALAPPDATA 'Programs\VSO'; $script:ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    Describe 'Strict process attribution from synthetic snapshots' {
        It 'starts a real cmd to Desktop chain without inheriting Core module paths' {
            $folder=Join-Path $TestDrive 'launch environment';[void][IO.Directory]::CreateDirectory($folder)
            $out=Join-Path $folder 'child.json';$probe=Join-Path $folder 'probe.ps1'
            $body='param($Out); @{Edition=$PSVersionTable.PSEdition;HashCommand=(Get-Command Get-FileHash -ErrorAction Stop).Name}|ConvertTo-Json|Set-Content -LiteralPath $Out'
            [IO.File]::WriteAllText($probe,$body,[Text.UTF8Encoding]::new($true))
            $batch='@echo off'+[Environment]::NewLine+'"'+$script:ps+'" -NoProfile -ExecutionPolicy Bypass -File "'+$probe+'" -Out "'+$out+'"'+[Environment]::NewLine
            [IO.File]::WriteAllText((Join-Path $folder 'START VSO7.bat'),$batch)
            $before=$env:PSModulePath
            $info=New-VSOLaunchInfo $folder $script:ctx
            $child=[Diagnostics.Process]::Start($info)
            try{$child.WaitForExit(60000)|Should -BeTrue;$child.ExitCode|Should -Be 0}finally{if(-not $child.HasExited){$child.Kill()};$child.Dispose()}
            $r=Get-Content -LiteralPath $out -Raw|ConvertFrom-Json
            $r.Edition|Should -Be Desktop;$r.HashCommand|Should -Be Get-FileHash
            $env:PSModulePath|Should -BeExactly $before
        }
        It 'parses paths with spaces and Unicode using native Windows arguments' {
            $a=@(Split-VSOCommandLine ('"'+$script:ps+'" -NoProfile -File "D:\VSO á spaces\VSO7.ps1"'))
            $a[-1]|Should -Be 'D:\VSO á spaces\VSO7.ps1'
        }
        It 'attributes only an exact script path and protected executable path' {
            $now=[DateTime]::UtcNow
            $snapshot=@(
                [pscustomobject]@{ProcessId=101;ParentProcessId=1;Name='powershell.exe';ExecutablePath=$script:ps;CommandLine=('"'+$script:ps+'" -File "'+(Join-Path $script:root 'VSO7.ps1')+'"');CreationDate=$now},
                [pscustomobject]@{ProcessId=102;ParentProcessId=1;Name='powershell.exe';ExecutablePath=$script:ps;CommandLine=('"'+$script:ps+'" -File "D:\Other\VSO7.ps1"');CreationDate=$now},
                [pscustomobject]@{ProcessId=103;ParentProcessId=101;Name='WindowsTerminal.exe';ExecutablePath='D:\Shared\WindowsTerminal.exe';CommandLine='terminal';CreationDate=$now}
            )
            $r=Get-VSOProcesses $script:root $script:ctx -Snapshot $snapshot
            $r.Processes.Count|Should -Be 1
            $r.Processes[0].ProcessId|Should -Be 101
        }
        It 'does not interpret a -File string inside another PowerShell command as ownership' {
            $snapshot=@([pscustomobject]@{ProcessId=105;ParentProcessId=1;Name='powershell.exe';ExecutablePath=$script:ps;CommandLine=('"'+$script:ps+'" -Command Write-Output -File "'+(Join-Path $script:root 'VSO7.ps1')+'"');CreationDate=[DateTime]::UtcNow})
            (Get-VSOProcesses $script:root $script:ctx -Snapshot $snapshot).Processes.Count|Should -Be 0
        }
        It 'attributes the exact sanitized launcher and excludes a command with a suffix' {
            $cmd=Join-Path (Get-VSOSystemDirectory $script:ctx) 'cmd.exe'
            $arguments='/d /s /c "set "PSModulePath=" & call "'+(Join-Path $script:root 'START VSO7.bat')+'""'
            $snapshot=@(
                [pscustomobject]@{ProcessId=201;ParentProcessId=1;Name='cmd.exe';ExecutablePath=$cmd;CommandLine=('"'+$cmd+'" '+$arguments);CreationDate=[DateTime]::UtcNow},
                [pscustomobject]@{ProcessId=202;ParentProcessId=1;Name='cmd.exe';ExecutablePath=$cmd;CommandLine=('"'+$cmd+'" '+$arguments+' & echo unrelated');CreationDate=[DateTime]::UtcNow}
            )
            $r=Get-VSOProcesses $script:root $script:ctx -Snapshot $snapshot
            $r.Processes.Count|Should -Be 1;$r.Processes[0].ProcessId|Should -Be 201
        }
        It 'marks inaccessible host command lines Unknown and never attributes them' {
            $snapshot=@([pscustomobject]@{ProcessId=106;ParentProcessId=1;Name='powershell.exe';ExecutablePath=$null;CommandLine=$null;CreationDate=[DateTime]::UtcNow})
            $r=Get-VSOProcesses $script:root $script:ctx -Snapshot $snapshot
            $r.Reliable|Should -BeFalse; $r.Processes.Count|Should -Be 0
        }
        It 'checks source and expected SHA-256 in protected-memory wrappers without execution' {
            $text=New-LabMemoryWrapper $script:root
            Test-VSOEncodedHost $text $script:root @('a'*64)|Should -BeTrue
            Test-VSOEncodedHost $text $script:root @('b'*64)|Should -BeFalse
            Test-VSOEncodedHost $text 'D:\Other' @('a'*64)|Should -BeFalse
        }
        It 'recognizes a literal Terminal broker payload but excludes the shared terminal process' {
            $inner=New-LabMemoryWrapper $script:root
            $bare='$payload='''+$inner.Replace("'","''")+'''; throw ''synthetic never execute'''
            Test-VSOEncodedHost $bare $script:root @('a'*64)|Should -BeFalse
            $outer=$bare+'; $name=''VSO7.Terminal.synthetic''; $pipe=New-Object IO.Pipes.NamedPipeServerStream; & ([ScriptBlock]::Create($payload))'
            Test-VSOEncodedHost $outer $script:root @('a'*64)|Should -BeTrue
        }
        It 'does not attribute merely quoted wrapper text or a missing integrity guard' {
            $inner=New-LabMemoryWrapper $script:root
            $quoted='Write-Output '''+$inner.Replace("'","''")+''''
            Test-VSOEncodedHost $quoted $script:root @('a'*64)|Should -BeFalse
            $unguarded=$inner.Replace('if($actual-cne$expected){throw ''Synthetic checksum mismatch''}','')
            Test-VSOEncodedHost $unguarded $script:root @('a'*64)|Should -BeFalse
            $decoy=$inner.Replace('$source=D(',"`$source='D:\Other\VSO7.ps1'; # `$source=D(")
            Test-VSOEncodedHost $decoy $script:root @('a'*64)|Should -BeFalse
        }
        It 'refuses a reused PID before any process handle or kill' {
            $old=[pscustomobject]@{ProcessId=12345;CreationDate=[DateTime]::UtcNow.AddMinutes(-1);CommandLine='old';ExecutablePath=$script:ps}
            Mock Get-VSOProcessSnapshot {[pscustomobject]@{ProcessId=12345;CreationDate=[DateTime]::UtcNow;CommandLine='different';ExecutablePath=$script:ps}}
            Mock Get-Process {throw 'Must never obtain a foreign process'}
            {Stop-VSOAttributedProcess $old $script:ctx}|Should -Throw '*ambiguous*'
            Should -Invoke Get-Process -Times 0
        }
        It 'accepts an already exited owned host without touching another process' {
            Mock Get-VSOProcessSnapshot {@()}
            Mock Get-Process {throw 'No handle may be obtained for an absent PID'}
            {Stop-VSOAttributedProcess ([pscustomobject]@{ProcessId=12345}) $script:ctx}|Should -Not -Throw
            Should -Invoke Get-Process -Times 0
        }
        It 'rechecks absence if an owned host exits between snapshot and handle acquisition' {
            $script:exiting=[pscustomobject]@{ProcessId=12345;CreationDate=[DateTime]::UtcNow;CommandLine='owned';ExecutablePath=$script:ps}
            $script:snapshotCalls=0
            Mock Get-VSOProcessSnapshot {$script:snapshotCalls++;if($script:snapshotCalls -eq 1){$script:exiting}}
            Mock Get-Process {throw 'Exited before handle acquisition'}
            {Stop-VSOAttributedProcess $script:exiting $script:ctx}|Should -Not -Throw
            Should -Invoke Get-Process -Times 1
        }
        It 'waits for a matching terminating CIM entry to disappear after process enumeration stops seeing it' {
            $script:exiting=[pscustomobject]@{ProcessId=12345;CreationDate=[DateTime]::UtcNow;CommandLine='owned';ExecutablePath=$script:ps}
            $script:snapshotCalls=0
            Mock Get-VSOProcessSnapshot {$script:snapshotCalls++;if($script:snapshotCalls -lt 4){$script:exiting}}
            Mock Get-Process {throw 'Terminated process no longer enumerated'}
            Mock Start-Sleep {}
            {Stop-VSOAttributedProcess $script:exiting $script:ctx}|Should -Not -Throw
            Should -Invoke Get-Process -Times 1
            Should -Invoke Start-Sleep -Times 2
        }
        It 'rejects PID reuse while waiting for a terminated CIM entry to disappear' {
            $script:exiting=[pscustomobject]@{ProcessId=12345;CreationDate=[DateTime]::UtcNow;CommandLine='owned';ExecutablePath=$script:ps}
            $script:snapshotCalls=0
            Mock Get-VSOProcessSnapshot {$script:snapshotCalls++;if($script:snapshotCalls -lt 3){$script:exiting}else{[pscustomobject]@{ProcessId=12345;CreationDate=[DateTime]::UtcNow.AddSeconds(1);CommandLine='foreign';ExecutablePath=$script:ps}}}
            Mock Get-Process {throw 'Terminated process no longer enumerated'}
            Mock Start-Sleep {}
            {Stop-VSOAttributedProcess $script:exiting $script:ctx}|Should -Throw '*ambiguous*'
            Should -Invoke Get-Process -Times 1
        }
    }
}
