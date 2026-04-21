# ZDM Prerequisites — Pre-loaded Check Catalogs

## Purpose

This directory contains pre-loaded ZDM prerequisite check catalogs, organized by ZDM version. These files replace the runtime `fetch_webpage` approach that was previously used by CR-14.

The catalogs are extracted from the Oracle ZDM documentation and stored here so that:
- Migration steps (Steps 3–6) can read checks directly without web fetches.
- There are no repeated approval prompts during a migration session.
- The content is version-controlled and auditable.

## Directory Structure

```
ZDM-Prerequisites/
  README.md                               ← this file
  26.1/
    online-physical.md                    ← Layer 0/1/2 checks for ONLINE_PHYSICAL
    offline-physical.md                   ← Layer 0/1/2 checks for OFFLINE_PHYSICAL
```

## Versioning

Each subdirectory is named after the ZDM version string returned by `$ZDM_HOME/bin/zdmcli -version` (e.g., `26.1`). Steps should select the catalog matching the discovered ZDM version.

**Default version**: `26.1` — used when the discovered version has no matching directory.

## Oracle Documentation Source

Oracle publishes the ZDM 26.x release family under a single documentation set. The current published URL is:

```
https://docs.oracle.com/en/database/oracle/zero-downtime-migration/26.1/zdmug/preparing-for-database-migration.html
```

The content in the `26.1/` catalogs was extracted from this page on **2026-04-21**.

## Updating Prerequisites

When ZDM is upgraded to a new major version or Oracle updates the documentation:

1. Run the `@Phase10-Update-ZDM-Prerequisites` prompt (to be created).
2. The prompt fetches the relevant doc URLs, extracts checks, and writes a new versioned directory.
3. Commit the new directory to git so all users get the update.

## Format

Each catalog file uses the CR-14-C format from `COMMON-REQUIREMENTS.md`. Copilot steps consume these files directly using read_file and do not require `fetch_webpage`.
