# Step 2 Remediation Scripts

This folder contains scripts to fix issues identified during the PRODDB discovery phase.

## Scripts

| Script | Purpose | Run On |
|--------|---------|--------|
| `fix_supplemental_logging.sql` | Enable supplemental logging on source database | Source DB Server |
| `install_oci_cli.sh` | Install OCI CLI on ZDM server | ZDM Server |
| `configure_ssh_keys.sh` | Configure SSH key authentication | ZDM Server |
| `verify_fixes.sh` | Verify all fixes have been applied | ZDM Server |

## Execution Order

1. **fix_supplemental_logging.sql** - Run on source database first
2. **install_oci_cli.sh** - Run on ZDM server
3. **configure_ssh_keys.sh** - Run on ZDM server
4. **verify_fixes.sh** - Run to confirm all issues resolved

## Usage

### 1. Fix Supplemental Logging (Source Database)

```bash
# SSH to source server
ssh oracle@10.1.0.10

# Run the SQL script
sqlplus / as sysdba @fix_supplemental_logging.sql
```

### 2. Install OCI CLI (ZDM Server)

```bash
# SSH to ZDM server
ssh azureuser@10.1.0.8

# Run installation script
bash install_oci_cli.sh
```

### 3. Configure SSH Keys (ZDM Server)

```bash
# SSH to ZDM server as zdmuser
ssh zdmuser@10.1.0.8

# Run SSH configuration script
bash configure_ssh_keys.sh
```

### 4. Verify All Fixes (ZDM Server)

```bash
# SSH to ZDM server as zdmuser
ssh zdmuser@10.1.0.8

# Run verification script
bash verify_fixes.sh
```

## Expected Results

After running all scripts, the verification should show:
- ✅ Supplemental logging enabled (MIN=YES, PK=YES)
- ✅ OCI CLI installed and configured
- ✅ SSH connectivity to source and target
- ✅ ZDM service running
- ✅ Sufficient disk space

## Next Steps

Once all verifications pass:
1. Update the Issue Resolution Log
2. Proceed to Step 3: Generate Migration Artifacts
