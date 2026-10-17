@{
    RootModule = 'VSO.psm1'
    ModuleVersion = '1.0.2'
    GUID = '97ce321c-99d7-4797-b4a8-c7dc982537fc'
    Author = 'saturnus25'
    CompanyName = 'saturnus25'
    Copyright = 'Copyright (c) 2026 saturnus25'
    Description = 'Official installation and lifecycle manager for Vico Safe Optimizer. Windows 11 x64.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @('Install-VSO','Start-VSO','Stop-VSO','Update-VSO','Get-VSOStatus','Get-VSOInstallation','Reset-VSO','Help-VSO')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    FormatsToProcess = @('VSO.format.ps1xml')
    PrivateData = @{
        PSData = @{
            Tags = @('Windows','VSO','Installer','Management')
            LicenseUri = 'https://github.com/saturnus25/VSO-PowerShell-Module/blob/v1.0.2/LICENSE'
            ProjectUri = 'https://github.com/saturnus25/VSO-PowerShell-Module'
            ReleaseNotes = 'Structured NotInstalled status with localized native formatting, pipeline discovery, clearer numbered native help examples, complete parameter metadata and separate application/module removal guidance. See validation for exact-package acceptance.'
            RequireLicenseAcceptance = $false
        }
    }
}
