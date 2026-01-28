# Example: Completed Discovery Questionnaire for PRODDB Migration

This example demonstrates a fully completed Step 1 questionnaire for a production Oracle database migration to Oracle Database@Azure using online physical migration.

## Prerequisites

Before using this example:
- Run `Step0-Generate-Discovery-Scripts.prompt.md` to generate discovery scripts
- Execute scripts on all servers and collect outputs
- Have OCI/Azure console access for OCIDs

---

## Example Prompt

Copy and use this prompt with your completed questionnaire:

```
@Step1-Discovery-Questionnaire.prompt.md

I have completed the discovery questionnaire for our PRODDB migration.

## Attached Discovery Files
#file:C:\Migrations\PRODDB\Discovery\zdm_source_discovery_proddb01_20260128_140532.txt
#file:C:\Migrations\PRODDB\Discovery\zdm_source_discovery_proddb01_20260128_140532.json
#file:C:\Migrations\PRODDB\Discovery\zdm_target_discovery_proddb-oda_20260128_141022.txt
#file:C:\Migrations\PRODDB\Discovery\zdm_target_discovery_proddb-oda_20260128_141022.json
#file:C:\Migrations\PRODDB\Discovery\zdm_server_discovery_zdm-jumpbox_20260128_141545.txt
#file:C:\Migrations\PRODDB\Discovery\zdm_server_discovery_zdm-jumpbox_20260128_141545.json

## Completed Questionnaire

[See completed questionnaire below]
```

---

## Completed Questionnaire Example

### SECTION 1: Migration Strategy

#### 1.1 Migration Type (Required)
```
Migration Method: [X] ONLINE_PHYSICAL  [ ] OFFLINE_PHYSICAL

Justification: Production database requiring minimal downtime. Business can 
tolerate only 15 minutes of downtime during switchover window.
```

#### 1.2 Migration Timeline
```
Planned Migration Date: 2026-02-15
Maintenance Window Start: 02:00 AM PST
Maintenance Window End: 06:00 AM PST
Maximum Acceptable Downtime: 15 minutes
```

---

### SECTION 2: Source Database Information

#### 2.1 Database Identification 🔍
*Auto-populated from: zdm_source_discovery output*

```
Database Name (DB_NAME):        PRODDB
Database Unique Name:           PRODDB_PRIMARY
Database SID:                   PRODDB
Database ID (DBID):             2847563921
Database Version:               19.21.0.0.0
Database Role:                  PRIMARY
```

#### 2.2 Database Configuration 🔍
```
Database Size (GB):             2,450
Character Set:                  AL32UTF8
National Character Set:         AL16UTF16
Open Mode:                      READ WRITE
Log Mode:                       [X] ARCHIVELOG  [ ] NOARCHIVELOG
Force Logging:                  [X] YES  [ ] NO
```

#### 2.3 Container Database Information 🔍
```
Is CDB:                         [X] YES  [ ] NO
PDB Names (comma-separated):    PRODPDB1, PRODPDB2, PRODPDB3
```

#### 2.4 TDE Configuration 🔍
```
TDE Enabled:                    [X] YES  [ ] NO
TDE Wallet Type:                [X] FILE  [ ] HSM  [ ] OKV
TDE Wallet Location:            /u01/app/oracle/admin/PRODDB/wallet/tde
```

#### 2.5 TDE Credentials 🔐
```
TDE Wallet Password:            ********** (stored in /home/zdmuser/creds/tde_password.txt)
```

#### 2.6 Supplemental Logging 🔍
*Required for Online Migration*

```
Supplemental Log Data Min:      [X] YES  [ ] NO
Supplemental Log Data PK:       [X] YES  [ ] NO
Supplemental Log Data UI:       [X] YES  [ ] NO
```

#### 2.7 Source Host Information 🔍
```
Hostname:                       proddb01.corp.example.com
IP Address:                     10.100.50.25
Operating System:               Oracle Linux Server
OS Version:                     8.7
```

#### 2.8 Source Oracle Installation 🔍
```
Oracle Home Path:               /u01/app/oracle/product/19.21.0/dbhome_1
Oracle Base Path:               /u01/app/oracle
Oracle OS User:                 oracle
Oracle OS Group:                oinstall
Listener Port:                  1521
Service Name:                   PRODDB.corp.example.com
```

