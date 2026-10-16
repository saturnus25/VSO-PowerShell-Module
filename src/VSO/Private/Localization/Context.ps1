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
