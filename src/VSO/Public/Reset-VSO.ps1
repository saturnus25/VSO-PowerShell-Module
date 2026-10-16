function Reset-VSO {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param([ValidateNotNullOrEmpty()][string]$Path,[ValidateNotNullOrEmpty()][string]$Version,[switch]$Full,[switch]$RemoveBackups,[switch]$AcknowledgeBackupLoss,[switch]$Force,[switch]$Quiet,[ValidateNotNullOrEmpty()][string]$Language,[switch]$PassThru)
    $context=New-VSOContext $Language -Quiet:$Quiet
    Assert-VSOQuietConfirmation $context $PSBoundParameters
    Assert-VSOPlatform $context
    if ($RemoveBackups -and (-not $Full -or -not $AcknowledgeBackupLoss)) { Throw-VSOError $context BackupIntent }
    if ($Quiet -and -not $Force -and -not $WhatIfPreference) { Throw-VSOError $context QuietDestructive }
    if ($Quiet -or ($Force -and -not $PSBoundParameters.ContainsKey('Confirm'))) { $ConfirmPreference='None' }
    $installation=Select-VSOInstallation $context $Path $Version -AllowDamaged
    $plan=Get-VSORemovalPlan $installation $context -Full:$Full -RemoveBackups:$RemoveBackups
    if (-not $Quiet) { Write-Warning $context.Text.FullWarning; if ($RemoveBackups) { Write-Warning $context.Text.BackupWarning } }
    # PassThru WhatIf returns the exact file plan without creating locks or temp files.
    $description=$context.Text.Reset+[Environment]::NewLine+$context.Text.RemovalList+($plan.Remove.Path -join ', ')+[Environment]::NewLine+$context.Text.PreserveList+($plan.Preserve -join ', ')
    if ($plan.PSObject.Properties['Directories']) { $description+=[Environment]::NewLine+$context.Text.DirectoryList+($plan.Directories -join ', ') }
    if ($plan.PSObject.Properties['Protected']) { $description+=[Environment]::NewLine+(@($plan.Protected|ForEach-Object {$_.Path+' ['+$_.Reason+'; '+$_.Ownership+']'}) -join [Environment]::NewLine) }
    if (-not $Quiet -and -not $WhatIfPreference -and (Test-VSOInteractive $context)) { Write-Information $description -InformationAction Continue }
    if (-not $PSCmdlet.ShouldProcess($description,$context.Text.Reset)) { if ($PassThru) { $plan }; return }
    if (-not (Test-VSOInteractive $context) -and -not $Force) { Throw-VSOError $context QuietDestructive }
    if ($installation.Scope -eq 'AllUsers' -and -not (Test-VSOAdministrator)) {
        $result=Invoke-VSOElevation 'Reset-VSO' @{ Path=$installation.Path; Full=[bool]$Full; RemoveBackups=[bool]$RemoveBackups; AcknowledgeBackupLoss=[bool]$AcknowledgeBackupLoss; Force=$true; Language=$context.Language } $context
    } else { $result=Invoke-VSORemoval $plan $context }
    if ($PassThru) { $result } elseif (-not $Quiet) { Write-Information $context.Text.Removed -InformationAction Continue }
}
