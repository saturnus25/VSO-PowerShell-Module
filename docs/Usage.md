# Command usage

## Commands

| Command | Purpose | Main parameters |
|---|---|---|
| `Install-VSO` | Download and install an official release | `Path`, `Scope`, `AllUsers`, `Version`, `Prerelease`, `AssetName`, `Force`, `Quiet`, `Language`, `PassThru`, `WhatIf`, `Confirm` |
| `Start-VSO` | Open the official launcher | `Path`, `Version`, `AllowUnregistered`, `Language`, `PassThru`, `WhatIf`, `Confirm` |
| `Stop-VSO` | Terminate strictly attributed processes, with explicit force | `Path`, `Version`, `Force`, `Quiet`, `Language`, `PassThru`, `WhatIf`, `Confirm` |
| `Update-VSO` | Verified replacement with previous-copy retention | `Path`, `Version`, `Prerelease`, `AssetName`, `Force`, `Quiet`, `Language`, `PassThru`, `WhatIf`, `Confirm` |
| `Get-VSOInstallation` | Read-only discovery and integrity | `Path`, `Scope`, `Version`, `Language`, `Quiet` |
| `Get-VSOStatus` | Read-only installation and process status | `Path`, `Scope`, `Version`, `Language`, `Quiet` |
| `Reset-VSO` | Remove attributable application files | `Path`, `Version`, `Full`, `RemoveBackups`, `AcknowledgeBackupLoss`, `Force`, `Quiet`, `Language`, `PassThru`, `WhatIf`, `Confirm` |
| `Help-VSO` | Localized help | `Command`, `Examples`, `Language`, `PassThru` |

Public commands are advanced functions. Only these eight are exported. Informational commands return objects and never ask for confirmation. `WhatIf` never downloads, creates a lock, opens UAC, launches VSO or removes files. Discovery may still read installation metadata, file hashes and process data.

## Install VSO

```powershell
Install-VSO
Install-VSO -Path 'D:\Programs\VSO'
Install-VSO -Scope CurrentUser -Quiet -PassThru
Install-VSO -AllUsers
Install-VSO -AllUsers -Path 'D:\Applications\VSO'
Install-VSO -Version 1.2.2 -Language es
Install-VSO -Prerelease
Install-VSO -WhatIf
```

With no arguments in an interactive console, native letter choices select CurrentUser (default), AllUsers or Cancel, then the default folder or a custom folder. Cancellation raises a terminating localized PowerShell error. An explicit `Scope` or `AllUsers` resolves scope only; interactive execution still asks whether to use its default destination. An explicit `Path` skips both choices. `Path` alone implies CurrentUser. `AllUsers` conflicts with explicit `Scope CurrentUser`.

CurrentUser defaults to `$env:LOCALAPPDATA\Programs\VSO`. AllUsers defaults to `$env:ProgramFiles\VSO`. The selected folder is the managed installation root; the official payload stays in its `VSO7` child, for example `D:\Programs\VSO\VSO7\START VSO7.bat`. VSO7's first-run code otherwise offers to relocate a package whose folder is not named VSO7, which would invalidate manager paths. `ApplicationPath` reports the actual payload folder. The working directory is never used. In an STA host a Windows folder picker is loaded on demand. In MTA or when the graphical picker is unavailable, the module requests an absolute path in the console. Cancelling a displayed picker cancels the operation; it does not silently fall back.

Quiet uses CurrentUser and its default folder unless parameters select otherwise. It never opens UAC or a dialog. Missing permissions or ambiguous choices fail with descriptive errors. AllUsers requests UAC only outside an already elevated session; its custom parent must exist and be protected against non-administrator writes. The module does not weaken a shared parent ACL to make installation succeed. Protected CurrentUser destinations fail rather than silently escalating a user installation.

Each release must have a single distribution ZIP or an exact `AssetName`. GitHub automatic source archives are never used. A GitHub asset SHA-256 digest is preferred, followed by an official sidecar checksum. Every extracted file is also checked against the internal manifest. Missing archive integrity data is fatal, including with Force. HTTPS and repository provenance anchor the download; these SHA-256 values are not an independent author signature and do not prove a compromised release account is trustworthy.

The archive is limited to 128 MiB compressed, 512 MiB expanded, 256 MiB per file and 10,000 entries, with additional expansion-ratio limits. Traversal, rooted paths, reserved Windows names, aliases, duplicate case-insensitive paths, links, special entries and unlisted files are rejected before promotion. Installation paths containing command-shell metacharacters are rejected because VSO7 uses a batch launcher; spaces, apostrophes and Unicode remain supported.

The managed installation root is limited to 160 characters, reserving space for the VSO7 child and sibling transaction/staging paths under Windows PowerShell 5.1. This deliberate compatibility limit is checked before writing files; the payload child is validated as a descendant rather than applying the root-length limit to it again.

An existing managed installation requires `Update-VSO` or `Install-VSO -Force`. A manual installation can be adopted with Force only if its application files exactly match the independently verified requested release. Other files are retained. Modified managed code is never overwritten via Force; use a fresh destination and review the damaged copy separately.

## Discovery, launch and process handling

```powershell
Get-VSOInstallation | Select-Object Version, Path, Scope, State
Get-VSOStatus -Quiet | Format-List
Start-VSO -Path 'D:\Programs\VSO' -PassThru
Stop-VSO -Path 'D:\Programs\VSO' -WhatIf
Stop-VSO -Path 'D:\Programs\VSO' -Force -PassThru
```

