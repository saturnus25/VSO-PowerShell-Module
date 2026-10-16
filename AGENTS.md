# VSO PowerShell Module development

This project is an independent application manager. Do not modify VSO7/VSO8 or implement tweaks here.
Public attribution is exclusively saturnus25. Never derive author metadata from the machine or Git.
Support Windows PowerShell 5.1 and PowerShell 7 on Windows 11 x64. Save PowerShell sources as UTF-8 with BOM.
Do not run VSO, installation, update, removal, elevation, or process termination on the development host.
Dynamic tests belong in an explicitly authorized disposable Windows VM. Host verification is static only.
Keep the eight public commands, centralized localization, official release discovery, archive validation,
transaction receipts, exact process attribution and ShouldProcess boundaries intact.
Force must never bypass integrity, path, ownership or compatibility checks. Preserve unknown files and
shared VSO Recovery. Uninstalling files never restores Windows tweaks. Do not publish without permission.
Before packaging, run build/Test-Privacy.ps1 and build/Build.ps1. Before release, run tests/Invoke-LabTests.ps1
in an authorized VM under both supported editions. Record actual results; do not invent PASS evidence.
Do not add absolute personal paths, credentials, email addresses, logs or machine identifiers to public files.

Keep the VSO7 payload in its original VSO7 leaf folder inside the managed root. Its
first-run organizer can otherwise relocate the app and invalidate manager identity.
Do not use PSScriptRoot in a script parameter default: Windows PowerShell 5.1 may
evaluate it before initialization. Resolve script-relative defaults in the body.
Audit embedded nupkg core properties as well as nuspec; publish the audited nupkg
instead of implicitly repackaging and reintroducing packager attribution metadata.
VSO7's memory host hashes UTF-8 loaded source text without the file BOM. Keep that
identity separate from the byte SHA-256 used by archives and installation receipts.

Windows PowerShell 5.1 converts a null String argument in File.Replace into an empty
backup path. Use Language.NullString.Value for atomic JSON replacement and test both editions.
An intermediate cmd launched from Core can pass Core's PSModulePath to Desktop and
break built-in command discovery. Clear it only in the child, preserve the separate
window, and keep CMD attribution restricted to the exact reviewed launcher command.
UAC does not inherit the caller's process execution policy. The pinned bootstrap needs
its own process-scoped policy argument; never change a stored Windows policy for this.
An attributed process may exit while a sibling is stopped. Absence needs no kill;
an occupied PID must still pass every identity check before obtaining/using its handle.
Harness WM_USER string pointers cannot cross process boundaries. Classic folder selection
messages require the owner STA process. Core can present the modern folder dialog instead;
use observed native controls/keyboard input and verify the returned path, not classic BFFM assumptions.

Keep Build, Validate, Approve and Publish separate. Publish must never rebuild or repackage.
Any package/input change invalidates validation and approval; never approve CONDITIONAL candidates.
Full removes only provable owned data and reports each preserved path/reason. Recovery remains separate.
Declared distribution inventory cannot grant another launcher or generation an execution adapter.
Dynamic Windows campaigns have run; preserve their failures and report remaining acceptance gaps exactly.

CIM can briefly retain a terminating process after Get-Process reports absence. A bounded wait
may confirm absence; any reused/changed PID must fail immediately without obtaining another handle.
Acceptance campaigns sharing account registration storage must run separately from tests that
intentionally lock or deny access to index files; retain safe failures rather than masking them.
Before removal, preflight read-only attributes and directory DELETE access as well as file access.
Old transaction names alone do not authenticate journals or backup receipts; preserve unpinned data.
