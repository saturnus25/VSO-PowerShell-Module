[CmdletBinding()]
param([string]$Path,[string[]]$ForbiddenText=@())
$ErrorActionPreference='Stop'
if (-not $Path) { $Path=Split-Path -Parent $PSScriptRoot }
$root=[IO.Path]::GetFullPath($Path)
$findings=[Collections.Generic.List[string]]::new()
$textExtensions=@('.ps1','.psm1','.psd1','.md','.txt','.json','.xml','.nuspec','.rels','.psmdcp','.yml','.yaml','.gitignore')
function Test-PublicText([string]$Name,[string]$Text) {
    $patterns=@(
        '(?i)[a-z]:[\\/]+Users[\\/]+(?!<USER>|<USUARIO>|Public(?:[\\/]|$)|Default(?:[\\/]|$))[^\\/\s<>"'']+',
        '(?i)[a-z]:[\\/]+(?:Documents and Settings)[\\/]+[^\\/\s]+',
        '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
        '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        '(?i)\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b'
    )
    foreach ($pattern in $patterns) { if ($Text -match $pattern) { $findings.Add($Name+': prohibited personal data or secret pattern'); break } }
    foreach ($term in $ForbiddenText) { if ($term -and $Text.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0) { $findings.Add($Name+': prohibited owner-supplied term'); break } }
    # File and package attribution are constrained to the explicitly public identity.
    if ($Name -like '*VSO.psd1') {
        foreach ($field in @('Author','CompanyName')) { if ($Text -notmatch ($field+'\s*=\s*''saturnus25''')) { $findings.Add($Name+': invalid public attribution') } }
        if ($Text -notmatch "Copyright = 'Copyright \(c\) 2026 saturnus25'") { $findings.Add($Name+': invalid copyright') }
    }
    if ($Name -like '*.nuspec') {
        $document=[xml]$Text
        foreach ($field in @('authors','owners')) {
            $node=$document.SelectSingleNode('//*[local-name()="metadata"]/*[local-name()="'+$field+'"]')
            if ($node -and $node.InnerText -cne 'saturnus25') { $findings.Add($Name+': invalid package attribution') }
        }
        $authors=$document.SelectSingleNode('//*[local-name()="metadata"]/*[local-name()="authors"]')
        if (-not $authors) { $findings.Add($Name+': missing package author') }
    }
    if ($Name -like '*core-properties*') {
        $document=[xml]$Text
        foreach ($node in $document.SelectNodes('//*[local-name()="creator" or local-name()="lastModifiedBy"]')) {
            if ($node.InnerText -and $node.InnerText -cne 'saturnus25') { $findings.Add($Name+': invalid embedded author') }
        }
    }
}
$files=[Collections.Generic.List[object]]::new()
if ([IO.File]::Exists($root)) { $files.Add((Get-Item -LiteralPath $root)) }
else {
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
    while($pending.Count){
        $directory=$pending.Pop();$item=Get-Item -LiteralPath $directory -Force -ErrorAction Stop
        if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$findings.Add('Linked public directory');continue}
        foreach($child in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)){
            if($child.PSIsContainer){if($child.Name-notin@('.git','.work','TestResults')){$pending.Push($child.FullName)}}
            else{$files.Add($child)}
        }
    }
}
$checked=0
foreach ($file in $files) {
    $name=if ([IO.File]::Exists($root)) { $file.Name } else { $file.FullName.Substring($root.TrimEnd('\').Length+1) }
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { $findings.Add($name+': linked public file'); continue }
    if ($file.Extension -eq '.nupkg' -or $file.Extension -eq '.zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead($file.FullName)
        try {
            foreach ($entry in $zip.Entries) {
                if (-not $entry.Name) { continue }
                $extension=[IO.Path]::GetExtension($entry.Name)
                if ($extension -notin $textExtensions -and $entry.Name -ne 'LICENSE') { $findings.Add($name+': unexpected binary or resource in package'); continue }
                if ($entry.Length -gt 4194304) { $findings.Add($name+': oversized public file'); continue }
                $reader=[IO.StreamReader]::new($entry.Open())
                try { Test-PublicText ($name+'/'+$entry.FullName) $reader.ReadToEnd(); $checked++ } finally { $reader.Dispose() }
            }
        } finally { $zip.Dispose() }
    } elseif ($file.Extension -in $textExtensions -or $file.Name -in @('LICENSE','AGENTS.md','.gitignore')) {
        Test-PublicText $name ([IO.File]::ReadAllText($file.FullName)); $checked++
    } else { $findings.Add($name+': unexpected public file type') }
}
if ($findings.Count) { throw ('Privacy audit failed: '+($findings -join '; ')) }
[pscustomobject]@{ Audit='Privacy'; FilesChecked=$checked; Result='No prohibited patterns found'; Attribution='saturnus25'; Scope='Public files and embedded package text; manual owner review remains required.' }
