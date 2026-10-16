Set-StrictMode -Version 2.0
$script:ModuleRoot = $PSScriptRoot
$script:PublicCommands = @('Install-VSO','Start-VSO','Stop-VSO','Update-VSO','Get-VSOStatus','Get-VSOInstallation','Reset-VSO','Help-VSO')
$parts=@('Utilities/Common','Localization/Context','UI/Prompt','Security/Paths','Security/Archive','GitHub/Release','Installation/Distribution','Installation/Registry','Installation/Transaction','Processes/Processes','Security/Elevation')
$script:RuntimeFiles=@('VSO.psd1','VSO.psm1','en-US/Messages.psd1','es-ES/Messages.psd1','en-US/Help.psd1','es-ES/Help.psd1')
$script:RuntimeFiles+=@($parts|ForEach-Object { 'Private/'+$_+'.ps1' })
$script:RuntimeFiles+=@($script:PublicCommands|ForEach-Object { 'Public/'+$_+'.ps1' })
$script:RuntimeHashes=[ordered]@{}
$handles=[Collections.Generic.List[IO.FileStream]]::new()
try {
    # Capture the imported source identity, not a later editable copy, for UAC.
    # Read handles deny writes/deletes until all local definitions have loaded.
    foreach ($relative in $script:RuntimeFiles) {
        $path=Join-Path $PSScriptRoot $relative
        $handle=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $handles.Add($handle)
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $script:RuntimeHashes[$relative]=([BitConverter]::ToString($sha.ComputeHash($handle))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    }
    foreach ($part in $parts) { . (Join-Path $PSScriptRoot ('Private/' + $part + '.ps1')) }
    foreach ($name in $script:PublicCommands) { . (Join-Path $PSScriptRoot ('Public/' + $name + '.ps1')) }
} finally {
    foreach ($handle in $handles) { $handle.Dispose() }
}
Export-ModuleMember -Function $script:PublicCommands
