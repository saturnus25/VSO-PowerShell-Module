function Get-VSO7RequiredFiles {
    return @('START VSO7.bat','VSO7.ps1','VSO7_7.0.0_RC_R80.ps1','Tools/VSO7_STARTUP_GATE.ps1','Resources/VSO7_APP_CATALOG.json','Resources/VSO7_FEATURE_CATALOG.json','Resources/VSO7_NATIVE_TWEAKS.json','Resources/VSO7_SANITY_FIXTURES.json','Resources/VSO7_TWEAK_RESEARCH.json','LICENSE.Win11Debloat.txt','README.md','THIRD_PARTY_NOTICES.md','UNBLOCK VSO7.bat')
}

function Get-VSOContractFiles {
    param($Definition, $Context)
    $schema=Get-VSOProperty $Definition schemaVersion 0
    $fields=@('schemaVersion','product','generation','version','platform','adapter','launcher','launcherType','requirements','filesManifest','persistentData','update','uninstall')
    if ($schema -eq 2) { $fields+=@('packageType','requiredFiles','optionalFiles') }
    if ($schema -notin @(1,2) -or @(Compare-Object $fields @($Definition.PSObject.Properties.Name)).Count) { Throw-VSOError $Context Layout @('manifest fields or schema') }
    if ($Definition.product -cne 'VicoSafeOptimizer' -or $Definition.platform -cne 'windows-x64' -or $Definition.generation -ne '7' -or $Definition.adapter -cne 'vso7-classic-v1' -or $Definition.launcher -cne 'START VSO7.bat' -or $Definition.launcherType -cne 'Batch') { Throw-VSOError $Context Layout @('adapter not implemented for this generation or launcher') }
    $null=ConvertTo-VSOVersion ([string]$Definition.version) $Context
    $requirements=$Definition.requirements
    foreach ($pair in @(@('requirements',@('host','minimumVersion','architecture')),@('update',@('compatibleGenerations','preserveUnknownFiles')),@('uninstall',@('restoreWindowsTweaks','preserveUnknownFiles')))) {
        if (@(Compare-Object @($pair[1]) @($Definition.($pair[0]).PSObject.Properties.Name)).Count) { Throw-VSOError $Context Layout @('nested contract fields') }
    }
    if ($requirements.host -cne 'WindowsPowerShell' -or $requirements.minimumVersion -ne '5.1' -or $requirements.architecture -cne 'x64' -or $Definition.filesManifest -cne 'SHA256SUMS.txt') { Throw-VSOError $Context Layout @('host or checksum contract') }
    $update=$Definition.update; $uninstall=$Definition.uninstall
    if (@($update.compatibleGenerations).Count -ne 1 -or @($update.compatibleGenerations)[0] -ne '7' -or $update.preserveUnknownFiles -ne $true -or $uninstall.restoreWindowsTweaks -ne $false -or $uninstall.preserveUnknownFiles -ne $true) { Throw-VSOError $Context Layout @('migration or uninstall contract') }
    foreach ($location in @($Definition.persistentData)) {
        if (@(Compare-Object @('base','path','ownership','removeByDefault') @($location.PSObject.Properties.Name)).Count) { Throw-VSOError $Context Layout @('persistence fields') }
        $known=($location.base -ceq 'Installation' -and $location.path -cin @('Logs','Informes','Config','Recuperacion')) -or ($location.base -ceq 'ProgramData' -and $location.path -ceq 'VicoreDevelopment/VSO7')
        if (-not $known -or $location.ownership -cne 'SharedOrUntracked' -or $location.removeByDefault -ne $false) { Throw-VSOError $Context Layout @('persistent data ownership') }
    }
    $inventory=[ordered]@{}
    if ($schema -eq 1) { return $inventory }
    if ($Definition.packageType -cne 'PortableZip') { Throw-VSOError $Context Layout @('package type') }
    $core=@((Get-VSO7RequiredFiles)+@('LICENSE','LICENSE.txt'))
    foreach ($group in @('requiredFiles','optionalFiles')) {
        foreach ($entry in @($Definition.$group)) {
            if (@(Compare-Object @('path','role') @($entry.PSObject.Properties.Name)).Count) { Throw-VSOError $Context Layout @('inventory fields') }
            $path=[string]$entry.path; $role=[string]$entry.role
            # This adapter can extend data, never discover executable launchers from a ZIP.
            $data=$path -cmatch '^(Resources|Docs|Config|Cache|Logs|Temp|Recuperacion)/[A-Za-z0-9_/-]+\.(json|txt|md|xml|csv|ini|dat)$'
            if ($path -cnotin $core -and -not $data) { Throw-VSOError $Context Layout @('unsupported additional file: '+$path) }
            if ($path -match '(^|/)\.{1,2}(/|$)' -or $inventory.Contains($path) -or $role -cnotin @('Application','Configuration','Cache','Log','Temporary','Recovery')) { Throw-VSOError $Context Layout @('inventory identity or role') }
            if ($path -cin $core -and ($role -cne 'Application' -or $group -cne 'requiredFiles')) { Throw-VSOError $Context Layout @('required adapter file') }
            if ($path -clike 'Recuperacion/*' -and $role -cne 'Recovery') { Throw-VSOError $Context Layout @('Recovery ownership') }
            $inventory[$path]=[pscustomobject]@{Role=$role;Required=($group -eq 'requiredFiles')}
        }
    }
    foreach ($path in (Get-VSO7RequiredFiles)) { if (-not $inventory.Contains($path)) { Throw-VSOError $Context Layout @('missing adapter requirement: '+$path) } }
    if (-not $inventory.Contains('LICENSE') -and -not $inventory.Contains('LICENSE.txt')) { Throw-VSOError $Context Layout @('MIT license requirement') }
    return $inventory
}

