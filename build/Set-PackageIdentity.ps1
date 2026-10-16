[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$items=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
$zip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Path))
try {
    foreach ($entry in $zip.Entries) {
        $stream=$entry.Open();$memory=[IO.MemoryStream]::new()
        try {$stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$memory.Dispose();$stream.Dispose()}
        $name=$entry.FullName
        if ($name -like '*core-properties*') {
            $document=[xml][Text.Encoding]::UTF8.GetString($bytes)
            foreach ($node in $document.SelectNodes('//*[local-name()="creator" or local-name()="lastModifiedBy"]')) {$node.InnerText='saturnus25'}
            $bytes=[Text.Encoding]::UTF8.GetBytes($document.OuterXml)
            $name='package/services/metadata/core-properties/vso.psmdcp'
        } elseif ($name -ceq '_rels/.rels') {
            $document=[xml][Text.Encoding]::UTF8.GetString($bytes)
            foreach ($node in $document.DocumentElement.ChildNodes) {
                if ($node.Type -like '*/core-properties') {$node.Target='/package/services/metadata/core-properties/vso.psmdcp';$node.Id='RCoreProperties'}
                else {$node.Id='RManifest'}
            }
            $bytes=[Text.Encoding]::UTF8.GetBytes($document.OuterXml)
        }
        $items.Add($name,$bytes)
    }
}finally{$zip.Dispose()}
$temporary=$Path+'.normalized-'+[guid]::NewGuid().ToString('N')
try {
    $zip=[IO.Compression.ZipFile]::Open($temporary,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in @($items.Keys|Sort-Object -CaseSensitive)) {
            $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
            $stream=$entry.Open();try {$stream.Write($items[$name],0,$items[$name].Length)}finally{$stream.Dispose()}
        }
    }finally{$zip.Dispose()}
    [IO.File]::Copy($temporary,$Path,$true)
}finally{if ([IO.File]::Exists($temporary)) {[IO.File]::Delete($temporary)}}
