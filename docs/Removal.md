# Removal ownership and recovery limits

Reset removes application files; it never reverses Windows tweaks or invokes VSO Recovery. An exact `Reset-VSO -Path $install -Full -WhatIf -PassThru` plan contains Remove records with hashes/ownership/roles, candidate Directories, backward-compatible Preserve paths and Protected records with Path, Reason, Ownership and Exists. Preview creates no lock, staging directory, metadata or UAC request. Interactive execution displays that plan before confirmation, including with Force. Quiet automation can inspect the structured preview.

| Mode | Eligible data |
|---|---|
| Normal reset | Unchanged receipt-owned Application files and current registration/receipt |
| Full | Normal data plus unchanged declared Configuration, Cache, Log and Temporary files; attributable committed transaction metadata when no surviving backup depends on it |
| Full + RemoveBackups + AcknowledgeBackupLoss | Also unchanged attributable previous application copies, only with receipt-bound journal and prior-receipt SHA-256 pins |

Force suppresses prompting; it never implies backup-loss acknowledgement or bypasses checks. Packaged Recovery roles and VSO7/Recuperacion backup paths remain protected. Shared ProgramData Recovery/runtime material, foreign files, changed bytes, untracked configuration/logs, unknown empty directories and the installed manager module remain outside automatic cleanup. The result therefore reports CompleteCleanup false whenever a protected path remains, including the conservative shared-data entry even if Exists is false.

| Protected reason | Meaning |
|---|---|
| UntrackedOwnership / UntrackedEmptyDirectory | No installation receipt proves ownership |
| ModifiedSinceInstall | Bytes differ from the recorded installation |
| PersistentDataNormalReset | Declared data requires Full |
| RecoveryRequiresSeparateOwnership | Recovery is deliberately excluded from this adapter |
| BackupLossNotAcknowledged | Previous copy retained without explicit backup-loss intent |
| TransactionJournalNotPinned / BackupReceiptNotPinned | Legacy or incomplete metadata does not authenticate removal ownership |
| MissingBackupReceipt / TransactionNotBoundToReceipt | No usable receipt or current installation binding |
| UntrackedModifiedOrRecoveryBackup / UntrackedTransactionData | Unknown, modified or recovery data survives in the transaction tree |
| PreservedBackupProvenance / PreservedTransactionProvenance | Metadata kept to explain surviving backup data |
| SharedRecoveryAndRuntimeData | Shared/historical application state cannot be assigned to this installation |

Under the destination lock, removal revalidates protected-directory ACLs, idle state, all file hashes and native READ/DELETE access. Read-only files and denied DELETE access for directories expected to become empty fail before the first deletion. Handles deny write/replacement during preflight. The writer rechecks each path/hash immediately before deleting and verifies absence afterward. Empty directories are pruned without recursion; unknown children keep their parent intact.

Removal is not an atomic filesystem transaction. Its receipt is deleted last so an interruption after some application files were deleted can be replanned and retried by Path. It does not reconstruct deleted files. External drift, access changes, linked components or concurrent operations can still produce a safe partial result/error. Inspect diagnostics and retained metadata instead of forcing unknown data deletion. Receipt pins rely on the same trust boundary as registration: Windows ACLs, not an independent author signature against the owning user or an administrator.
