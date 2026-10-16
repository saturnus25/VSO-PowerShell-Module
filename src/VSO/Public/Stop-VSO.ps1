function Stop-VSO {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param([ValidateNotNullOrEmpty()][string]$Path,[ValidateNotNullOrEmpty()][string]$Version,[switch]$Force,[switch]$Quiet,[ValidateNotNullOrEmpty()][string]$Language,[switch]$PassThru)
    $context=New-VSOContext $Language -Quiet:$Quiet
    Assert-VSOQuietConfirmation $context $PSBoundParameters
    Assert-VSOPlatform $context
    if ($Quiet -or ($Force -and -not $PSBoundParameters.ContainsKey('Confirm'))) { $ConfirmPreference='None' }
    $installation=Select-VSOInstallation $context $Path $Version -AllowDamaged
    if (-not $installation.Receipt) { Throw-VSOError $context Corrupt @($installation.Diagnostic) }
    $activity=Get-VSOProcesses $installation.ApplicationPath $context $installation.Receipt
    if (-not $activity.Reliable) {
        if (-not $Force) { Throw-VSOError $context ProcessUnknown }
        if (-not (Test-VSOAdministrator) -and $PSCmdlet.ShouldProcess($installation.Path,$context.Text.Stop)) {
            $result=Invoke-VSOElevation 'Stop-VSO' @{ Path=$installation.Path; Force=$true; Language=$context.Language } $context
            if ($PassThru) { $result }; return
        }
        Throw-VSOError $context ProcessUnknown
    }
    if ($activity.Processes.Count -eq 0) {
        if ($PassThru) { [pscustomobject]@{ Changed=$false; Path=$installation.Path; ProcessIds=@() } }
        elseif (-not $Quiet) { Write-Information $context.Text.Idle -InformationAction Continue }
        return
    }
    # VSO7 exposes no verified clean-shutdown protocol. Do not send a shared console
    # window a close message: it could close unrelated tabs or interrupt Recovery.
    if (-not $Force -and -not $WhatIfPreference) { Throw-VSOError $context ForceStop }
    if ($PSCmdlet.ShouldProcess(($installation.Path+' | PID '+($activity.Processes.ProcessId -join ',')),$context.Text.Stop)) {
        $lock=Enter-VSOLock $installation.Path $context
        try { foreach ($process in @($activity.Processes | Sort-Object ProcessId -Descending)) { Stop-VSOAttributedProcess $process $context } }
        finally { $lock.Dispose() }
        if ($PassThru) { [pscustomobject]@{ PSTypeName='VSO.Result'; Changed=$true; Operation='Stop'; Path=$installation.Path; ProcessIds=@($activity.Processes.ProcessId); Forced=$true } }
        elseif (-not $Quiet) { Write-Information $context.Text.Stopped -InformationAction Continue }
    }
}
