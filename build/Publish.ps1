[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([string]$PackagePath,[string]$ValidationPath,[string]$ApprovalPath,[Security.SecureString]$ApiKey,[switch]$Publish)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $PackagePath) {$PackagePath=Join-Path $project 'dist/VSO.1.0.2.nupkg'}
if (-not $ValidationPath) {$ValidationPath=Join-Path $project '.work/validated-package.json'}
if (-not $ApprovalPath) {$ApprovalPath=Join-Path $project '.work/approved-package.json'}
. (Join-Path $PSScriptRoot 'PackageContract.ps1')
# Preparation never builds, requests secrets or publishes.
$handle=[IO.FileStream]::new($PackagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
$pointer=[IntPtr]::Zero;$plain=$null
try {
    $validated=Assert-ReleaseValidation $PackagePath $ValidationPath $project
    $approval=Get-Content -LiteralPath $ApprovalPath -Raw | ConvertFrom-Json
    if ($approval.Schema -ne 1 -or $approval.Product -cne 'VSO' -or $approval.LabAcceptanceComplete -ne $true -or $approval.Sha256 -cne $validated.Sha256 -or $approval.ValidationSha256 -cne (Get-FileHash -LiteralPath $ValidationPath -Algorithm SHA256).Hash.ToLowerInvariant()) {throw 'Approval invalidated. Validate and approve the exact package again.'}
    $null=Test-ReleasePackage $PackagePath (Join-Path $project 'dist/VSO')
    if (-not $Publish) { [pscustomobject]@{Publish=$false;Sha256=$validated.Sha256;ApprovalVerified=$true};return }
    if (-not $PSCmdlet.ShouldProcess(('PSGallery / VSO 1.0.2 / SHA256 '+$validated.Sha256),'Publish approved package bytes')) {return}
    $publisher=Get-Command Publish-PSResource -ErrorAction Stop
    if (-not $publisher.Parameters.ContainsKey('NupkgPath')) {throw 'PSResourceGet with NupkgPath support is required.'}
    if (-not $ApiKey) {$ApiKey=Read-Host -Prompt 'PowerShell Gallery API key' -AsSecureString}
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($ApiKey)
    $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    # Recheck after confirmation/key entry. The shared-read handle denies writes
    # and replacement throughout validation and the official publisher's call.
    $null=Assert-ReleaseValidation $PackagePath $ValidationPath $project
    if ((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $approval.Sha256) {throw 'Approved package changed immediately before publication.'}
    Publish-PSResource -NupkgPath $PackagePath -Repository PSGallery -ApiKey $plain -Confirm:$false
}finally{$plain=$null;if ($pointer -ne [IntPtr]::Zero) {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)};$handle.Dispose()}