#### 2.9 Source Credentials 🔐
```
SYS Password:                   ********** (stored in /home/zdmuser/creds/source_sys_password.txt)
Password File Location:         /u01/app/oracle/product/19.21.0/dbhome_1/dbs/orapwPRODDB
```

---

### SECTION 3: Target Database Information (Oracle Database@Azure)

#### 3.1 Azure/OCI Identifiers (Required - from Azure/OCI Console)
```
OCI Tenancy OCID:               ocid1.tenancy.oc1..aaaaaaaabcdefghijklmnopqrstuvwxyz123456789
OCI User OCID:                  ocid1.user.oc1..aaaaaaaaxyz987654321abcdefghijklmnopqrstuv
OCI Compartment OCID:           ocid1.compartment.oc1..aaaaaaaacompabcdef123456789xyz
OCI Region:                     us-ashburn-1
Target DB System OCID:          ocid1.dbsystem.oc1.iad..aaaaaaaaproddbsystem12345
Target Database OCID:           ocid1.database.oc1.iad..aaaaaaaaproddbazure67890
```

#### 3.2 Database Identification 🔍
*Auto-populated from: zdm_target_discovery output*

```
Database Name (DB_NAME):        PRODDB
Database Unique Name:           PRODDB_AZURE
Database Version:               19.21.0.0.0
```

#### 3.3 Target Host Information 🔍
```
Hostname:                       proddb-oda.eastus.azure.example.com
IP Address:                     10.200.100.50
SCAN Name (if RAC):             proddb-scan.eastus.azure.example.com
Operating System:               Oracle Linux Server 8.8
```

#### 3.4 Target Oracle Installation 🔍
```
Oracle Home Path:               /u02/app/oracle/product/19.0.0.0/dbhome_1
Oracle Base Path:               /u02/app/oracle
Oracle OS User:                 oracle
Listener Port:                  1521
Service Name:                   PRODDB_AZURE.eastus.azure.example.com
```

#### 3.5 Target Credentials 🔐
```
SYS Password:                   ********** (stored in /home/zdmuser/creds/target_sys_password.txt)
```

---

### SECTION 4: ZDM Server Information

#### 4.1 ZDM Host Information 🔍
*Auto-populated from: zdm_server_discovery output*

```
Hostname:                       zdm-jumpbox.corp.example.com
IP Address:                     10.100.50.100
Operating System:               Oracle Linux Server 8.6
```

#### 4.2 ZDM Installation 🔍
```
ZDM Home Path:                  /opt/oracle/zdm21c
ZDM Version:                    21.4.0.0.0
ZDM Service Status:             [X] Running  [ ] Stopped
ZDM OS User:                    zdmuser
ZDM OS Group:                   zdmgroup
```

#### 4.3 OCI CLI Configuration 🔍
```
OCI CLI Installed:              [X] YES  [ ] NO
OCI CLI Version:                3.37.0
OCI Config Path:                /home/zdmuser/.oci/config
OCI Private Key Path:           /home/zdmuser/.oci/oci_api_key.pem
API Key Fingerprint:            aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
```

#### 4.4 SSH Configuration
```
SSH Private Key Path:           /home/zdmuser/.ssh/zdm_migration_key
SSH Public Key Path:            /home/zdmuser/.ssh/zdm_migration_key.pub
```

---

### SECTION 5: Network Configuration

#### 5.1 Connectivity Matrix
*Test each connection and record results*

| From | To | Port | Protocol | Status |
|------|-----|------|----------|--------|
| ZDM Server | Source DB | 22 | SSH | [X] OK [ ] FAIL |
| ZDM Server | Source DB | 1521 | Oracle | [X] OK [ ] FAIL |
| ZDM Server | Target DB | 22 | SSH | [X] OK [ ] FAIL |
| ZDM Server | Target DB | 1521 | Oracle | [X] OK [ ] FAIL |
| ZDM Server | OCI OSS | 443 | HTTPS | [X] OK [ ] FAIL |
| Source DB | Target DB | 1521 | Oracle | [X] OK [ ] FAIL |

#### 5.2 Network Path
```
ExpressRoute/VPN Configured:    [X] YES  [ ] NO
Network Path Description:       Azure ExpressRoute with 1Gbps dedicated circuit
Estimated Bandwidth (Mbps):     1000
```

