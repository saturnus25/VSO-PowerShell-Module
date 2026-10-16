function Get-VSOInstallation {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding()]
    param([ValidateNotNullOrEmpty()][string]$Path,[ValidateSet('CurrentUser','AllUsers')][string]$Scope,[ValidateNotNullOrEmpty()][string]$Version,[ValidateNotNullOrEmpty()][string]$Language,[switch]$Quiet)
    $context=New-VSOContext $Language -Quiet:$Quiet
    Assert-VSOPlatform $context
    try { Get-VSOInstallationsInternal $context $Path $Scope $Version }
    finally { Write-VSOProgress $context Enumerate -Completed }
}
