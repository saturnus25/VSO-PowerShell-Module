[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([Parameter(Mandatory=$true)][string]$ValidationPath,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedSha256,[string]$PackagePath,[string]$RecordPath,[switch]$LabAcceptanceComplete)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $PackagePath) {$PackagePath=Join-Path $project 'dist/VSO.1.0.0.nupkg'}
if (-not $RecordPath) {$RecordPath=Join-Path $project '.work/approved-package.json'}
. (Join-Path $PSScriptRoot 'PackageContract.ps1')
$handle=[IO.FileStream]::new($PackagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
    $validated=Assert-ReleaseValidation $PackagePath $ValidationPath $project
    if ($validated.Sha256 -cne $ExpectedSha256) {throw 'Expected approval SHA-256 differs.'}
    if (-not $LabAcceptanceComplete -or @($validated.Evidence).Count -ne 6) {throw 'Six passing matrix records and explicit completion of manual lab acceptance are required. Do not approve CONDITIONAL candidates.'}
    $pairs=@($validated.Evidence|ForEach-Object {$_.Edition+'/'+$_.Artifact}|Sort-Object -Unique)
    $expected=@('Core/dist','Core/package','Core/src','Desktop/dist','Desktop/package','Desktop/src')
    if (@(Compare-Object $expected $pairs).Count -or @($validated.Evidence.Sha256|Sort-Object -Unique).Count -ne 6) {throw 'Approval requires six distinct edition/artifact matrix records.'}
    if (-not $PSCmdlet.ShouldProcess(('VSO 1.0.0 SHA256 '+$ExpectedSha256),'Record exact package approval')) {return}
    $record=[ordered]@{Schema=1;Product='VSO';Sha256=$ExpectedSha256;ValidationSha256=(Get-FileHash -LiteralPath $ValidationPath -Algorithm SHA256).Hash.ToLowerInvariant();ApprovedUtc=[DateTime]::UtcNow.ToString('o');LabAcceptanceComplete=$true}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($RecordPath)))
    [IO.File]::WriteAllText($RecordPath,($record|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [pscustomobject]$record
}finally{$handle.Dispose()}
