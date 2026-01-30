-- =============================================================================
-- Script: fix_supplemental_logging.sql
-- Purpose: Enable supplemental logging on source database for ZDM migration
-- Database: PRODDB (ORADB01)
-- Target: temandin-oravm-vm01 (10.1.0.10)
-- 
-- Usage:
--   1. SSH to source server: ssh oracle@10.1.0.10
--   2. Connect as SYSDBA: sqlplus / as sysdba
--   3. Run this script: @fix_supplemental_logging.sql
-- =============================================================================

SET ECHO ON
SET FEEDBACK ON
SET LINESIZE 200
SET PAGESIZE 100

SPOOL fix_supplemental_logging_output.log

PROMPT ================================================================
PROMPT Step 1: Check current supplemental logging status (BEFORE)
PROMPT ================================================================

SELECT 
    'Minimal Logging: ' || SUPPLEMENTAL_LOG_DATA_MIN || 
    ', PK Logging: ' || SUPPLEMENTAL_LOG_DATA_PK ||
    ', UI Logging: ' || SUPPLEMENTAL_LOG_DATA_UI ||
    ', FK Logging: ' || SUPPLEMENTAL_LOG_DATA_FK ||
    ', All Logging: ' || SUPPLEMENTAL_LOG_DATA_ALL AS "Current Status"
FROM V$DATABASE;

PROMPT ================================================================
PROMPT Step 2: Enable minimal supplemental logging (REQUIRED for online migration)
PROMPT ================================================================

ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

PROMPT ================================================================
PROMPT Step 3: Enable primary key supplemental logging (RECOMMENDED)
PROMPT ================================================================

ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;

PROMPT ================================================================
PROMPT Step 4: Force log switch to capture changes
PROMPT ================================================================

ALTER SYSTEM SWITCH LOGFILE;

-- Wait a moment for log switch to complete
EXEC DBMS_LOCK.SLEEP(2);

PROMPT ================================================================
PROMPT Step 5: Verify supplemental logging status (AFTER)
PROMPT ================================================================

SELECT 
    'Minimal Logging: ' || SUPPLEMENTAL_LOG_DATA_MIN || 
    ', PK Logging: ' || SUPPLEMENTAL_LOG_DATA_PK AS "New Status"
FROM V$DATABASE;

-- Detailed verification
SELECT 
    SUPPLEMENTAL_LOG_DATA_MIN AS "Min Logging",
    SUPPLEMENTAL_LOG_DATA_PK AS "PK Logging",
    SUPPLEMENTAL_LOG_DATA_UI AS "UI Logging",
    SUPPLEMENTAL_LOG_DATA_FK AS "FK Logging",
    SUPPLEMENTAL_LOG_DATA_ALL AS "All Logging"
FROM V$DATABASE;

PROMPT ================================================================
PROMPT Verification Complete
PROMPT Expected: Min Logging = YES, PK Logging = YES
PROMPT ================================================================

SPOOL OFF

-- Display completion message
PROMPT
PROMPT ================================================================
PROMPT Script completed. Check fix_supplemental_logging_output.log
PROMPT If both values show YES, supplemental logging is configured correctly.
PROMPT ================================================================
PROMPT

EXIT;