function Get-VSODistribution {
    param([string]$Root, $Context, [string]$ExpectedVersion, [switch]$Package)
    Assert-VSONoReparse $Root $Context
    $manifestPath=Join-VSOChild $Root 'vso-distribution.json' $Context
    $generation='7'; $layout='vso7-classic-v1'; $launcher='START VSO7.bat'; $launcherType='Batch'; $version=$ExpectedVersion
    $definition=$null; $inventory=[ordered]@{}
    if ([IO.File]::Exists($manifestPath)) {
        $definition=Read-VSOJson $manifestPath $Context
        $inventory=Get-VSOContractFiles $definition $Context
        $version=[string]$definition.version
        if ($ExpectedVersion -and $version -ne $ExpectedVersion) { Throw-VSOError $Context Integrity @('version mismatch') }
    }
    foreach ($relative in (Get-VSO7RequiredFiles)) {
        $file=Join-VSOChild $Root $relative $Context
        if (-not [IO.File]::Exists($file)) { Throw-VSOError $Context Layout @($relative) }
    }
    if (-not [IO.File]::Exists((Join-Path $Root 'LICENSE')) -and -not [IO.File]::Exists((Join-Path $Root 'LICENSE.txt'))) { Throw-VSOError $Context Layout @('MIT license') }
    $files=Read-VSOChecksumManifest $Root $Context
    if (-not $files.Contains('LICENSE') -and -not $files.Contains('LICENSE.txt')) { Throw-VSOError $Context Integrity @('license checksum') }
    foreach ($relative in (Get-VSO7RequiredFiles)) { if (-not $files.Contains($relative)) { Throw-VSOError $Context Integrity @($relative) } }
    if ($files['VSO7.ps1'] -cne $files['VSO7_7.0.0_RC_R80.ps1']) { Throw-VSOError $Context Integrity @('protected core copies differ') }
    $allowed=@((Get-VSO7RequiredFiles)+@('LICENSE','LICENSE.txt','vso-distribution.json'))
    if ($definition -and $definition.schemaVersion -eq 2) {
        $allowed+=@($inventory.Keys)
        foreach ($relative in $inventory.Keys) { if ($inventory[$relative].Required -and -not $files.Contains($relative)) { Throw-VSOError $Context Integrity @($relative) } }
    }
    # Additional data must be explicitly declared by the versioned contract.
    foreach ($relative in $files.Keys) { if ($relative -cnotin $allowed) { Throw-VSOError $Context Layout @($relative) } }
    if ([IO.File]::Exists($manifestPath) -and -not $files.Contains('vso-distribution.json')) { Throw-VSOError $Context Integrity @('unsigned distribution manifest') }
    $index=0
    foreach ($relative in $files.Keys) {
        $file=Join-VSOChild $Root $relative $Context
        if (-not [IO.File]::Exists($file) -or (Get-VSOHash $file) -cne $files[$relative]) { Throw-VSOError $Context Integrity @($relative) }
        $index++; Write-VSOProgress $Context Verify $index $files.Count
    }
    $files['SHA256SUMS.txt']=Get-VSOHash (Join-Path $Root 'SHA256SUMS.txt')
    if ($Package) {
        foreach ($file in @(Get-VSOTreeFiles $Root $Context)) {
            $relative=$file.FullName.Substring($Root.TrimEnd('\').Length+1).Replace('\','/')
            if (-not $files.Contains($relative)) { Throw-VSOError $Context Layout @('unlisted file: '+$relative) }
        }
    }
    if (-not $version) {
        $batch=[IO.File]::ReadAllText((Join-Path $Root $launcher))
        if ($batch -match '(?m)^title VSO7 ([0-9]+\.[0-9]+\.[0-9]+) ') { $version=$Matches[1] } else { $version='Unknown' }
    }
    return [pscustomobject]@{ Root=$Root; Generation=$generation; Layout=$layout; Launcher=$launcher; LauncherType=$launcherType; Version=$version; Files=$files; Contract=$definition; PersistentRelative=@('Logs','Informes','Config','Recuperacion'); SharedData=(Join-Path $env:ProgramData 'VicoreDevelopment\VSO7') }
}

function Find-VSOPackageRoot {
    param([string]$Extracted, $Context)
    # All six inspected official releases contain a single VSO7 top-level folder.
    $children=@(Get-ChildItem -LiteralPath $Extracted -Force -ErrorAction Stop)
    if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
        $root=$children[0].FullName
        if ([IO.File]::Exists((Join-Path $root 'START VSO7.bat')) -or [IO.File]::Exists((Join-Path $root 'vso-distribution.json'))) { return $root }
    }
    if ([IO.File]::Exists((Join-Path $Extracted 'vso-distribution.json'))) { return $Extracted }
    Throw-VSOError $Context Layout @('archive root')
}
