# VSO PowerShell Module

**The official PowerShell installation and lifecycle manager for [Vico Safe Optimizer](https://github.com/saturnus25/VSO).**

[PowerShell Gallery](https://www.powershellgallery.com/packages/VSO) · [Main Project](https://github.com/saturnus25/VSO) · [Documentation](docs/Usage.md) · [License](LICENSE)

VSO PowerShell Module provides a simple, secure and automated way to install, launch, update and remove Vico Safe Optimizer directly from PowerShell.

The module is maintained by **saturnus25** and distributed independently of the application. It downloads and verifies official GitHub release assets rather than bundling the optimizer.

**Current module version:** `1.0.1`

> Module versions and Vico Safe Optimizer application versions are maintained independently.

---

## Installation

### Recommended — PSResourceGet

```powershell
Install-PSResource VSO
Install-VSO
```

The first command installs the PowerShell module. The second launches VSO's interactive installation wizard.

### Alternative — Windows PowerShell 5.1

For systems using PowerShellGet:

```powershell
Install-Module VSO
Install-VSO
```

Both methods install the same module from PowerShell Gallery.

### Custom installation

```powershell
# Install VSO to a custom directory
Install-VSO -Path "D:\VSO"

# Install VSO for all users
Install-VSO -AllUsers
```

By default, the installation wizard allows you to select the installation scope and destination.

| Scope | Default location |
|---|---|
| CurrentUser | `%LOCALAPPDATA%\Programs\VSO` |
| AllUsers | `%ProgramFiles%\VSO` |

AllUsers installation requests UAC elevation when required. Custom installation paths are supported, including native Windows folder selection.

The official VSO7 payload is stored inside a `VSO7` subdirectory of the selected installation folder.

## Available commands

| Command | Description |
|---|---|
| `Install-VSO` | Download, verify and install an official VSO release |
| `Start-VSO` | Launch the installed application |
| `Stop-VSO` | Inspect running VSO processes and optionally terminate them |
| `Update-VSO` | Update VSO while preserving supported data and backups |
| `Get-VSOStatus` | Display installation, integrity and process status |
| `Get-VSOInstallation` | Discover registered VSO installations |
| `Reset-VSO` | Safely remove VSO application files and attributable data |
| `Help-VSO` | Display localized module help and usage examples |

### Quick usage

```powershell
# Launch VSO
Start-VSO

# Check installation status
Get-VSOStatus

# Update VSO
Update-VSO

# View installed versions and locations
Get-VSOInstallation

# Display all available commands
Help-VSO

# Detailed help for a specific command
Get-Help Install-VSO -Full
```

To terminate VSO processes, `Stop-VSO` requires explicit `-Force`. It validates process identity to avoid terminating unrelated PowerShell or CMD processes.

### Uninstalling VSO

There are two separate components: **the VSO application** and **the PowerShell management module**.

**1. Remove the VSO application**

```powershell
Reset-VSO
```

For deeper cleanup of safely attributable application data:

```powershell
Reset-VSO -Full
```

To preview removal without changing anything:

```powershell
Reset-VSO -Full -WhatIf
```

Removing backups requires additional explicit acknowledgement:

```powershell
Reset-VSO -Full -RemoveBackups -AcknowledgeBackupLoss
```

**2. Uninstall the PowerShell module**

If installed with PSResourceGet:

```powershell
Uninstall-PSResource VSO
```

If installed with PowerShellGet:

```powershell
Uninstall-Module VSO
```

**Important:** Removing the PowerShell module does not automatically uninstall the VSO application. Run `Reset-VSO` first if you also want to remove the application.

Likewise, removing VSO does not revert Windows optimizations previously applied by the application. Shared Recovery, modified files and data of uncertain ownership remain protected.

See [Removal Documentation](docs/Removal.md) for details.

---

## Features

- **Official release integration:** Dynamically discovers VSO releases from GitHub.
- **Integrity verification:** Validates downloaded packages and expected files.
- **Interactive installation:** Native PowerShell choices and Windows folder selection.
- **Flexible installation:** CurrentUser, AllUsers and custom paths.
- **Safe updates:** Staged installation, integrity checks and previous-copy retention.
- **Controlled removal:** Ownership-aware cleanup designed to protect unrelated files.
- **Native progress reporting:** PowerShell progress bars for measurable operations.
- **Localization:** English and Spanish messages and help.
- **Automation support:** Non-interactive execution, structured results and compatible parameters.
- **No telemetry:** The module does not collect or transmit usage analytics.

Mutating commands support `-WhatIf` and `-Confirm`.

Use `-Quiet` where supported to suppress interactive prompts. Operations requiring unresolved decisions or unavailable permissions return errors rather than proceeding unsafely.

Language selection can be overridden using `-Language en` or `-Language es`.

## Requirements and compatibility

| Component | Requirement |
|---|---|
| Operating system | Windows 11 x64 |
| PowerShell | 64-bit Windows PowerShell 5.1 or PowerShell 7.x |
| Connectivity | Internet access for installation and updates |
| Application support | Official VSO7 releases |
| Permissions | Administrator privileges only when required |

The existing platform guard excludes Windows 10, Windows Server and ARM64.

Six official VSO7 releases, from `1.0.0` through `1.2.2`, have isolated Windows acceptance evidence.

**VSO8 is not yet supported.** Its execution adapter will be implemented and validated separately.

## Security and safety

The module is designed to manage VSO installations without applying Windows tweaks itself.

Security measures include:

- Download and file-integrity verification.
- Protected extraction and controlled installation paths.
- Process identity verification before termination.
- Installation transaction and rollback safeguards.
- Preservation of unknown, modified or shared data.
- Explicit acknowledgement for destructive backup removal.
- Process-scoped execution-policy arguments when required by the official launcher and elevation helper.

The module does not modify stored PowerShell execution policies or disable Windows security features.

Additional technical information is available in the [Security](docs/Security.md), [Architecture](docs/Architecture.md) and [Distribution Contracts](docs/Distribution.md) documentation.

## Documentation

| Document | Contents |
|---|---|
| [Usage Guide](docs/Usage.md) | Commands, parameters and examples |
| [Removal Guide](docs/Removal.md) | Safe uninstallation and backup handling |
| [Architecture](docs/Architecture.md) | Module structure and implementation |
| [Security](docs/Security.md) | Security model and safeguards |
| [Privacy](docs/Privacy.md) | Privacy and data handling |
| [Distribution Contracts](docs/Distribution.md) | Release formats and compatibility |
| [Validation](VALIDATION.md) | Tested environments and known limitations |
| [Publishing](docs/Publishing.md) | Build, validation and publishing procedures |

You can also access command documentation directly from PowerShell:

```powershell
Help-VSO
Help-VSO -Command Install-VSO
Get-Help Reset-VSO -Full
```

## Development

The module follows a modular architecture with separate public commands, private utilities, localized resources and automated tests.

Development instructions are available in [AGENTS.md](AGENTS.md).

Static validation:

```powershell
.\build\Test-Static.ps1
.\build\Test-Privacy.ps1
```

Building the module from source:

```powershell
.\build\Build.ps1 -Package
Import-Module .\dist\VSO\VSO.psd1
```

Runtime testing and system-changing operations must be performed in an authorized, isolated and disposable test environment.

Build, validation, package approval and publication are independent stages. Development tools and tests are excluded from the distributed runtime package.

## License

VSO PowerShell Module is distributed under the [VSO PowerShell Module Source-Available License 1.0](LICENSE).

The license permits viewing, studying, installing and running the module for personal or professional use. Exact, unmodified copies may be shared with attribution.

General modification, redistribution of modified versions, derivative projects and rebranding require separate permission, subject to the exceptions stated in the license.

**This project is source available, not OSI-approved open source.**

See the [License Rationale](docs/License-Rationale.md) for further information.

The separate [Vico Safe Optimizer](https://github.com/saturnus25/VSO) application retains its MIT license. Third-party components remain subject to their respective licenses.

## AI Development Notice

This project was developed with substantial assistance from artificial intelligence, including code generation, debugging, testing and documentation.

Project direction, release decisions and ongoing maintenance are overseen by **saturnus25**.

---

Maintained by **saturnus25** · [Vico Safe Optimizer](https://github.com/saturnus25/VSO) · [PowerShell Gallery](https://www.powershellgallery.com/packages/VSO)
