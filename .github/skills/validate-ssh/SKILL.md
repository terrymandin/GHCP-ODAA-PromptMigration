---
name: validate-ssh
description: "Validate SSH connectivity prerequisites between ZDM infrastructure and Oracle source database hosts."
---

# Validate SSH

## Procedure

1. Read execution hosts only from `source.ssh_node` and `target.ssh_node`; do not use
	listener or SCAN endpoints as SSH hosts.
2. Identify the ZDM service host and both SSH execution nodes.
3. Verify required hostnames, operating-system users, ports, absolute identity-file
	paths, absolute sudo paths, and key-based authentication prerequisites.
4. Run non-destructive connectivity checks when authorized.
5. Return `pass`, `fail`, or `needs-review` with host-level evidence attached to the
	exact SSH node tested.

Never read, print, or store private key material.
