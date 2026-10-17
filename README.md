# VSO PowerShell Module

Official installation and lifecycle manager for [Vico Safe Optimizer](https://github.com/saturnus25/VSO), maintained by **saturnus25**. The PowerShell module is named **VSO**; module version **1.0.2** is independent of the application's version. It downloads official release assets instead of bundling the optimizer.

## Installation

PowerShell with PSResourceGet:

```powershell
Install-PSResource VSO
Install-VSO
```

The first command installs the module. The second opens the native VSO installation wizard. Windows PowerShell 5.1 with PowerShellGet:

```powershell
Install-Module VSO
Install-VSO
```

Gallery availability and exact package acceptance are recorded in the GitHub release. See [validation](VALIDATION.md) for tested environments and limits. To review a source checkout in an isolated environment, build with `build/Build.ps1 -Package`, then import `dist/VSO/VSO.psd1`.

## Commands

| Command | Purpose |
|---|---|
| `Install-VSO` | Download, verify and install an official application release |
| `Start-VSO` | Start its official launcher |
| `Stop-VSO` | Inspect running VSO; termination requires explicit `-Force` |
| `Update-VSO` | Update with integrity checks and previous-copy retention |
| `Get-VSOStatus` | Read installation, integrity and process status |
| `Get-VSOInstallation` | Discover registered installations |
| `Reset-VSO` | Remove attributable application files |
| `Help-VSO` | Show localized command help |

```powershell
Install-VSO -Path "D:\VSO"
Install-VSO -AllUsers
Start-VSO
Stop-VSO
Update-VSO
Get-VSOStatus
Get-VSOInstallation
Help-VSO
Get-Help Reset-VSO -Full
Reset-VSO -WhatIf
```

CurrentUser is the default and uses `$env:LOCALAPPDATA\Programs\VSO`. AllUsers uses `$env:ProgramFiles\VSO` and requests UAC when necessary. An explicit `Path` selects a custom managed folder; the official payload remains in its `VSO7` child. Native choices and folder selection are interactive. `-Quiet` suppresses prompts and elevation; unresolved choices or permissions produce errors. English and Spanish messages and help are included; `-Language en` or `-Language es` overrides automatic selection. Mutating commands support `-WhatIf` and `-Confirm`.

`Reset-VSO` preserves unknown or modified data. `-Full` also considers provably owned declared data; backups additionally require `-RemoveBackups -AcknowledgeBackupLoss`. Shared VSO Recovery and untracked files remain protected. Removing the application never restores Windows tweaks, and does not uninstall the PowerShell module. See [usage](docs/Usage.md) and [removal](docs/Removal.md) for details.

`Get-VSOStatus` returns a structured `NotInstalled` query summary when nothing matches. Its default display follows `Language`; raw properties remain stable English tokens, nulls and Booleans. `Get-VSOInstallation` enumerates actual candidates and returns an empty collection when none match. Both accept paths or objects with a `Path` property through the pipeline.

## Uninstallation

The application and the PowerShell module are independent components:

```powershell
Reset-VSO                 # Remove the application, preserving protected data
Reset-VSO -Full            # Also consider additional attributable application data
Uninstall-PSResource VSO   # Remove the module installed with PSResourceGet
# Or, for a module installed with PowerShellGet:
Uninstall-Module VSO
```

Choose the applicable command. `Reset-VSO` keeps the module; uninstalling the module keeps the application. Close sessions importing the module before removing it. Use `Help-VSO`, `Help-VSO -Command Reset-VSO`, or `Get-Help Reset-VSO -Examples` to review syntax and removal limits. Native `Get-Help -Full` places examples after NOTES; numbered example headings distinguish them from the preceding notes.

## Requirements and compatibility

Windows 11 x64, a 64-bit Windows PowerShell 5.1 or PowerShell 7 session, and network access to the official GitHub releases for installation and updates. The existing platform guard excludes Windows 10, Windows Server and ARM64. Six official VSO7 releases, 1.0.0 through 1.2.2, have isolated Windows acceptance evidence. VSO8 has no execution adapter and is not supported by this release.

The module does not apply tweaks, change stored execution policies or send telemetry. The official application and pinned UAC helper use process-scoped execution-policy arguments. Starting VSO delegates to its own launcher and safety gates. See [architecture](docs/Architecture.md), [security](docs/Security.md), [privacy](docs/Privacy.md) and [distribution contracts](docs/Distribution.md).

## License

The module uses the [VSO PowerShell Module Source-Available License 1.0](LICENSE). It is free to view, study, install and run for personal or professional use. Exact unmodified copies may be shared with attribution. General modification, modified redistribution, derivative projects and rebranding require separate permission, subject to platform and legal exceptions in the license. This is **source available**, not OSI-approved open source. [License rationale](docs/License-Rationale.md) explains the platform exceptions.

The separate [Vico Safe Optimizer application](https://github.com/saturnus25/VSO) retains its own MIT license; its third-party components retain their respective licenses. The module license does not replace them.

## Development

Read [AGENTS.md](AGENTS.md). Runtime testing and system-changing operations belong in an authorized disposable VM. Static checks: `build/Test-Static.ps1` and `build/Test-Privacy.ps1`. Build, validation, exact-package approval and publication are separate steps; see [publishing](docs/Publishing.md). Build tools and tests are excluded from the runtime package.

## AI Development Notice

The VSO PowerShell Module was developed with substantial assistance from artificial intelligence, including code generation, debugging, testing, and documentation. Project direction, release decisions, and maintenance are overseen by saturnus25.
