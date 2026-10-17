function Get-ReleaseInputIdentity {
    param([string]$Project)
    $files=@(foreach ($directory in @('src','docs','build','tests')) { Get-ChildItem -LiteralPath (Join-Path $Project $directory) -Recurse -File })
    $files+=@(foreach ($name in @('README.md','VALIDATION.md','LICENSE','AGENTS.md','CHANGELOG.md')) { $path=Join-Path $Project $name;if ([IO.File]::Exists($path)) { Get-Item -LiteralPath $path } })
    $records=@($files | Sort-Object FullName | ForEach-Object { [ordered]@{Path=$_.FullName.Substring($Project.TrimEnd('\').Length+1).Replace('\','/');Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} })
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($records|ConvertTo-Json -Depth 4 -Compress))))).Replace('-','').ToLowerInvariant() } finally {$sha.Dispose()}
}

function Test-ReleasePackage {
    param([string]$PackagePath,[string]$ModulePath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $data=Import-PowerShellDataFile -LiteralPath (Join-Path $ModulePath 'VSO.psd1')
    if ($data.ModuleVersion -ne '1.0.2' -or $data.Author -cne 'saturnus25' -or $data.CompanyName -cne 'saturnus25' -or $data.RequiredModules) {throw 'Unexpected manifest identity or dependencies.'}
    $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($file in @(Get-ChildItem -LiteralPath $ModulePath -Recurse -File)) {
        if ($file.Attributes-band[IO.FileAttributes]::ReparsePoint) {throw 'Linked package input rejected.'}
        $relative=$file.FullName.Substring($ModulePath.TrimEnd('\').Length+1).Replace('\','/')
        $expected.Add($relative,(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
    }
    $metadata=@('VSO.nuspec','_rels/.rels','[Content_Types].xml','package/services/metadata/core-properties/vso.psmdcp')
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $zip=[IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        if ($zip.Entries.Count -gt 256) {throw 'Package entry limit exceeded.'}
        foreach ($entry in $zip.Entries) {
            if (-not $seen.Add($entry.FullName) -or $entry.Length -gt 4194304 -or ($entry.FullName -cnotin $metadata -and -not $expected.ContainsKey($entry.FullName))) {throw 'Unexpected or duplicate package entry.'}
            if ($expected.ContainsKey($entry.FullName)) {
                $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
                try {$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$stream.Dispose()}
                if ($hash -cne $expected[$entry.FullName]) {throw 'Package differs from validated distribution.'}
            }
        }
        foreach ($name in @($expected.Keys)+$metadata) {if (-not $seen.Contains($name)) {throw 'Missing package entry.'}}
        $reader=[IO.StreamReader]::new($zip.GetEntry('VSO.nuspec').Open())
        try {$nuspec=[xml]$reader.ReadToEnd()}finally{$reader.Dispose()}
        foreach ($pair in @(@('id','VSO'),@('version','1.0.2'),@('authors','saturnus25'))) {
            $node=$nuspec.SelectSingleNode('//*[local-name()="metadata"]/*[local-name()="'+$pair[0]+'"]')
            if (-not $node -or $node.InnerText -cne $pair[1]) {throw 'Unexpected nuspec identity.'}
        }
        if ($nuspec.SelectNodes('//*[local-name()="dependency"]').Count) {throw 'Unexpected package dependency.'}
    } finally {$zip.Dispose()}
    [pscustomobject]@{Files=$expected.Count;MetadataFiles=$metadata.Count;Version=$data.ModuleVersion}
}

function Assert-ReleaseValidation {
    param([string]$PackagePath,[string]$ValidationPath,[string]$Project)
    $record=Get-Content -LiteralPath $ValidationPath -Raw | ConvertFrom-Json
    $hash=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($record.Schema -ne 1 -or $record.Product -cne 'VSO' -or $record.Sha256 -cne $hash -or $record.InputSha256 -cne (Get-ReleaseInputIdentity $Project)) {throw 'Validation invalidated: package or reviewed inputs changed. Validate and approve again.'}
    foreach ($evidence in @($record.Evidence)) {
        if (-not [IO.File]::Exists($evidence.Path) -or (Get-FileHash -LiteralPath $evidence.Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $evidence.Sha256) {throw 'Validation evidence changed.'}
    }
    return $record
}
