# ZDM Migration Step 1: Discovery and Questionnaire

## Purpose
This prompt guides the discovery phase of a Zero Downtime Migration (ZDM) from on-premise Oracle databases to Oracle Database@Azure. After running discovery scripts from Step 0, complete this questionnaire with gathered information.

---

## Prerequisites

Before completing this questionnaire:
1. Run `Step0-Generate-Discovery-Scripts.prompt.md` to generate fresh discovery scripts
2. Execute discovery scripts on all servers
3. Check in the output files to the repository under the appropriate database folder

---

## How to Use This Prompt

When running this prompt, attach the discovery files from Step0 using the `#file:` syntax:

```
@Step1-Discovery-Questionnaire.prompt.md

I have completed the discovery questionnaire for our <DATABASE> migration.

## Attached Discovery Files

### Source Database Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/source/zdm_source_discovery_<hostname>_<timestamp>.json

### Target Database Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/target/zdm_target_discovery_<hostname>_<timestamp>.json

### ZDM Server Discovery (from Step0)
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.txt
#file:Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/server/zdm_server_discovery_<hostname>_<timestamp>.json

## Completed Questionnaire

[Paste your completed questionnaire here]
```

**Note:** Replace `<DATABASE>`, `<hostname>`, and `<timestamp>` with actual values. Use the most recent discovery files (highest timestamp).

---

## Instructions

### Phase 1A: Discovery Output Files

The discovery output files from Step 0 should be checked into the repository at:

```
Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/
├── source/
│   ├── zdm_source_discovery_<hostname>_<timestamp>.txt
│   └── zdm_source_discovery_<hostname>_<timestamp>.json
├── target/
│   ├── zdm_target_discovery_<hostname>_<timestamp>.txt
│   └── zdm_target_discovery_<hostname>_<timestamp>.json
└── server/
    ├── zdm_server_discovery_<hostname>_<timestamp>.txt
    └── zdm_server_discovery_<hostname>_<timestamp>.json
```

**Note:** Replace `<DATABASE>` with your database name (e.g., PRODDB). Use the most recent discovery files based on timestamp.

### Phase 1B: Complete Questionnaire

Fill in all fields below. Fields marked with 🔍 can be auto-populated from discovery scripts. Fields marked with 🔐 require manual entry (credentials).

---

## SECTION 1: Migration Strategy

### 1.1 Migration Type (Required)
```
Migration Method: [ ] ONLINE_PHYSICAL  [ ] OFFLINE_PHYSICAL

Justification: ________________________________________________
```

| Decision Factor | Online Physical | Offline Physical |
|----------------|-----------------|------------------|
| Downtime Tolerance | Minimal (minutes) | Extended (hours) |
| Data Guard Required | Yes | No |
| Complexity | Higher | Lower |
| Network Requirements | Sustained connectivity | Backup transfer only |

### 1.2 Migration Timeline
```
Planned Migration Date: ____________________
Maintenance Window Start: __________________
Maintenance Window End: ____________________
Maximum Acceptable Downtime: ________________
```

---

## SECTION 2: Source Database Information

### 2.1 Database Identification 🔍
*Auto-populated from: zdm_source_discovery.sh*

```
Database Name (DB_NAME):        ____________________
Database Unique Name:           ____________________
Database SID:                   ____________________
Database ID (DBID):             ____________________
Database Version:               ____________________
Database Role:                  ____________________
```

### 2.2 Database Configuration 🔍
*Auto-populated from: zdm_source_discovery.sh*

```
Database Size (GB):             ____________________
Character Set:                  ____________________
National Character Set:         ____________________
Open Mode:                      ____________________
Log Mode:                       [ ] ARCHIVELOG  [ ] NOARCHIVELOG
Force Logging:                  [ ] YES  [ ] NO
```

### 2.3 Container Database Information 🔍
```
Is CDB:                         [ ] YES  [ ] NO
PDB Names (comma-separated):    ____________________
```

### 2.4 TDE Configuration 🔍
```
TDE Enabled:                    [ ] YES  [ ] NO
TDE Wallet Type:                [ ] FILE  [ ] HSM  [ ] OKV
TDE Wallet Location:            ____________________
```