---

### SECTION 6: Backup and Storage Configuration

#### 6.1 Object Storage Settings
```
Object Storage Namespace:       examplecorp
Bucket Name:                    zdm-proddb-migration
Bucket Region:                  us-ashburn-1
Bucket Already Exists:          [X] YES  [ ] NO
```

#### 6.2 RMAN Settings
```
Parallel Channels:              8 (optimized for 1Gbps network)
Compression Level:              [ ] LOW  [X] MEDIUM  [ ] HIGH
Encryption Algorithm:           [ ] AES128  [ ] AES192  [X] AES256
```

#### 6.3 Backup Location
```
Backup Method:                  [X] Object Storage  [ ] NFS  [ ] Local
NFS Mount Path (if NFS):        N/A
Local Path (if Local):          N/A
```

---

### SECTION 7: Migration Options

#### 7.1 Data Guard Configuration (Online Migration Only)
```
Protection Mode:                [X] MAXIMUM_PERFORMANCE  [ ] MAXIMUM_AVAILABILITY
Transport Type:                 [X] ASYNC  [ ] SYNC
```

#### 7.2 Post-Migration Actions
```
Auto Switchover:                [ ] YES  [X] NO  (manual switchover for controlled cutover)
Delete Backup After Migration:  [ ] YES  [X] NO  (retain for 7 days post-migration)
Include Performance Data:       [X] YES  [ ] NO
```

#### 7.3 Pause Points
```
Pause After Phase:              [X] ZDM_CONFIGURE_DG_SRC
                                [ ] ZDM_SWITCHOVER_SRC
                                [ ] None (run to completion)
```

---

### SECTION 8: Validation Checklist

#### 8.1 Pre-requisites Verification

| Requirement | Status | Notes |
|-------------|--------|-------|
| Source DB in ARCHIVELOG mode | [X] | Verified via discovery |
| Force Logging enabled | [X] | Verified via discovery |
| Supplemental Logging enabled | [X] | MIN, PK, UI enabled |
| TDE wallet accessible | [X] | Wallet open and auto-login configured |
| SSH keys configured | [X] | Keys deployed to all servers |
| OCI CLI working | [X] | Tested with oci iam region list |
| Network connectivity verified | [X] | All ports tested successfully |
| Sufficient OSS storage | [X] | 5TB available in bucket |
| ZDM service running | [X] | Service status verified |

---

### SECTION 9: Additional Notes

```
Special Considerations:
- Database has 3 PDBs with different SLA requirements
- PRODPDB1 contains financial data - extra validation required
- Application team needs 2-hour notice before switchover
- Rollback window: 4 hours post-switchover

Known Issues or Constraints:
- Source server maintenance every Sunday 3-5 AM - avoid migration during this window
- Target database time zone set to UTC (source is PST) - application team aware

Rollback Plan:
- Before switchover: Abort ZDM job, no data loss, source remains primary
- After switchover: Reinstate source as primary using Data Guard switchover
- RPO: Zero (synchronous shipping before switchover)
- RTO: 30 minutes for rollback procedure
```

---

### SECTION 10: Questionnaire Completion

```
Completed By:                   John Smith (DBA Team Lead)
Completion Date:                2026-01-28
Reviewed By:                    Sarah Johnson (Database Architect)
Review Date:                    2026-01-29
```

---

## Next Steps

With this completed questionnaire:

1. **Save the questionnaire** - Keep for audit and documentation
2. **Run Step 2 prompt** with:
   ```
   @Step2-Generate-Migration-Artifacts.prompt.md
   
   Generate migration artifacts for PRODDB using the completed questionnaire above.
   
   Output Directory: C:\Migrations\PRODDB\
   ```
3. **Review generated artifacts** before execution
4. **Create password files** in `/home/zdmuser/creds/` as referenced

---

## Tips for Completing Your Questionnaire

1. **Discovery outputs are your friend** - Most 🔍 fields come directly from scripts
2. **Double-check OCIDs** - Copy directly from Azure/OCI console to avoid typos
3. **Test network connectivity** - Run nc/telnet tests for all port combinations
4. **Secure credentials** - Never embed passwords; always use file references
5. **Document everything** - The "Additional Notes" section is crucial for troubleshooting
