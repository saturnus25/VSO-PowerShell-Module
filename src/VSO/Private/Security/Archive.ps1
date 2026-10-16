function Expand-VSOArchive {
    param([string]$Archive, [string]$Destination, $Context)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $zip=$null
    try {
        $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
        if ($zip.Entries.Count -eq 0 -or $zip.Entries.Count -gt 10000) { Throw-VSOError $Context Archive @('entry count') }
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $entries=[Collections.Generic.List[object]]::new(); [long]$total=0
        foreach ($entry in $zip.Entries) {
            $name=$entry.FullName.Replace('\','/'); $directory=$name.EndsWith('/'); $relative=$name.TrimEnd('/')
            $target=Join-VSOChild $Destination $relative $Context
            if (-not $seen.Add($target)) { Throw-VSOError $Context Archive @('duplicate path') }
            $unixMode=([long]$entry.ExternalAttributes -shr 16) -band 61440
            if ($unixMode -notin @(0,16384,32768) -or ($entry.ExternalAttributes -band 1024)) { Throw-VSOError $Context Archive @('link or special entry') }
            if ($entry.Length -gt 268435456 -or ($entry.Length -gt 10485760 -and $entry.CompressedLength -gt 0 -and ($entry.Length / $entry.CompressedLength) -gt 200)) { Throw-VSOError $Context Archive @('expansion ratio') }
            $total += $entry.Length
            if ($total -gt 536870912) { Throw-VSOError $Context Archive @('expanded size') }
            $entries.Add([pscustomobject]@{ Entry=$entry; Target=$target; Directory=$directory })
        }
        # Validate every entry before writing any payload.
        [long]$done=0
        foreach ($item in $entries) {
            Assert-VSONoReparse $item.Target $Context
            if ($item.Directory) { [void][IO.Directory]::CreateDirectory($item.Target); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Target))
            $input=$item.Entry.Open(); $output=$null
            try {
                $output=[IO.FileStream]::new($item.Target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                $buffer=[byte[]]::new(65536); [long]$written=0
                while (($read=$input.Read($buffer,0,$buffer.Length)) -gt 0) {
                    $written+=$read; $done+=$read
                    if ($written -gt $item.Entry.Length -or $done -gt 536870912) { Throw-VSOError $Context Archive @('length mismatch') }
                    $output.Write($buffer,0,$read)
                }
                if ($written -ne $item.Entry.Length) { Throw-VSOError $Context Archive @('truncated entry') }
            } finally { if ($output) { $output.Dispose() }; $input.Dispose() }
            Write-VSOProgress $Context Extract $done $total
        }
    } catch { Throw-VSOError $Context Archive @($_.Exception.Message) $_.Exception }
    finally { if ($zip) { $zip.Dispose() }; Write-VSOProgress $Context Extract -Completed }
}

function Read-VSOChecksumManifest {
    param([string]$Root, $Context)
    $path=Join-VSOChild $Root 'SHA256SUMS.txt' $Context
    if (-not [IO.File]::Exists($path) -or ([IO.FileInfo]::new($path)).Length -gt 2097152) { Throw-VSOError $Context Integrity @('SHA256SUMS.txt') }
    $files=[ordered]@{}; $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        if (-not $line.Trim()) { continue }
        if ($line -notmatch '^([a-fA-F0-9]{64})[ \t]+\*?(.+)$') { Throw-VSOError $Context Integrity @('checksum syntax') }
        $hash=$Matches[1].ToLowerInvariant(); $relative=$Matches[2].Replace('\','/')
        $null=Join-VSOChild $Root $relative $Context
        if (-not $seen.Add($relative) -or $relative -eq 'SHA256SUMS.txt' -or $relative -eq '.vso-manager.json') { Throw-VSOError $Context Integrity @('duplicate or reserved entry') }
        $files[$relative]=$hash
    }
    if ($files.Count -eq 0) { Throw-VSOError $Context Integrity @('empty manifest') }
    return $files
}