**Note:** TDE wallet password should be set via the `SOURCE_TDE_WALLET_PASSWORD` environment variable at migration runtime. See Step0 for password environment variable configuration. Never commit passwords to source control.

### 2.5 Supplemental Logging 🔍
*Required for Online Migration*

```
Supplemental Log Data Min:      [ ] YES  [ ] NO
Supplemental Log Data PK:       [ ] YES  [ ] NO
Supplemental Log Data UI:       [ ] YES  [ ] NO
```

### 2.6 Source Host Information 🔍
```
Hostname:                       ____________________
IP Address:                     ____________________
Operating System:               ____________________
OS Version:                     ____________________
```

### 2.7 Source Oracle Installation 🔍
```
Oracle Home Path:               ____________________
Oracle Base Path:               ____________________
Oracle OS User:                 ____________________
Oracle OS Group:                ____________________
Listener Port:                  ____________________
Service Name:                   ____________________
```

### 2.8 Source Credentials
```
Password File Location:         ____________________
```

**Security Note:** The SYS password should be set via the `SOURCE_SYS_PASSWORD` environment variable at migration runtime. Password environment variables are defined in Step0. Never commit passwords to GitHub or any source control system.

---

## SECTION 3: Target Database Information (Oracle Database@Azure)

### 3.1 Azure/OCI Identifiers (Required)
```
OCI Tenancy OCID:               ____________________
OCI User OCID:                  ____________________
OCI Compartment OCID:           ____________________
OCI Region:                     ____________________
Target DB System OCID:          ____________________
Target Database OCID:           ____________________
```

### 3.2 Database Identification 🔍
*Auto-populated from: zdm_target_discovery.sh*

```
Database Name (DB_NAME):        ____________________
Database Unique Name:           ____________________
Database Version:               ____________________
```

### 3.3 Target Host Information 🔍
```
Hostname:                       ____________________
IP Address:                     ____________________
SCAN Name (if RAC):             ____________________
Operating System:               ____________________
```

### 3.4 Target Oracle Installation 🔍
```
Oracle Home Path:               ____________________
Oracle Base Path:               ____________________
Oracle OS User:                 ____________________
Listener Port:                  ____________________
Service Name:                   ____________________
```

### 3.5 Target Credentials

**Security Note:** The target SYS password should be set via the `TARGET_SYS_PASSWORD` environment variable at migration runtime. Password environment variables are defined in Step0. Never commit passwords to GitHub or any source control system.

---

## SECTION 4: ZDM Server Information

### 4.1 ZDM Host Information 🔍
*Auto-populated from: zdm_server_discovery.sh*

```
Hostname:                       ____________________
IP Address:                     ____________________
Operating System:               ____________________
```

### 4.2 ZDM Installation 🔍
```
ZDM Home Path:                  ____________________
ZDM Version:                    ____________________
ZDM Service Status:             [ ] Running  [ ] Stopped
ZDM OS User:                    ____________________
ZDM OS Group:                   ____________________
```

### 4.3 OCI CLI Configuration 🔍
```
OCI CLI Installed:              [ ] YES  [ ] NO
OCI CLI Version:                ____________________
OCI Config Path:                ____________________
OCI Private Key Path:           ____________________
API Key Fingerprint:            ____________________
```

### 4.4 SSH Configuration
```
SSH Private Key Path:           ____________________
SSH Public Key Path:            ____________________
```

---

## SECTION 5: Network Configuration

### 5.1 Connectivity Matrix
*Test each connection and record results*

| From | To | Port | Protocol | Status |
|------|-----|------|----------|--------|
| ZDM Server | Source DB | 22 | SSH | [ ] OK [ ] FAIL |
| ZDM Server | Source DB | 1521 | Oracle | [ ] OK [ ] FAIL |
| ZDM Server | Target DB | 22 | SSH | [ ] OK [ ] FAIL |
| ZDM Server | Target DB | 1521 | Oracle | [ ] OK [ ] FAIL |
| ZDM Server | OCI OSS | 443 | HTTPS | [ ] OK [ ] FAIL |
| Source DB | Target DB | 1521 | Oracle | [ ] OK [ ] FAIL |

