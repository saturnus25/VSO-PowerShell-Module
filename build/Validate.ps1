[CmdletBinding()]
param([string]$PackagePath,[string]$RecordPath,[string[]]$EvidencePath)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $PackagePath) {$PackagePath=Join-Path $project 'dist/VSO.1.0.1.nupkg'}
if (-not $RecordPath) {$RecordPath=Join-Path $project '.work/validated-package.json'}
. (Join-Path $PSScriptRoot 'PackageContract.ps1')
$handle=[IO.FileStream]::new($PackagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
    $null=& (Join-Path $PSScriptRoot 'Test-Static.ps1') -ProjectPath $project
    $package=Test-ReleasePackage $PackagePath (Join-Path $project 'dist/VSO')
    $null=& (Join-Path $PSScriptRoot 'Test-Privacy.ps1') -Path $PackagePath
    $evidence=@(foreach ($path in @($EvidencePath | Where-Object {$_})) {
        $full=[IO.Path]::GetFullPath($path);$xml=[xml][IO.File]::ReadAllText($full)
        if (-not $xml.'test-results' -or [int]$xml.'test-results'.failures -ne 0 -or [int]$xml.'test-results'.errors -ne 0 -or [int]$xml.'test-results'.total -lt 1) {throw 'Failed or invalid Pester evidence.'}
        if ([IO.Path]::GetFileName($full) -notmatch '^(Desktop|Core)-(src|dist|package)-') {throw 'Evidence filename must identify its edition and artifact.'}
        [ordered]@{Path=$full;Edition=$Matches[1];Artifact=$Matches[2];Sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant();Total=[int]$xml.'test-results'.total;Skipped=[int]$xml.'test-results'.skipped}
    })
    $record=[ordered]@{Schema=1;Product='VSO';Version=$package.Version;Sha256=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant();InputSha256=(Get-ReleaseInputIdentity $project);ValidatedUtc=[DateTime]::UtcNow.ToString('o');Evidence=$evidence;Validation='Static content, privacy and input identity; supplied Pester evidence does not replace manual acceptance.'}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($RecordPath)))
    [IO.File]::WriteAllText($RecordPath,($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    [pscustomobject]$record
} finally {$handle.Dispose()}
