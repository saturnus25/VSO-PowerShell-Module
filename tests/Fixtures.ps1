# Synthetic filesystem fixtures only. Never copy an application engine into tests.
function New-LabDistribution {
    param([string]$Root,[string]$Version='1.2.2',[switch]$Contract2)
    [void][IO.Directory]::CreateDirectory($Root)
    $files=@((Get-VSO7RequiredFiles)+@('LICENSE'))
    $lines=@()
    foreach ($relative in $files) {
        $path=Join-Path $Root $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        $contentName=if ($relative -eq 'VSO7_7.0.0_RC_R80.ps1') {'VSO7.ps1'}else{$relative}
        $content="throw 'Synthetic fixture must never execute' # "+$contentName+' '+$Version
        [IO.File]::WriteAllText($path,$content,[Text.UTF8Encoding]::new($false))
        $lines+=((Get-VSOHash $path)+'  '+$relative)
    }
    [IO.File]::WriteAllLines((Join-Path $Root 'SHA256SUMS.txt'),$lines,[Text.UTF8Encoding]::new($false))
    if ($Contract2) {
        $required=@($files|ForEach-Object {[ordered]@{path=$_;role='Application'}})
        foreach ($pair in @(@('Config/default.json','Configuration'),@('Cache/cache.dat','Cache'),@('Logs/install.txt','Log'),@('Temp/session.dat','Temporary'),@('Recuperacion/baseline.json','Recovery'))) {
            $path=Join-Path $Root $pair[0];[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.File]::WriteAllText($path,'Synthetic packaged data')
            $required+=[ordered]@{path=$pair[0];role=$pair[1]}
        }
        $definition=[ordered]@{schemaVersion=2;product='VicoSafeOptimizer';generation='7';version=$Version;platform='windows-x64';packageType='PortableZip';adapter='vso7-classic-v1';launcher='START VSO7.bat';launcherType='Batch';requirements=@{host='WindowsPowerShell';minimumVersion='5.1';architecture='x64'};filesManifest='SHA256SUMS.txt';requiredFiles=$required;optionalFiles=@([ordered]@{path='Resources/next.json';role='Application'});persistentData=@();update=@{compatibleGenerations=@('7');preserveUnknownFiles=$true};uninstall=@{restoreWindowsTweaks=$false;preserveUnknownFiles=$true}}
        [IO.File]::WriteAllText((Join-Path $Root 'Resources/next.json'),'Synthetic optional data')
        [IO.File]::WriteAllText((Join-Path $Root 'vso-distribution.json'),($definition|ConvertTo-Json -Depth 8))
        Set-LabChecksums $Root
    }
}

function Set-LabChecksums {
    param([string]$Root)
    $lines=@(Get-ChildItem -LiteralPath $Root -File -Recurse|Where-Object Name -NE 'SHA256SUMS.txt'|ForEach-Object {(Get-VSOHash $_.FullName)+'  '+$_.FullName.Substring($Root.Length+1).Replace('\','/')})
    [IO.File]::WriteAllLines((Join-Path $Root 'SHA256SUMS.txt'),$lines,[Text.UTF8Encoding]::new($false))
}

function New-LabRelease {
    param([string]$Root,[string]$Version='1.2.2',[switch]$Contract2)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $payload=Join-Path $Root ('payload-'+[guid]::NewGuid().ToString('N'))
    New-LabDistribution (Join-Path $payload 'VSO7') $Version -Contract2:$Contract2
    $archive=Join-Path $Root ([guid]::NewGuid().ToString('N')+'.zip')
    [IO.Compression.ZipFile]::CreateFromDirectory($payload,$archive)
    return [pscustomobject]@{ Version=$Version; Tag=('v'+$Version); ReleaseUri=('https://github.com/saturnus25/VSO/releases/tag/v'+$Version); AssetName='fixture.zip'; AssetUri=('https://github.com/saturnus25/VSO/releases/download/v'+$Version+'/fixture.zip'); Size=([IO.FileInfo]::new($archive)).Length; Sha256=(Get-VSOHash $archive); IntegrityMethod='SyntheticFixture'; Prerelease=$false; Fixture=$archive }
}

function New-LabZip {
    param([string]$Path,[string[]]$Entries,[switch]$Link)
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries) {
            $entry=$zip.CreateEntry($name)
            if ($Link) { $entry.ExternalAttributes=-1577123840 }
            $writer=[IO.StreamWriter]::new($entry.Open())
            try { $writer.Write('synthetic') } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function New-LabApiRelease {
    param([string]$Version='1.2.2',[switch]$Prerelease,[switch]$NoDigest)
    $asset=[pscustomobject]@{ name='official.zip'; state='uploaded'; size=1234; digest=('sha256:'+('a'*64)); browser_download_url=('https://github.com/saturnus25/VSO/releases/download/v'+$Version+'/official.zip') }
    if ($NoDigest) { $asset.digest=$null }
    return [pscustomobject]@{ tag_name=('v'+$Version); html_url=('https://github.com/saturnus25/VSO/releases/tag/v'+$Version); draft=$false; prerelease=[bool]$Prerelease; assets=@($asset) }
}

function New-LabHttpResponse {
    param([int]$Status,[hashtable]$Values=@{})
    $headers=[pscustomobject]@{Values=$Values}
    $headers|Add-Member -MemberType ScriptMethod -Name Contains -Value {param($Name) return $this.Values.ContainsKey($Name)}
    $headers|Add-Member -MemberType ScriptMethod -Name GetValues -Value {param($Name) return $this.Values[$Name]}
    return [pscustomobject]@{StatusCode=$Status;Headers=$headers;IsSuccessStatusCode=($Status -ge 200 -and $Status -lt 300)}
}

function New-LabMemoryWrapper {
    param([string]$Root,[string]$Hash=('a'*64))
    $source=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $Root 'VSO7.ps1')))
    $template=@'
function D([string]$v){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($v))}
$source=D('__SOURCE__');$expected='__HASH__'
$text=[IO.File]::ReadAllText($stage,[Text.Encoding]::UTF8)
$h=[Security.Cryptography.SHA256]::Create()
try{$actual=([BitConverter]::ToString($h.ComputeHash($enc.GetBytes($text)))).Replace('-','')}finally{$h.Dispose()}
if($actual-cne$expected){throw 'Synthetic checksum mismatch'}
$sb=[ScriptBlock]::Create($text)
$invoke=@{VSOTrustedHost=$true;VSOTrustedMemoryHost=$true;VSOOriginalSourcePath=$source;VSOExpectedSourceSha256=$expected;VSOExpectedUserSid=$sid;DirectAction=$action;StartupProbe=$probe}
& $sb @invoke
'@
    return $template.Replace('__SOURCE__',$source).Replace('__HASH__',$Hash)
}
