[CmdletBinding()]
param([string]$ProjectPath)
$ErrorActionPreference='Stop'
if (-not $ProjectPath) { $ProjectPath=Split-Path -Parent $PSScriptRoot }
$root=[IO.Path]::GetFullPath($ProjectPath); $module=Join-Path $root 'src/VSO'
$data=Import-PowerShellDataFile -LiteralPath (Join-Path $module 'VSO.psd1')
$functions=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$asts=[Collections.Generic.List[object]]::new(); $files=0
foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1','.psd1') -and $_.FullName -notmatch '[\\/](dist|TestResults|\.work|\.git)[\\/]'})) {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count) {throw ('Parser error in '+$file.Name+': '+($errors.Message -join '; '))}
    $bytes=[IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length-lt3-or$bytes[0]-ne239-or$bytes[1]-ne187-or$bytes[2]-ne191){throw ('Missing UTF-8 BOM: '+$file.Name)}
    $files++
    if ($file.FullName.StartsWith($module+'\',[StringComparison]::OrdinalIgnoreCase)) {
        $asts.Add([pscustomobject]@{File=$file.FullName;Ast=$ast})
        foreach ($f in @($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]},$true))) {if(-not$functions.Add($f.Name)){throw ('Duplicate runtime function: '+$f.Name)}}
    }
}
$banned=@('Invoke-Expression','Set-ItemProperty','Remove-ItemProperty','Set-Service','New-Service','Remove-Service','Set-MpPreference','Add-MpPreference','Set-ExecutionPolicy','Remove-AppxPackage','Remove-AppxProvisionedPackage','bcdedit','bcdedit.exe','powercfg','powercfg.exe','netsh','netsh.exe','schtasks','schtasks.exe','reg.exe','sc.exe')
foreach ($source in $asts) {
    foreach ($command in @($source.Ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]},$true))) {
        $name=$command.GetCommandName()
        if ($name -in $banned) {throw ('Forbidden system mutation command: '+$name)}
        if ($name -match '^[A-Za-z]+-VSO' -and -not $functions.Contains($name)) {throw ('Undefined internal command: '+$name)}
    }
}
$rootAst=@($asts|Where-Object {$_.File.EndsWith('VSO.psm1')})[0].Ast
$partsAssignment=$rootAst.Find({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$parts'},$false)
foreach ($part in @($partsAssignment.Right.FindAll({param($n)$n-is[Management.Automation.Language.StringConstantExpressionAst]},$true))) {
    if (-not [IO.File]::Exists((Join-Path $module ('Private/'+$part.Value+'.ps1')))) {throw 'Missing loader dependency.'}
}
foreach ($culture in @('en-US','es-ES')) {
    $help=Import-PowerShellDataFile -LiteralPath (Join-Path $module ($culture+'/Help.psd1'))
    $messages=Import-PowerShellDataFile -LiteralPath (Join-Path $module ($culture+'/Messages.psd1'))
    $maml=[xml][IO.File]::ReadAllText((Join-Path $module ($culture+'/VSO-help.xml')))
    if (@($maml.SelectNodes('//*[local-name()="command"]')).Count -ne $data.FunctionsToExport.Count) {throw 'Incomplete native help.'}
    foreach ($name in $data.FunctionsToExport) {
        $source=@($asts|Where-Object {$_.File.EndsWith('Public\'+$name+'.ps1')})[0]
        $function=$source.Ast.Find({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-eq$name},$false)
        foreach ($p in $function.Body.ParamBlock.Parameters) {if(-not$help.Parameters.ContainsKey($p.Name.VariablePath.UserPath)){throw 'Undocumented public parameter.'}}
        $xmlCommand=$maml.SelectSingleNode('//*[local-name()="command"][*[local-name()="details"]/*[local-name()="name" and text()="'+$name+'"]]')
        if(-not$xmlCommand){throw 'Missing MAML command.'}
        $xmlNames=@($xmlCommand.SelectNodes('*[local-name()="parameters"]/*[local-name()="parameter"]/*[local-name()="name"]')|ForEach-Object InnerText)
        $parameterNames=@($function.Body.ParamBlock.Parameters|ForEach-Object {$_.Name.VariablePath.UserPath})
        if ($name -in @('Install-VSO','Start-VSO','Stop-VSO','Update-VSO','Reset-VSO')) { $parameterNames+=@('WhatIf','Confirm') }
        if(@(Compare-Object $parameterNames $xmlNames).Count){throw ('MAML parameter mismatch: '+$name)}
        if (-not $help[$name].Synopsis -or -not $help[$name].Description -or -not $help[$name].Examples.Count) {throw 'Incomplete structured help.'}
        $examples=@($xmlCommand.SelectNodes('*[local-name()="examples"]/*[local-name()="example"]'))
        if ($examples.Count -ne $help[$name].Examples.Count -or $xmlCommand.SelectNodes('*[local-name()="alertSet"]//*[local-name()="example"]').Count) {throw 'Invalid native example structure.'}
    }
    # Every literal localization key used by an error/progress helper must exist.
    foreach ($source in $asts) {
        foreach ($call in @($source.Ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]-and$n.GetCommandName()-in@('Throw-VSOError','Write-VSOProgress')},$true))) {
            if($call.CommandElements.Count-gt2-and$call.CommandElements[2]-is[Management.Automation.Language.StringConstantExpressionAst]){
                $key=$call.CommandElements[2].Value;if(-not$messages.ContainsKey($key)){throw ('Missing translated key: '+$key)}
            }
        }
    }
}
$elevation=@($asts|Where-Object {$_.File.EndsWith('Security\Elevation.ps1')})[0].Ast
$template=$elevation.Find({param($n)$n-is[Management.Automation.Language.StringConstantExpressionAst]-and$n.Value.Contains('__REQUEST__')-and$n.Value.Contains('$ErrorActionPreference')},$true)
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($template.Value.Replace('__REQUEST__','e30='),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'The fixed UAC bootstrap does not parse.'}
$sourceParts=@($asts|Where-Object {$_.File.EndsWith('Processes\Processes.ps1')})[0].Ast
$csharp=$sourceParts.Find({param($n)$n-is[Management.Automation.Language.StringConstantExpressionAst]-and$n.Value.Contains('namespace VSOManager')},$true)
if(-not$csharp){throw 'Missing native argument adapter source.'}
$null=Test-ModuleManifest -Path (Join-Path $module 'VSO.psd1')
$null=& (Join-Path $PSScriptRoot 'Test-Privacy.ps1') -Path $root
[pscustomobject]@{Validation='Static';PowerShell=$PSVersionTable.PSVersion.ToString();Edition=$PSVersionTable.PSEdition;ParsedFiles=$files;RuntimeFunctions=$functions.Count;LocalizedCommands=16;UacBootstrap='Parses';ModuleRuntimeImported=$false;DynamicTestsExecuted=$false}
