function Get-VSORegistryRoot {
    param([string]$Scope, $Context)
    $base=if ($Scope -eq 'AllUsers') { $env:ProgramData } else { $env:LOCALAPPDATA }
    if (-not $base) { Throw-VSOError $Context Metadata @('scope storage') }
    return (Join-Path $base 'VicoSafeOptimizer.Module\Installations')
}

function ConvertTo-VSOFileMap {
    param($Records, [string]$Root, $Context, $Contract)
    $map=[ordered]@{}
    $allowed=@((Get-VSO7RequiredFiles)+@('LICENSE','LICENSE.txt','SHA256SUMS.txt','vso-distribution.json') | ForEach-Object { 'VSO7/'+$_ })
    if ($Contract) {
        $inventory=Get-VSOContractFiles $Contract $Context
        $allowed+=@($inventory.Keys | ForEach-Object { 'VSO7/'+$_ })
    }
    foreach ($entry in @($Records)) {
        $relative=[string](Get-VSOProperty $entry Path ''); $hash=[string](Get-VSOProperty $entry Sha256 '')
        if ($relative -cnotin $allowed -or $hash -notmatch '^[a-f0-9]{64}$' -or $map.Contains($relative)) { Throw-VSOError $Context Metadata @('file ownership') }
        $null=Join-VSOChild $Root $relative $Context; $map[$relative]=$hash
    }
    foreach ($required in @((Get-VSO7RequiredFiles)+@('SHA256SUMS.txt') | ForEach-Object { 'VSO7/'+$_ })) { if (-not $map.Contains($required)) { Throw-VSOError $Context Metadata @($required) } }
    if ($Contract) {
        if (-not $map.Contains('VSO7/vso-distribution.json')) { Throw-VSOError $Context Metadata @('distribution contract ownership') }
        foreach ($relative in $inventory.Keys) { if ($inventory[$relative].Required -and -not $map.Contains('VSO7/'+$relative)) { Throw-VSOError $Context Metadata @($relative) } }
    }
    if (-not $map.Contains('VSO7/LICENSE') -and -not $map.Contains('VSO7/LICENSE.txt')) { Throw-VSOError $Context Metadata @('license ownership') }
    if ($map['VSO7/VSO7.ps1'] -cne $map['VSO7/VSO7_7.0.0_RC_R80.ps1']) { Throw-VSOError $Context Metadata @('protected core identity') }
    return $map
}

