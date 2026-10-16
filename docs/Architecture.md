# Architecture and responsibility boundaries

The manager is independent of VSO7/VSO8 and has no tweak engine. Eight public advanced functions coordinate private helpers loaded in an explicit order. There are no public aliases, implicit module installation hooks or wildcard exports.

| Layer | Contract |
|---|---|
| Public | Parameter validation, native ShouldProcess and result presentation |
| Localization/UI | Per-call culture context, native PromptForChoice, STA picker or console fallback |
| GitHub | Bounded HTTPS transport, official release resolution, exact asset selection and archive identity |
| Security | Local canonical paths, component checks, reparse rejection, ACLs, bounded extraction |
| Distribution | Versioned adapter recognition and complete checksum inventory |
| Registration | Scope-specific index and per-installation receipt; no Windows registry writes |
| Transaction | Per-target lock, staging, previous-copy retention, promotion and rollback journal |
| Processes | Read-only CIM snapshots, exact command arguments, memory-wrapper evidence and PID revalidation |
| Elevation | Fixed encoded bootstrap, primitive request data, pinned module hashes held open and private result channel |

Module state contains its root, export list and a fingerprint of the imported runtime sources for later elevation. Import holds read handles while loading local definitions and captures their SHA-256 without Windows queries or filesystem writes. A context carries culture and Quiet explicitly. Graphics and networking assemblies are loaded only on demand. Private adapters such as Get-VSOProcessSnapshot, Invoke-VSOHttp and Start-VSOElevationProcess can be replaced by Pester mocks. All getters remain read-only.

The installation receipt records schema, product, random installation ID, independent application version, generation, canonical path, scope, release provenance, archive SHA-256, integrity method, UTC time, layout, launcher, installed state, exact file hashes and attributable previous-copy names. The scope index pins the receipt hash. Inputs are treated as data and constrained again before use; relative inventory entries must belong to the implemented adapter's canonical file list or validated schema 2 data inventory. Optional receipt fields preserve the validated distribution contract and pin committed transaction journals and prior backup receipts. Legacy receipts without those pins retain their application behavior; ambiguous legacy backup/journal ownership is preserved. AllUsers storage and application directories have restricted writer ACLs. The CurrentUser receipt also requires a directory protected against other users' writes.

The managed root contains the official VSO7 child, preserving the upstream first-run folder contract. Receipts distinguish ApplicationDirectory, the prefixed launcher path and MemorySourceSha256. That memory identity is the SHA-256 of UTF-8 loaded source text without BOM, matching the inspected native bootstrap; it must not be substituted with the file-byte checksum. The two protected core copies must be byte-identical before installation. Encoded process evidence additionally requires actual AST assignments, a SHA-256 comparison/throw guard, the protected invocation dictionary and the invocation itself; quoted lookalike text or an unused payload is insufficient.

Transactions use sibling work and journal directories on the same volume. A persistent journal describes Prepared, Promoted, Committed or RolledBack. Interrupted restoration only runs when the target is absent and the old copy is available with matching transaction ownership. Existing ambiguous target data is never overwritten automatically. Committed previous copies remain available; unknown files are never automatically pruned.

Start delegates to the precise official batch and leaves application-specific elevation and startup gates intact. VSO7's original use of process-scoped ExecutionPolicy flags belongs to that distribution; the manager adds no policy override to the application launch. Its separate pinned UAC bootstrap uses an explicit child-process Bypass argument without changing stored policy. The manager never calls VSO functions, Recovery runners, unblock scripts or downloaded maintenance scripts. There is no connection to the application's native mutation writer beyond launching the app at the user's request.

Future adapters must recognize an actual official distribution, validate its versioned contract, implement safe launcher and process evidence, define file ownership and compatible data handling, and add lab coverage. A declarative manifest cannot authorize a new launcher type or a destructive data path by itself. Cross-generation update is disabled until equivalence and migration are explicitly implemented.

The public module name is VSO. The VicoSafeOptimizer application product identifiers, VicoSafeOptimizer.Transaction journal product and VicoSafeOptimizer.Module\\Installations storage leaf remain unchanged compatibility contracts. They are not a second module name or alias. The rename must continue to discover existing receipts and validate their pinned hashes.
