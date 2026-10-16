@{
    RootModule = 'VSO.psm1'
    ModuleVersion = '1.0.1'
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
    PrivateData = @{
        PSData = @{
            Tags = @('Windows','VSO','Installer','Management')
            LicenseUri = 'https://github.com/saturnus25/VSO-PowerShell-Module/blob/v1.0.1/LICENSE'
            ProjectUri = 'https://github.com/saturnus25/VSO-PowerShell-Module'
            ReleaseNotes = 'Metadata and documentation patch: shorter package description and canonical PowerShell capitalization in installation examples. Runtime behavior is unchanged. See the tagged release for exact-package acceptance.'
            RequireLicenseAcceptance = $false
        }
    }
}
