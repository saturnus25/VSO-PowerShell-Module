function Enter-VSOLock {
    param([string]$Target, $Context)
    $bytes=[Text.Encoding]::UTF8.GetBytes($Target.ToUpperInvariant()); $sha=[Security.Cryptography.SHA256]::Create()
    try { $key=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    $path=Join-Path ([IO.Path]::GetDirectoryName($Target)) ('.vso-lock-'+$key)
    Assert-VSONoReparse $path $Context
    try { return [IO.FileStream]::new($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None,1,[IO.FileOptions]::DeleteOnClose) }
    catch { Throw-VSOError $Context Busy @() $_.Exception }
}

function Assert-VSOIdle {
    param([string]$Target, $Context, $Receipt, [string]$ApplicationPath)
    if (-not $ApplicationPath) { $ApplicationPath=Join-VSOChild $Target 'VSO7' $Context }
    $activity=Get-VSOProcesses $ApplicationPath $Context $Receipt
    if (-not $activity.Reliable -or $activity.Processes.Count -gt 0) { Throw-VSOError $Context Busy }
}

function Repair-VSOTransactions {
    param([string]$Target, $Context)
    $parent=[IO.Path]::GetDirectoryName($Target)
    foreach ($dir in @(Get-ChildItem -LiteralPath $parent -Directory -Filter '.vso-txn-*' -Force -ErrorAction Stop)) {
        if ($dir.Name -notmatch '^\.vso-txn-[a-f0-9]{32}$') { continue }
        Assert-VSONoReparse $dir.FullName $Context
        $journalPath=Join-VSOChild $dir.FullName 'transaction.json' $Context
        if (-not [IO.File]::Exists($journalPath)) { continue }
        $j=Read-VSOJson $journalPath $Context
        if ((Get-VSOProperty $j Target '') -ine $Target) { continue }
        if ((Get-VSOProperty $j Schema '') -ne 1 -or (Get-VSOProperty $j Product '') -cne 'VicoSafeOptimizer.Transaction' -or (Get-VSOProperty $j State '') -cnotin @('Prepared','Promoted','Committed','RolledBack')) { Throw-VSOError $Context Interrupted @($dir.FullName) }
        if ($j.State -in @('Committed','RolledBack')) { continue }
        Assert-VSOProtectedDirectory $dir.FullName $Context -UserAllowed
        $previous=Join-VSOChild $dir.FullName 'previous' $Context
        if (-not [IO.Directory]::Exists($Target) -and [IO.Directory]::Exists($previous)) {
            # Recovery only moves the saved directory back; no downloaded code is executed.
            $null=@(Get-VSOTreeFiles $previous $Context)
            $oldMarker=Read-VSOJson (Join-VSOChild $previous '.vso-manager.json' $Context) $Context
            if ($oldMarker.Product -cne 'VicoSafeOptimizer' -or $oldMarker.Id -cne $j.InstallationId -or $oldMarker.Path -ine $Target) { Throw-VSOError $Context Interrupted @($dir.FullName) }
            $null=ConvertTo-VSOFileMap $oldMarker.Files $previous $Context (Get-VSOProperty $oldMarker DistributionContract $null)
            [IO.Directory]::Move($previous,$Target); $j.State='RolledBack'; Write-VSOJson $journalPath $j $Context
        } else {
            # An existing target could contain new user data: never replace it automatically.
            Throw-VSOError $Context Interrupted @($dir.FullName)
        }
    }
}

function Invoke-VSOInstallTransaction {
    param($Options, $Release, $Context, [switch]$Force, [switch]$Update)
    $target=$Options.Path; $scope=$Options.Scope; $parent=[IO.Path]::GetDirectoryName($target)
    if ($scope -eq 'AllUsers') {
        if (-not (Test-VSOAdministrator)) { Throw-VSOError $Context Admin }
        if (-not [IO.Directory]::Exists($parent)) { Throw-VSOError $Context ProtectedParent }
        Assert-VSOProtectedDirectory $parent $Context
    } elseif (-not [IO.Directory]::Exists($parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    Assert-VSONoReparse $parent $Context
    $lock=Enter-VSOLock $target $Context
    $work=$null; $txn=$null; $journal=$null; $oldMoved=$false; $promoted=$false; $committed=$false; $registered=$false
    try {
        Repair-VSOTransactions $target $Context
        $old=$null
        if ([IO.File]::Exists((Join-Path $target '.vso-manager.json'))) {
            $old=Read-VSOReceipt $target $Context
            if ($old.Scope -cne $scope) { Throw-VSOError $Context ScopeConflict }
            Test-VSOInstalledFiles $old $Context
            if (-not $Force -and -not $Update) { Throw-VSOError $Context Existing }
            if (-not $Force -and (Compare-VSOVersion $Release.Version $old.Version $Context) -le 0) { return [pscustomobject]@{ Changed=$false; Message=$Context.Text.Current; Path=$target; Version=$old.Version } }
        } elseif ($Update) { Throw-VSOError $Context Manual }
        Assert-VSOIdle $target $Context $old
        $work=Join-Path $parent ('.vso-work-'+[guid]::NewGuid().ToString('N'))
        New-VSOSecureDirectory $work $scope $Context
        $archive=Join-VSOChild $work 'distribution.zip' $Context
        Invoke-VSOHttp ([uri]$Release.AssetUri) $Context -OutFile $archive -ExpectedSize $Release.Size -MaximumBytes 134217728
        if ((Get-VSOHash $archive) -cne $Release.Sha256) { Throw-VSOError $Context Integrity @('archive SHA-256') }
        $extracted=Join-VSOChild $work 'extracted' $Context
        [void][IO.Directory]::CreateDirectory($extracted)
        Expand-VSOArchive $archive $extracted $Context
        $packageRoot=Find-VSOPackageRoot $extracted $Context
        $distribution=Get-VSODistribution $packageRoot $Context -ExpectedVersion $Release.Version -Package
        if ($old -and $distribution.Generation -ne $old.Generation) { Throw-VSOError $Context Generation }
        $txn=Join-Path $parent ('.vso-txn-'+[guid]::NewGuid().ToString('N'))
        New-VSOSecureDirectory $txn $scope $Context
        $stage=Join-VSOChild $txn 'next' $Context
        # Preserve the official VSO7 leaf name: upstream otherwise offers relocation
        # on first launch, invalidating manager paths and process attribution.
        [void][IO.Directory]::CreateDirectory($stage)
        [IO.Directory]::Move($packageRoot,(Join-VSOChild $stage 'VSO7' $Context))
        $distributionFiles=[ordered]@{}
        foreach ($relative in $distribution.Files.Keys) { $distributionFiles['VSO7/'+$relative]=$distribution.Files[$relative] }
        $oldFiles=if ($old) { ConvertTo-VSOFileMap $old.Files $target $Context (Get-VSOProperty $old DistributionContract $null) } else { [ordered]@{} }
        if ([IO.Directory]::Exists($target)) {
            $contents=@(Get-VSOTreeFiles $target $Context)
            if (-not $old -and $contents.Count -gt 0) {
                if (-not $Force) { Throw-VSOError $Context Existing }
                # Adoption requires byte-identical files from the independently verified release.
                foreach ($relative in $distributionFiles.Keys) {
                    $existing=Join-VSOChild $target $relative $Context
                    if (-not [IO.File]::Exists($existing) -or (Get-VSOHash $existing) -cne $distributionFiles[$relative]) { Throw-VSOError $Context Destination @($relative) }
                    $oldFiles[$relative]=$distributionFiles[$relative]
                }
            }
            foreach ($file in $contents) {
                $relative=$file.FullName.Substring($target.Length+1).Replace('\','/')
                if ($relative -eq '.vso-manager.json' -or $oldFiles.Contains($relative)) { continue }
                if ($distributionFiles.Contains($relative)) { Throw-VSOError $Context Destination @($relative) }
                $destination=Join-VSOChild $stage $relative $Context
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                [IO.File]::Copy($file.FullName,$destination,$false)
                if ((Get-VSOHash $file.FullName) -cne (Get-VSOHash $destination)) { Throw-VSOError $Context Destination @($relative) }
            }
        }
        $id=if ($old) { $old.Id } else { [guid]::NewGuid().ToString('N') }
        $fileRecords=@(foreach ($relative in $distributionFiles.Keys) { [ordered]@{ Path=$relative; Sha256=$distributionFiles[$relative] } })
        $backups=@(); if ($old) { $backups=@(Get-VSOProperty $old Backups @()) }
        if ([IO.Directory]::Exists($target)) { $backups+=[IO.Path]::GetFileName($txn) }
        $journal=[ordered]@{ Schema=1; Product='VicoSafeOptimizer.Transaction'; Target=$target; InstallationId=$id; State='Committed'; CreatedUtc=[DateTime]::UtcNow.ToString('o') }
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $journalHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($journal|ConvertTo-Json -Depth 15))))).Replace('-','').ToLowerInvariant() } finally {$sha.Dispose()}
        $journal.State='Prepared'
        $receipt=[ordered]@{ Schema=1; Product='VicoSafeOptimizer'; Id=$id; Version=$Release.Version; Generation=$distribution.Generation; Path=$target; Scope=$scope; ReleaseTag=$Release.Tag; ReleaseUri=$Release.ReleaseUri; AssetUri=$Release.AssetUri; ArchiveSha256=$Release.Sha256; IntegrityMethod=$Release.IntegrityMethod; InstalledUtc=[DateTime]::UtcNow.ToString('o'); Layout=$distribution.Layout; ApplicationDirectory='VSO7'; Launcher='VSO7/START VSO7.bat'; State='Installed'; Files=$fileRecords; Backups=$backups }
        $receipt.DistributionContract=$distribution.Contract
        $receipt.Transactions=@(@(Get-VSOProperty $old Transactions @())+@([IO.Path]::GetFileName($txn)))
        $receipt.TransactionReceipts=@(@(Get-VSOProperty $old TransactionReceipts @())+@([ordered]@{Transaction=[IO.Path]::GetFileName($txn);JournalSha256=$journalHash}))
        $receipt.BackupReceipts=@(Get-VSOProperty $old BackupReceipts @())
        if ($old) { $receipt.BackupReceipts+=@([ordered]@{Transaction=[IO.Path]::GetFileName($txn);ReceiptSha256=(Get-VSOHash (Join-Path $target '.vso-manager.json'))}) }
        $receipt.MemorySourceSha256=Get-VSOSourceTextHash (Join-VSOChild $stage 'VSO7/VSO7.ps1' $Context) $Context
        Write-VSOJson (Join-VSOChild $stage '.vso-manager.json' $Context) $receipt $Context
        $journalPath=Join-VSOChild $txn 'transaction.json' $Context
        Write-VSOJson $journalPath $journal $Context
        Assert-VSOIdle $target $Context $old
        Assert-VSONoReparse $target $Context
        if ($old) { Test-VSOInstalledFiles $old $Context }
        if ([IO.Directory]::Exists($target)) { [IO.Directory]::Move($target,(Join-VSOChild $txn 'previous' $Context)); $oldMoved=$true }
        [IO.Directory]::Move($stage,$target); $promoted=$true
        $journal.State='Promoted'; Write-VSOJson $journalPath $journal $Context
        $validated=Read-VSOReceipt $target $Context; Test-VSOInstalledFiles $validated $Context
        Register-VSOReceipt $validated $Context
        $registered=$true
        $journal.State='Committed'; Write-VSOJson $journalPath $journal $Context; $committed=$true
        return [pscustomobject]@{ PSTypeName='VSO.Result'; Changed=$true; Operation=$(if ($Update) { 'Update' } else { 'Install' }); Path=$target; Version=$Release.Version; Scope=$scope; InstallationId=$id; BackupPath=$(if ($oldMoved) { Join-Path $txn 'previous' } else { $null }); IntegrityMethod=$Release.IntegrityMethod }
    } catch {
        $originalError=$_
        if ($txn -and -not $committed) {
            try {
                if ($promoted -and [IO.Directory]::Exists($target)) { [IO.Directory]::Move($target,(Join-VSOChild $txn 'failed' $Context)) }
                if ($oldMoved) { [IO.Directory]::Move((Join-VSOChild $txn 'previous' $Context),$target) }
                if ($old) { Register-VSOReceipt $old $Context }
                elseif ($registered) {
                    $index=Join-VSOChild (Get-VSORegistryRoot $scope $Context) ($id+'.json') $Context
                    $entry=Read-VSOJson $index $Context
                    if ($entry.Id -cne $id -or $entry.Path -ine $target) { Throw-VSOError $Context Metadata @('failed-install registration') }
                    [IO.File]::Delete($index)
                }
                if ($journal) { $journal.State='RolledBack'; Write-VSOJson (Join-Path $txn 'transaction.json') $journal $Context }
            } catch { Throw-VSOError $Context Rollback @($txn) $_.Exception }
        }
        throw $originalError
    } finally {
        try { if ($work) { Remove-VSOPrivateTree $work $parent $Context } }
        finally { $lock.Dispose(); Write-VSOProgress $Context Verify -Completed }
    }
}

