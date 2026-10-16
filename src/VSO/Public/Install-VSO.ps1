function Install-VSO {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [ValidateNotNullOrEmpty()][string]$Path,
        [ValidateSet('CurrentUser','AllUsers')][string]$Scope,
        [switch]$AllUsers,
        [ValidateNotNullOrEmpty()][string]$Version,
        [switch]$Prerelease,
        [ValidateNotNullOrEmpty()][string]$AssetName,
        [switch]$Force, [switch]$Quiet,
        [ValidateNotNullOrEmpty()][string]$Language,
        [switch]$PassThru
    )
    $context=New-VSOContext $Language -Quiet:$Quiet
    Assert-VSOQuietConfirmation $context $PSBoundParameters
    Assert-VSOPlatform $context
    if ($Version) { $null=ConvertTo-VSOVersion $Version $context }
    if ($Quiet -or ($Force -and -not $PSBoundParameters.ContainsKey('Confirm'))) { $ConfirmPreference='None' }
    $options=Resolve-VSOInstallOptions $context $Path $Scope -AllUsers:$AllUsers -Preview:$WhatIfPreference
    if (-not $PSCmdlet.ShouldProcess($options.Path,$context.Text.Install)) { return }
    $release=Get-VSORelease $context $Version -Prerelease:$Prerelease -AssetName $AssetName
    if ($options.Scope -eq 'AllUsers' -and -not (Test-VSOAdministrator)) {
        $arguments=@{ Path=$options.Path; Scope='AllUsers'; Version=$release.Version; Prerelease=[bool]$Prerelease; Language=$context.Language; Force=[bool]$Force; AssetName=$release.AssetName }
        $result=Invoke-VSOElevation 'Install-VSO' $arguments $context
    } else { $result=Invoke-VSOInstallTransaction $options $release $context -Force:$Force }
    if ($PassThru) { $result } elseif (-not $Quiet) { Write-Information $context.Text.Installed -InformationAction Continue }
}
