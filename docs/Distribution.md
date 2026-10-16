# Inspected distribution and optional future contract

Inspection date: 2026-10-15. Source: the official [release API](https://api.github.com/repos/saturnus25/VSO/releases) and [release list](https://github.com/saturnus25/VSO/releases). Six stable ZIPs were inspected as data; the subsequent isolated Windows campaign installed and launched their unmodified payloads, as detailed in the lab report.

| Tag | ZIP bytes | Archive SHA-256 from GitHub, independently compared to download |
|---|---:|---|
| v1.0.0 | 878636 | a7a863edd38b19fecfe9a8f0ab56486ada26b28035bcce94e6a96be66fae4c2f |
| v1.1.0 | 900252 | cc8e68df2087277a8605c54241c7d69aba46e5e0cb504fa7a9ca3f74782511ef |
| v1.1.1 | 2629155 | 3f783e6ae443cdb89a79525b018d768132b531f4fe64bc79c6034a968c217331 |
| v1.2.0 | 2634548 | 134643b18efcbefaaa6ad3f90f971f471d27ec479c8cd40e78fbc1ae920bfb0c |
| v1.2.1 | 2635661 | d445d4b8fb947b22be9e3ea7870dd1462908fe4e64011412b1ad760d4882716a |
| v1.2.2 | 2635814 | aee33983bd3bedabfc2038e82d4a46338480506e91c4c52f9ad4b2910a926701 |

These historical values document inspection and are not runtime release pins. The installer always reads current official asset metadata. It never constructs a ZIP filename from a version or uses GitHub's automatic source archive.

All releases contain one VSO7 top-level folder. Required protected content comprises START VSO7.bat, both historically named core scripts, Tools/VSO7_STARTUP_GATE.ps1, five Resources catalogs, README, third-party notices, the unblock batch and license files. The initial release names its MIT license LICENSE.txt; later ones use LICENSE. SHA256SUMS.txt lists the other fourteen files with either GNU `hash *path` or `hash  path` syntax. The adapter recognizes both forms, hashes the checksum manifest itself into the receipt and rejects unlisted package files. Archive directory entries differ by release but do not affect the file inventory.

The manager retains the VSO7 folder inside the selected destination. Its receipt and registration address the parent; owned file paths have a VSO7/ prefix. This is required by inspected Invoke-FirstRunOrganization: a payload folder whose leaf is VSO7 bypasses the application relocation offer. Flattening into an arbitrarily named destination would allow the app to relocate itself and invalidate the manager's launch/process/update identity. No organization preference or application source is modified to avoid that offer.

VSO7 1.2.2 places sensitive data in `%ProgramData%\VicoreDevelopment\VSO7`: Config, Recovery, Secrets, RecoveryRunners, state files, disabled-startup copies and downloaded utilities. Local Logs and Informes are preferred, with protected ProgramData fallbacks. The code also recognizes older state paths. This shared and historical ownership model prevents safe per-installation full deletion; the manager does not delete those locations.

The optional [schema](vso-distribution.schema.json) proposes an explicit generation contract. Include `vso-distribution.json` at the payload root, list it in SHA256SUMS.txt, and cover the ZIP with an official archive digest. Example for a future VSO7 package using the existing adapter:

```json
{
  "schemaVersion": 1,
  "product": "VicoSafeOptimizer",
  "generation": "7",
  "version": "1.2.2",
  "platform": "windows-x64",
  "adapter": "vso7-classic-v1",
  "launcher": "START VSO7.bat",
  "launcherType": "Batch",
  "requirements": { "host": "WindowsPowerShell", "minimumVersion": "5.1", "architecture": "x64" },
  "filesManifest": "SHA256SUMS.txt",
  "persistentData": [
    { "base": "Installation", "path": "Logs", "ownership": "SharedOrUntracked", "removeByDefault": false },
    { "base": "ProgramData", "path": "VicoreDevelopment/VSO7", "ownership": "SharedOrUntracked", "removeByDefault": false }
  ],
  "update": { "compatibleGenerations": ["7"], "preserveUnknownFiles": true },
  "uninstall": { "restoreWindowsTweaks": false, "preserveUnknownFiles": true }
}
```

The current implementation validates the identity, generation, adapter, version, platform, launcher and host requirements that it actually consumes. Its remaining fields must agree with the existing VSO7 safety contract. No metadata can enable arbitrary scripts, declare another user's files removable or grant cross-generation compatibility. VSO8 must publish its real layout and ownership semantics before an adapter can be implemented and accepted. No VSO8 claim is made here.

Trust hierarchy: signed/authenticated manifests would outrank hashes but are not present in these inspected releases. The current module supports the observed GitHub asset digest and official checksum sidecars, plus extracted-file validation. Neither same-release hashes nor HTTPS supply an independent author signature. A future signature scheme needs an explicit trust-root policy and implementation, not a speculative generic manifest executor.

## Implemented schema 2 extension

Schema 1 and the six historical packages without a distribution manifest retain their original inventory. Schema 2 adds `packageType: PortableZip`, `requiredFiles` and `optionalFiles`; each inventory record has exactly `path` and `role`. The implemented adapter still requires its known core, gate, catalogs and official launcher. New executable layouts require a reviewed adapter.

Additional data is accepted only below Resources, Docs, Config, Cache, Logs, Temp or Recuperacion, with simple relative names and json/txt/md/xml/csv/ini/dat extensions. Every present file must be declared and checksummed; required files must exist, optional files may be absent. The manifest itself must be checksummed, and official archive provenance/digest checks remain mandatory before installation. Unlisted files and invented launchers are rejected even with fresh checksums.

Roles consumed by removal are Application, Configuration, Cache, Log, Temporary and Recovery. The first is eligible for normal reset. The next four are eligible only for Full, only while bytes still match the receipt. Recovery is always preserved by this adapter, including separately acknowledged application backups. Unknown files and changed data are preserved with reasons. The receipt stores the validated contract and inventory; registration pins its hash. It is not authenticated against the account that owns a CurrentUser installation.

Compatible-generation metadata is validated against the implemented migration policy (7 to 7). Generation 8 remains rejected until a real distribution, launcher/process adapter and migration/ownership semantics have been implemented and tested. This is an extension point, not a claim of VSO8 compatibility.
