---
name: generate-eval-command
description: "Generate a customer-run Oracle ZDM zdmcli migrate database -eval command from validated profile and response-file inputs."
---

# Generate ZDM Eval Command

## Procedure

1. Require successful validation and a generated response file.
   Reject unmatched or disabled routes before command generation.
2. Read command inputs only from the canonical migration profile. For a
   single-instance source without Grid Infrastructure, use `-sourcesid`; do not
   substitute the database unique name.
3. Keep SSH execution nodes separate from database listener or SCAN endpoints.
   Use `source.ssh_node` and `target.ssh_node`; never infer either from network
   validation or substitute `source.listener_endpoint` or `target.listener_endpoint`.
4. For the `zdmauth` plug-in, require user, absolute identity-file path, and absolute
   sudo path for both source and target. Render all three corresponding plug-in
   arguments, including `sudo_location` as `srcarg3` and `tgtarg3`.
5. Require the absolute target Oracle home and absolute response-file path on the ZDM
   host.
6. When the source uses a password-based TDE keystore, render the flag
   `-tdekeystorepasswd` by itself so ZDM prompts locally. Never request, persist,
   generate, echo, or place the password in the command or an argument.
7. Always append `-eval`. Do not add `-ignore`, `-skipadvisor`, or destructive
   cutover options unless the customer explicitly approves them for a later run.
8. Shell-quote every value and reject control characters, shell metacharacters,
   parent traversal, relative paths where absolute paths are required, and missing
   inputs.
9. Return a customer-run command. Do not claim it succeeded until sanitized output
   from the customer is observed.

## Result Contract

Return and persist a sanitized result with:

- `status`: `pass`, `fail`, or `needs-review`;
- `route_id`, `zdm_release`, and command-shape identifier;
- `output_file` and a list of rendered flag names, but no password values;
- `findings` and `remediation`.

Use `pass` only when the route is enabled, the RSP result passed, every route-required
argument is present exactly once, all path checks pass, `-tdekeystorepasswd` has no
value, and `-eval` is the final flag.

## VMDB to ODAA Command Shape

```sh
$ZDM_HOME/bin/zdmcli migrate database \
  -rsp '<response-file>' \
  -sourcesid '<source-sid>' \
  -sourcenode '<source-node>' \
  -srcauth zdmauth \
  -srcarg1 'user:<source-user>' \
  -srcarg2 'identity_file:<source-key-path>' \
  -srcarg3 'sudo_location:<source-sudo-path>' \
  -targetnode '<target-node>' \
  -tgtauth zdmauth \
  -tgtarg1 'user:<target-user>' \
  -tgtarg2 'identity_file:<target-key-path>' \
  -tgtarg3 'sudo_location:<target-sudo-path>' \
  -targethome '<target-oracle-home>' \
  -tdekeystorepasswd \
  -eval
```