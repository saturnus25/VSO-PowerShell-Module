function Start-VSOElevationProcess {
    param([Diagnostics.ProcessStartInfo]$Info)
    return [Diagnostics.Process]::Start($Info)
}

function Invoke-VSOElevation {
    param([ValidateSet('Install-VSO','Update-VSO','Reset-VSO','Stop-VSO')][string]$Operation, [hashtable]$Arguments, $Context)
    if ($Context.Quiet) { Throw-VSOError $Context Admin }
    $parent=[IO.Path]::GetTempPath().TrimEnd('\')
    $work=Join-Path $parent ('.vso-work-'+[guid]::NewGuid().ToString('N'))
    New-VSOSecureDirectory $work CurrentUser $Context
    try {
        $resultPath=Join-VSOChild $work 'result.json' $Context
        [IO.File]::WriteAllText($resultPath,'', [Text.UTF8Encoding]::new($false))
        $files=@(foreach ($relative in $script:RuntimeFiles) {
            $file=Join-VSOChild $script:ModuleRoot $relative $Context
            if ((Get-VSOHash $file) -cne $script:RuntimeHashes[$relative]) { Throw-VSOError $Context Elevation @('Imported module source changed. Re-import a reviewed copy before elevation.') }
            [ordered]@{ Path=$relative; Sha256=$script:RuntimeHashes[$relative] }
        })
        $request=[ordered]@{ Operation=$Operation; Arguments=$Arguments; ModuleRoot=$script:ModuleRoot; Files=$files; Result=$resultPath; Owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
        $encodedRequest=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Depth 8 -Compress)))
        # Only base64 data is substituted into this constant program. Paths and arguments
        # are never concatenated into executable PowerShell text.
        $bootstrap=@'
$ErrorActionPreference='Stop'
$request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__REQUEST__'))|ConvertFrom-Json
$handles=New-Object 'Collections.Generic.List[IO.FileStream]'
$result=$null
try {
    if($request.Operation -cnotin @('Install-VSO','Update-VSO','Reset-VSO','Stop-VSO')){throw 'Operation rejected.'}
    $root=[IO.Path]::GetFullPath([string]$request.ModuleRoot).TrimEnd('\')
    foreach($file in $request.Files){
        if([IO.Path]::IsPathRooted([string]$file.Path)-or[string]$file.Path-match '(^|[\\/])\.\.([\\/]|$)|:'){throw 'Module path rejected.'}
        $path=[IO.Path]::GetFullPath((Join-Path $root ([string]$file.Path)))
        if(-not$path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Module path escaped.'}
        $cursor=$path
        while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Module link rejected.'};$cursor=[IO.Path]::GetDirectoryName($cursor)}
        $handle=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $handles.Add($handle)
        $sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash($handle))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($hash-cne[string]$file.Sha256){throw 'Module changed before elevation.'}
    }
    $known=@('VSO.psd1','VSO.psm1')
    foreach($name in $known){if(@($request.Files|Where-Object Path -CEQ $name).Count-ne1){throw 'Module inventory rejected.'}}
    Import-Module -Name (Join-Path $root 'VSO.psd1') -Force -ErrorAction Stop
    $allowed=@{
      'Install-VSO'=@('Path','Scope','Version','Prerelease','AssetName','Language','Force');
      'Update-VSO'=@('Path','Version','Prerelease','AssetName','Language','Force');
      'Reset-VSO'=@('Path','Full','RemoveBackups','AcknowledgeBackupLoss','Language','Force');
      'Stop-VSO'=@('Path','Language','Force')
    }
    $parameters=@{Quiet=$true;PassThru=$true;Confirm=$false}
    foreach($property in $request.Arguments.PSObject.Properties){
      if($property.Name-cnotin$allowed[[string]$request.Operation]){throw 'Parameter rejected.'}
      $parameters[$property.Name]=$property.Value
    }
    $data=@(& ('VSO\'+[string]$request.Operation) @parameters)
    $result=@{Success=$true;Data=$data}
}catch{$result=@{Success=$false;Message=$_.Exception.Message;ErrorId=$_.FullyQualifiedErrorId}}
finally{
    foreach($handle in $handles){$handle.Dispose()}
    $destination=[IO.Path]::GetFullPath([string]$request.Result)
    $cursor=$destination
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Result link rejected.'};$cursor=[IO.Path]::GetDirectoryName($cursor)}
    $acl=Get-Acl -LiteralPath ([IO.Path]::GetDirectoryName($destination))
    if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne[string]$request.Owner){throw 'Result owner changed.'}
    $allowedSids=@([string]$request.Owner,'S-1-5-18','S-1-5-32-544')
    $mask=[Security.AccessControl.FileSystemRights]::Write-bor[Security.AccessControl.FileSystemRights]::Delete-bor[Security.AccessControl.FileSystemRights]::ChangePermissions-bor[Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($rule.AccessControlType-eq'Allow'-and($rule.FileSystemRights-band$mask)-and$rule.IdentityReference.Value-cnotin$allowedSids){throw 'Result permissions changed.'}}
    [IO.File]::WriteAllText($destination,($result|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
}
if(-not$result.Success){exit 1}
'@
        $bootstrap=$bootstrap.Replace('__REQUEST__',$encodedRequest)
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
        if ($encoded.Length -gt 30000) { Throw-VSOError $Context Elevation @('UAC command exceeds the Windows command-line limit; use an elevated PowerShell session.') }
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=Join-Path (Get-VSOSystemDirectory $Context) 'WindowsPowerShell\v1.0\powershell.exe'
        # UAC starts a fresh environment and does not inherit the caller's
        # process execution policy. The child imports only the pinned inventory.
        $info.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encoded
        $info.Verb='runas'; $info.UseShellExecute=$true; $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        try { $process=Start-VSOElevationProcess $info }
        catch {
            $ex=$_.Exception; while ($ex.InnerException) { $ex=$ex.InnerException }
            if ($ex -is [ComponentModel.Win32Exception] -and $ex.NativeErrorCode -eq 1223) { Throw-VSOError $Context UacCancelled }
            Throw-VSOError $Context Elevation @($ex.Message) $ex
        }
        if (-not $process) { Throw-VSOError $Context Elevation @('no process result') }
        try { $process.WaitForExit(); $exitCode=$process.ExitCode } finally { $process.Dispose() }
        $result=Read-VSOJson $resultPath $Context -MaximumBytes 8388608
        if (-not (Get-VSOProperty $result Success $false) -or $exitCode -ne 0) { Throw-VSOError $Context Elevation @([string](Get-VSOProperty $result Message ('exit '+$exitCode))) }
        return $result.Data
    } finally { Remove-VSOPrivateTree $work $parent $Context }
}