function Read-VSOReceipt {
    param([string]$Root, $Context)
    $Root=Resolve-VSOPath $Root $Context -Installation
    $marker=Join-VSOChild $Root '.vso-manager.json' $Context
    $receipt=Read-VSOJson $marker $Context
    $id=[string](Get-VSOProperty $receipt Id '')
    if ((Get-VSOProperty $receipt Schema 0) -ne 1 -or (Get-VSOProperty $receipt Product '') -cne 'VicoSafeOptimizer' -or $id -notmatch '^[a-f0-9]{32}$' -or (Get-VSOProperty $receipt Scope '') -cnotin @('CurrentUser','AllUsers') -or (Get-VSOProperty $receipt Path '') -ine $Root -or (Get-VSOProperty $receipt Layout '') -cne 'vso7-classic-v1' -or (Get-VSOProperty $receipt ApplicationDirectory '') -cne 'VSO7' -or (Get-VSOProperty $receipt Launcher '') -cne 'VSO7/START VSO7.bat' -or (Get-VSOProperty $receipt Generation '') -ne '7' -or (Get-VSOProperty $receipt State '') -cne 'Installed') { Throw-VSOError $Context Metadata @('receipt identity') }
    $null=ConvertTo-VSOVersion ([string]$receipt.Version) $Context
    if ([string](Get-VSOProperty $receipt ArchiveSha256 '') -notmatch '^[a-f0-9]{64}$') { Throw-VSOError $Context Metadata @('archive identity') }
    if ([string](Get-VSOProperty $receipt MemorySourceSha256 '') -notmatch '^[a-f0-9]{64}$') { Throw-VSOError $Context Metadata @('memory source identity') }
    Assert-VSOUri ([uri]$receipt.AssetUri) $Context
    $null=ConvertTo-VSOFileMap $receipt.Files $Root $Context (Get-VSOProperty $receipt DistributionContract $null)
    $contract=Get-VSOProperty $receipt DistributionContract $null
    $contractPath=Join-VSOChild $Root 'VSO7/vso-distribution.json' $Context
    if ($contract -and [IO.File]::Exists($contractPath)) {
        $map=ConvertTo-VSOFileMap $receipt.Files $Root $Context $contract
        $actual=Read-VSOJson $contractPath $Context
        if ((Get-VSOHash $contractPath) -cne $map['VSO7/vso-distribution.json'] -or ($actual|ConvertTo-Json -Depth 20 -Compress) -cne ($contract|ConvertTo-Json -Depth 20 -Compress)) { Throw-VSOError $Context Metadata @('distribution contract changed') }
    }
    $backupNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($backup in @((Get-VSOProperty $receipt Backups @()))) {
        if ([string]$backup -notmatch '^\.vso-txn-[a-f0-9]{32}$' -or -not $backupNames.Add([string]$backup)) { Throw-VSOError $Context Metadata @('backup identity') }
    }
    foreach ($transaction in @(Get-VSOProperty $receipt Transactions @())) {
        if ([string]$transaction -notmatch '^\.vso-txn-[a-f0-9]{32}$') { Throw-VSOError $Context Metadata @('transaction identity') }
    }
    $pinnedNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pin in @(Get-VSOProperty $receipt TransactionReceipts @())) {
        if ([string]$pin.Transaction -cnotin @(Get-VSOProperty $receipt Transactions @()) -or [string]$pin.JournalSha256 -notmatch '^[a-f0-9]{64}$' -or -not $pinnedNames.Add([string]$pin.Transaction) -or @(Compare-Object @('Transaction','JournalSha256') @($pin.PSObject.Properties.Name)).Count) { Throw-VSOError $Context Metadata @('transaction journal pin') }
    }
    $pinnedNames.Clear()
    foreach ($pin in @(Get-VSOProperty $receipt BackupReceipts @())) {
        if ([string]$pin.Transaction -cnotin @($receipt.Backups) -or [string]$pin.ReceiptSha256 -notmatch '^[a-f0-9]{64}$' -or -not $pinnedNames.Add([string]$pin.Transaction) -or @(Compare-Object @('Transaction','ReceiptSha256') @($pin.PSObject.Properties.Name)).Count) { Throw-VSOError $Context Metadata @('backup receipt pin') }
    }
    Assert-VSOProtectedDirectory $Root $Context -UserAllowed:($receipt.Scope -eq 'CurrentUser')
    return $receipt
}

function Register-VSOReceipt {
    param($Receipt, $Context)
    $root=Get-VSORegistryRoot $Receipt.Scope $Context
    $parent=[IO.Path]::GetDirectoryName($root)
    New-VSOSecureDirectory $parent $Receipt.Scope $Context
    New-VSOSecureDirectory $root $Receipt.Scope $Context
    $marker=Join-VSOChild $Receipt.Path '.vso-manager.json' $Context
    $entry=[ordered]@{ Schema=1; Product='VicoSafeOptimizer'; Id=$Receipt.Id; Path=$Receipt.Path; Scope=$Receipt.Scope; ReceiptSha256=(Get-VSOHash $marker) }
    Write-VSOJson (Join-VSOChild $root ($Receipt.Id+'.json') $Context) $entry $Context
}

