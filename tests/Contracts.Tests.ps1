if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
Describe 'Public module contract' {
    BeforeAll {
        $expected=@('Install-VSO','Start-VSO','Stop-VSO','Update-VSO','Get-VSOStatus','Get-VSOInstallation','Reset-VSO','Help-VSO')
    }
    It 'has a valid independent manifest and public attribution' {
        $m=Test-ModuleManifest $env:VSO_MODULE_LAB_MANIFEST
        $m.Version.ToString()|Should -Be '1.0.2'
        $m.Name|Should -BeExactly 'VSO'
        $m.RootModule|Should -BeExactly 'VSO.psm1'
        $m.PrivateData.PSData.LicenseUri|Should -BeExactly 'https://github.com/saturnus25/VSO-PowerShell-Module/blob/v1.0.2/LICENSE'
        $m.Author|Should -BeExactly 'saturnus25'
        $m.CompanyName|Should -BeExactly 'saturnus25'
        $m.PowerShellVersion.ToString()|Should -Be '5.1'
    }
    It 'exports exactly the eight public advanced functions' {
        $commands=@(Get-Command -Module VSO)
        @(Compare-Object $expected $commands.Name).Count|Should -Be 0
        foreach ($c in $commands) { $c.CmdletBinding|Should -BeTrue }
    }
    It 'does not export private functions, aliases or variables' {
        (Get-Module VSO).ExportedAliases.Count|Should -Be 0
        (Get-Module VSO).ExportedVariables.Count|Should -Be 0
        Get-Command Invoke-VSOHttp -ErrorAction SilentlyContinue|Should -BeNullOrEmpty
    }
    It 'does not change caller preferences or the working directory on import' {
        $before=Get-Location; $progress=$ProgressPreference; $errorSetting=$ErrorActionPreference
        Import-Module $env:VSO_MODULE_LAB_MANIFEST -Force
        (Get-Location).Path|Should -Be $before.Path
        $ProgressPreference|Should -Be $progress
        $ErrorActionPreference|Should -Be $errorSetting
    }
    It 'has ShouldProcess only on mutating commands' {
        foreach ($name in @('Install-VSO','Start-VSO','Stop-VSO','Update-VSO','Reset-VSO')) { (Get-Command $name).Parameters.ContainsKey('WhatIf')|Should -BeTrue }
        foreach ($name in @('Get-VSOStatus','Get-VSOInstallation','Help-VSO')) { (Get-Command $name).Parameters.ContainsKey('WhatIf')|Should -BeFalse }
    }
    It 'rejects invalid scope and unknown parameters' {
        {Install-VSO -Scope Other}|Should -Throw
        {Start-VSO -Quiet}|Should -Throw
    }
    It 'renders native external help and examples' {
        foreach ($name in $expected) {
            $h=Get-Help $name -Full
            $h.Name|Should -Be $name
            $h.Description|Should -Not -BeNullOrEmpty
            $h.Examples.Example|Should -Not -BeNullOrEmpty
            @($h.Examples.Example).Count|Should -BeGreaterThan 0
        }
    }
    It 'renders explicit Spanish help from the common source' {
        $h=Help-VSO -Command Install-VSO -Language es -PassThru
        $h.Language|Should -Be 'es-ES'
        $h.Synopsis|Should -Match 'Descarga'
        $h.Parameters.Contains('Scope')|Should -BeTrue
    }
}
InModuleScope VSO {
    BeforeAll { $script:ctx=New-VSOContext en -Quiet }
    Describe 'Localization and semantics' {
        It 'requires x64 hardware rather than accepting any 64-bit architecture' {
            Mock Get-CimInstance {[pscustomobject]@{BuildNumber='26100';ProductType=1}} -ParameterFilter {$ClassName -eq 'Win32_OperatingSystem'}
            Mock Get-CimInstance {[pscustomobject]@{Architecture=12}} -ParameterFilter {$ClassName -eq 'Win32_Processor'}
            {Assert-VSOPlatform $script:ctx}|Should -Throw '*x64*'
            Mock Get-CimInstance {[pscustomobject]@{Architecture=9}} -ParameterFilter {$ClassName -eq 'Win32_Processor'}
            {Assert-VSOPlatform $script:ctx}|Should -Not -Throw
        }
        It 'uses explicit language fallback' {
            (New-VSOContext es-MX).Language|Should -Be 'es-ES'
            (New-VSOContext fr-FR).Language|Should -Be 'en-US'
            (New-VSOContext en).Language|Should -Be 'en-US'
        }
        It 'has identical message keys in both languages' {
            $en=Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'en-US/Messages.psd1')
            $es=Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'es-ES/Messages.psd1')
            @(Compare-Object @($en.Keys) @($es.Keys)).Count|Should -Be 0
        }
        It 'raises a terminating localized cancellation error' {
            {Throw-VSOError (New-VSOContext es) Cancelled}|Should -Throw '*Has cancelado*'
            {Throw-VSOError $script:ctx Cancelled}|Should -Throw '*cancelled*'
        }
        It 'orders semantic versions and build metadata correctly' -TestCases @(
            @{A='1.10.0';B='1.2.9';Expected=1},@{A='1.0.0';B='1.0.0-rc.1';Expected=1},
            @{A='1.0.0-alpha.2';B='1.0.0-alpha.10';Expected=-1},@{A='1.0.0+build';B='1.0.0';Expected=0},
            @{A='2.0.0';B='3.0.0';Expected=-1},@{A='999999999999999999999.0.0';B='2.0.0';Expected=1}
        ) {param($A,$B,$Expected) Compare-VSOVersion $A $B $script:ctx|Should -Be $Expected}
        It 'rejects malformed semantic versions' -TestCases @(@{V='1.2'},@{V='01.2.3'},@{V='1.2.3-01'},@{V='latest'}) {param($V) {ConvertTo-VSOVersion $V $script:ctx}|Should -Throw}
        It 'resolves CurrentUser without using System32 as its default' {
            Push-Location (Join-Path $env:SystemRoot 'System32')
            try {
                $result=Resolve-VSOInstallOptions $script:ctx
                $result.Scope|Should -Be 'CurrentUser'
                $result.Path|Should -Be (Join-Path $env:LOCALAPPDATA 'Programs\VSO')
            } finally {Pop-Location}
        }
        It 'resolves AllUsers and rejects conflicting scope' {
            (Resolve-VSOInstallOptions $script:ctx -AllUsers).Path|Should -Be (Join-Path $env:ProgramFiles 'VSO')
            {Resolve-VSOInstallOptions $script:ctx -Scope CurrentUser -AllUsers}|Should -Throw
        }
        It 'never prompts in Quiet mode' {
            Mock Request-VSOChoice {throw 'Prompt unexpectedly called'}
            Mock Request-VSOFolder {throw 'Picker unexpectedly called'}
            $null=Resolve-VSOInstallOptions $script:ctx
            Should -Invoke Request-VSOChoice -Times 0
            Should -Invoke Request-VSOFolder -Times 0
            {Request-VSOChoice $script:ctx 'title' 'message' @('A')}|Should -Throw
        }
        It 'asks for destination after an explicit scope without repeating the scope question' -TestCases @(@{Scope='CurrentUser'},@{Scope='AllUsers'}) {
            param($Scope)
            $interactive=New-VSOContext en
            Mock Test-VSOInteractive {$true}
            Mock Request-VSOChoice {0}
            $resolved=Resolve-VSOInstallOptions $interactive -Scope $Scope
            $resolved.Scope|Should -Be $Scope
            Should -Invoke Request-VSOChoice -Times 1 -Exactly -ParameterFilter {$Title -eq $interactive.Text.DefaultTitle}
        }
        It 'resolves a path alone as CurrentUser with no choices or picker' {
            Mock Test-VSOInteractive {$true}
            Mock Request-VSOChoice {throw 'Unexpected choice'}
            Mock Request-VSOFolder {throw 'Unexpected picker'}
            $path=Join-Path $env:LOCALAPPDATA 'Programs/VSO custom á'
            (Resolve-VSOInstallOptions (New-VSOContext en) -Path $path).Scope|Should -Be CurrentUser
            (Resolve-VSOInstallOptions (New-VSOContext en) -Path $path -AllUsers).Scope|Should -Be AllUsers
            Should -Invoke Request-VSOChoice -Times 0
        }
        It 'honors cancellation and the custom picker after explicit AllUsers' {
            Mock Test-VSOInteractive {$true}
            Mock Request-VSOChoice {2}
            {Resolve-VSOInstallOptions (New-VSOContext en) -AllUsers}|Should -Throw '*cancelled*'
            Mock Request-VSOChoice {1}
            Mock Request-VSOFolder {Join-Path $env:ProgramFiles 'VSO space á'}
            (Resolve-VSOInstallOptions (New-VSOContext en) -AllUsers).Path|Should -Be (Join-Path $env:ProgramFiles 'VSO space á')
        }
        It 'emits a real parent activity and a child percentage tied to measured work' {
            Mock Write-Progress {}
            Write-VSOProgress (New-VSOContext en) Download 25 100
            Should -Invoke Write-Progress -Times 1 -Exactly -ParameterFilter {$Id -eq 731}
            Should -Invoke Write-Progress -Times 1 -Exactly -ParameterFilter {$Id -eq 732 -and $ParentId -eq 731 -and $PercentComplete -eq 25}
        }
        It 'completes both progress levels' {
            Mock Write-Progress {}
            Write-VSOProgress (New-VSOContext en) Verify -Completed
            Should -Invoke Write-Progress -Times 2 -Exactly -ParameterFilter {$Completed}
        }
        It 'suppresses both progress levels in Quiet' {
            Mock Write-Progress {}
            Write-VSOProgress $script:ctx Download 25 100
            Write-VSOProgress $script:ctx Verify -Completed
            Should -Invoke Write-Progress -Times 0
        }
    }
}
