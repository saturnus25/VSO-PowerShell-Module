if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
InModuleScope VSO {
    BeforeAll {
        . (Join-Path $env:VSO_MODULE_LAB_PROJECT 'tests/Fixtures.ps1')
        $script:ctx=New-VSOContext en -Quiet
    }
    Describe 'Path and archive attack resistance' {
        It 'accepts absolute paths with spaces, Unicode and apostrophes' {
            $base=Join-Path $env:LOCALAPPDATA 'Programs'
            Resolve-VSOPath (Join-Path $base "VSO prueba á 'safe'") $script:ctx -Installation|Should -Match 'á'
        }
        It 'rejects dangerous installation paths' -TestCases @(
            @{P='.'},@{P='C:\'},@{P='C:\Windows\System32\VSO'},@{P='D:\VSO\..\other'},
            @{P='\\server\share\VSO'},@{P='D:\VSO:stream'},@{P='D:\VSO & other'},@{P='D:\VSO%PATH%'},
            @{P='D:\VSO\NUL.txt'},@{P='D:\VSO\trailing.'}
        ) {param($P) {Resolve-VSOPath $P $script:ctx -Installation}|Should -Throw}
        It 'rejects shared roots and temporary installation folders' {
            {Resolve-VSOPath $env:ProgramFiles $script:ctx -Installation}|Should -Throw
            {Resolve-VSOPath $env:LOCALAPPDATA $script:ctx -Installation}|Should -Throw
            {Resolve-VSOPath (Join-Path ([IO.Path]::GetTempPath()) 'VSO') $script:ctx -Installation}|Should -Throw
        }
        It 'reserves staging-path headroom without treating a payload child as another root' {
            $long='D:\'+('a'*158)
            {Resolve-VSOPath $long $script:ctx -Installation}|Should -Throw
            {Resolve-VSOPath $long $script:ctx}|Should -Not -Throw
        }
        It 'rejects relative inventory escapes and device aliases' -TestCases @(
            @{P='../outside'},@{P='a/../../outside'},@{P='/rooted'},@{P='C:\rooted'},@{P='file:stream'},
            @{P='a//b'},@{P='COM1'},@{P='dir/PRN.txt'},@{P='trailing. '}
        ) {param($P) {Join-VSOChild $TestDrive $P $script:ctx}|Should -Throw}
        It 'rejects a junction rather than following it' {
            $outside=Join-Path $TestDrive 'outside'; [void][IO.Directory]::CreateDirectory($outside)
            $junction=Join-Path $TestDrive 'junction'
            New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop|Out-Null
            try { {Join-VSOChild $TestDrive 'junction/file.txt' $script:ctx}|Should -Throw }
            finally { Remove-Item -LiteralPath $junction -Force }
            Test-Path -LiteralPath $outside|Should -BeTrue
        }
        It 'rejects Zip Slip before any entry is extracted' {
            $zip=Join-Path $TestDrive 'slip.zip'; New-LabZip $zip @('good.txt','../escape.txt')
            $destination=Join-Path $TestDrive 'extracted'; [void][IO.Directory]::CreateDirectory($destination)
            {Expand-VSOArchive $zip $destination $script:ctx}|Should -Throw
            @(Get-ChildItem -LiteralPath $destination -Force).Count|Should -Be 0
            Test-Path -LiteralPath (Join-Path $TestDrive 'escape.txt')|Should -BeFalse
        }
        It 'rejects case-insensitive duplicate ZIP paths' {
            $zip=Join-Path $TestDrive 'duplicate.zip'; New-LabZip $zip @('same.txt','SAME.TXT')
            {Expand-VSOArchive $zip (Join-Path $TestDrive 'duplicate-out') $script:ctx}|Should -Throw
        }
        It 'rejects symbolic link archive entries' {
            $zip=Join-Path $TestDrive 'link.zip'; New-LabZip $zip @('link') -Link
            {Expand-VSOArchive $zip (Join-Path $TestDrive 'link-out') $script:ctx}|Should -Throw
        }
        It 'rejects corrupt and empty archives' {
            $zip=Join-Path $TestDrive 'invalid.zip'; [IO.File]::WriteAllText($zip,'not a zip')
            {Expand-VSOArchive $zip (Join-Path $TestDrive 'invalid-out') $script:ctx}|Should -Throw
            $empty=Join-Path $TestDrive 'empty.zip'; New-LabZip $empty @()
            {Expand-VSOArchive $empty (Join-Path $TestDrive 'empty-out') $script:ctx}|Should -Throw
        }
        It 'requires every protected file to be in the internal checksum manifest' {
            $root=Join-Path $TestDrive 'layout'; New-LabDistribution $root
            $manifest=Join-Path $root 'SHA256SUMS.txt'
            $lines=[IO.File]::ReadAllLines($manifest)|Where-Object {$_ -notmatch 'START VSO7.bat$'}
            [IO.File]::WriteAllLines($manifest,[string[]]$lines)
            {Get-VSODistribution $root $script:ctx -Package}|Should -Throw
        }
        It 'rejects changed content and unlisted package files' {
            $root=Join-Path $TestDrive 'changed'; New-LabDistribution $root
            [IO.File]::AppendAllText((Join-Path $root 'VSO7.ps1'),'changed')
            {Get-VSODistribution $root $script:ctx -Package}|Should -Throw
            $root2=Join-Path $TestDrive 'extra'; New-LabDistribution $root2
            [IO.File]::WriteAllText((Join-Path $root2 'unknown.ps1'),'throw')
            {Get-VSODistribution $root2 $script:ctx -Package}|Should -Throw
        }
        It 'accepts GNU asterisk checksum syntax' {
            $root=Join-Path $TestDrive 'gnu'; New-LabDistribution $root
            $p=Join-Path $root 'SHA256SUMS.txt'; $text=[IO.File]::ReadAllText($p).Replace('  ',' *'); [IO.File]::WriteAllText($p,$text)
            (Get-VSODistribution $root $script:ctx -Package).Layout|Should -Be 'vso7-classic-v1'
        }
        It 'accepts declared additional data and an absent optional file in schema 2' {
            $root=Join-Path $TestDrive 'contract2';New-LabDistribution $root -Contract2
            (Get-VSODistribution $root $script:ctx -Package).Files.Contains('Resources/next.json')|Should -BeTrue
            [IO.File]::Delete((Join-Path $root 'Resources/next.json'));Set-LabChecksums $root
            {Get-VSODistribution $root $script:ctx -Package}|Should -Not -Throw
        }
        It 'rejects incompatible contracts and discovered launchers even with fresh checksums' -TestCases @(
            @{Field='generation';Value='8'},@{Field='launcher';Value='evil.bat'},@{Field='packageType';Value='InstallerExe'},@{Field='schemaVersion';Value=99}
        ) {
            param($Field,$Value)
            $root=Join-Path $TestDrive ('contract-'+$Field);New-LabDistribution $root -Contract2
            $p=Join-Path $root 'vso-distribution.json';$d=Read-VSOJson $p $script:ctx;$d.$Field=$Value;Write-VSOJson $p $d $script:ctx;Set-LabChecksums $root
            {Get-VSODistribution $root $script:ctx -Package}|Should -Throw
        }
        It 'rejects required missing data and unlisted or executable extensions' {
            $root=Join-Path $TestDrive 'required2';New-LabDistribution $root -Contract2
            [IO.File]::Delete((Join-Path $root 'Config/default.json'));Set-LabChecksums $root
            {Get-VSODistribution $root $script:ctx -Package}|Should -Throw
            New-LabDistribution $root -Contract2
            [IO.File]::WriteAllText((Join-Path $root 'Resources/unknown.json'),'not declared');Set-LabChecksums $root
            {Get-VSODistribution $root $script:ctx -Package}|Should -Throw
            $d=Read-VSOJson (Join-Path $root 'vso-distribution.json') $script:ctx
            $d.optionalFiles+=@([pscustomobject]@{path='Resources/helper.ps1';role='Application'})
            {Get-VSOContractFiles $d $script:ctx}|Should -Throw
        }
        It 'rejects metadata ownership paths outside the canonical adapter inventory' {
            {ConvertTo-VSOFileMap @([pscustomobject]@{Path='../foreign.txt';Sha256=('a'*64)}) $TestDrive $script:ctx}|Should -Throw
            {ConvertTo-VSOFileMap @([pscustomobject]@{Path='foreign.txt';Sha256=('a'*64)}) $TestDrive $script:ctx}|Should -Throw
        }
    }
    Describe 'Official release resolution and transport failures' {
        BeforeEach { Mock Write-VSOProgress {} }
        It 'uses latest stable endpoint and real asset metadata' {
            Mock Invoke-VSOHttp { (New-LabApiRelease)|ConvertTo-Json -Depth 5 }
            $r=Get-VSORelease $script:ctx
            $r.AssetName|Should -Be 'official.zip'
            $r.Sha256|Should -Be ('a'*64)
            Should -Invoke Invoke-VSOHttp -Times 1 -ParameterFilter {$Uri.AbsolutePath.EndsWith('/latest')}
        }
        It 'handles a nonexistent explicit release' {
            Mock Invoke-VSOHttp {'[]'}
            {Get-VSORelease $script:ctx -Version 9.9.9}|Should -Throw '*not found*'
        }
        It 'propagates GitHub network failure without manufacturing a release' {
            Mock Invoke-VSOHttp {Throw-VSOError $Context Network @('unreachable')}
            {Get-VSORelease $script:ctx}|Should -Throw '*unreachable*'
        }
        It 'rejects a release with no archive digest or official checksum' {
            Mock Invoke-VSOHttp { (New-LabApiRelease -NoDigest)|ConvertTo-Json -Depth 5 }
            {Get-VSORelease $script:ctx}|Should -Throw '*SHA-256*'
        }
        It 'does not silently choose one of multiple ZIP assets' {
            Mock Invoke-VSOHttp { $r=New-LabApiRelease; $other=New-LabApiRelease; $other.assets[0].name='other.zip';$r.assets+=@($other.assets[0]);$r|ConvertTo-Json -Depth 5 }
            {Get-VSORelease $script:ctx}|Should -Throw '*AssetName*'
            (Get-VSORelease $script:ctx -AssetName official.zip).AssetName|Should -Be 'official.zip'
        }
        It 'requires the prerelease switch for a specific prerelease' {
            Mock Invoke-VSOHttp { @((New-LabApiRelease -Version '1.3.0-rc.1' -Prerelease))|ConvertTo-Json -Depth 5 }
            {Get-VSORelease $script:ctx -Version '1.3.0-rc.1'}|Should -Throw '*Prerelease*'
            (Get-VSORelease $script:ctx -Version '1.3.0-rc.1' -Prerelease).Prerelease|Should -BeTrue
        }
        It 'reports rate limiting and missing releases distinctly' {
            $uri=[uri]'https://api.github.com/repos/saturnus25/VSO/releases/latest'
            {Assert-VSOHttpStatus (New-LabHttpResponse 429) $uri $script:ctx}|Should -Throw '*rate limit*'
            {Assert-VSOHttpStatus (New-LabHttpResponse 403 @{'X-RateLimit-Remaining'=@('0');'X-RateLimit-Reset'=@('123')}) $uri $script:ctx}|Should -Throw
            {Assert-VSOHttpStatus (New-LabHttpResponse 404) $uri $script:ctx}|Should -Throw '*not found*'
            {Assert-VSOHttpStatus (New-LabHttpResponse 503) $uri $script:ctx}|Should -Throw '*HTTP 503*'
        }
        It 'rejects non-official URLs and unsafe redirects' -TestCases @(
            @{U='http://github.com/saturnus25/VSO/releases/download/v1/a.zip'},
            @{U='https://example.invalid/a.zip'},@{U='https://github.com/other/VSO/releases/download/v1/a.zip'},
            @{U='https://api.github.com:444/repos/saturnus25/VSO/releases/latest'}
        ) {param($U) {Assert-VSOUri ([uri]$U) $script:ctx -Redirect}|Should -Throw}
    }
}
