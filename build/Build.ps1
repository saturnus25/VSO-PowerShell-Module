[CmdletBinding()]
param([switch]$Package)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$source=Join-Path $root 'src/VSO'
$manifestPath=Join-Path $source 'VSO.psd1'
$data=Import-PowerShellDataFile -LiteralPath $manifestPath
$parseCount=0
foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1','.psd1') -and $_.FullName -notmatch '[\\/](dist|\.work|\.git|TestResults)[\\/]' })) {
    $tokens=$null; $errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ('Parser errors: '+$file.Name+': '+($errors.Message -join '; ')) }
    $bytes=[IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw ('UTF-8 BOM required: '+$file.Name) }
    $parseCount++
}
$null=Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
$expected=@('Install-VSO','Start-VSO','Stop-VSO','Update-VSO','Get-VSOStatus','Get-VSOInstallation','Reset-VSO','Help-VSO')
if (@(Compare-Object $expected $data.FunctionsToExport).Count -or $data.Author -cne 'saturnus25' -or $data.CompanyName -cne 'saturnus25' -or $data.ModuleVersion -ne '1.0.0') { throw 'Invalid module contract.' }
& (Join-Path $PSScriptRoot 'Build-Help.ps1') -ModulePath $source
$null=& (Join-Path $PSScriptRoot 'Test-Privacy.ps1') -Path $root
$dist=Join-Path $root 'dist'; [void][IO.Directory]::CreateDirectory($dist)
$destination=Join-Path $dist 'VSO'
if ([IO.Directory]::Exists($destination)) {
    $old=Import-PowerShellDataFile -LiteralPath (Join-Path $destination 'VSO.psd1')
    if ($old.GUID -ne $data.GUID -or -not ([IO.Path]::GetFullPath($destination)).StartsWith($dist+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to replace an unowned build directory.' }
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($destination)
    while($pending.Count){
        $directory=$pending.Pop();$item=Get-Item -LiteralPath $directory -Force
        if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Linked build directory rejected.'}
        foreach($child in @(Get-ChildItem -LiteralPath $directory -Force)){
            if($child.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Linked build directory rejected.'}
            if($child.PSIsContainer){$pending.Push($child.FullName)}
        }
    }
    Remove-Item -LiteralPath $destination -Recurse -Force
}
Copy-Item -LiteralPath $source -Destination $destination -Recurse
foreach ($name in @('README.md','LICENSE','VALIDATION.md','CHANGELOG.md')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $destination $name) }
Copy-Item -LiteralPath (Join-Path $root 'docs') -Destination (Join-Path $destination 'docs') -Recurse
Copy-Item -LiteralPath (Join-Path $root 'tests/Manual-Acceptance.md') -Destination (Join-Path $destination 'docs/LabAcceptance.md')
$readmePath=Join-Path $destination 'README.md'
$readme=[IO.File]::ReadAllText($readmePath)
$readme=[regex]::Replace($readme,'(?ms)^## AI Development Notice\r?\n.*?(?=^## |\z)','').TrimEnd()+[Environment]::NewLine
$readme+=[Environment]::NewLine+'Build, test and publication commands require the separate source project. Developer tools and test code are deliberately excluded from this runtime package.'+[Environment]::NewLine
[IO.File]::WriteAllText($readmePath,$readme,[Text.UTF8Encoding]::new($false))
$publishingPath=Join-Path $destination 'docs/Publishing.md'
$publishing=[IO.File]::ReadAllText($publishingPath).Replace('../tests/Manual-Acceptance.md','LabAcceptance.md')
[IO.File]::WriteAllText($publishingPath,$publishing,[Text.UTF8Encoding]::new($false))
$null=Test-ModuleManifest -Path (Join-Path $destination 'VSO.psd1') -ErrorAction Stop
$null=& (Join-Path $PSScriptRoot 'Test-Privacy.ps1') -Path $destination
if ($Package) {
    if (-not (Get-Command Compress-PSResource -ErrorAction SilentlyContinue)) { throw 'PSResourceGet with Compress-PSResource is required for nupkg generation.' }
    $nupkg=Join-Path $dist ('VSO.'+$data.ModuleVersion+'.nupkg')
    if ([IO.File]::Exists($nupkg)) { Remove-Item -LiteralPath $nupkg -Force }
    Compress-PSResource -Path $destination -DestinationPath $dist -Confirm:$false
    & (Join-Path $PSScriptRoot 'Set-PackageIdentity.ps1') -Path $nupkg
    $null=& (Join-Path $PSScriptRoot 'Test-Privacy.ps1') -Path $nupkg
}
$hashes=@(Get-ChildItem -LiteralPath $destination -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_.FullName.Substring($dist.Length+1).Replace('\','/') })
if ($Package) { $hashes+=((Get-FileHash -LiteralPath $nupkg -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($nupkg)) }
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),$hashes,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Module='VSO'; Version=$data.ModuleVersion; ParsedSourceFiles=$parseCount; BuiltFiles=$hashes.Count; PackageRequested=[bool]$Package; Validation='Static parser, manifest, help generation and privacy only; dynamic acceptance is separate.' }
