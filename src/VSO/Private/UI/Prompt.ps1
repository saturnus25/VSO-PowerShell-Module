function Test-VSOInteractive {
    param($Context)
    if ($Context.Quiet -or -not [Environment]::UserInteractive) { return $false }
    if ([Environment]::GetCommandLineArgs() -contains '-NonInteractive') { return $false }
    try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
    return ($null -ne $Host.UI)
}

function Request-VSOChoice {
    param($Context, [string]$Title, [string]$Message, [string[]]$Options, [int]$Default = 0)
    if (-not (Test-VSOInteractive $Context)) { Throw-VSOError $Context InteractiveRequired }
    $choices = [Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]]::new()
    foreach ($option in $Options) { $choices.Add([Management.Automation.Host.ChoiceDescription]::new($option)) }
    try { return $Host.UI.PromptForChoice($Title,$Message,$choices,$Default) }
    catch { Throw-VSOError $Context InteractiveRequired @() $_.Exception }
}

function Request-VSOFolder {
    param($Context)
    if (-not (Test-VSOInteractive $Context)) { Throw-VSOError $Context InteractiveRequired }
    $selection = $null; $dialogAvailable = $false
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq [Threading.ApartmentState]::STA) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $dialog = [Windows.Forms.FolderBrowserDialog]::new()
            try {
                $dialog.Description=$Context.Text.FolderTitle; $dialog.ShowNewFolderButton=$true
                $result=$dialog.ShowDialog(); $dialogAvailable=$true
                if ($result -eq [Windows.Forms.DialogResult]::OK) { $selection=$dialog.SelectedPath }
            } finally { $dialog.Dispose() }
        } catch { Write-Verbose $_.Exception.Message }
    }
    # A console fallback avoids changing apartments or starting another GUI process.
    if (-not $dialogAvailable) { $selection=Read-Host -Prompt $Context.Text.PathPrompt }
    if ([string]::IsNullOrWhiteSpace($selection)) { Throw-VSOError $Context Cancelled }
    return $selection
}

function Resolve-VSOInstallOptions {
    param($Context, [string]$Path, [string]$Scope, [switch]$AllUsers, [switch]$Preview)
    if ($AllUsers -and $Scope -and $Scope -ne 'AllUsers') { Throw-VSOError $Context ScopeConflict }
    if ($AllUsers) { $Scope='AllUsers' }
    if (-not $Scope) {
        $Scope='CurrentUser'
        if (-not $Path -and -not $Preview -and (Test-VSOInteractive $Context)) {
            $choice=Request-VSOChoice $Context $Context.Text.ScopeTitle $Context.Text.ScopePrompt @($Context.Text.UserChoice,$Context.Text.AllChoice,$Context.Text.CancelChoice)
            if ($choice -eq 2) { Throw-VSOError $Context Cancelled }
            if ($choice -eq 1) { $Scope='AllUsers' }
        }
    }
    if (-not $Path) {
        $Path=Get-VSODefaultPath $Scope $Context
        if (-not $Preview -and (Test-VSOInteractive $Context)) {
            $choice=Request-VSOChoice $Context $Context.Text.DefaultTitle ($Context.Text.DefaultPrompt + [Environment]::NewLine + $Path) @($Context.Text.YesChoice,$Context.Text.NoChoice,$Context.Text.CancelChoice)
            if ($choice -eq 2) { Throw-VSOError $Context Cancelled }
            if ($choice -eq 1) { $Path=Request-VSOFolder $Context }
        }
    }
    return [pscustomobject]@{ Path=(Resolve-VSOPath $Path $Context -Installation); Scope=$Scope }
}
