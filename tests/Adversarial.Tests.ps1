if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
InModuleScope VSO {
    BeforeAll { . (Join-Path $env:VSO_MODULE_LAB_PROJECT 'tests/Fixtures.ps1'); $script:ctx=New-VSOContext en -Quiet }
    Describe 'Bounded adversarial inputs and actual Windows exclusion' {
        It 'creates a protected directory without emitting implementation objects' {
            @(New-VSOSecureDirectory (Join-Path $TestDrive 'private-directory') CurrentUser $script:ctx).Count|Should -Be 0
        }
        It 'atomically replaces JSON on both editions without an empty backup path' {
            $path=Join-Path $TestDrive 'atomic.json'
            Write-VSOJson $path @{State='First'} $script:ctx
            Write-VSOJson $path @{State='Second'} $script:ctx
            (Read-VSOJson $path $script:ctx).State|Should -BeExactly 'Second'
            # Native Windows -Filter also matches an extensionless base for "x.*".
            @(Get-ChildItem -LiteralPath $TestDrive -File|Where-Object Name -like 'atomic.json.*').Count|Should -Be 0
        }
        It 'rejects a controlled high-ratio archive before extracting any file' {
            Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
            $zipPath=Join-Path $TestDrive 'bounded-bomb.zip'
            $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
            try{
                $stream=$zip.CreateEntry('zeros.bin',[IO.Compression.CompressionLevel]::Optimal).Open()
                try{$block=New-Object byte[] 65536;for($i=0;$i -lt 176;$i++){$stream.Write($block,0,$block.Length)}}finally{$stream.Dispose()}
            }finally{$zip.Dispose()}
            $out=Join-Path $TestDrive 'bomb-out';[void][IO.Directory]::CreateDirectory($out)
            {Expand-VSOArchive $zipPath $out $script:ctx}|Should -Throw
            @(Get-ChildItem -LiteralPath $out -Force).Count|Should -Be 0
        }
        It 'rejects an archive exceeding the bounded entry count' {
            Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
            $zipPath=Join-Path $TestDrive 'many-entries.zip'
            $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
            try{for($i=0;$i -lt 10001;$i++){$null=$zip.CreateEntry(('entry'+$i+'.txt'))}}finally{$zip.Dispose()}
            {Expand-VSOArchive $zipPath (Join-Path $TestDrive 'many-out') $script:ctx}|Should -Throw
        }
        It 'fails closed on manipulated or incomplete release JSON' -TestCases @(
            @{Json='{'},@{Json='null'},@{Json='{}'},@{Json='{"tag_name":"v1.2.2","draft":false}'},
            @{Json='{"tag_name":"v1.2.2","draft":false,"assets":[{"name":"x.zip","state":"uploaded","size":1,"browser_download_url":"file:///C:/outside.zip"}]}'},
            @{Json='{"tag_name":"v999.0","draft":false,"assets":[]}'}
        ) {
            param($Json)
            $script:adversarialJson=$Json
            Mock Invoke-VSOHttp {$script:adversarialJson}
            {Get-VSORelease $script:ctx}|Should -Throw
        }
        It 'holds an exclusive installation lock against a second real Windows process' {
            $target=Join-Path $TestDrive 'concurrent-install';$out=Join-Path $TestDrive 'child-result.json'
            $lock=Enter-VSOLock $target $script:ctx
            $child=$null
            try{
                $manifest=$env:VSO_MODULE_LAB_MANIFEST.Replace("'","''")
                $safeTarget=$target.Replace("'","''");$safeOut=$out.Replace("'","''")
                $code="Import-Module '$manifest' -Force; & (Get-Module VSO) { param(`$target,`$out) `$ctx=New-VSOContext en -Quiet; try{`$l=Enter-VSOLock `$target `$ctx;`$l.Dispose();`$r=@{Acquired=`$true}}catch{`$r=@{Acquired=`$false;ErrorId=`$_.FullyQualifiedErrorId}};`$r|ConvertTo-Json|Set-Content -LiteralPath `$out } '$safeTarget' '$safeOut'"
                $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
                $binary=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Desktop'){'powershell.exe'}else{'pwsh.exe'})
                $child=Start-Process -FilePath $binary -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -WindowStyle Hidden -PassThru
                $child.WaitForExit(60000)|Should -BeTrue
                $result=Get-Content -LiteralPath $out -Raw|ConvertFrom-Json
                $result.Acquired|Should -BeFalse
                $result.ErrorId|Should -Match '^VSO\.Busy'
            }finally{if($child){if(-not $child.HasExited){$child.Kill();$null=$child.WaitForExit(10000)};$child.Dispose()};$lock.Dispose()}
            { $available=Enter-VSOLock $target $script:ctx; $available.Dispose() }|Should -Not -Throw
        }
    }
}
