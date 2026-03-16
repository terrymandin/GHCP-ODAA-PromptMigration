# SSH Connectivity Report — Step 1

| | |
|---|---|
| **Project** | ODAA-ORA-DB |
| **Timestamp** | 20260316-133259 |
| **Run by** | zdmuser@zdmhost |
| **ZDM Server** | 10.200.1.13 |
| **Overall Result** | ALL CHECKS PASSED |

---

## Check Results

| Check | Status | Detail |
|-------|--------|--------|
| ZDM `~/.ssh` directory | PASS | /home/zdmuser/.ssh exists |
| ZDM identity key (`~/.ssh/id_rsa`) | PASS | /home/zdmuser/.ssh/id_rsa  permissions: 600 |
| SOURCE SSH (`azureuser@10.200.1.12`) | PASS | hostname: factvmhost |
| TARGET SSH (`opc@10.200.0.250`) | PASS | hostname: vmclusterpoc-ytlat1 |

---

## SSH Options Used

```
-o BatchMode=yes
-o StrictHostKeyChecking=accept-new
-o ConnectTimeout=10
-o PasswordAuthentication=no
```

> **Note:** No `-i` key-file argument is passed to SSH for source/target connections.
> Public keys are pre-authorised in `~/.ssh/authorized_keys` on both hosts.

---

## Next Step

Proceed to **Step 2**: run `@Phase10-ZDM-Step2-Generate-Discovery-Scripts`.
