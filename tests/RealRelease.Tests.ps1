if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
InModuleScope VSO {
    Describe 'Live official release data inspection; no application execution' -Tag Network {
        It 'downloads and validates the latest official payload as data in TestDrive' -Skip:($env:VSO_MODULE_LAB_NETWORK -ne 'True') {
            $context=New-VSOContext en -Quiet
            $release=Get-VSORelease $context
            $zip=Join-Path $TestDrive 'official.zip'
            Invoke-VSOHttp ([uri]$release.AssetUri) $context -OutFile $zip -ExpectedSize $release.Size -MaximumBytes 134217728
            Get-VSOHash $zip|Should -BeExactly $release.Sha256
            $out=Join-Path $TestDrive 'extracted';[void][IO.Directory]::CreateDirectory($out)
            Expand-VSOArchive $zip $out $context
            $root=Find-VSOPackageRoot $out $context
            (Get-VSODistribution $root $context -ExpectedVersion $release.Version -Package).Launcher|Should -BeExactly 'START VSO7.bat'
        }
    }
}
