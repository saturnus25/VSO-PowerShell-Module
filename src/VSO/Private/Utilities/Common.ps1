function Get-VSOProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] }; return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}

function Assert-VSOPlatform {
    param($Context)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem) { Throw-VSOError $Context Platform }
    if (-not [Environment]::Is64BitProcess) { Throw-VSOError $Context Platform }
    # Windows 11 client uses build 22000 or later. Server has a separate product type.
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.BuildNumber -lt 22000 -or [int]$os.ProductType -ne 1) { Throw-VSOError $Context Platform }
    $processors=@(Get-CimInstance -ClassName Win32_Processor -Property Architecture -ErrorAction Stop)
    # Win32_Processor distinguishes x64 (9) from ARM64 (12), including emulation.
    if ($processors.Count -eq 0 -or @($processors|Where-Object {[int]$_.Architecture -ne 9}).Count -gt 0) { Throw-VSOError $Context Platform }
}

function Test-VSOAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    finally { $identity.Dispose() }
}

function Assert-VSOQuietConfirmation {
    param($Context,$Parameters)
    if ($Context.Quiet -and $Parameters.ContainsKey('Confirm') -and $Parameters['Confirm']) { Throw-VSOError $Context QuietConfirm }
}

function Get-VSOSystemDirectory {
    param($Context)
    $path=[Environment]::GetFolderPath([Environment+SpecialFolder]::System)
    if (-not $path -or -not [IO.Directory]::Exists($path)) { Throw-VSOError $Context Platform }
    Assert-VSONoReparse $path $Context
    return $path
}

function Write-VSOProgress {
    param($Context, [string]$Key, [long]$Done = -1, [long]$Total = -1, [switch]$Completed)
    if ($Context.Quiet) { return }
    if ($Completed) {
        Write-Progress -Id 732 -ParentId 731 -Activity $Context.Text[$Key] -Completed
        Write-Progress -Id 731 -Activity $Context.Text.Activity -Completed
        return
    }
    Write-Progress -Id 731 -Activity $Context.Text.Activity -Status $Context.Text[$Key]
    $p = @{ Id = 732; ParentId = 731; Activity = $Context.Text[$Key]; Status = $Context.Text[$Key] }
    if ($Done -ge 0 -and $Total -gt 0) { $p.PercentComplete = [int][Math]::Min(100, [Math]::Floor(100.0 * $Done / $Total)) }
    else { $p.PercentComplete = -1 }
    Write-Progress @p
}

function Read-VSOJson {
    param([string]$Path, $Context, [int]$MaximumBytes = 2097152)
    Assert-VSONoReparse $Path $Context
    $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt $MaximumBytes) { Throw-VSOError $Context Metadata }
    try { return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop) }
    catch { Throw-VSOError $Context Metadata @($_.Exception.Message) }
}

function Write-VSOJson {
    param([string]$Path, $Value, $Context)
    Assert-VSONoReparse $Path $Context
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 15), [Text.UTF8Encoding]::new($false))
        # Windows PowerShell converts $null to an empty String for this overload.
        # NullString preserves the native null backup name required by File.Replace.
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Get-VSOHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Get-VSOSourceTextHash {
    param([string]$Path,$Context)
    Assert-VSONoReparse $Path $Context
    if (([IO.FileInfo]::new($Path)).Length -gt 16777216) { Throw-VSOError $Context Integrity @('source text size') }
    # Upstream's protected memory host hashes UTF-8 source text without the disk BOM.
    # This identity is distinct from the package/receipt byte hash.
    $text=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash(([Text.UTF8Encoding]::new($false)).GetBytes($text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-VSOVersion {
    param([string]$Version, $Context)
    $value = $Version -replace '^[vV]', ''
    if ($value -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z.-]+))?$') { Throw-VSOError $Context Version @($Version) }
    $major=[string]$Matches[1]; $minor=[string]$Matches[2]; $patch=[string]$Matches[3]
    $pre = [string]$Matches[4]
    foreach ($piece in @($pre -split '\.')) { if ($piece -match '^0[0-9]+$') { Throw-VSOError $Context Version @($Version) } }
    return [pscustomobject]@{ Text=$value; Major=$major; Minor=$minor; Patch=$patch; Pre=$pre }
}

function Compare-VSOVersion {
    param([string]$Left, [string]$Right, $Context)
    $a = ConvertTo-VSOVersion $Left $Context; $b = ConvertTo-VSOVersion $Right $Context
    foreach ($part in @('Major','Minor','Patch')) { $comparison=Compare-VSONumeric $a.$part $b.$part; if ($comparison) { return $comparison } }
    if ($a.Pre -ceq $b.Pre) { return 0 }; if (-not $a.Pre) { return 1 }; if (-not $b.Pre) { return -1 }
    $x = @($a.Pre -split '\.'); $y = @($b.Pre -split '\.')
    for ($i=0; $i -lt [Math]::Min($x.Count,$y.Count); $i++) {
        if ($x[$i] -ceq $y[$i]) { continue }
        $xn=$x[$i] -match '^\d+$'; $yn=$y[$i] -match '^\d+$'
        if ($xn -and $yn) { return (Compare-VSONumeric $x[$i] $y[$i]) }
        if ($xn) { return -1 }; if ($yn) { return 1 }
        return [Math]::Sign([StringComparer]::Ordinal.Compare($x[$i],$y[$i]))
    }
    return [Math]::Sign($x.Count-$y.Count)
}

function Compare-VSONumeric {
    param([string]$Left,[string]$Right)
    if ($Left.Length -ne $Right.Length) { return [Math]::Sign($Left.Length-$Right.Length) }
    return [Math]::Sign([StringComparer]::Ordinal.Compare($Left,$Right))
}
