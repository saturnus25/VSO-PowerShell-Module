function New-VSOContext {
    param([string]$Language, [switch]$Quiet)
    if ([string]::IsNullOrWhiteSpace($Language)) { $Language = $PSUICulture }
    $culture = if ($Language -match '^es(?:-|$)') { 'es-ES' } else { 'en-US' }
    $text = Import-PowerShellDataFile -LiteralPath (Join-Path $script:ModuleRoot ($culture + '/Messages.psd1'))
    return [pscustomobject]@{ Language=$culture; Text=$text; Quiet=[bool]$Quiet }
}

function Throw-VSOError {
    param($Context, [string]$Key, [object[]]$Arguments = @(), [Exception]$Inner)
    $message = [string]$Context.Text[$Key]
    if (-not $message) { $message = [string]$Context.Text.Failure }
    if ($Arguments.Count) { $message = $message -f $Arguments }
    else { $message = $message -replace '\{[0-9]+\}', '' }
    $ex = if ($Inner) { [InvalidOperationException]::new($message,$Inner) } else { [InvalidOperationException]::new($message) }
    $category = [Management.Automation.ErrorCategory]::InvalidOperation
    if ($Key -in @('Cancelled','UacCancelled')) { $category = [Management.Automation.ErrorCategory]::OperationStopped }
    throw [Management.Automation.ErrorRecord]::new($ex, ('VSO.'+$Key), $category, $null)
}

function Add-VSOStatusDisplay {
    param($Status,$Context)
    # Formatting reads only this presentation property. Raw state, nulls and
    # booleans remain available to Select-Object, filtering and serialization.
    $version=if ($null -eq $Status.Version) { $Context.Text.NotAvailable } else { $Status.Version }
    $path=if ($null -eq $Status.Path) { $Context.Text.NotAvailable } else { $Status.Path }
    $running=if ($null -eq $Status.Running) { $Context.Text.Unknown } elseif ($Status.Running) { $Context.Text.Yes } else { $Context.Text.No }
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add($Context.Text.StatusTitle); $lines.Add('')
    $labels=@($Context.Text.StatusLabel,$Context.Text.VersionLabel,$Context.Text.PathLabel,$Context.Text.RunningLabel)
    $width=($labels|Measure-Object -Property Length -Maximum).Maximum
    $values=@($Status.InstallationStateDisplay,$version,$path,$running)
    for ($index=0; $index -lt $labels.Count; $index++) { $lines.Add($labels[$index].PadRight($width)+' : '+$values[$index]) }
    if ($Status.Kind -eq 'Installation') { $lines.Add($Context.Text.ProcessLabel.PadRight($width)+' : '+$Status.ProcessStateDisplay) }
    if ($Status.Message) { $lines.Add(''); $lines.Add($Status.Message); $lines.Add($Context.Text.InstallHint) }
    foreach ($diagnostic in @($Status.Diagnostic,$Status.ProcessDiagnostic)) { if ($diagnostic) { $lines.Add(''); $lines.Add([string]$diagnostic) } }
    $Status|Add-Member -NotePropertyName DisplayText -NotePropertyValue ($lines -join [Environment]::NewLine)
    return $Status
}
