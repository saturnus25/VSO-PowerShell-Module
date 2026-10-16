if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
InModuleScope VSO {
    BeforeAll { . (Join-Path $env:VSO_MODULE_LAB_PROJECT 'tests/Fixtures.ps1'); $script:ctx=New-VSOContext en -Quiet }
    Describe 'Simulated filesystem lifecycle in TestDrive' {
        BeforeEach {
            $script:caseRoot=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($script:caseRoot)
            $script:target=Join-Path $script:caseRoot 'VSO espacio á'
            $script:options=[pscustomobject]@{Path=$script:target;Scope='CurrentUser'}
            $script:release=New-LabRelease $script:caseRoot '1.2.2'
            # TestDrive is intentionally temporary; only the pure path validator tests
            # exercise the production prohibition on installing into temp folders.
            Mock Resolve-VSOPath {param($Path) [IO.Path]::GetFullPath($Path).TrimEnd('\')}
            Mock Assert-VSOPlatform {}
            Mock Get-VSOProcessSnapshot { @() }
            Mock Get-VSORegistryRoot {param($Scope) Join-Path $script:caseRoot ('registry/'+$Scope+'/Installations')}
            Mock Invoke-VSOHttp {param($Uri,$Context,$OutFile) [IO.File]::Copy($script:release.Fixture,$OutFile,$false)}
        }
        It 'installs and registers verified fixture files' {
            $result=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $result.Changed|Should -BeTrue
            $receipt=Read-VSOReceipt $script:target $script:ctx
            $receipt.Version|Should -Be '1.2.2'
            {Test-VSOInstalledFiles $receipt $script:ctx}|Should -Not -Throw
            Test-Path -LiteralPath (Join-Path (Get-VSORegistryRoot CurrentUser $script:ctx) ($receipt.Id+'.json'))|Should -BeTrue
        }
        It 'detects a registered installation independently of the working directory' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            Mock Get-VSODefaultPath {Join-Path $script:caseRoot 'absent-default'}
            Push-Location (Join-Path $env:SystemRoot 'System32')
            try { $found=@(Get-VSOInstallationsInternal $script:ctx -Scope CurrentUser); $found.Count|Should -Be 1; $found[0].Path|Should -Be $script:target }
            finally {Pop-Location}
        }
        It 'does not overwrite an existing installation without explicit intent' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            {Invoke-VSOInstallTransaction $script:options $script:release $script:ctx}|Should -Throw '*exists*'
        }
        It 'rejects unrelated content in a custom destination' {
            [void][IO.Directory]::CreateDirectory($script:target)
            $foreign=Join-Path $script:target 'foreign.txt'; [IO.File]::WriteAllText($foreign,'keep')
            {Invoke-VSOInstallTransaction $script:options $script:release $script:ctx -Force}|Should -Throw
            [IO.File]::ReadAllText($foreign)|Should -Be 'keep'
        }
        It 'rejects an incorrect archive SHA-256 with Force' {
            $script:release.Sha256='0'*64
            {Invoke-VSOInstallTransaction $script:options $script:release $script:ctx -Force}|Should -Throw '*SHA-256*'
            Test-Path -LiteralPath $script:target|Should -BeFalse
        }
        It 'cleans partial downloads and leaves the original installation unchanged' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $before=Get-VSOHash (Join-Path $script:target '.vso-manager.json')
            Mock Invoke-VSOHttp {param($OutFile) [IO.File]::WriteAllText($OutFile,'partial'); throw 'Interrupted download'}
            {Invoke-VSOInstallTransaction $script:options $script:release $script:ctx -Force -Update}|Should -Throw '*Interrupted*'
            Get-VSOHash (Join-Path $script:target '.vso-manager.json')|Should -Be $before
            @(Get-ChildItem -LiteralPath $script:caseRoot -Directory -Filter '.vso-work-*').Count|Should -Be 0
        }
        It 'skips equal versions without a download' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            Mock Invoke-VSOHttp {throw 'Must not download'}
            (Invoke-VSOInstallTransaction $script:options $script:release $script:ctx -Update).Changed|Should -BeFalse
            # The initial installation made one transfer in this It scope.
            # The throwing replacement mock also detects any additional transfer.
            Should -Invoke Invoke-VSOHttp -Times 1
        }
        It 'preserves foreign and runtime data and retains a previous directory during update' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            [IO.File]::WriteAllText((Join-Path $script:target 'foreign.txt'),'keep')
            [void][IO.Directory]::CreateDirectory((Join-Path $script:target 'VSO7/Recuperacion'))
            [IO.File]::WriteAllText((Join-Path $script:target 'VSO7/Recuperacion/backup.json'),'recovery fixture')
            $script:release=New-LabRelease $script:caseRoot '1.2.3'
            $result=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx -Update
            $result.Version|Should -Be '1.2.3'
            [IO.File]::ReadAllText((Join-Path $script:target 'foreign.txt'))|Should -Be 'keep'
            Test-Path -LiteralPath (Join-Path $script:target 'VSO7/Recuperacion/backup.json')|Should -BeTrue
            Test-Path -LiteralPath (Join-Path $result.BackupPath 'VSO7/VSO7.ps1')|Should -BeTrue
        }
        It 'restores the previous directory if registration fails after promotion' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $before=Get-VSOHash (Join-Path $script:target 'VSO7/VSO7.ps1')
            $script:release=New-LabRelease $script:caseRoot '1.2.3'
            Mock Register-VSOReceipt {param($Receipt) if ($Receipt.Version -eq '1.2.3') {throw 'Synthetic registration failure'} }
            {Invoke-VSOInstallTransaction $script:options $script:release $script:ctx -Update}|Should -Throw '*registration failure*'
            (Read-VSOReceipt $script:target $script:ctx).Version|Should -Be '1.2.2'
            Get-VSOHash (Join-Path $script:target 'VSO7/VSO7.ps1')|Should -Be $before
        }
        It 'blocks update when process visibility is insufficient' {
            Mock Get-VSOProcesses {[pscustomobject]@{Reliable=$false;Processes=@()}}
            {Invoke-VSOInstallTransaction $script:options $script:release $script:ctx}|Should -Throw '*running*'
            Should -Invoke Invoke-VSOHttp -Times 0
        }
        It 'preserves foreign and modified files during Full removal' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $foreign=Join-Path $script:target 'foreign.txt'; [IO.File]::WriteAllText($foreign,'keep')
            $modified=Join-Path $script:target 'VSO7/README.md'; [IO.File]::AppendAllText($modified,' user edit')
            $installation=[pscustomobject]@{Path=$script:target}
            $plan=Get-VSORemovalPlan $installation $script:ctx -Full
            $plan.Preserve|Should -Contain $foreign
            $plan.Preserve|Should -Contain $modified
            $result=Invoke-VSORemoval $plan $script:ctx
            [IO.File]::ReadAllText($foreign)|Should -Be 'keep'
            Test-Path -LiteralPath $modified|Should -BeTrue
            $result.RestoredWindowsTweaks|Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:target 'VSO7/VSO7.ps1')|Should -BeFalse
        }
        It 'distinguishes normal and Full plans using attributable packaged data and manager metadata' {
            $script:release=New-LabRelease $script:caseRoot '1.2.2' -Contract2
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $item=[pscustomobject]@{Path=$script:target}
            $normal=Get-VSORemovalPlan $item $script:ctx
            $full=Get-VSORemovalPlan $item $script:ctx -Full
            $config=Join-Path $script:target 'VSO7/Config/default.json'
            $normal.Preserve|Should -Contain $config
            $full.Remove.Path|Should -Contain $config
            @($full.Remove|Where-Object Role -EQ Metadata).Count|Should -BeGreaterThan @($normal.Remove|Where-Object Role -EQ Metadata).Count
            $full.Protected.Reason|Should -Contain 'RecoveryRequiresSeparateOwnership'
            $full.Protected.Reason|Should -Contain 'SharedRecoveryAndRuntimeData'
            $result=Invoke-VSORemoval $full $script:ctx
            Test-Path $config|Should -BeFalse
            Test-Path (Join-Path $script:target 'VSO7/Recuperacion/baseline.json')|Should -BeTrue
            $result.CompleteCleanup|Should -BeFalse
        }
        It 'retries an interrupted removal by retaining the receipt until the last deletion' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $item=[pscustomobject]@{Path=$script:target};$plan=Get-VSORemovalPlan $item $script:ctx -Full
            $script:progressCalls=0
            Mock Write-VSOProgress {param($Done,$Completed) if (-not $Completed -and $Done -eq 2) {throw 'Synthetic removal interruption'}}
            {Invoke-VSORemoval $plan $script:ctx}|Should -Throw '*interruption*'
            Test-Path (Join-Path $script:target '.vso-manager.json')|Should -BeTrue
            Mock Write-VSOProgress {}
            $retry=Get-VSORemovalPlan $item $script:ctx -Full
            $null=Invoke-VSORemoval $retry $script:ctx
            Test-Path (Join-Path $script:target '.vso-manager.json')|Should -BeFalse
        }
        It 'reports and preserves an empty directory whose ownership is unknown' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $foreign=Join-Path $script:target 'foreign-empty';[void][IO.Directory]::CreateDirectory($foreign)
            $plan=Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx -Full
            @($plan.Protected|Where-Object Path -EQ $foreign)[0].Reason|Should -Be UntrackedEmptyDirectory
            $null=Invoke-VSORemoval $plan $script:ctx
            Test-Path $foreign|Should -BeTrue
        }
        It 'preflights access denial without deleting an earlier owned file' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $plan=Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx -Full
            $path=$plan.Remove[-1].Path;$acl=Get-Acl -LiteralPath $path
            $denied=Get-Acl -LiteralPath $path;$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
            $denied.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::ReadData,[Security.AccessControl.AccessControlType]::Deny))
            try {
                Set-Acl -LiteralPath $path -AclObject $denied
                {Invoke-VSORemoval $plan $script:ctx}|Should -Throw
                Test-Path $plan.Remove[0].Path|Should -BeTrue
            }finally{Set-Acl -LiteralPath $path -AclObject $acl}
        }
        It 'rejects a read-only owned file before deleting any earlier candidate' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $plan=Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx -Full
            $file=Get-Item -LiteralPath $plan.Remove[-1].Path
            try {$file.IsReadOnly=$true;{Invoke-VSORemoval $plan $script:ctx}|Should -Throw '*read-only*';Test-Path $plan.Remove[0].Path|Should -BeTrue}
            finally {$file.IsReadOnly=$false}
        }
        It 'preflights directory deletion rights before deleting its owned files' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $plan=Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx -Full
            $parentAcl=Get-Acl $script:caseRoot;$rootAcl=Get-Acl $script:target;$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
            $denyParent=Get-Acl $script:caseRoot;$denyRoot=Get-Acl $script:target
            $denyParent.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles,[Security.AccessControl.AccessControlType]::Deny))
            $denyRoot.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::Delete,[Security.AccessControl.AccessControlType]::Deny))
            try {
                Set-Acl $script:caseRoot $denyParent;Set-Acl $script:target $denyRoot
                {Invoke-VSORemoval $plan $script:ctx}|Should -Throw
                Test-Path $plan.Remove[0].Path|Should -BeTrue
            }finally{Set-Acl $script:caseRoot $parentAcl;Set-Acl $script:target $rootAcl}
        }
        It 'rejects tampered registration or receipt before deletion' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $p=Join-Path $script:target '.vso-manager.json';$r=Read-VSOJson $p $script:ctx
            $r.Files[0].Path='../outside.txt'; Write-VSOJson $p $r $script:ctx
            {Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx}|Should -Throw
            Test-Path -LiteralPath (Join-Path $script:target 'VSO7/VSO7.ps1')|Should -BeTrue
        }
        It 'preflights all removal hashes before deleting the first file' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $plan=Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx
            [IO.File]::AppendAllText($plan.Remove[-1].Path,'changed')
            {Invoke-VSORemoval $plan $script:ctx}|Should -Throw
            Test-Path -LiteralPath $plan.Remove[0].Path|Should -BeTrue
        }
        It 'fails closed on an ambiguous interrupted transaction' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $txn=Join-Path $script:caseRoot ('.vso-txn-'+[guid]::NewGuid().ToString('N'))
            New-VSOSecureDirectory $txn CurrentUser $script:ctx
            Write-VSOJson (Join-Path $txn 'transaction.json') @{Schema=1;Product='VicoSafeOptimizer.Transaction';Target=$script:target;State='Promoted'} $script:ctx
            {Repair-VSOTransactions $script:target $script:ctx}|Should -Throw '*interrupted*'
            Test-Path -LiteralPath (Join-Path $script:target 'VSO7/VSO7.ps1')|Should -BeTrue
        }
        It 'recovers an interrupted rename when the destination is absent' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $receipt=Read-VSOReceipt $script:target $script:ctx
            $txn=Join-Path $script:caseRoot ('.vso-txn-'+[guid]::NewGuid().ToString('N'))
            New-VSOSecureDirectory $txn CurrentUser $script:ctx
            [IO.Directory]::Move($script:target,(Join-Path $txn 'previous'))
            Write-VSOJson (Join-Path $txn 'transaction.json') @{Schema=1;Product='VicoSafeOptimizer.Transaction';Target=$script:target;InstallationId=$receipt.Id;State='Prepared'} $script:ctx
            Repair-VSOTransactions $script:target $script:ctx
            (Read-VSOReceipt $script:target $script:ctx).Id|Should -Be $receipt.Id
            (Read-VSOJson (Join-Path $txn 'transaction.json') $script:ctx).State|Should -Be 'RolledBack'
        }
        It 'removes only attributable previous application files when backup loss is acknowledged' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            [IO.File]::WriteAllText((Join-Path $script:target 'foreign.txt'),'keep')
            $script:release=New-LabRelease $script:caseRoot '1.2.3'
            $result=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx -Update
            $plan=Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx -Full -RemoveBackups
            $null=Invoke-VSORemoval $plan $script:ctx
            Test-Path -LiteralPath (Join-Path $result.BackupPath 'VSO7/VSO7.ps1')|Should -BeFalse
            [IO.File]::ReadAllText((Join-Path $result.BackupPath 'foreign.txt'))|Should -Be 'keep'
            [IO.File]::ReadAllText((Join-Path $script:target 'foreign.txt'))|Should -Be 'keep'
        }
        It 'rejects a forged previous receipt before any selected installation file is deleted' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $script:release=New-LabRelease $script:caseRoot '1.2.3'
            $result=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx -Update
            $marker=Join-Path $result.BackupPath '.vso-manager.json';$old=Read-VSOJson $marker $script:ctx
            $old.Files[0].Sha256='0'*64;Write-VSOJson $marker $old $script:ctx
            {Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx -Full -RemoveBackups}|Should -Throw '*backup receipt changed*'
            Test-Path (Join-Path $script:target 'VSO7/VSO7.ps1')|Should -BeTrue
        }
        It 'rejects changed transaction metadata and preserves legacy journals without pins' {
            $null=Invoke-VSOInstallTransaction $script:options $script:release $script:ctx
            $receipt=Read-VSOReceipt $script:target $script:ctx
            $journal=Join-Path (Join-Path $script:caseRoot $receipt.Transactions[0]) 'transaction.json'
            [IO.File]::AppendAllText($journal,' ')
            {Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx -Full}|Should -Throw '*journal changed*'
            $marker=Join-Path $script:target '.vso-manager.json';$receipt.PSObject.Properties.Remove('TransactionReceipts')
            Write-VSOJson $marker $receipt $script:ctx;Register-VSOReceipt $receipt $script:ctx
            $plan=Get-VSORemovalPlan ([pscustomobject]@{Path=$script:target}) $script:ctx -Full
            $plan.Protected.Reason|Should -Contain TransactionJournalNotPinned
            $plan.Remove.Path|Should -Not -Contain $journal
        }
    }
}
