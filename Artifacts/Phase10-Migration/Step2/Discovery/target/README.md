# Discovery Output: Target Database (Oracle Database@Azure)

Discovery output files from the target Oracle Database@Azure server (`10.0.1.160`) are collected
here by `zdm_orchestrate_discovery.sh` after running `zdm_target_discovery.sh`.

## Expected Files

| File | Description |
|------|-------------|
| `zdm_target_discovery_<hostname>_<timestamp>.txt` | Full human-readable discovery report |
| `zdm_target_discovery_<hostname>_<timestamp>.json` | Machine-parseable JSON summary |

## Contents Covered

- OS information
- Oracle environment (ORACLE_HOME, ORACLE_SID, version)
- Database configuration (name, role, open mode, character set)
- CDB/PDB status and pre-configured PDBs
- TDE wallet status
- Network configuration (listener, SCAN listener, tnsnames.ora)
- OCI/Azure integration (OCI CLI, config, connectivity, instance metadata)
- Grid Infrastructure / CRS status (RAC)
- Exadata/ASM storage capacity (disk groups, free space)
- Network security group rules (iptables, firewalld, OCI NSG)
- SSH authentication