function Test-VSOInstalledFiles {
    param($Receipt, $Context)
    $map=ConvertTo-VSOFileMap $Receipt.Files $Receipt.Path $Context (Get-VSOProperty $Receipt DistributionContract $null)
    $index=0
    foreach ($relative in $map.Keys) {
        $file=Join-VSOChild $Receipt.Path $relative $Context
        if (-not [IO.File]::Exists($file) -or (Get-VSOHash $file) -cne $map[$relative]) { Throw-VSOError $Context Corrupt @($relative) }
        $index++; Write-VSOProgress $Context Verify $index $map.Count
    }
}

function Get-VSOIndexEntries {
    param([string]$Scope,$Context)
    $root=Get-VSORegistryRoot $Scope $Context
    # Directory.Exists suppresses access errors and would look like an empty index.
    try { $directory=Get-Item -LiteralPath $root -Force -ErrorAction Stop }
    catch [Management.Automation.ItemNotFoundException] { return }
    if (-not $directory.PSIsContainer) { Throw-VSOError $Context Metadata @('index directory') }
    Assert-VSONoReparse $root $Context
    Assert-VSOProtectedDirectory $root $Context -UserAllowed:($Scope -eq 'CurrentUser')
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -Force -ErrorAction Stop)) {
        if ($file.BaseName -notmatch '^[a-f0-9]{32}$') { Throw-VSOError $Context Metadata @('index filename') }
        $entry=Read-VSOJson $file.FullName $Context
        if ((Get-VSOProperty $entry Schema 0) -ne 1 -or (Get-VSOProperty $entry Product '') -cne 'VicoSafeOptimizer' -or (Get-VSOProperty $entry Id '') -cne $file.BaseName -or (Get-VSOProperty $entry Scope '') -cne $Scope -or [string](Get-VSOProperty $entry ReceiptSha256 '') -notmatch '^[a-f0-9]{64}$') { Throw-VSOError $Context Metadata @('index identity') }
        $candidate=Resolve-VSOPath ([string]$entry.Path) $Context -Installation
        [pscustomobject]@{Path=$candidate;Index=$entry;Scope=$Scope}
    }
}

