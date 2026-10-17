[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ModulePath)
$ErrorActionPreference='Stop'
$module=[IO.Path]::GetFullPath($ModulePath)
$manifest=Import-PowerShellDataFile -LiteralPath (Join-Path $module 'VSO.psd1')
foreach ($culture in @('en-US','es-ES')) {
    $data=Import-PowerShellDataFile -LiteralPath (Join-Path $module ($culture+'/Help.psd1'))
    $messages=Import-PowerShellDataFile -LiteralPath (Join-Path $module ($culture+'/Messages.psd1'))
    $xml=[xml]'<?xml version="1.0" encoding="utf-8"?><helpItems schema="maml" xmlns:command="http://schemas.microsoft.com/maml/dev/command/2004/10" xmlns:maml="http://schemas.microsoft.com/maml/2004/10" xmlns:dev="http://schemas.microsoft.com/maml/dev/2004/10" />'
    $ns=@{ command='http://schemas.microsoft.com/maml/dev/command/2004/10'; maml='http://schemas.microsoft.com/maml/2004/10'; dev='http://schemas.microsoft.com/maml/dev/2004/10' }
    function Add-HelpNode($Parent,[string]$Name,[string]$Text) {
        $prefix,$local=$Name.Split(':',2)
        $node=$xml.CreateElement($prefix,$local,$ns[$prefix])
        if ($PSBoundParameters.ContainsKey('Text')) { $node.InnerText=$Text }
        [void]$Parent.AppendChild($node); return ,$node
    }
    function Add-HelpParagraph($Parent,[string]$Text) {
        $description=Add-HelpNode $Parent 'maml:description'
        $null=Add-HelpNode $description 'maml:para' $Text
    }
    foreach ($name in $manifest.FunctionsToExport) {
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $module ('Public/'+$name+'.ps1')),[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw 'Help generation encountered a parser error.' }
        $function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$false)
        $entry=$data[$name]
        if (-not $entry -or -not $entry.Examples.Count) { throw ('Incomplete help for '+$name) }
        $command=Add-HelpNode $xml.helpItems 'command:command'
        $details=Add-HelpNode $command 'command:details'
        $null=Add-HelpNode $details 'command:name' $name
        $null=Add-HelpNode $details 'command:verb' ($name.Split('-')[0])
        $null=Add-HelpNode $details 'command:noun' ($name.Split('-')[1])
        Add-HelpParagraph $details $entry.Synopsis
        Add-HelpParagraph $command $entry.Description
        $syntax=Add-HelpNode $command 'command:syntax'; $syntaxItem=Add-HelpNode $syntax 'command:syntaxItem'
        $null=Add-HelpNode $syntaxItem 'maml:name' $name
        $parameters=Add-HelpNode $command 'command:parameters'
        $position=0
        $parameterDefinitions=@(foreach ($parameter in $function.Body.ParamBlock.Parameters) {
            $parameterName=$parameter.Name.VariablePath.UserPath
            $constraint=@($parameter.Attributes | Where-Object { $_ -is [Management.Automation.Language.TypeConstraintAst] })
            $type=if ($constraint.Count) { $constraint[0].TypeName.FullName } else { 'Object' }
            $pipeline=$false; $propertyPipeline=$false
            foreach ($attribute in @($parameter.Attributes|Where-Object {$_.TypeName.FullName -eq 'Parameter'})) {
                foreach ($argument in $attribute.NamedArguments) {
                    if ($argument.ArgumentName -eq 'ValueFromPipeline') { $pipeline=[bool]$argument.Argument.SafeGetValue() }
                    if ($argument.ArgumentName -eq 'ValueFromPipelineByPropertyName') { $propertyPipeline=[bool]$argument.Argument.SafeGetValue() }
                }
            }
            $parameterPosition=if ($type -eq 'switch') { 'named' } else { [string]$position; $position++ }
            [pscustomobject]@{Name=$parameterName;Type=$type;Position=$parameterPosition;Pipeline=$pipeline;PropertyPipeline=$propertyPipeline}
        })
        $binding=@($function.Body.ParamBlock.Attributes|Where-Object {$_.TypeName.FullName -eq 'CmdletBinding'})
        $supportsShouldProcess=@($binding.NamedArguments|Where-Object {$_.ArgumentName -eq 'SupportsShouldProcess' -and $_.Argument.SafeGetValue()}).Count -gt 0
        if ($supportsShouldProcess) {
            foreach ($common in @('WhatIf','Confirm')) { $parameterDefinitions+=[pscustomobject]@{Name=$common;Type='switch';Position='named';Pipeline=$false;PropertyPipeline=$false} }
        }
        foreach ($definition in $parameterDefinitions) {
            $parameterName=$definition.Name; $type=$definition.Type
            if (-not $data.Parameters.ContainsKey($parameterName)) { throw ('Missing parameter help: '+$parameterName) }
            foreach ($parent in @($syntaxItem,$parameters)) {
                $p=Add-HelpNode $parent 'command:parameter'
                $pipelineInput=if ($definition.Pipeline -and $definition.PropertyPipeline) { 'true (ByValue, ByPropertyName)' } elseif ($definition.Pipeline) { 'true (ByValue)' } elseif ($definition.PropertyPipeline) { 'true (ByPropertyName)' } else { 'false' }
                foreach ($a in ([ordered]@{required='false';position=$definition.Position;pipelineInput=$pipelineInput;globbing='false'}).GetEnumerator()) { $p.SetAttribute($a.Key,$a.Value) }
                $null=Add-HelpNode $p 'maml:name' $parameterName
                Add-HelpParagraph $p $data.Parameters[$parameterName]
                if ($type -ne 'switch') { $value=Add-HelpNode $p 'command:parameterValue' $type; $value.SetAttribute('required','true') }
                if ($parent -eq $parameters) {
                    $devType=Add-HelpNode $p 'dev:type'; $null=Add-HelpNode $devType 'maml:name' $type
                    $default=if ($data.Defaults.ContainsKey($parameterName)) { $data.Defaults[$parameterName] } else { '' }
                    $null=Add-HelpNode $p 'dev:defaultValue' $default
                }
            }
        }
        $inputName=if (@($parameterDefinitions|Where-Object Pipeline).Count) { 'System.String, System.Management.Automation.PSObject (Path)' } else { 'None' }
        $inputTypes=Add-HelpNode $command 'command:inputTypes'; $inputType=Add-HelpNode $inputTypes 'command:inputType'; $devType=Add-HelpNode $inputType 'dev:type'; $null=Add-HelpNode $devType 'maml:name' $inputName
        $returns=Add-HelpNode $command 'command:returnValues'; $return=Add-HelpNode $returns 'command:returnValue'; $devType=Add-HelpNode $return 'dev:type'; $null=Add-HelpNode $devType 'maml:name' 'System.Management.Automation.PSCustomObject'
        $alerts=Add-HelpNode $command 'maml:alertSet'; $alert=Add-HelpNode $alerts 'maml:alert'; $null=Add-HelpNode $alert 'maml:para' ($messages.FullWarning+' '+$messages.Permissions+' '+$messages.Compatibility)
        if ($name -in @('Reset-VSO','Help-VSO')) { $alert=Add-HelpNode $alerts 'maml:alert'; $null=Add-HelpNode $alert 'maml:para' $messages.RemovalHint }
        $examples=Add-HelpNode $command 'command:examples'
        $exampleNumber=0
        foreach ($example in $entry.Examples) {
            $exampleNumber++
            $node=Add-HelpNode $examples 'command:example'
            $null=Add-HelpNode $node 'maml:title' ($messages.ExampleTitle -f $exampleNumber,$example.Title)
            $null=Add-HelpNode $node 'dev:code' $example.Code
            $remarks=Add-HelpNode $node 'dev:remarks'; $null=Add-HelpNode $remarks 'maml:para' $example.Remarks
        }
        $null=Add-HelpNode $command 'maml:relatedLinks'
    }
    $settings=[Xml.XmlWriterSettings]::new(); $settings.Indent=$true; $settings.Encoding=[Text.UTF8Encoding]::new($true)
    $output=Join-Path $module ($culture+'/VSO-help.xml')
    $writer=[Xml.XmlWriter]::Create($output,$settings)
    try { $xml.Save($writer) } finally { $writer.Dispose() }
}
Copy-Item -LiteralPath (Join-Path $module 'en-US/VSO-help.xml') -Destination (Join-Path $module 'VSO-help.xml') -Force
