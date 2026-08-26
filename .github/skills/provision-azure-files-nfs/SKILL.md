---
name: provision-azure-files-nfs
description: "Provision or validate an Azure Files NFS share for Oracle ZDM staging. Use when the selected migration transfer medium is NFS and shared storage must be created or verified."
---

# Provision Azure Files NFS

Use this skill only when `migration.transfer.medium` is `nfs`. Skip it for
`direct`, `oss`, and every other transfer medium, regardless of whether the
migration mode is online or offline.

## Supported Scope

- Standalone NFS shares created with `Microsoft.FileShares`.
- Private endpoint and private DNS access.
- Oracle Linux source and target database hosts using NFSv4.1.
- Customer-run Azure CLI, package installation, mount, and verification commands.

Classic `Microsoft.Storage` shares, service endpoints, SMB, Windows clients, and
agent-executed provisioning are outside this skill's scope.

## Invocation

1. If `migration.transfer.medium` is not `nfs`, return `skipped` without asking
   storage questions or presenting commands.
2. Read `migration.transfer.nfs.action`:
   - `create_azure_files`: guide provisioning and validation.
   - `use_existing`: skip provisioning and validate the existing NFS share.
3. Never infer the need for NFS from physical migration or offline mode alone.

## Procedure

1. Validate the non-secret inputs and require the same absolute `backup_path` for
   the source and target database hosts.
2. Before Azure resource creation, explain cost and network effects and obtain
   explicit customer approval. The customer runs every Azure command.
3. For `create_azure_files`, render the customer-run provisioning asset, then
   pause for sanitized evidence that the share, private endpoint, and private DNS
   are ready. Stop on an existing resource conflict; never replace or delete it.
   Use [01-provision-share.sh](./scripts/01-provision-share.sh).
4. Before package installation, mounting, or `/etc/fstab` changes, explain the
   host impact and obtain separate customer approval.
5. Render the customer-run mount asset for both database hosts. The NFS share is
   not required on the ZDM service host, and a ZDM-host mount is not pass evidence.
   Use [02-mount-and-verify.sh](./scripts/02-mount-and-verify.sh).
6. Require observed NFSv4.1 mounts at the same path, source database-user `rwx`,
   target database-user read access, sufficient capacity, and a temporary marker
   created by the source and read by the target.
7. Persist only the allowlisted result fields below. Raw Azure, DNS, mount, and
   filesystem output is transient.

## Approval And Secret Rules

- Never execute Azure, package-management, mount, or filesystem mutation commands.
- Never request or persist account keys, SAS tokens, access tokens, credentials,
  connection strings, subscription or tenant IDs, private IPs, or raw output.
- Never enable unrestricted public NFS access.
- Never overwrite or delete an existing Azure resource.

## Result Contract

Return `nfs_storage` with:

- `status`: `pass`, `fail`, `needs-review`, or `skipped`;
- `action`: `none`, `customer-execution-required`, or `storage-review-required`;
- `evidence`: provider model, NFS version, private endpoint/DNS readiness,
  same-path mount, source permissions, target read access, marker visibility,
  capacity result, persistence result, and approval booleans only;
- `findings`: sanitized blockers and warnings;
- `remediation`: the next customer-owned action.

Return `pass` only after observed source-and-target evidence satisfies every mount,
permission, marker, and capacity requirement. Route DNS or network failures to
`validate-network` and SSH execution failures to `validate-ssh`.