function Get-VSOInstallationsInternal {
    param($Context, [string]$Path, [string]$Scope, [string]$Version)
    $candidates=[Collections.Generic.List[object]]::new(); $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $scopes=if ($Scope) { @($Scope) } else { @('CurrentUser','AllUsers') }
    if ($Path) {
        $canonical=Resolve-VSOPath $Path $Context -Installation
        $registeredMatches=@(foreach ($scopeName in $scopes) { Get-VSOIndexEntries $scopeName $Context | Where-Object Path -EQ $canonical })
        if ($registeredMatches.Count -gt 1) { Throw-VSOError $Context Metadata @('duplicate path registrations') }
        if ($registeredMatches.Count -eq 1) { $candidates.Add($registeredMatches[0]) }
        else { $candidates.Add([pscustomobject]@{Path=$canonical;Index=$null;Scope=$null}) }
    }
    else {
        foreach ($scopeName in $scopes) {
            foreach ($entry in @(Get-VSOIndexEntries $scopeName $Context)) { $candidates.Add($entry) }
            $default=Get-VSODefaultPath $scopeName $Context
            $directory=$null
            try { $directory=Get-Item -LiteralPath $default -Force -ErrorAction Stop }
            catch [Management.Automation.ItemNotFoundException] { }
            if ($directory -and $directory.PSIsContainer) { $candidates.Add([pscustomobject]@{ Path=$default; Index=$null; Scope=$scopeName }) }
        }
    }
    foreach ($candidate in $candidates) {
        if (-not $seen.Add($candidate.Path)) { continue }
        $record=[ordered]@{ PSTypeName='VSO.Installation'; Id=$(if ($candidate.Index) { $candidate.Index.Id } else { $null }); Version='Unknown'; Generation='7'; Path=$candidate.Path; ApplicationPath=(Join-Path $candidate.Path 'VSO7'); Scope=$candidate.Scope; Managed=($null -ne $candidate.Index); State='Missing'; StateDisplay=$Context.Text.Missing; Launcher=$null; Receipt=$null; Diagnostic=$null }
        $directory=$null
        try { $directory=Get-Item -LiteralPath $candidate.Path -Force -ErrorAction Stop }
        catch [Management.Automation.ItemNotFoundException] { }
        if ($directory) {
            try {
                if (-not $directory.PSIsContainer) { Throw-VSOError $Context Metadata @('installation directory') }
                $marker=Join-VSOChild $candidate.Path '.vso-manager.json' $Context
                if ([IO.File]::Exists($marker)) {
                    $receipt=Read-VSOReceipt $candidate.Path $Context
                    if ($candidate.Index -and ($candidate.Index.Id -cne $receipt.Id -or $candidate.Index.Scope -cne $receipt.Scope -or $candidate.Index.ReceiptSha256 -cne (Get-VSOHash $marker))) { Throw-VSOError $Context Metadata @('index does not match receipt') }
                    $record.Id=$receipt.Id; $record.Version=$receipt.Version; $record.Generation=$receipt.Generation; $record.Scope=$receipt.Scope; $record.Managed=$true; $record.Receipt=$receipt; $record.Launcher=$receipt.Launcher
                    Test-VSOInstalledFiles $receipt $Context
                    $record.State='Ready'; $record.StateDisplay=$Context.Text.Ready
                } else {
                    $app=if ([IO.File]::Exists((Join-Path $record.ApplicationPath 'START VSO7.bat'))) { $record.ApplicationPath } else { $candidate.Path }
                    $distribution=Get-VSODistribution $app $Context
                    $record.ApplicationPath=$app
                    $record.Version=$distribution.Version; $record.Launcher=$distribution.Launcher; $record.State='Unregistered'; $record.StateDisplay=$Context.Text.ManualState
                }
            } catch { $record.State='Modified'; $record.StateDisplay=$Context.Text.Modified; $record.Diagnostic=$_.Exception.Message }
            finally { Write-VSOProgress $Context Verify -Completed }
        }
        if ($Scope -and $record.Scope -and $record.Scope -ne $Scope) { continue }
        if ($Version -and $record.Version -ne (ConvertTo-VSOVersion $Version $Context).Text) { continue }
        [pscustomobject]$record
    }
}

function Select-VSOInstallation {
    param($Context, [string]$Path, [string]$Version, [string]$Scope, [switch]$AllowDamaged, [switch]$AllowManual, [switch]$AllowMissing)
    $items=@(Get-VSOInstallationsInternal $Context $Path $Scope $Version)
    if ($items.Count -eq 0) { Throw-VSOError $Context NotFound }
    if ($items.Count -gt 1) {
        if (-not (Test-VSOInteractive $Context) -or $items.Count -gt 20) { Throw-VSOError $Context Multiple }
        $options=@(); $letters='ABDEFGHIJKLMNOPQRSTUV'
        for ($i=0; $i -lt $items.Count; $i++) { $options+=('&'+$letters[$i]+': '+$items[$i].Version+' | '+$items[$i].Scope+' | '+$items[$i].Path+' | '+$items[$i].StateDisplay) }
        $options+=$Context.Text.CancelChoice
        $selected=Request-VSOChoice $Context $Context.Text.ScopeTitle $Context.Text.Selection $options
        if ($selected -eq $items.Count) { Throw-VSOError $Context Cancelled }; $item=$items[$selected]
    } else { $item=$items[0] }
    if ($item.State -eq 'Missing' -and -not $AllowMissing) { Throw-VSOError $Context NotFound }
    if (-not $item.Managed -and -not $AllowManual) { Throw-VSOError $Context Manual }
    if ($item.State -eq 'Modified' -and -not $AllowDamaged) { Throw-VSOError $Context Corrupt @($item.Diagnostic) }
    return $item
}
