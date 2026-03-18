# Step1 System Requirements - SSH Validation Script Implementation

## Scope

This file defines script-level coding and runtime behavior constraints for Step1 generation.

## S1-03: SSH check behavior

1. Validate source and target SSH connectivity.
2. Use non-interactive SSH options.
3. Validate optional key file existence/readability and strict permissions when key paths are provided.
4. Treat placeholder values containing `<...>` as unset.
5. Exit non-zero on failure.
6. Include these non-interactive SSH options in generated script logic:
   - `-o BatchMode=yes`
   - `-o StrictHostKeyChecking=accept-new`
   - `-o ConnectTimeout=10`
   - `-o PasswordAuthentication=no`

## S1-05: Execution output visibility

The Step1 prompt must produce a script that shows validation status directly in console output when the script is run, while also saving results to report files.

Minimum expectation:

1. During runtime, the script prints per-check status (pass/fail) for each major validation step (at minimum: source SSH probe and target SSH probe).
2. During runtime, the script prints a final overall summary status (pass/fail).
3. Script exit code remains aligned to outcome: `0` when all checks pass, non-zero when any check fails.
4. Step1 guidance should still include commands to display the saved reports from `Artifacts/Phase10-Migration/Step1/Validation` (for example, by using `cat` on the latest markdown and JSON report files) for post-run review.

## S1-07: Runtime user model

1. The generated script is intended to run as `zdmuser` on the jumpbox/ZDM server.
2. Step1 documentation must state the required runtime user explicitly.

## S1-08: Shell-safe report rendering

When writing markdown/json report content from shell:

1. Formatting logic must be safe for lines that start with `-` or other option-like prefixes.
2. Avoid `printf` option parsing hazards by using shell-safe patterns (for example `printf -- '...\n'` or equivalent `%s`-based formatting for leading-dash literals).
3. Report rendering must not emit raw shell usage/invalid-option noise to users; rendering failures must be surfaced as explicit Step1 validation errors.
4. Report rendering must behave consistently under bash on Oracle Linux/RHEL-family systems used for ZDM jumpboxes.

## S1-09: Runtime report write verification

After writing runtime reports, script must run explicit verification checks:

1. Confirm markdown and JSON report files exist and are non-empty.
2. Confirm markdown contains populated value lines for each required report section.
3. Confirm markdown/json summary parity for overall status and failure count.
4. If any verification fails, print fail reason to console and exit non-zero.
