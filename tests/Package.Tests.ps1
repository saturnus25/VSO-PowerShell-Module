if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
Describe 'Publication artifacts and privacy' {
    It 'audits the entire public project without importing its runtime' {
        $result=& (Join-Path $env:VSO_MODULE_LAB_PROJECT 'build/Test-Privacy.ps1') -Path $env:VSO_MODULE_LAB_PROJECT
        $result.Attribution|Should -BeExactly 'saturnus25'
    }
    It 'rejects private data in a public text fixture without exposing the value' {
        $fixture=Join-Path $TestDrive 'public.txt'
        [IO.File]::WriteAllText($fixture,('private'+'@'+'example'+'.invalid'))
        {& (Join-Path $env:VSO_MODULE_LAB_PROJECT 'build/Test-Privacy.ps1') -Path $fixture}|Should -Throw '*Privacy audit failed*'
    }
    It 'has generated MAML for both languages and an English root fallback' {
        $module=Split-Path -Parent $env:VSO_MODULE_LAB_MANIFEST
        foreach ($relative in @('VSO-help.xml','en-US/VSO-help.xml','es-ES/VSO-help.xml')) {
            $xml=[xml][IO.File]::ReadAllText((Join-Path $module $relative))
            @($xml.SelectNodes('//*[local-name()="command"]')).Count|Should -Be 8
        }
    }
    It 'keeps built artifacts free of test and build files' -Skip:($env:VSO_MODULE_LAB_MANIFEST -match '[\\/]src[\\/]') {
        $module=Split-Path -Parent $env:VSO_MODULE_LAB_MANIFEST
        foreach ($relative in @('tests','build','AGENTS.md','VSO7.ps1','VSO8')) {Test-Path -LiteralPath (Join-Path $module $relative)|Should -BeFalse}
    }
    It 'ships the custom license without the repository-only disclosure' {
        $module=Join-Path $env:VSO_MODULE_LAB_PROJECT 'dist/VSO'
        $license=[IO.File]::ReadAllText((Join-Path $module 'LICENSE'))
        $license|Should -Match '^VSO PowerShell Module Source-Available License 1.0'
        $license|Should -Match 'personal or professional'
        foreach ($file in @(Get-ChildItem -LiteralPath $module -Recurse -File)) {
            [IO.File]::ReadAllText($file.FullName)|Should -Not -Match 'developed with substantial assistance from artificial intelligence'
        }
    }
}
Describe 'Exact package preparation without keys or publication' {
    BeforeAll {
        $script:project=$env:VSO_MODULE_LAB_PROJECT
        $script:build=Join-Path $script:project 'build'
        # Test-local stand-in also works on Desktop without PSResourceGet installed.
        function Publish-PSResource {param($NupkgPath,$Repository,$ApiKey,[switch]$Confirm) throw 'Actual publication forbidden in tests'}
        . (Join-Path $script:build 'PackageContract.ps1')
        $script:originalPackage=Join-Path $script:project 'dist/VSO.1.0.2.nupkg'
        $script:validation=Join-Path $TestDrive 'validated.json';$script:approval=Join-Path $TestDrive 'approved.json'
        $proof=@(foreach ($edition in @('Desktop','Core')) {foreach ($kind in @('src','dist','package')) {
            $p=Join-Path $TestDrive ($edition+'-'+$kind+'-synthetic.xml')
            [IO.File]::WriteAllText($p,('<test-results total="1" failures="0" errors="0" skipped="0"><!-- Synthetic '+$edition+' '+$kind+' fixture; never acceptance evidence. --></test-results>'));$p
        }})
        $script:record=& (Join-Path $script:build 'Validate.ps1') -PackagePath $script:originalPackage -RecordPath $script:validation -EvidencePath $proof
        $null=& (Join-Path $script:build 'Approve.ps1') -PackagePath $script:originalPackage -ValidationPath $script:validation -RecordPath $script:approval -ExpectedSha256 $script:record.Sha256 -LabAcceptanceComplete -Confirm:$false
    }
    BeforeEach {
        $script:copy=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.nupkg')
        [IO.File]::Copy($script:originalPackage,$script:copy)
        Mock Publish-PSResource {throw 'Actual publication forbidden in tests'}
        Mock Read-Host {throw 'Secret prompt forbidden in tests'}
    }
    It 'verifies the approved bytes without rebuilding, requesting keys or publishing' {
        $before=(Get-FileHash $script:originalPackage).Hash
        $r=& (Join-Path $script:build 'Publish.ps1') -PackagePath $script:copy -ValidationPath $script:validation -ApprovalPath $script:approval
        $r.ApprovalVerified|Should -BeTrue
        (Get-FileHash $script:originalPackage).Hash|Should -Be $before
        Should -Invoke Publish-PSResource -Times 0
        Should -Invoke Read-Host -Times 0
        & (Join-Path $script:build 'Publish.ps1') -PackagePath $script:copy -ValidationPath $script:validation -ApprovalPath $script:approval -Publish -WhatIf
        Should -Invoke Publish-PSResource -Times 0
    }
    It 'invalidates approval when the same filename and version contain different bytes' {
        $stream=[IO.File]::Open($script:copy,[IO.FileMode]::Append)
        try {$stream.WriteByte(0)}finally{$stream.Dispose()}
        {& (Join-Path $script:build 'Publish.ps1') -PackagePath $script:copy -ValidationPath $script:validation -ApprovalPath $script:approval -Publish -WhatIf}|Should -Throw '*invalidated*'
        Should -Invoke Publish-PSResource -Times 0
    }
    It 'keeps the approved package pinned through a simulated publisher call' {
        $previousExpectation=Get-Variable VsoLabPublisherExpectedHash -Scope Global -ErrorAction SilentlyContinue
        $global:VsoLabPublisherExpectedHash=$script:record.Sha256
        Mock Publish-PSResource {
            param($NupkgPath)
            (Get-FileHash $NupkgPath).Hash.ToLowerInvariant()|Should -Be $global:VsoLabPublisherExpectedHash
            { $stream=[IO.File]::Open($NupkgPath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$stream.Dispose() }|Should -Throw
            [pscustomobject]@{Simulated=$true;Published=$false}
        }
        $fixtureKey=[Security.SecureString]::new();$fixtureKey.AppendChar([char]32)
        try {
            $r=& (Join-Path $script:build 'Publish.ps1') -PackagePath $script:copy -ValidationPath $script:validation -ApprovalPath $script:approval -Publish -ApiKey $fixtureKey -Confirm:$false
            $r.Simulated|Should -BeTrue
            Should -Invoke Publish-PSResource -Times 1 -Exactly -ParameterFilter {$NupkgPath -eq $script:copy}
        }finally{
            $fixtureKey.Dispose()
            if($previousExpectation){$global:VsoLabPublisherExpectedHash=$previousExpectation.Value}else{Remove-Variable VsoLabPublisherExpectedHash -Scope Global -ErrorAction SilentlyContinue}
        }
        Should -Invoke Read-Host -Times 0
    }
    It 'rejects unexpected files inside an otherwise valid nupkg' {
        $zip=[IO.Compression.ZipFile]::Open($script:copy,[IO.Compression.ZipArchiveMode]::Update)
        try {$null=$zip.CreateEntry('unreviewed.txt')}finally{$zip.Dispose()}
        {Test-ReleasePackage $script:copy (Join-Path $script:project 'dist/VSO')}|Should -Throw '*Unexpected*'
    }
    It 'does not create approval without manual acceptance or for a mismatched expected hash' {
        $p=Join-Path $TestDrive 'not-approved.json'
        {& (Join-Path $script:build 'Approve.ps1') -PackagePath $script:copy -ValidationPath $script:validation -RecordPath $p -ExpectedSha256 $script:record.Sha256 -Confirm:$false}|Should -Throw '*manual*'
        {& (Join-Path $script:build 'Approve.ps1') -PackagePath $script:copy -ValidationPath $script:validation -RecordPath $p -ExpectedSha256 ('0'*64) -LabAcceptanceComplete -Confirm:$false}|Should -Throw '*differs*'
        Test-Path $p|Should -BeFalse
    }
    It 'invalidates validation when reviewed inputs change' {
        $fixture=Join-Path $TestDrive 'review-inputs';[void][IO.Directory]::CreateDirectory($fixture)
        foreach ($name in @('src','docs','build','tests')) {[void][IO.Directory]::CreateDirectory((Join-Path $fixture $name))}
        $readme=Join-Path $fixture 'README.md';[IO.File]::WriteAllText($readme,'Reviewed input')
        $p=Join-Path $TestDrive 'input-validation.json'
        @{Schema=1;Product='VSO';Sha256=(Get-FileHash $script:copy).Hash.ToLowerInvariant();InputSha256=(Get-ReleaseInputIdentity $fixture);Evidence=@()}|ConvertTo-Json|Set-Content $p
        {Assert-ReleaseValidation $script:copy $p $fixture}|Should -Not -Throw
        [IO.File]::AppendAllText($readme,' changed')
        {Assert-ReleaseValidation $script:copy $p $fixture}|Should -Throw '*inputs changed*'
    }
}