Registration is separate for CurrentUser and AllUsers in `VicoSafeOptimizer.Module\Installations`, below LOCALAPPDATA and ProgramData respectively. Each install also has a `.vso-manager.json` receipt. The separate name avoids VSO7's historical `%ProgramData%\VicoSafeOptimizer\state.json` format. Only registered folders and the two defaults are inspected automatically; `Path` allows explicit manual discovery. Several matches prompt for selection, or fail in Quiet/non-interactive mode. Get commands enumerate all matches without prompting.

Manual folders can be inspected, but their local checksums alone do not establish official provenance. `Start-VSO -AllowUnregistered -Path ...` explicitly accepts that limitation after layout validation; its actual payload folder must retain the VSO7 leaf name. Adoption with Install -Force accepts an identical official VSO7 child inside the selected root, while preserving unknown files. Normal managed launch is offline and revalidates all registered file hashes. `Start-VSO -PassThru` reports creation of the launcher process; `StartupVerified` remains false because no reliable cross-version readiness API exists. Start intentionally opens an application window and therefore has no Quiet parameter.

Stop never targets all PowerShell, cmd or Terminal processes. It recognizes exact command arguments and the inspected VSO7 protected-memory source/hash contract. It rechecks PID, creation time, executable and command line, and opens a process handle before termination. Unreadable or unfamiliar VSO process evidence fails safely. Because elevated process command lines can be inaccessible to a normal user, you may need an elevated session for reliable status, launch-duplication checks, stop or updates. Arbitrary descendants and shared Windows Terminal windows are not closed.

VSO7 does not expose a verified clean shutdown IPC contract. Close the application normally yourself. `Stop-VSO` without Force reports that requirement when it finds VSO running. `-Force` authorizes termination and can interrupt active changes or Recovery; there is no claim of graceful shutdown.

## Update and recovery of file operations

```powershell
Update-VSO -Path 'D:\Programs\VSO' -WhatIf
Update-VSO -Path 'D:\Programs\VSO' -Quiet -PassThru
Update-VSO -Version 1.2.2 -Force -PassThru
```

Semantic version precedence includes prerelease identifiers. Equal/older releases are skipped unless Force explicitly requests reinstall/downgrade. Activity checks and an exclusive per-target lock guard replacement. Download and staging precede any rename of the installation. Unknown files are copied and hash-checked; the original directory remains in a sibling `.vso-txn-<random>/previous` backup with a transaction journal. File-operation failure attempts restoration and registration of the old copy. This is installer rollback, not Windows tweak Recovery.

After an interrupted transaction, a missing target with an attributable previous copy can be restored on the next operation. An ambiguous existing target causes a fail-closed error with the journal path; the module will not guess which copy is authoritative. No maintenance script from the ZIP is executed. Automatic migration to another generation is blocked until an adapter and compatible data migration have been validated.

## Remove

```powershell
Reset-VSO -Path 'D:\Programs\VSO' -Full -WhatIf -PassThru
Reset-VSO -Path 'D:\Programs\VSO' -Quiet -Force -PassThru
Reset-VSO -Full -RemoveBackups -AcknowledgeBackupLoss -Confirm
```

Review the exact Remove, Preserve and Protected lists before approving. Protected gives a reason and ownership classification for each preserved object. Normal reset deletes unchanged owned application files and matching registration/receipt, preserving declared persistent data. Full additionally deletes unchanged configuration, cache, logs and temporary data from a verified distribution inventory, and attributable committed transaction metadata. Modified, unknown and foreign files survive. It never recursively deletes the installation folder. Non-interactive destructive removal requires Force; backup removal additionally requires Full and AcknowledgeBackupLoss. Explicit Confirm remains honored.

VSO7's current contract cannot attribute shared `%ProgramData%\VicoreDevelopment\VSO7` Recovery, secrets, configuration, downloaded utilities or fallback reports to one installation. It also supplies no per-file ownership ledger for newly created local runtime data. Consequently **Full preserves those data**, including local files without provenance. This is a deliberate safety limitation, not a claim to remove every trace. `RemoveBackups` can delete unchanged application files from attributable previous manager copies, while retaining unknown backup contents and the journals/receipts needed to explain them. No backups of Windows state are deleted. The module creates no shortcuts, scheduled tasks or persistent downloader cache to clean up. The Gallery module itself is retained; after application removal, the owner can use `Uninstall-PSResource VSO` or `Uninstall-Module VSO` in a separate session.

## Localization and progress

```powershell
Help-VSO -Language es
Help-VSO -Command Reset-VSO -Examples -Language en
Get-Help Install-VSO -Full
Get-Help Reset-VSO -Examples
```

Spanish UI cultures use es-ES; other cultures explicitly fall back to en-US. Every applicable command accepts Language. Structured machine states and property names remain stable English tokens, with localized display values. Help-VSO renders readable syntax, parameter/default descriptions and examples; PassThru returns its structured metadata for scripts. Native Get-Help uses generated external MAML for en-US/es-ES plus an English root fallback. Language overrides Help-VSO only; Get-Help follows PowerShell's own session culture. English native rendering and explicit Spanish Help-VSO ran in both editions; automatic Spanish session culture remains a separate acceptance limit.

Native Write-Progress reports streamed download bytes, extracted bytes and checked/removed file counts. Unknown-length activities are indeterminate. Progress respects ProgressPreference, is suppressed by Quiet and is completed in finally blocks.

