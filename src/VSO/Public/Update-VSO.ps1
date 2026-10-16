function Update-VSO {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param([ValidateNotNullOrEmpty()][string]$Path,[ValidateNotNullOrEmpty()][string]$Version,[switch]$Prerelease,[ValidateNotNullOrEmpty()][string]$AssetName,[switch]$Force,[switch]$Quiet,[ValidateNotNullOrEmpty()][string]$Language,[switch]$PassThru)
    $context=New-VSOContext $Language -Quiet:$Quiet
    Assert-VSOQuietConfirmation $context $PSBoundParameters
    Assert-VSOPlatform $context
    if ($Quiet -or ($Force -and -not $PSBoundParameters.ContainsKey('Confirm'))) { $ConfirmPreference='None' }
    $installation=Select-VSOInstallation $context $Path -AllowDamaged -AllowMissing
    if (-not $PSCmdlet.ShouldProcess($installation.Path,$context.Text.Update)) { return }
    $release=Get-VSORelease $context $Version -Prerelease:$Prerelease -AssetName $AssetName
    if ($installation.State -eq 'Ready' -and -not $Force -and (Compare-VSOVersion $release.Version $installation.Version $context) -le 0) {
        if ($PassThru) { [pscustomobject]@{ Changed=$false; Path=$installation.Path; Version=$installation.Version; Message=$context.Text.Current } }
        elseif (-not $Quiet) { Write-Information $context.Text.Current -InformationAction Continue }
        return
    }
    if ($installation.Scope -eq 'AllUsers' -and -not (Test-VSOAdministrator)) {
        $result=Invoke-VSOElevation 'Update-VSO' @{ Path=$installation.Path; Version=$release.Version; Prerelease=[bool]$Prerelease; AssetName=$release.AssetName; Language=$context.Language; Force=[bool]$Force } $context
    } else {
        $options=[pscustomobject]@{ Path=$installation.Path; Scope=$installation.Scope }
        $result=Invoke-VSOInstallTransaction $options $release $context -Force:$Force -Update
    }
    if ($PassThru) { $result } elseif (-not $Quiet) { Write-Information $context.Text.Updated -InformationAction Continue }
}