function Get-VSORemovalPlan {
    param($Installation, $Context, [switch]$Full, [switch]$RemoveBackups)
    if ($RemoveBackups -and -not $Full) { Throw-VSOError $Context BackupIntent }
    $receipt=Read-VSOReceipt $Installation.Path $Context
    $contract=Get-VSOProperty $receipt DistributionContract $null
    $map=ConvertTo-VSOFileMap $receipt.Files $receipt.Path $Context $contract
    $roles=if ($contract) { Get-VSOContractFiles $contract $Context } else { [ordered]@{} }
    $remove=[Collections.Generic.List[object]]::new(); $preserve=[Collections.Generic.List[string]]::new(); $protected=[Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-VSOTreeFiles $receipt.Path $Context)) {
        $relative=$file.FullName.Substring($receipt.Path.Length+1).Replace('\','/')
        if ($relative -eq '.vso-manager.json') { continue }
        $role='Application'; $leaf=$relative.Substring([Math]::Min(5,$relative.Length))
        if ($roles.Contains($leaf)) { $role=$roles[$leaf].Role }
        $reason=$null
        if (-not $map.Contains($relative)) { $reason='UntrackedOwnership' }
        elseif ((Get-VSOHash $file.FullName) -cne $map[$relative]) { $reason='ModifiedSinceInstall' }
        elseif ($role -eq 'Recovery') { $reason='RecoveryRequiresSeparateOwnership' }
        elseif (-not $Full -and $role -ne 'Application') { $reason='PersistentDataNormalReset' }
        if ($reason) { $preserve.Add($file.FullName); $protected.Add([pscustomobject]@{Path=$file.FullName;Reason=$reason;Ownership=$role}) }
        else { $remove.Add([pscustomobject]@{Path=$file.FullName;Sha256=$map[$relative];Ownership='ReceiptHash';Role=$role}) }
    }
    $marker=Join-Path $receipt.Path '.vso-manager.json'
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($receipt.Path)
    while ($pending.Count) {
        $folder=$pending.Pop();Assert-VSONoReparse $folder $Context
        $children=@(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)
        foreach ($child in $children) {if ($child.PSIsContainer) {$pending.Push($child.FullName)}}
        if ($children.Count -eq 0 -and $folder -ine $receipt.Path) {
            $prefix=$folder.Substring($receipt.Path.Length+1).Replace('\','/')+'/'
            if (@($map.Keys|Where-Object {$_.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 0) { $preserve.Add($folder);$protected.Add([pscustomobject]@{Path=$folder;Reason='UntrackedEmptyDirectory';Ownership='Unknown'}) }
        }
    }
    $index=Join-Path (Get-VSORegistryRoot $receipt.Scope $Context) ($receipt.Id+'.json')
    if ([IO.File]::Exists($index)) {
        $entry=Read-VSOJson $index $Context
        if ($entry.Id -cne $receipt.Id -or $entry.Path -ine $receipt.Path -or $entry.Scope -cne $receipt.Scope -or $entry.ReceiptSha256 -cne (Get-VSOHash $marker)) { Throw-VSOError $Context Metadata @('removal index') }
        $remove.Add([pscustomobject]@{Path=$index;Sha256=(Get-VSOHash $index);Ownership='ReceiptIndex';Role='Metadata'})
    }
    $names=@(@($receipt.Backups)+@(Get-VSOProperty $receipt Transactions @()) | Select-Object -Unique)
    foreach ($name in $names) {
        $backupRoot=Join-VSOChild ([IO.Path]::GetDirectoryName($receipt.Path)) $name $Context
        if (-not [IO.Directory]::Exists($backupRoot)) { continue }
        Assert-VSOProtectedDirectory $backupRoot $Context -UserAllowed:($receipt.Scope -eq 'CurrentUser')
        $journalPath=Join-VSOChild $backupRoot 'transaction.json' $Context
        $journalPins=@(Get-VSOProperty $receipt TransactionReceipts @()|Where-Object Transaction -CEQ $name)
        if ($journalPins.Count -eq 0) { $preserve.Add($backupRoot);$protected.Add([pscustomobject]@{Path=$backupRoot;Reason='TransactionJournalNotPinned';Ownership='Unproven'});continue }
        if ($journalPins.Count -ne 1 -or (Get-VSOHash $journalPath) -cne $journalPins[0].JournalSha256) { Throw-VSOError $Context Metadata @('transaction journal changed') }
        $journal=Read-VSOJson $journalPath $Context
        if ($journal.Schema -ne 1 -or $journal.Product -cne 'VicoSafeOptimizer.Transaction' -or $journal.Target -ine $receipt.Path -or $journal.InstallationId -cne $receipt.Id -or $journal.State -cne 'Committed') { Throw-VSOError $Context Metadata @('backup ownership') }
        $previous=Join-VSOChild $backupRoot 'previous' $Context
        $keepJournal=$false
        if ([IO.Directory]::Exists($previous)) {
            if (-not $RemoveBackups) {
                $preserve.Add($previous); $protected.Add([pscustomobject]@{Path=$previous;Reason='BackupLossNotAcknowledged';Ownership='Transaction'}); $keepJournal=$true
            } else {
                $oldMarker=Join-VSOChild $previous '.vso-manager.json' $Context
                if (-not [IO.File]::Exists($oldMarker)) { $preserve.Add($previous);$protected.Add([pscustomobject]@{Path=$previous;Reason='MissingBackupReceipt';Ownership='Unknown'});$keepJournal=$true }
                else {
                    $pins=@(Get-VSOProperty $receipt BackupReceipts @()|Where-Object Transaction -CEQ $name)
                    if ($pins.Count -eq 0) { $preserve.Add($previous);$protected.Add([pscustomobject]@{Path=$previous;Reason='BackupReceiptNotPinned';Ownership='Unproven'});$preserve.Add($journalPath);$protected.Add([pscustomobject]@{Path=$journalPath;Reason='PreservedTransactionProvenance';Ownership='Metadata'});continue }
                    if ($pins.Count -ne 1 -or (Get-VSOHash $oldMarker) -cne $pins[0].ReceiptSha256) { Throw-VSOError $Context Metadata @('backup receipt changed') }
                    $old=Read-VSOJson $oldMarker $Context
                    if ($old.Id -cne $receipt.Id -or $old.Path -ine $receipt.Path -or $old.Product -cne 'VicoSafeOptimizer') { Throw-VSOError $Context Metadata @('backup receipt') }
                    $oldMap=ConvertTo-VSOFileMap $old.Files $previous $Context (Get-VSOProperty $old DistributionContract $null)
                    $oldContract=Get-VSOProperty $old DistributionContract $null
                    $oldRoles=if ($oldContract) { Get-VSOContractFiles $oldContract $Context } else { [ordered]@{} }
                    foreach ($file in @(Get-VSOTreeFiles $previous $Context)) {
                        $relative=$file.FullName.Substring($previous.Length+1).Replace('\','/')
                        if ($relative -eq '.vso-manager.json') { continue }
                        $oldLeaf=$relative.Substring([Math]::Min(5,$relative.Length));$recoveryRole=$oldRoles.Contains($oldLeaf) -and $oldRoles[$oldLeaf].Role -eq 'Recovery'
                        if ($oldMap.Contains($relative) -and (Get-VSOHash $file.FullName) -ceq $oldMap[$relative] -and $relative -cnotlike 'VSO7/Recuperacion/*' -and -not $recoveryRole) { $remove.Add([pscustomobject]@{Path=$file.FullName;Sha256=$oldMap[$relative];Ownership='BackupReceiptHash';Role='Backup'}) }
                        else { $preserve.Add($file.FullName);$protected.Add([pscustomobject]@{Path=$file.FullName;Reason='UntrackedModifiedOrRecoveryBackup';Ownership='Unknown'});$keepJournal=$true }
                    }
                    # Keep proof for any backup data that survives, permitting later inspection.
                    if ($keepJournal) { $preserve.Add($oldMarker);$protected.Add([pscustomobject]@{Path=$oldMarker;Reason='PreservedBackupProvenance';Ownership='Metadata'}) }
                    else { $remove.Add([pscustomobject]@{Path=$oldMarker;Sha256=(Get-VSOHash $oldMarker);Ownership='BackupReceipt';Role='Metadata'}) }
                }
            }
        }
        foreach ($file in @(Get-VSOTreeFiles $backupRoot $Context)) {
            if ($file.FullName -ieq $journalPath -or $file.FullName.StartsWith($previous+'\',[StringComparison]::OrdinalIgnoreCase)) { continue }
            $preserve.Add($file.FullName);$protected.Add([pscustomobject]@{Path=$file.FullName;Reason='UntrackedTransactionData';Ownership='Unknown'});$keepJournal=$true
        }
        if ($Full -and -not $keepJournal) { $remove.Add([pscustomobject]@{Path=$journalPath;Sha256=(Get-VSOHash $journalPath);Ownership='ReceiptTransaction';Role='Metadata'}) }
        else { $preserve.Add($journalPath);$protected.Add([pscustomobject]@{Path=$journalPath;Reason='PreservedTransactionProvenance';Ownership='Metadata'}) }
    }
    # Receipt is last: partial removal retains the map for a new plan/retry by Path.
    $remove.Add([pscustomobject]@{Path=$marker;Sha256=(Get-VSOHash $marker);Ownership='Receipt';Role='Metadata'})
    $shared=Join-Path $env:ProgramData 'VicoreDevelopment\VSO7'
    $preserve.Add($shared);$protected.Add([pscustomobject]@{Path=$shared;Reason='SharedRecoveryAndRuntimeData';Ownership='SharedOrUntracked'})
    # Orphans have no receipt binding. Diagnose them instead of guessing ownership.
    foreach ($dir in @(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($receipt.Path)) -Directory -Filter '.vso-txn-*' -Force -ErrorAction Stop)) {
        if ($dir.Name -in $names -or $dir.Name -notmatch '^\.vso-txn-[a-f0-9]{32}$') { continue }
        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $path=Join-Path $dir.FullName 'transaction.json'
        if ([IO.File]::Exists($path)) {
            $orphan=Read-VSOJson $path $Context
            if ((Get-VSOProperty $orphan Target '') -ieq $receipt.Path) { $preserve.Add($dir.FullName);$protected.Add([pscustomobject]@{Path=$dir.FullName;Reason='TransactionNotBoundToReceipt';Ownership='Unproven'}) }
        }
    }
    $directorySet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $roots=@($receipt.Path)+@($names|ForEach-Object {Join-VSOChild ([IO.Path]::GetDirectoryName($receipt.Path)) $_ $Context})
    $directorySources=@($remove)+@($map.Keys|ForEach-Object {[pscustomobject]@{Path=(Join-VSOChild $receipt.Path $_ $Context)}})
    foreach ($file in $directorySources) {
        foreach ($root in $roots) {
            if (-not $file.Path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {continue}
            $cursor=[IO.Path]::GetDirectoryName($file.Path)
            while ($cursor -and ($cursor -ieq $root -or $cursor.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase))) { $null=$directorySet.Add($cursor);$cursor=[IO.Path]::GetDirectoryName($cursor) }
        }
    }
    $directories=@($directorySet|Sort-Object Length -Descending)
    foreach ($item in $protected) { $item|Add-Member -NotePropertyName Exists -NotePropertyValue ([IO.File]::Exists($item.Path) -or [IO.Directory]::Exists($item.Path)) }
    return [pscustomobject]@{PSTypeName='VSO.RemovalPlan';Path=$receipt.Path;Full=[bool]$Full;RemoveBackups=[bool]$RemoveBackups;Remove=@($remove.ToArray());Directories=$directories;Preserve=@($preserve.ToArray());Protected=@($protected.ToArray());Receipt=$receipt}
}

function Open-VSORemovalFile {
    param([string]$Path, $Context, [switch]$Directory)
    if (-not ('VsoRemovalFile' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class VsoRemovalFile {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 public static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
}
'@
    }
    Assert-VSONoReparse $Path $Context
    if (-not $Directory -and ((Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReadOnly)) { Throw-VSOError $Context Destination @('read-only file: '+$Path) }
    # Request DELETE during preflight without deleting. Keep the object pinned against
    # writes/replacement until its turn; all permission failures precede the first delete.
    $access=if ($Directory) { [uint32]65536 } else { [uint32]2147549184 }
    $flags=if ($Directory) { [uint32]35651584 } else { [uint32]2097152 }
    $handle=[VsoRemovalFile]::CreateFile($Path,$access,1,[IntPtr]::Zero,3,$flags,[IntPtr]::Zero)
    if ($handle.IsInvalid) { $code=[Runtime.InteropServices.Marshal]::GetLastWin32Error();$handle.Dispose();throw [ComponentModel.Win32Exception]::new($code) }
    if ($Directory) { return $handle }
    try { return [IO.FileStream]::new($handle,[IO.FileAccess]::Read) } catch { $handle.Dispose();throw }
}

function Invoke-VSORemoval {
    param($Plan, $Context)
    $lock=Enter-VSOLock $Plan.Path $Context
    $handles=[Collections.Generic.List[IO.FileStream]]::new()
    $directoryHandles=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        Assert-VSOProtectedDirectory $Plan.Path $Context -UserAllowed:($Plan.Receipt.Scope -eq 'CurrentUser')
        Assert-VSOIdle $Plan.Path $Context $Plan.Receipt
        foreach ($file in $Plan.Remove) {
            $stream=Open-VSORemovalFile $file.Path $Context; $handles.Add($stream)
            $sha=[Security.Cryptography.SHA256]::Create()
            try { $hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
            if ($hash -cne $file.Sha256) { Throw-VSOError $Context Destination @($file.Path) }
        }
        # Preflight DELETE access for directories expected to become empty, too.
        # Unknown children keep a directory out of this set; no recursive deletion.
        $scheduled=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in $Plan.Remove) { $null=$scheduled.Add($file.Path) }
        foreach ($folder in $Plan.Directories) {
            Assert-VSONoReparse $folder $Context
            if (-not [IO.Directory]::Exists($folder)) { continue }
            $children=@(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)
            if (@($children|Where-Object {-not $scheduled.Contains($_.FullName)}).Count -eq 0) {
                $directoryHandles.Add($folder,(Open-VSORemovalFile $folder $Context -Directory))
                $null=$scheduled.Add($folder)
            }
        }
        $done=0
        foreach ($file in $Plan.Remove) {
            Assert-VSONoReparse $file.Path $Context
            $handles[$done].Dispose()
            if ((Get-VSOHash $file.Path) -cne $file.Sha256) { Throw-VSOError $Context Destination @($file.Path) }
            [IO.File]::Delete($file.Path)
            if ([IO.File]::Exists($file.Path)) { Throw-VSOError $Context Destination @($file.Path) }
            $done++; Write-VSOProgress $Context Remove $done $Plan.Remove.Count
        }
        foreach ($folder in @($Plan.Directories)+@((Join-Path $Plan.Path 'VSO7'),$Plan.Path)) {
            Assert-VSONoReparse $folder $Context
            if ($directoryHandles.ContainsKey($folder)) { $directoryHandles[$folder].Dispose() }
            if ([IO.Directory]::Exists($folder) -and @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop).Count -eq 0) { [IO.Directory]::Delete($folder,$false) }
        }
        return [pscustomobject]@{PSTypeName='VSO.Result';Changed=$true;Operation='Reset';Path=$Plan.Path;Full=$Plan.Full;Removed=@($Plan.Remove.Path);Preserved=$Plan.Preserve;Protected=$Plan.Protected;RestoredWindowsTweaks=$false;CompleteCleanup=($Plan.Protected.Count -eq 0)}
    } finally { foreach ($stream in $handles) { $stream.Dispose() };foreach ($handle in $directoryHandles.Values) { $handle.Dispose() };$lock.Dispose();Write-VSOProgress $Context Remove -Completed }
}
