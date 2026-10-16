function Start-VSO {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param([ValidateNotNullOrEmpty()][string]$Path,[ValidateNotNullOrEmpty()][string]$Version,[ValidateNotNullOrEmpty()][string]$Language,[switch]$AllowUnregistered,[switch]$PassThru)
    $context=New-VSOContext $Language
    Assert-VSOPlatform $context
    $installation=Select-VSOInstallation $context $Path $Version -AllowManual:$AllowUnregistered
    $activity=Get-VSOProcesses $installation.ApplicationPath $context $installation.Receipt
    if (-not $activity.Reliable) { Throw-VSOError $context ProcessUnknown }
    if ($activity.Processes.Count) {
        if ($PassThru) { [pscustomobject]@{ Path=$installation.Path; Version=$installation.Version; AlreadyRunning=$true; ProcessIds=@($activity.Processes.ProcessId) } }
        else { Write-Information $context.Text.AlreadyRunning -InformationAction Continue }
        return
    }
    if ($PSCmdlet.ShouldProcess($installation.Path,$context.Text.Launch)) {
        $lock=Enter-VSOLock $installation.Path $context
        try { Assert-VSOIdle $installation.Path $context $installation.Receipt -ApplicationPath $installation.ApplicationPath; $result=Invoke-VSOLauncher $installation $context }
        finally { $lock.Dispose() }
        if ($PassThru) { $result } else { Write-Information $context.Text.Started -InformationAction Continue }
    }
}
