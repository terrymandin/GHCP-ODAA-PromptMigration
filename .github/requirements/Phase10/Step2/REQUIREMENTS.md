# Step2 Requirements - Generate Discovery Scripts

## Objective

Generate read-only discovery tooling for source, target, and ZDM server assessment.

## S2-01: Output contract

Required generated files:

- `Artifacts/Phase10-Migration/Step2/Scripts/zdm_source_discovery.sh`
- `Artifacts/Phase10-Migration/Step2/Scripts/zdm_target_discovery.sh`
- `Artifacts/Phase10-Migration/Step2/Scripts/zdm_server_discovery.sh`
- `Artifacts/Phase10-Migration/Step2/Scripts/zdm_orchestrate_discovery.sh`
- `Artifacts/Phase10-Migration/Step2/Scripts/README.md`

Required placeholder directories:

- `Artifacts/Phase10-Migration/Step2/Discovery/source/`
- `Artifacts/Phase10-Migration/Step2/Discovery/target/`
- `Artifacts/Phase10-Migration/Step2/Discovery/server/`

## S2-02: Read-only enforcement

1. Generated scripts must be strictly read-only.
2. SQL must be `SELECT`-only with no DDL/DML.
3. No OS/service mutation commands are allowed.
4. Each discovery script must include a read-only banner comment.

## S2-03: Auth and user model

1. Source and target scripts SSH as admin users, then run SQL as `oracle` via `sudo -u oracle`.
2. ZDM server script runs locally as `zdmuser` and enforces a user guard.
3. `SOURCE_SSH_USER` and `TARGET_SSH_USER` map to generated `SOURCE_ADMIN_USER` and `TARGET_ADMIN_USER`.

## S2-04: Key normalization

1. Empty or placeholder key values must be treated as unset.
2. `-i` is included only when a normalized key path is non-empty.

## S2-05: Runtime behavior boundary

1. Prompt execution does not run discovery.
2. Discovery outputs are created only when scripts run on the jumpbox/ZDM server.

## S2-06: Discovery items generated (runtime output content)

Use this section as the editable source-of-truth list for discovery coverage. Add new items here first, then regenerate/update prompts and scripts.

### Source discovery

1. Connectivity and auth context: source host, SSH user, SSH key mode.
2. Remote system details: hostname, OS, kernel, uptime.
3. Oracle environment details:
	- `/etc/oratab` entries.
	- PMON SIDs detected.
	- Oracle home in use.
	- Oracle SID in use.
	- Database unique name (configured value).
	- `sqlplus` version.
4. Database configuration: name/unique name/role/open mode/character sets; archivelog/force/supplemental logging.
5. CDB/PDB posture: CDB status and PDB names/open modes.
6. TDE status: wallet type/location and encrypted tablespaces.
7. Tablespace/datafile posture: autoextend settings and current/max sizing.
8. Redo/archive posture: redo groups/sizes/members and archive destinations.
9. Network config: listener status, `tnsnames.ora`, `sqlnet.ora`.
10. Authentication artifacts: password file location and SSH directory contents.
11. Schema posture: non-system schema sizes and invalid object counts.
12. Backup posture: schedules/policies and most recent successful backup evidence.
13. Integration objects: database links, materialized views/logs, scheduler jobs that may require post-cutover updates.
14. Data Guard parameters/config evidence when applicable.

### Target discovery

1. Connectivity and auth context: target host, SSH user, SSH key mode.
2. Remote system details: hostname, OS, kernel, uptime.
3. Oracle environment details:
	- `/etc/oratab` entries.
	- PMON SIDs detected.
	- Oracle home in use.
	- Oracle SID in use.
	- Database unique name (configured value).
	- `sqlplus` version.
4. Database configuration: name/unique name/role/open mode/character set.
5. CDB/PDB posture: CDB status and PDB open mode(s), including pre-created migration PDB.
6. TDE wallet status/type.
7. Storage posture: ASM disk groups and free space (plus Exadata cell/grid disk details when available).
8. Network posture: listener status, SCAN status when applicable, and `tnsnames.ora`.
9. OCI/Azure integration metadata (sanitized profile/metadata only).
10. Grid infrastructure status when RAC/Exadata applies.
11. Network security checks relevant to SSH/listener ports.

### ZDM server discovery

1. Local system details: hostname, OS, kernel, uptime, current user.
2. ZDM installation details: `ZDM_HOME`, existence/permissions, `zdmcli` path, version evidence.
3. Capacity snapshot: disk and memory summary.
4. Java details: JAVA_HOME and Java version (prefer bundled JDK check first).
5. OCI authentication configuration: config location, profile metadata (masked), API key presence/permissions.
6. SSH/credential inventory in `zdmuser` home context.
7. Network context: IP/routing/DNS summaries.
8. Optional connectivity tests to source/target when env vars are provided (ping/port checks).
9. Endpoint traceability: source and target endpoint values used during discovery.

### Orchestration summary

1. Effective runtime configuration used for source and target values.
2. Per-script execution status (`PASS`/`FAIL`) and log file paths.
3. Overall Step2 discovery status.
4. Output format references produced by script runs (raw text, markdown report, JSON report).
