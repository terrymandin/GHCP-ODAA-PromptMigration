# ZDM Environment Variables

Optional environment variable overrides for ZDM discovery scripts.
Reference this file in your prompt with `@zdm-env.md` if you need to override auto-detection.

## Usage

These values are only needed if auto-detection fails. The scripts will attempt to discover these automatically by:
- Checking /etc/oratab for Oracle homes and SIDs
- Searching common installation paths
- Checking running processes
- Examining user environment files

If auto-detection works for your environment, you don't need to set these.

---

## ZDM Server Environment
- ZDM_REMOTE_ZDM_HOME: /home/zdmuser/zdmhome
- ZDM_REMOTE_JAVA_HOME: /usr/java/jdk1.8.0_391

## Source Database Environment
- SOURCE_REMOTE_ORACLE_HOME: /u01/app/oracle/product/19.0.0.0/dbhome_1
- SOURCE_REMOTE_ORACLE_SID: PRODDB

## Target Database Environment
- TARGET_REMOTE_ORACLE_HOME: /u01/app/oracle/product/19.0.0.0/dbhome_1
- TARGET_REMOTE_ORACLE_SID: PRODDB
