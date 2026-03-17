# Step 2 Discovery Scripts

These scripts are generated using zdm-env.md values at creation time.
They are runtime-independent and do not read zdm-env.md when executed on the jumpbox/ZDM server.

## Generated Scripts

- zdm_source_discovery.sh
- zdm_target_discovery.sh
- zdm_server_discovery.sh
- zdm_orchestrate_discovery.sh

All scripts are read-only and only collect discovery information.

## Defaults Rendered From zdm-env.md

- SOURCE_HOST=10.200.1.12
- TARGET_HOST=10.200.0.250
- SOURCE_ADMIN_USER=azureuser
- TARGET_ADMIN_USER=opc
- ORACLE_USER=oracle
- ZDM_USER=zdmuser
- SOURCE_REMOTE_ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
- SOURCE_ORACLE_SID=POCAKV
- SOURCE_DATABASE_UNIQUE_NAME=POCAKV
- TARGET_REMOTE_ORACLE_HOME=/u02/app/oracle/product/19.0.0.0/dbhome_1
- TARGET_ORACLE_SID=POKAKV1
- TARGET_DATABASE_UNIQUE_NAME=POCAKV_ODAA

SSH key placeholders (<...>) are treated as unset; scripts omit -i in that case.

## Usage (on jumpbox/ZDM server)

Run as zdmuser from repo clone:

```bash
cd Artifacts/Phase10-Migration/Step2/Scripts
chmod +x *.sh
./zdm_orchestrate_discovery.sh -c
./zdm_orchestrate_discovery.sh
```

Test connectivity only:

```bash
./zdm_orchestrate_discovery.sh -t
```

## Output Locations

- Source outputs: Artifacts/Phase10-Migration/Step2/Discovery/source/
- Target outputs: Artifacts/Phase10-Migration/Step2/Discovery/target/
- ZDM server outputs: Artifacts/Phase10-Migration/Step2/Discovery/server/

## Notes

- Scripts SSH as admin users and run SQL as oracle via sudo -u oracle.
- If SQL sections fail with ORA-01034, validate ORACLE_SID against pmon on the remote host.
- If sqlplus is not found, validate ORACLE_HOME and install path.
