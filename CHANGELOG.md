# Changelog

## 1.0.2

- Return an explicit structured NotInstalled query summary from Get-VSOStatus when no installations match. Keep raw states, nulls and Boolean activity separate from localized native formatting, including unknown visibility and filtered-query wording.
- Preserve empty collection semantics for Get-VSOInstallation; support pipeline paths on both query commands and validate version filters even when discovery is empty. Preserve index access failures instead of silently reporting an empty index.
- Use numbered English/Spanish native examples. Get-Help already stored examples separately; its Full renderer displays them after NOTES without a general examples heading. Correct MAML namespaces, positional/pipeline metadata and missing WhatIf/Confirm syntax; generate from AST without importing runtime during builds.
- Make Help-VSO syntax include the command name, keep overview descriptions wrapped, explain independent application/module removal and reject Examples without Command with a localized actionable error.
- Add focused regression coverage; retain the existing installation/update/launch/removal implementations, source-available license and immutable published packages. Prepare locally for owner review; no publication is performed by this iteration.

## 1.0.1

- Shortened the package description and used canonical PowerShell capitalization in the packaged installation examples.
- Updated release metadata and the User-Agent version; application management behavior is unchanged.
- Retained the published 1.0.0 artifact and its evidence. Gallery requires a new package version to update package metadata.

## 1.0.0

- Public module and Gallery package name: VSO. The eight public commands remain unchanged; module-qualified calls, pinned UAC bootstrap, native help and package tooling use the new name.
- Separate source-available module license and official repository. The managed VSO application retains its own license and serialized identity.
- Preserved native installation choices, localized help, official release validation, transactions, exact process attribution, WhatIf/Confirm and attributable Full removal. Shared Recovery and unknown data remain protected; removal never reverses Windows tweaks.
- Kept exact-byte package approval and publication without rebuilding. Added privacy documentation and platform-license rationale.
- Retained the previously validated Desktop atomic JSON, child module-path isolation, pinned UAC policy and bounded CIM absence fixes. See VALIDATION.md and the release for actual acceptance results and remaining limits.
