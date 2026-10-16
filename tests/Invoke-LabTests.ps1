[CmdletBinding()]
param([switch]$IsolatedLab,[string]$ModulePath,[switch]$EnableNetwork)
$ErrorActionPreference='Stop'
if (-not $IsolatedLab) { throw 'Dynamic tests require explicit -IsolatedLab authorization in a disposable Windows VM.' }
$computer=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
if ($computer.Model -notmatch 'Virtual Machine|VMware|VirtualBox|KVM|QEMU|Parallels') { throw 'A recognized isolated virtual machine is required. Do not run this test suite on the development PC.' }
Import-Module Pester -MinimumVersion 5.5 -MaximumVersion 5.99 -ErrorAction Stop
$project=Split-Path -Parent $PSScriptRoot
if (-not $ModulePath) { $ModulePath=Join-Path $project 'src/VSO/VSO.psd1' }
$ModulePath=(Resolve-Path -LiteralPath $ModulePath).ProviderPath
$saved=@{Authorized=$env:VSO_MODULE_LAB_AUTHORIZED;Project=$env:VSO_MODULE_LAB_PROJECT;Manifest=$env:VSO_MODULE_LAB_MANIFEST;Network=$env:VSO_MODULE_LAB_NETWORK}
try {
    $env:VSO_MODULE_LAB_AUTHORIZED='1'; $env:VSO_MODULE_LAB_PROJECT=$project; $env:VSO_MODULE_LAB_MANIFEST=$ModulePath
    $env:VSO_MODULE_LAB_NETWORK=[string][bool]$EnableNetwork
    # InModuleScope is evaluated during Pester discovery, before BeforeAll runs.
    # Load once here so discovery and execution share the same module instance.
    # Different src/dist/package paths can coexist under the same module name.
    Get-Module -Name VSO -All|Remove-Module -Force -ErrorAction Stop
    Import-Module -Name $ModulePath -Force -ErrorAction Stop
    $configuration=New-PesterConfiguration
    $configuration.Run.Path=$PSScriptRoot; $configuration.Run.PassThru=$true
    $configuration.Output.Verbosity='Detailed'
    $configuration.TestResult.Enabled=$true
    $results=Join-Path $project 'TestResults'; [void][IO.Directory]::CreateDirectory($results)
    $edition=$PSVersionTable.PSEdition; $kind=if ($ModulePath -match '[\\/]dist[\\/]') { 'dist' } elseif ($ModulePath -match '[\\/]src[\\/]') { 'src' } else { 'package' }
    $configuration.TestResult.OutputPath=Join-Path $results ($edition+'-'+$PSVersionTable.PSVersion+'-'+$kind+'.xml')
    $result=Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { throw 'Lab tests did not pass. Inspect the private TestResults artifact.' }
    $result
} finally {
    $env:VSO_MODULE_LAB_AUTHORIZED=$saved.Authorized; $env:VSO_MODULE_LAB_PROJECT=$saved.Project
    $env:VSO_MODULE_LAB_MANIFEST=$saved.Manifest; $env:VSO_MODULE_LAB_NETWORK=$saved.Network
}
