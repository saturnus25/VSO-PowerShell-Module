if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
InModuleScope VSO {
    BeforeAll {. (Join-Path $env:VSO_MODULE_LAB_PROJECT 'tests/Fixtures.ps1');$script:ctx=New-VSOContext en -Quiet;$script:selectOriginal=${function:Select-VSOInstallation}}
    Describe 'Public orchestration and WhatIf' {
        BeforeEach {
            Mock Assert-VSOPlatform {}
            $script:item=[pscustomobject]@{Path=(Join-Path $env:LOCALAPPDATA 'Programs\VSO');ApplicationPath=(Join-Path $env:LOCALAPPDATA 'Programs\VSO\VSO7');Version='1.2.2';Scope='CurrentUser';Receipt=[pscustomobject]@{MemorySourceSha256=('a'*64)};Diagnostic=$null;State='Ready';Managed=$true}
            Mock Select-VSOInstallation {$script:item}
            Mock Get-VSOProcesses {[pscustomobject]@{Reliable=$true;Processes=@()}}
            Mock Enter-VSOLock {throw 'A lock must not be created'}
            Mock Invoke-VSOInstallTransaction {throw 'Must not mutate'}
            Mock Invoke-VSOLauncher {throw 'Must not launch'}
            Mock Invoke-VSORemoval {throw 'Must not remove'}
            Mock Invoke-VSOElevation {throw 'Must not elevate'}
            Mock Get-VSORelease {New-LabApiRelease}
        }
        It 'Install WhatIf performs no network, elevation or staging' {
            Install-VSO -Quiet -WhatIf
            Should -Invoke Get-VSORelease -Times 0
            Should -Invoke Invoke-VSOElevation -Times 0
            Should -Invoke Invoke-VSOInstallTransaction -Times 0
            Should -Invoke Enter-VSOLock -Times 0
        }
        It 'Update WhatIf performs no network or replacement' {
            Update-VSO -Quiet -WhatIf
            Should -Invoke Get-VSORelease -Times 0
            Should -Invoke Invoke-VSOInstallTransaction -Times 0
        }
        It 'Start WhatIf does not create a window or lock' {
            Start-VSO -WhatIf
            Should -Invoke Invoke-VSOLauncher -Times 0
            Should -Invoke Enter-VSOLock -Times 0
        }
        It 'Reset WhatIf returns an exact removal plan and performs no mutation' {
            Mock Get-VSORemovalPlan {[pscustomobject]@{Path=$script:item.Path;Remove=@([pscustomobject]@{Path='synthetic-owned.txt'});Preserve=@('synthetic-foreign.txt')}}
            $plan=Reset-VSO -Full -Quiet -WhatIf -PassThru
            $plan.Remove[0].Path|Should -Be 'synthetic-owned.txt'
            Should -Invoke Invoke-VSORemoval -Times 0
            Should -Invoke Invoke-VSOElevation -Times 0
        }
        It 'Quiet reset requires explicit destructive intent' {
            {Reset-VSO -Quiet}|Should -Throw '*Force*'
            {Reset-VSO -Quiet -Force -Full -RemoveBackups}|Should -Throw '*AcknowledgeBackupLoss*'
        }
        It 'skips an unnecessary update' {
            Mock Get-VSORelease {[pscustomobject]@{Version='1.2.2'}}
            (Update-VSO -Quiet -PassThru).Changed|Should -BeFalse
            Should -Invoke Invoke-VSOInstallTransaction -Times 0
        }
        It 'does not duplicate a running instance' {
            Mock Get-VSOProcesses {[pscustomobject]@{Reliable=$true;Processes=@([pscustomobject]@{ProcessId=999})}}
            (Start-VSO -PassThru).AlreadyRunning|Should -BeTrue
            Should -Invoke Invoke-VSOLauncher -Times 0
        }
        It 'does not force a graceful-stop claim for VSO7' {
            Mock Get-VSOProcesses {[pscustomobject]@{Reliable=$true;Processes=@([pscustomobject]@{ProcessId=999})}}
            {Stop-VSO -Quiet}|Should -Throw '*IPC*'
            Stop-VSO -WhatIf
            Should -Invoke Enter-VSOLock -Times 0
        }
        It 'Quiet AllUsers fails rather than opening UAC' {
            Mock Invoke-VSOElevation {param($Context) if ($Context.Quiet) {Throw-VSOError $Context Admin}}
            Mock Get-VSORelease {[pscustomobject]@{Version='1.2.2';AssetName='fixture.zip'}}
            Mock Test-VSOAdministrator {$false}
            {Install-VSO -AllUsers -Quiet}|Should -Throw '*Quiet*'
        }
        It 'reports an explicit UAC rejection as cancellation' {
            Mock Get-VSORelease {[pscustomobject]@{Version='1.2.2';AssetName='fixture.zip'}}
            Mock Test-VSOAdministrator {$false}
            Mock Invoke-VSOElevation {param($Context) Throw-VSOError $Context UacCancelled}
            {Install-VSO -AllUsers}|Should -Throw '*cancelled the UAC*'
        }
        It 'requires an explicit selection when multiple installations exist in Quiet' {
            Mock Get-VSOInstallationsInternal {@($script:item,$script:item)}
            {& $script:selectOriginal $script:ctx}|Should -Throw '*Several*'
        }
    }
    Describe 'Elevation adapter cancellation' {
        It 'distinguishes native UAC cancellation and cleans its private result directory' {
            $context=New-VSOContext en
            Mock Start-VSOElevationProcess {
                param($Info)
                $Info.Arguments|Should -Match '-NonInteractive -ExecutionPolicy Bypass -EncodedCommand '
                throw [ComponentModel.Win32Exception]::new(1223)
            }
            {Invoke-VSOElevation 'Install-VSO' @{Path=(Join-Path $env:ProgramFiles 'VSO');Scope='AllUsers';Version='1.2.2';Force=$false;Language='en-US';Prerelease=$false;AssetName='fixture.zip'} $context}|Should -Throw '*cancelled the UAC*'
            Should -Invoke Start-VSOElevationProcess -Times 1
        }
    }
}
