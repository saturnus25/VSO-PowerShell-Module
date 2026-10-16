function Get-VSOStatus {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding()]
    param([ValidateNotNullOrEmpty()][string]$Path,[ValidateSet('CurrentUser','AllUsers')][string]$Scope,[ValidateNotNullOrEmpty()][string]$Version,[ValidateNotNullOrEmpty()][string]$Language,[switch]$Quiet)
    $context=New-VSOContext $Language -Quiet:$Quiet
    Assert-VSOPlatform $context
    foreach ($item in @(Get-VSOInstallationsInternal $context $Path $Scope $Version)) {
        $activity=Get-VSOProcesses $item.ApplicationPath $context $item.Receipt
        $state=if (-not $activity.Reliable) { 'Unknown' } elseif ($activity.Processes.Count) { 'Running' } else { 'Idle' }
        [pscustomobject]@{ PSTypeName='VSO.Status'; Id=$item.Id; Path=$item.Path; ApplicationPath=$item.ApplicationPath; Version=$item.Version; Generation=$item.Generation; Scope=$item.Scope; Managed=$item.Managed; InstallationState=$item.State; InstallationStateDisplay=$item.StateDisplay; ProcessState=$state; ProcessStateDisplay=$context.Text[$state]; ProcessIds=@($activity.Processes | ForEach-Object ProcessId); ProcessVisibilityReliable=$activity.Reliable; ProcessDiagnostic=$activity.Diagnostic; Diagnostic=$item.Diagnostic; SharedRecoveryPreserved=$true }
    }
}
