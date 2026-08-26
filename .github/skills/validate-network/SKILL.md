---
name: validate-network
description: "Validate DNS, routing, firewall, and port prerequisites for Oracle ZDM migration connectivity."
---

# Validate Network

## Procedure

1. Read database endpoints only from `source.listener_endpoint` and
	`target.listener_endpoint`. These may be listener, SCAN, or service FQDN values.
2. Identify the ZDM host and required database service ports. Do not consume or
	populate `source.ssh_node` or `target.ssh_node` in this skill.
3. Verify forward and reverse DNS expectations.
4. Check required routes, firewall rules, and ports using non-destructive tests.
5. Return `pass`, `fail`, or `needs-review` with endpoint-level evidence. Attach each
	observation to the exact listener endpoint and port tested.

Listener endpoints and SSH nodes are independent roles. Their values may happen to
match, but one must never be substituted for the other.
