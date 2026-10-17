function Get-VSOStatus {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$Path,[ValidateSet('CurrentUser','AllUsers')][string]$Scope,[ValidateNotNullOrEmpty()][string]$Version,[ValidateNotNullOrEmpty()][string]$Language,[switch]$Quiet)
    begin {
        $context=New-VSOContext $Language -Quiet:$Quiet
        Assert-VSOPlatform $context
        if ($Version) { $Version=(ConvertTo-VSOVersion $Version $context).Text }
    }
    process {
        try {
            $items=@(Get-VSOInstallationsInternal $context $Path $Scope $Version)
            if ($items.Count -eq 0) {
                # A query summary is a status result, never an installation record.
                $message=if ($Path -or $Scope -or $Version) { $context.Text.NoMatchingInstallation } else { $context.Text.NoInstallation }
                $result=[pscustomobject]@{ PSTypeName='VSO.Status'; Kind='Summary'; Id=$null; Path=$null; ApplicationPath=$null; Version=$null; Generation=$null; Scope=$null; Managed=$false; InstallationState='NotInstalled'; InstallationStateDisplay=$context.Text.NotInstalled; ProcessState='Idle'; ProcessStateDisplay=$context.Text.Idle; Running=$false; ProcessIds=@(); ProcessVisibilityReliable=$true; ProcessDiagnostic=$null; Diagnostic=$null; SharedRecoveryPreserved=$true; RequestedPath=$(if ($Path) { $Path } else { $null }); RequestedScope=$(if ($Scope) { $Scope } else { $null }); RequestedVersion=$(if ($Version) { $Version } else { $null }); Message=$message; NextAction='Install-VSO' }
                Add-VSOStatusDisplay $result $context
            }
            foreach ($item in $items) {
                $activity=Get-VSOProcesses $item.ApplicationPath $context $item.Receipt
                $state=if (-not $activity.Reliable) { 'Unknown' } elseif ($activity.Processes.Count) { 'Running' } else { 'Idle' }
                $result=[pscustomobject]@{ PSTypeName='VSO.Status'; Kind='Installation'; Id=$item.Id; Path=$item.Path; ApplicationPath=$item.ApplicationPath; Version=$(if ($item.Version -eq 'Unknown') { $null } else { $item.Version }); Generation=$item.Generation; Scope=$item.Scope; Managed=$item.Managed; InstallationState=$item.State; InstallationStateDisplay=$item.StateDisplay; ProcessState=$state; ProcessStateDisplay=$context.Text[$state]; Running=$(if ($activity.Reliable) { [bool]($activity.Processes.Count -gt 0) } else { $null }); ProcessIds=@($activity.Processes | ForEach-Object ProcessId); ProcessVisibilityReliable=$activity.Reliable; ProcessDiagnostic=$activity.Diagnostic; Diagnostic=$item.Diagnostic; SharedRecoveryPreserved=$true; RequestedPath=$(if ($Path) { $Path } else { $null }); RequestedScope=$(if ($Scope) { $Scope } else { $null }); RequestedVersion=$(if ($Version) { $Version } else { $null }); Message=$null; NextAction=$null }
                Add-VSOStatusDisplay $result $context
            }
        } finally { Write-VSOProgress $context Enumerate -Completed }
    }
}
