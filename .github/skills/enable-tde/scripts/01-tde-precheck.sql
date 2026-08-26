WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE
SET ECHO OFF FEEDBACK ON HEADING ON PAGESIZE 100 LINESIZE 220 VERIFY OFF

PROMPT TDE_STAGE=PRECHECK
SELECT banner_full AS database_version
FROM v$version
WHERE banner_full LIKE 'Oracle Database%';

SELECT cdb AS database_architecture FROM v$database;
SHOW PARAMETER wallet_root
SHOW PARAMETER tde_configuration

SELECT con_id, status, wallet_type, keystore_mode
FROM v$encryption_wallet
ORDER BY con_id;

SELECT con_id, COUNT(*) AS master_key_count
FROM v$encryption_keys
GROUP BY con_id
ORDER BY con_id;

{{CONTAINER_PRECHECK_COMMANDS}}

PROMPT TDE_RESULT=PRECHECK_COMPLETE
EXIT SUCCESS
