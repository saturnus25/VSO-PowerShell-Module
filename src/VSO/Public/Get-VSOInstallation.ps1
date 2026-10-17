function Get-VSOInstallation {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$Path,[ValidateSet('CurrentUser','AllUsers')][string]$Scope,[ValidateNotNullOrEmpty()][string]$Version,[ValidateNotNullOrEmpty()][string]$Language,[switch]$Quiet)
    begin {
        $context=New-VSOContext $Language -Quiet:$Quiet
        Assert-VSOPlatform $context
        if ($Version) { $Version=(ConvertTo-VSOVersion $Version $context).Text }
    }
    process {
        try { Get-VSOInstallationsInternal $context $Path $Scope $Version }
        finally { Write-VSOProgress $context Enumerate -Completed }
    }
}
