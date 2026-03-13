# Discovery Output: Source Database

Discovery output files from the source database server (`10.1.0.11`) are collected here by
`zdm_orchestrate_discovery.sh` after running `zdm_source_discovery.sh`.

## Expected Files

| File | Description |
|------|-------------|
| `zdm_source_discovery_<hostname>_<timestamp>.txt` | Full human-readable discovery report |
| `zdm_source_discovery_<hostname>_<timestamp>.json` | Machine-parseable JSON summary |

## Contents Covered

- OS information and disk space
- Oracle environment (ORACLE_HOME, ORACLE_SID, version)
- Database configuration (name, DBID, role, log mode, character set)
- CDB/PDB status
- TDE wallet configuration
- Supplemental logging status
- Redo log groups and archive destinations
- Network configuration (listener, tnsnames.ora, sqlnet.ora)
- Authentication (password file, SSH directory)
- Data Guard parameters
- Schema sizes and invalid objects
- Tablespace autoextend settings
- Backup configuration (RMAN, crontab, scheduler)
- Database links
- Materialized views and MV logs
- DBMS_SCHEDULER jobs
