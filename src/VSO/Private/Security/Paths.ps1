function Test-VSOWithin {
    param([string]$Path, [string]$Root, [switch]$AllowEqual)
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if ($AllowEqual -and $full.Equals($base,[StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)
}

function Assert-VSONoReparse {
    param([string]$Path, $Context)
    $cursor=[IO.Path]::GetFullPath($Path)
    while ($cursor) {
        # Get-Item, rather than Test-Path alone, also inspects dangling links.
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Throw-VSOError $Context Reparse @($cursor) }
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }; $cursor=$parent
    }
}

function Resolve-VSOPath {
    param([string]$Path, $Context, [switch]$Installation)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(2) -match '[:*?"<>|\x00-\x1f]' -or $Path -match '[%!&^()]') { Throw-VSOError $Context Path @($Path) }
    foreach ($component in ($Path.Substring(3) -split '[\\/]')) {
        if ($component -in @('.','..') -or $component -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { Throw-VSOError $Context Path @($Path) }
    }
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    # Reserve room for sibling staging/journal names under Windows PowerShell's
    # legacy filesystem APIs. The payload child is not a second installation root.
    $maximum=if ($Installation) {160}else{240}
    if ($full.Length -le 3 -or $full.Length -gt $maximum) { Throw-VSOError $Context Path @($Path) }
    Assert-VSONoReparse $full $Context
    if ($Installation) {
        $windows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        $protected=@($windows,$env:SystemRoot,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData,$env:USERPROFILE,$env:LOCALAPPDATA,$env:APPDATA,$script:ModuleRoot)
        foreach ($root in $protected) {
            if ($root -and ((Test-VSOWithin $root $full -AllowEqual) -or ($root -in @($windows,$env:SystemRoot) -and (Test-VSOWithin $full $root -AllowEqual)))) { Throw-VSOError $Context Path @($full) }
        }
        foreach ($root in @([IO.Path]::GetTempPath(),(Join-Path $env:SystemRoot 'Temp'))) {
            if (Test-VSOWithin $full $root -AllowEqual) { Throw-VSOError $Context Temporary }
        }
    }
    return $full
}

function Join-VSOChild {
    param([string]$Root, [string]$Relative, $Context)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:*?"<>|\x00-\x1f]' -or $Relative -match '[\\/]$') { Throw-VSOError $Context Path @($Relative) }
    foreach ($piece in ($Relative -split '[\\/]')) {
        if (-not $piece -or $piece -in @('.','..') -or $piece -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { Throw-VSOError $Context Path @($Relative) }
    }
    $path=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not (Test-VSOWithin $path $Root)) { Throw-VSOError $Context Path @($Relative) }
    Assert-VSONoReparse $path $Context
    return $path
}

function Get-VSODefaultPath {
    param([string]$Scope, $Context)
    $base=if ($Scope -eq 'AllUsers') { $env:ProgramFiles } else { $env:LOCALAPPDATA }
    if (-not $base) { Throw-VSOError $Context Path @($Scope) }
    if ($Scope -eq 'CurrentUser') { return (Join-Path $base 'Programs\VSO') }
    return (Join-Path $base 'VSO')
}

function Assert-VSOProtectedDirectory {
    param([string]$Path, $Context, [switch]$UserAllowed)
    Assert-VSONoReparse $Path $Context
    $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
    $allowed=@('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    if ($UserAllowed) { $allowed += [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
    $writeMask=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and ($rule.FileSystemRights -band $writeMask) -and $rule.IdentityReference.Value -notin $allowed -and -not ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)) { Throw-VSOError $Context ProtectedParent }
    }
    $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin $allowed) { Throw-VSOError $Context ProtectedParent }
}

function New-VSOSecureDirectory {
    param([string]$Path, [string]$Scope, $Context)
    Assert-VSONoReparse $Path $Context
    if ([IO.Directory]::Exists($Path)) { Assert-VSOProtectedDirectory $Path $Context -UserAllowed:($Scope -eq 'CurrentUser'); return }
    $acl=[Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    $inherit=[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none=[Security.AccessControl.PropagationFlags]::None
    $allow=[Security.AccessControl.AccessControlType]::Allow
    $identities=@('S-1-5-18','S-1-5-32-544')
    if ($Scope -eq 'CurrentUser') { $identities += [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
    foreach ($sid in $identities) { $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),[Security.AccessControl.FileSystemRights]::FullControl,$inherit,$none,$allow)) }
    if ($Scope -eq 'AllUsers') { $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),[Security.AccessControl.FileSystemRights]::ReadAndExecute,$inherit,$none,$allow)) }
    $owner=if ($Scope -eq 'AllUsers') { 'S-1-5-32-544' } else { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($owner))
    # Framework's overload creates with ACLs; Core uses the FileSystemAclExtensions API.
    if ($PSVersionTable.PSEdition -eq 'Desktop') { [void][IO.Directory]::CreateDirectory($Path,$acl) }
    else { [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($Path),$acl) }
    Assert-VSOProtectedDirectory $Path $Context -UserAllowed:($Scope -eq 'CurrentUser')
}

function Get-VSOTreeFiles {
    param([string]$Root, $Context, [int]$Limit = 20000)
    $pending=[Collections.Generic.Stack[string]]::new(); $pending.Push($Root); $count=0
    while ($pending.Count) {
        $dir=$pending.Pop(); Assert-VSONoReparse $dir $Context
        foreach ($item in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Throw-VSOError $Context Reparse @($item.FullName) }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else { $count++; if ($count -gt $Limit) { Throw-VSOError $Context Archive @('file count') }; $item }
        }
    }
}

function Remove-VSOPrivateTree {
    param([string]$Path, [string]$Parent, $Context)
    if (-not (Test-VSOWithin $Path $Parent) -or [IO.Path]::GetFileName($Path) -notmatch '^\.vso-(work|txn)-[a-f0-9]{32}$') { Throw-VSOError $Context Path @($Path) }
    if ([IO.Directory]::Exists($Path)) {
        $null=@(Get-VSOTreeFiles $Path $Context)
        Assert-VSONoReparse $Path $Context
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
}
