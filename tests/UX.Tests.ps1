if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
InModuleScope VSO {
    BeforeAll { . (Join-Path $env:VSO_MODULE_LAB_PROJECT 'tests/Fixtures.ps1') }
    Describe 'Read-only status and discovery UX' {
        BeforeEach {
            $script:caseRoot=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($script:caseRoot)
            $script:target=Join-Path $script:caseRoot 'VSO espacio á'
            $script:ctx=New-VSOContext en -Quiet
            Mock Resolve-VSOPath {param($Path) [IO.Path]::GetFullPath($Path).TrimEnd('\')}
            Mock Assert-VSOPlatform {}
            Mock Get-VSORegistryRoot {param($Scope) Join-Path $script:caseRoot ('registry/'+$Scope+'/Installations')}
            Mock Get-VSODefaultPath {param($Scope) Join-Path $script:caseRoot ('absent-default-'+$Scope)}
            Mock Get-VSOProcessSnapshot { @() }
            Mock Get-VSORelease { throw 'Status and discovery must remain offline' }
            Mock Invoke-VSOHttp { throw 'Discovery must not transfer data' }
            Mock Request-VSOChoice { throw 'Discovery must not prompt' }
        }
        It 'returns exactly one absence summary with raw nulls and Boolean data in <Language>' -TestCases @(@{Language='en'},@{Language='es'}) {
            param($Language)
            $result=@(Get-VSOStatus -Language $Language -Quiet)
            $result.Count|Should -Be 1
            $s=$result[0]; $s.PSObject.TypeNames|Should -Contain 'VSO.Status'
            $s.PSObject.TypeNames|Should -Not -Contain 'VSO.Installation'
            $s.Kind|Should -BeExactly 'Summary'; $s.InstallationState|Should -BeExactly 'NotInstalled'
            foreach ($name in @('Id','Version','Path','ApplicationPath','Generation','Scope','Diagnostic','RequestedPath','RequestedScope','RequestedVersion')) {($null -eq $s.$name)|Should -BeTrue}
            ($s.Running -is [bool])|Should -BeTrue; $s.Running|Should -BeFalse
            ($s.Managed -is [bool])|Should -BeTrue; $s.ProcessIds.Count|Should -Be 0
            $s.DisplayText|Should -Match $(if ($Language -eq 'es') {'Estado de instalación de VSO'} else {'VSO Installation Status'})
            $s.DisplayText|Should -Match 'Install-VSO'
            $json=$s|ConvertTo-Json|ConvertFrom-Json
            ($null -eq $json.Version)|Should -BeTrue; ($json.Running -is [bool])|Should -BeTrue
            @($result|Where-Object InstallationState -EQ NotInstalled|Select-Object InstallationState,Version,Path,Running).Count|Should -Be 1
            Should -Invoke Get-VSORelease -Times 0; Should -Invoke Invoke-VSOHttp -Times 0
        }
        It 'retains a collection with zero installations without information-stream noise in <Language>' -TestCases @(@{Language='en'},@{Language='es'}) {
            param($Language)
            @(Get-VSOInstallation -Language $Language 6>&1).Count|Should -Be 0
            @(Get-VSOInstallation -Language $Language -Quiet 6>&1).Count|Should -Be 0
        }
        It 'renders the native localized status view without changing the objects in <Culture>' -TestCases @(@{Expected='Not Installed';Title='VSO Installation Status';Culture='en-US';Unavailable='N/A'},@{Expected='No instalado';Title='Estado de instalación de VSO';Culture='es-ES';Unavailable='N/D'}) {
            param($Expected,$Title,$Culture,$Unavailable)
            # Explicit Language controls status presentation independently of OS UI.
            $s=Get-VSOStatus -Language $Culture -Quiet
            $text=$s|Out-String -Width 120
            $text|Should -Match $Title; $text|Should -Match $Expected; $text|Should -Match $Unavailable
            $text|Should -Not -Match 'SharedRecoveryPreserved|DisplayText'
            $s.InstallationState|Should -Be 'NotInstalled'
        }
        It 'keeps Quiet object output and suppresses progress' {
            Mock Write-Progress {throw 'No progress in Quiet'}
            @(Get-VSOStatus -Quiet 6>&1).Count|Should -Be 1
            Should -Invoke Write-Progress -Times 0
        }
        It 'validates Version even for an empty collection' {
            {Get-VSOStatus -Version broken -Quiet}|Should -Throw '*semantic*'
            {Get-VSOInstallation -Version broken -Quiet}|Should -Throw '*semantic*'
        }
        It 'limits an absence summary to the requested scope and version' {
            $s=Get-VSOStatus -Scope AllUsers -Version v1.2.2 -Quiet
            $s.Kind|Should -Be Summary; $s.RequestedScope|Should -Be AllUsers; $s.RequestedVersion|Should -Be '1.2.2'
            $s.Message|Should -Match 'matches this query'
            ($null -eq $s.Scope)|Should -BeTrue; ($null -eq $s.Version)|Should -BeTrue
        }
        It 'distinguishes an explicit absent path from an empty discovery result' {
            $s=Get-VSOStatus -Path $script:target -Quiet
            $i=@(Get-VSOInstallation -Path $script:target -Quiet)
            $s.Kind|Should -Be Installation; $s.InstallationState|Should -Be Missing; $s.Path|Should -Be $script:target
            ($null -eq $s.Version)|Should -BeTrue
            $i.Count|Should -Be 1; $i[0].State|Should -Be Missing
        }
        It 'accepts distinct paths by value and by property without duplicate or trailing summaries' {
            $second=Join-Path $script:caseRoot 'second'
            $strings=@($script:target,$second)|Get-VSOStatus -Quiet
            @($strings).Count|Should -Be 2; @($strings|Where-Object Kind -EQ Summary).Count|Should -Be 0
            $objects=@([pscustomobject]@{Path=$script:target},[pscustomobject]@{Path=$second})
            $found=@($objects|Get-VSOInstallation -Quiet)
            $found.Count|Should -Be 2; $found[0].Path|Should -Be $script:target
            $status=@($found|Get-VSOStatus -Quiet)
            $status.Count|Should -Be 2; $status[1].Path|Should -Be $second
        }
        It 'reports an incomplete folder as Modified with its actual diagnostic' {
            [void][IO.Directory]::CreateDirectory($script:target)
            $s=Get-VSOStatus -Path $script:target -Quiet
            $s.InstallationState|Should -Be Modified
            $s.Diagnostic|Should -Not -BeNullOrEmpty
        }
        It 'preserves access failures instead of fabricating NotInstalled' {
            Mock Get-VSOIndexEntries {throw [UnauthorizedAccessException]::new('Synthetic index access denied')}
            {Get-VSOStatus -Quiet}|Should -Throw '*access denied*'
            {Get-VSOInstallation -Quiet}|Should -Throw '*access denied*'
        }
        It 'does not suppress an access error while probing the index directory' {
            Mock Get-Item {throw [UnauthorizedAccessException]::new('Synthetic directory access denied')}
            {Get-VSOIndexEntries CurrentUser $script:ctx}|Should -Throw '*access denied*'
        }
        It 'does not misreport an inaccessible explicit path as Missing' {
            Mock Get-Item {throw [UnauthorizedAccessException]::new('Synthetic path access denied')} -ParameterFilter {$LiteralPath -eq $script:target}
            {Get-VSOStatus -Path $script:target -Quiet}|Should -Throw '*path access denied*'
            {Get-VSOInstallation -Path $script:target -Quiet}|Should -Throw '*path access denied*'
        }
        It 'does not misreport an inaccessible default path as an empty collection' {
            Mock Get-VSODefaultPath {$script:target}
            Mock Get-Item {throw [UnauthorizedAccessException]::new('Synthetic default access denied')} -ParameterFilter {$LiteralPath -eq $script:target}
            {Get-VSOStatus -Quiet}|Should -Throw '*default access denied*'
            {Get-VSOInstallation -Quiet}|Should -Throw '*default access denied*'
        }
        It 'does not invent a version for a valid manual distribution without version evidence' {
            New-LabDistribution $script:target '1.2.2'
            $s=Get-VSOStatus -Path $script:target -Quiet
            $s.InstallationState|Should -Be Unregistered; $s.Managed|Should -BeFalse; ($null -eq $s.Version)|Should -BeTrue
            @(Get-VSOInstallation -Quiet).Count|Should -Be 0
            Test-Path (Join-Path $script:target '.vso-manager.json')|Should -BeFalse
        }
        It 'reports the declared version of a valid manual distribution without adoption' {
            New-LabDistribution $script:target '1.2.2' -Contract2
            $s=Get-VSOStatus -Path $script:target -Quiet
            $s.InstallationState|Should -Be Unregistered; $s.Version|Should -Be '1.2.2'; $s.Managed|Should -BeFalse
            Test-Path (Join-Path $script:target '.vso-manager.json')|Should -BeFalse
        }
        It 'reports a registered ready, corrupt or disappeared installation accurately in <Language>' -TestCases @(@{Language='en'},@{Language='es'}) {
            param($Language)
            $script:release=New-LabRelease $script:caseRoot '1.2.2'
            Mock Invoke-VSOHttp {param($OutFile) [IO.File]::Copy($script:release.Fixture,$OutFile,$false)}
            $null=Invoke-VSOInstallTransaction ([pscustomobject]@{Path=$script:target;Scope='CurrentUser'}) $script:release $script:ctx
            $ready=@(Get-VSOStatus -Language $Language -Quiet)
            $ready.Count|Should -Be 1; $ready[0].InstallationState|Should -Be Ready; $ready[0].Version|Should -Be '1.2.2'; $ready[0].Running|Should -BeFalse
            @(Get-VSOInstallation -Scope CurrentUser -Version 1.2.2 -Quiet).Count|Should -Be 1
            (Get-VSOStatus -Version 9.0.0 -Quiet).Kind|Should -Be Summary
            [IO.File]::AppendAllText((Join-Path $script:target 'VSO7/VSO7.ps1'),'corruption fixture')
            $corrupt=Get-VSOStatus -Quiet
            $corrupt.InstallationState|Should -Be Modified; $corrupt.Diagnostic|Should -Not -BeNullOrEmpty
            # Relocate only synthetic TestDrive data; preserve the index to model disappearance.
            [IO.Directory]::Move($script:target,($script:target+'-moved'))
            $missing=Get-VSOStatus -Quiet
            $missing.InstallationState|Should -Be Missing; $missing.Kind|Should -Be Installation
        }
        It 'enumerates multiple installations once even when a default path overlaps a registration' {
            $script:release=New-LabRelease $script:caseRoot '1.2.2'
            Mock Invoke-VSOHttp {param($OutFile) [IO.File]::Copy($script:release.Fixture,$OutFile,$false)}
            $second=Join-Path $script:caseRoot 'second'
            foreach ($path in @($script:target,$second)) { $null=Invoke-VSOInstallTransaction ([pscustomobject]@{Path=$path;Scope='CurrentUser'}) $script:release $script:ctx }
            Mock Get-VSODefaultPath {$script:target}
            $all=@(Get-VSOStatus -Quiet)
            $all.Count|Should -Be 2; @($all.Path|Sort-Object -Unique).Count|Should -Be 2
            @($all|Where-Object Kind -EQ Summary).Count|Should -Be 0
        }
        It 'uses real Boolean running values and preserves unknown visibility' {
            Mock Get-VSOProcesses {[pscustomobject]@{Reliable=$true;Processes=@([pscustomobject]@{ProcessId=12345});Diagnostic=$null}}
            $running=Get-VSOStatus -Path $script:target -Quiet
            $running.Running|Should -BeTrue; ($running.Running -is [bool])|Should -BeTrue; $running.ProcessState|Should -Be Running
            $running.ProcessIds|Should -Contain 12345
            Mock Get-VSOProcesses {[pscustomobject]@{Reliable=$false;Processes=@();Diagnostic='Synthetic visibility gap'}}
            $unknown=Get-VSOStatus -Path $script:target -Quiet
            ($null -eq $unknown.Running)|Should -BeTrue; $unknown.ProcessState|Should -Be Unknown
            $unknown.ProcessVisibilityReliable|Should -BeFalse; $unknown.DisplayText|Should -Match 'Synthetic visibility gap'
        }
    }
    Describe 'Localized help overview and discoverability' {
        It 'returns exactly eight metadata objects without notices with PassThru in <Language>' -TestCases @(@{Language='es'},@{Language='en'}) {
            param($Language)
            $items=@(Help-VSO -Language $Language -PassThru 6>&1)
            $items.Count|Should -Be 8; @($items.Command|Sort-Object -Unique).Count|Should -Be 8
        }
        It 'explains separate application and module removal without adding success-stream records in <Language>' -TestCases @(@{Language='es'},@{Language='en'}) {
            param($Language)
            $information=@();$items=@(Help-VSO -Language $Language -InformationVariable information)
            $items.Count|Should -Be 8
            $text=$information|Out-String
            foreach($command in @('Reset-VSO','Reset-VSO -Full','Uninstall-PSResource VSO','Uninstall-Module VSO')) {$text|Should -Match ([regex]::Escape($command))}
        }
        It 'rejects Examples without Command with a localized actionable error' {
            {Help-VSO -Examples -Language es}|Should -Throw '*Especifica -Command*'
            {Help-VSO -Examples -Language en}|Should -Throw '*Specify -Command*'
            {Help-VSO -Command NoSuchCommand}|Should -Throw
        }
        It 'uses the actual command name, runtime syntax and numbered examples in <Language>' -TestCases @(@{Language='es'},@{Language='en'}) {
            param($Language)
            $text=Help-VSO -Command Install-VSO -Language $Language 6>&1|Out-String -Width 140
            $text|Should -Match 'Install-VSO \[\['
            $text|Should -Match '-WhatIf'; $text|Should -Match '-Confirm'
            $text|Should -Match $(if($Language -eq 'es'){'EJEMPLO 1'}else{'EXAMPLE 1'})
            $help=Help-VSO -Command Reset-VSO -Language $Language -PassThru
            $help.Description|Should -Match 'Uninstall-PSResource VSO'
            $help.Examples[-1].Code|Should -Be 'Uninstall-PSResource VSO'
        }
    }
}
Describe 'Native MAML contracts for all eight commands' {
    It 'matches actual syntax, parameters, positions and pipeline support for <Culture>' -TestCases @(@{Culture='en-US'},@{Culture='es-ES'}) {
        param($Culture)
        $module=Split-Path -Parent $env:VSO_MODULE_LAB_MANIFEST
        $xml=[xml][IO.File]::ReadAllText((Join-Path $module ($Culture+'/VSO-help.xml')))
        foreach($name in (Get-Module VSO).ExportedFunctions.Keys) {
            $node=$xml.SelectSingleNode('//*[local-name()="command"][*[local-name()="details"]/*[local-name()="name" and text()="'+$name+'"]]')
            $metadata=(Get-Command $name).ParameterSets[0].Parameters
            $xmlNames=@($node.SelectNodes('*[local-name()="parameters"]/*/*[local-name()="name"]')|ForEach-Object InnerText)
            $expected=@($metadata|Where-Object {$_.Name -notin @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable')})
            @(Compare-Object @($expected.Name) $xmlNames).Count|Should -Be 0
            foreach ($parameter in $expected) {
                $p=$node.SelectSingleNode('*[local-name()="parameters"]/*[*[local-name()="name" and text()="'+$parameter.Name+'"]]')
                $p.position|Should -Be $(if ($parameter.Position -lt 0) {'named'} else {[string]$parameter.Position})
                if ($parameter.ValueFromPipeline) {$p.pipelineInput|Should -Match 'ByValue'}
                if ($parameter.ValueFromPipelineByPropertyName) {$p.pipelineInput|Should -Match 'ByPropertyName'}
            }
            $examples=@($node.SelectNodes('*[local-name()="examples"]/*[local-name()="example"]'))
            $examples.Count|Should -BeGreaterThan 0
            foreach($e in $examples) {
                $e.SelectSingleNode('*[local-name()="title"]').InnerText|Should -Match $(if($Culture -eq 'es-ES'){'EJEMPLO \d+'}else{'EXAMPLE \d+'})
                $e.SelectSingleNode('*[local-name()="code"]').InnerText|Should -Not -BeNullOrEmpty
                $e.SelectSingleNode('*[local-name()="remarks"]/*[local-name()="para"]').InnerText|Should -Not -BeNullOrEmpty
            }
            $node.SelectNodes('*[local-name()="alertSet"]//*[local-name()="example"]').Count|Should -Be 0
        }
    }
    It 'keeps English root fallback byte-identical and generates MAML deterministically' {
        $module=Split-Path -Parent $env:VSO_MODULE_LAB_MANIFEST
        (Get-FileHash (Join-Path $module 'VSO-help.xml')).Hash|Should -Be (Get-FileHash (Join-Path $module 'en-US/VSO-help.xml')).Hash
        $copy=Join-Path $TestDrive 'help-input'; Copy-Item -LiteralPath $module -Destination $copy -Recurse
        $before=@(foreach($culture in @('en-US','es-ES')) {(Get-FileHash (Join-Path $copy ($culture+'/VSO-help.xml'))).Hash})
        & (Join-Path $env:VSO_MODULE_LAB_PROJECT 'build/Build-Help.ps1') -ModulePath $copy
        $after=@(foreach($culture in @('en-US','es-ES')) {(Get-FileHash (Join-Path $copy ($culture+'/VSO-help.xml'))).Hash})
        @(Compare-Object $before $after).Count|Should -Be 0
    }
    It 'renders native Examples and Full with independent example nodes' {
        foreach($name in @('Install-VSO','Reset-VSO','Update-VSO','Start-VSO','Stop-VSO','Get-VSOStatus','Get-VSOInstallation','Help-VSO')) {
            $full=Get-Help $name -Full; $examples=Get-Help $name -Examples
            @($examples.Examples.Example).Count|Should -Be @($full.Examples.Example).Count
            foreach($example in @($full.Examples.Example)) {
                ([string]$example.Code)|Should -Not -BeNullOrEmpty
                ($example.Remarks|Out-String)|Should -Not -BeNullOrEmpty
            }
            ($examples|Out-String -Width 140)|Should -Match 'EXAMPLE|EJEMPLO'
        }
    }
}