### 5.2 Network Path
```
ExpressRoute/VPN Configured:    [ ] YES  [ ] NO
Network Path Description:       ____________________
Estimated Bandwidth (Mbps):     ____________________
```

---

## SECTION 6: Backup and Storage Configuration

### 6.1 Object Storage Settings
```
Object Storage Namespace:       ____________________
Bucket Name:                    ____________________
Bucket Region:                  ____________________
Bucket Already Exists:          [ ] YES  [ ] NO
```

### 6.2 RMAN Settings
```
Parallel Channels:              ____________________ (default: 4)
Compression Level:              [ ] LOW  [ ] MEDIUM  [ ] HIGH
Encryption Algorithm:           [ ] AES128  [ ] AES192  [ ] AES256
```

### 6.3 Backup Location
```
Backup Method:                  [ ] Object Storage  [ ] NFS  [ ] Local
NFS Mount Path (if NFS):        ____________________
Local Path (if Local):          ____________________
```

---

## SECTION 7: Migration Options

### 7.1 Data Guard Configuration (Online Migration Only)
```
Protection Mode:                [ ] MAXIMUM_PERFORMANCE  [ ] MAXIMUM_AVAILABILITY
Transport Type:                 [ ] ASYNC  [ ] SYNC
```

### 7.2 Post-Migration Actions
```
Auto Switchover:                [ ] YES  [ ] NO
Delete Backup After Migration:  [ ] YES  [ ] NO
Include Performance Data:       [ ] YES  [ ] NO
```

### 7.3 Pause Points
```
Pause After Phase:              [ ] ZDM_CONFIGURE_DG_SRC
                                [ ] ZDM_SWITCHOVER_SRC
                                [ ] None (run to completion)
```

---

## SECTION 8: Validation Checklist

### 8.1 Pre-requisites Verification

| Requirement | Status | Notes |
|-------------|--------|-------|
| Source DB in ARCHIVELOG mode | [ ] | |
| Force Logging enabled | [ ] | |
| Supplemental Logging enabled | [ ] | |
| TDE wallet accessible | [ ] | |
| SSH keys configured | [ ] | |
| OCI CLI working | [ ] | |
| Network connectivity verified | [ ] | |
| Sufficient OSS storage | [ ] | |
| ZDM service running | [ ] | |

### 8.2 Discovery Files Attached

**Important:** When running this prompt, attach the discovery files from Step0 using the `#file:` syntax:

```
[ ] source/zdm_source_discovery_<hostname>_<timestamp>.txt attached
[ ] source/zdm_source_discovery_<hostname>_<timestamp>.json attached
[ ] target/zdm_target_discovery_<hostname>_<timestamp>.txt attached  
[ ] target/zdm_target_discovery_<hostname>_<timestamp>.json attached
[ ] server/zdm_server_discovery_<hostname>_<timestamp>.txt attached
[ ] server/zdm_server_discovery_<hostname>_<timestamp>.json attached
```

**File Location:** `Artifacts/Phase10-Migration/ZDM/<DATABASE>/Step0/Discovery/`

---

## SECTION 9: Additional Notes

```
Special Considerations:
________________________________________________________________
________________________________________________________________

Known Issues or Constraints:
________________________________________________________________
________________________________________________________________

Rollback Plan:
________________________________________________________________
________________________________________________________________
```

---

## Output Location

Save the completed questionnaire to: `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step1/`

**Filename:** `Completed-Questionnaire-<DB_NAME>.md`

---

## Next Steps

After completing this questionnaire:

1. **Save this file** to `Artifacts/Phase10-Migration/ZDM/<DB_NAME>/Step1/Completed-Questionnaire-<DB_NAME>.md`
2. **Attach discovery script outputs** from `Step0/Discovery/`
3. **Run Step 2 prompt**: `Step2-Generate-Migration-Artifacts.prompt.md`
   - This will generate the RSP file, ZDM CLI commands, and installation runbook to `Step2/`

---

## Questionnaire Completion Metadata

```
Completed By:                   ____________________
Completion Date:                ____________________
Reviewed By:                    ____________________
Review Date:                    ____________________
```
