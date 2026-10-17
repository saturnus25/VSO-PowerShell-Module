function Help-VSO {
    # .ExternalHelp VSO-help.xml
    [CmdletBinding()]
    param([ValidateSet('Install-VSO','Start-VSO','Stop-VSO','Update-VSO','Get-VSOStatus','Get-VSOInstallation','Reset-VSO','Help-VSO')][string]$Command,[switch]$Examples,[ValidateNotNullOrEmpty()][string]$Language,[switch]$PassThru)
    $context=New-VSOContext $Language
    if ($Examples -and -not $Command) { Throw-VSOError $context HelpExamplesCommand }
    $help=Import-PowerShellDataFile -LiteralPath (Join-Path $script:ModuleRoot ($context.Language+'/Help.psd1'))
    if (-not $Command) {
        if (-not $PassThru) { Write-Information ($context.Text.HelpIntro+[Environment]::NewLine+$context.Text.HelpHint+[Environment]::NewLine+[Environment]::NewLine+$context.Text.RemovalHint) -InformationAction Continue }
        foreach ($name in $script:PublicCommands) { [pscustomobject]@{ PSTypeName='VSO.CommandHelp'; Command=$name; Description=$help[$name].Synopsis } }
        return
    }
    $item=$help[$Command]
    $metadata=Get-Command -Name ('VSO\'+$Command) -ErrorAction Stop
    $parameters=[ordered]@{}
    foreach ($name in $metadata.Parameters.Keys) { if ($help.Parameters.ContainsKey($name)) { $parameters[$name]=$help.Parameters[$name] } }
    $result=[pscustomobject]@{ PSTypeName='VSO.Help'; Command=$Command; Language=$context.Language; Synopsis=$item.Synopsis; Description=$(if ($Examples) { $null } else { $item.Description }); Syntax=@($metadata.ParameterSets|ForEach-Object ToString); Parameters=$(if ($Examples) { $null } else { $parameters }); Defaults=$help.Defaults; Examples=$item.Examples; Permissions=$context.Text.Permissions; Compatibility=$context.Text.Compatibility; Safety=$context.Text.FullWarning }
    if ($PassThru) { return $result }
    # Human-readable presentation is separate from structured help metadata.
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add($Command); $lines.Add($item.Synopsis); $lines.Add('')
    if (-not $Examples) {
        $lines.Add($item.Description); $lines.Add(''); $lines.Add($context.Text.SyntaxLabel)
        foreach ($syntax in $result.Syntax) { $lines.Add('    '+$Command+' '+$syntax) }
        $lines.Add(''); $lines.Add($context.Text.ParametersLabel)
        foreach ($name in $parameters.Keys) {
            $lines.Add('    -'+$name); $lines.Add('        '+$parameters[$name])
            if ($help.Defaults.ContainsKey($name)) { $lines.Add('        '+$context.Text.DefaultLabel+' '+$help.Defaults[$name]) }
        }
    }
    $lines.Add(''); $lines.Add($context.Text.ExamplesLabel)
    $exampleNumber=0
    foreach ($example in $item.Examples) { $exampleNumber++; $lines.Add('    '+($context.Text.ExampleTitle -f $exampleNumber,$example.Title)); $lines.Add('        '+$example.Code); $lines.Add('        '+$example.Remarks); $lines.Add('') }
    $lines.Add($context.Text.PermissionsLabel+' '+$result.Permissions)
    $lines.Add($context.Text.CompatibilityLabel+' '+$result.Compatibility)
    $lines.Add($context.Text.SafetyLabel+' '+$result.Safety)
    Write-Information ($lines -join [Environment]::NewLine) -InformationAction Continue
}
