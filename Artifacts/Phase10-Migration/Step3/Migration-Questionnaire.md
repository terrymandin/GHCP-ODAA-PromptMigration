# Step 3 Migration Planning Questionnaire

Generated: 2026-03-17
Scope: Source (`POCAKV`) to Target (`POCAKV_ODAA`) with ZDM orchestration

## Instructions

- Review each section with DBA, infrastructure, network, security, and application owners.
- Replace `[TBD]` with agreed values.
- Mark each item as `Done`, `N/A`, or keep as `Open`.

## 1) Project Scope and Success Criteria

1. Migration objective (refresh, DR setup, switchover, one-time cutover): `[TBD]`
2. Planned migration method/pattern in ZDM: `[TBD]`
3. Downtime budget (minutes/hours): `[TBD]`
4. Data loss tolerance (RPO): `[TBD]`
5. Performance acceptance criteria post-cutover: `[TBD]`
6. Business go/no-go decision owner: `[TBD]`

## 2) Source and Target Database Readiness

1. Confirm source DB unique name is `POCAKV`: `Done` (discovery)
2. Confirm target DB unique name is `POCAKV_ODAA`: `Done` (discovery)
3. Confirm source SID/oracle home pinning (`POCAKV`, `/u01/app/oracle/product/19.0.0/dbhome_1`): `Done`
4. Confirm target SID/oracle home pinning (`POCAKV1`, `/u02/app/oracle/product/19.0.0.0/dbhome_1`): `Done`
5. Confirm exact Oracle DB patch levels on source and target (not captured in Step2): `[Open]`
6. Confirm archive log mode and force logging requirements: `[TBD]`
7. Confirm character set and national character set compatibility: `[TBD]`
8. Confirm timezone file version alignment strategy: `[TBD]`

## 3) RAC / Multi-Instance and Instance Selection Controls

1. Target host shows multiple PMON processes (`POCAKV1`, `+ASM1`, `+APX1`, `CDBAKV21`, `DB02251`). Confirm migration must target instance `POCAKV1`: `[TBD]`
2. Confirm all scripts/runbooks use explicit `TARGET_ORACLE_SID=POCAKV1` and do not rely on auto-detection: `[TBD]`
3. Confirm Node 1 instance mapping for all operations requiring local SID context: `[TBD]`

## 4) ZDM Server and Tooling Readiness

1. Confirm ZDM home path `/mnt/app/zdmhome` is correct and stable: `Done`
2. Confirm `zdmuser` has required sudo/OS privileges for all runbooks: `[TBD]`
3. Capture ZDM release/build with supported command (Step2 command returned invalid): `[Open]`
4. Validate free disk growth margin on ZDM host for logs/temp beyond current `1.2G` root free: `[Open]`
5. Confirm outbound/inbound connectivity from ZDM to source and target for all required ports: `[TBD]`

## 5) SSH and Security Configuration

1. Decide authentication mode for automation:
   - Agent/default keys (current discovery mode): `[TBD]`
   - Explicit key files in `zdm-env.md`: `[TBD]`
2. If explicit keys are chosen, provide final paths under `/home/zdmuser/.ssh/`: `[TBD]`
3. Verify key permissions (`600`) and ownership (`zdmuser`): `[TBD]`
4. Confirm firewall/NSG rules for SSH and Oracle network paths: `[TBD]`
5. Confirm credential rotation/secret handling procedure during migration window: `[TBD]`

## 6) Network, DNS, and Connectivity

1. Confirm name resolution strategy (IP vs FQDN) for source/target/ZDM: `[TBD]`
2. Confirm latency/bandwidth is sufficient for migration timeline: `[TBD]`
3. Confirm any jump host/proxy requirements for SSH or DB traffic: `[TBD]`
4. Confirm listener/service names and connect strings for precheck and cutover: `[TBD]`

## 7) Backup, Recovery, and Rollback

1. Confirm latest valid source backup and recovery test date: `[TBD]`
2. Define rollback trigger points and decision authority: `[TBD]`
3. Document rollback procedure and estimated rollback duration: `[TBD]`
4. Confirm flashback/restore point strategy (if used): `[TBD]`

## 8) Application and Cutover Planning

1. Identify all dependent applications/services using source DB: `[TBD]`
2. Confirm application freeze window and write-stop plan: `[TBD]`
3. Confirm connection string/service endpoint update method: `[TBD]`
4. Define cutover rehearsal plan and date: `[TBD]`
5. Define smoke tests and business validation checklist after cutover: `[TBD]`

## 9) Compliance, Audit, and Change Control

1. Change request/approval ID(s): `[TBD]`
2. Required audit evidence artifacts and storage location: `[TBD]`
3. Stakeholder communications plan (pre/during/post cutover): `[TBD]`
4. On-call escalation matrix and contact list: `[TBD]`

## 10) Open Items from Discovery (Action List)

1. Capture and record source/target `sqlplus`/database version evidence.
2. Capture and record ZDM version/build using a supported command.
3. Resolve SSH key strategy and update `zdm-env.md` if explicit keys are required.
4. Validate ZDM host disk headroom for migration runtime artifacts.
5. Confirm explicit target SID pinning (`POCAKV1`) across all subsequent scripts.

## 11) Sign-Off

1. DBA lead sign-off: `[Name / Date / Status]`
2. Infrastructure lead sign-off: `[Name / Date / Status]`
3. Application owner sign-off: `[Name / Date / Status]`
4. Migration manager sign-off: `[Name / Date / Status]`
