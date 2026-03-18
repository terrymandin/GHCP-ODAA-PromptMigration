# Step1 Requirements - Test SSH Connectivity

## Objective

Generate a single SSH validation script for pre-discovery connectivity checks.

## S1-01: Output contract

Required generated file:

- `Artifacts/Phase10-Migration/Step1/Scripts/zdm_test_ssh_connectivity.sh`

Do not generate runtime report files during prompt execution.

## S1-02: Runtime report behavior

When the generated script is executed on the jumpbox/ZDM server, it must write:

- `Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-<timestamp>.md`
- `Artifacts/Phase10-Migration/Step1/Validation/ssh-connectivity-report-<timestamp>.json`

## S1-02A: Validation report items (runtime output content)

Step1 report outputs should include at least:

1. Execution metadata: timestamp, host running the script, effective user.
2. Effective SSH model per endpoint: user, host, key mode (explicit key vs default/agent).
3. Key checks (when keys are provided): existence, readability, permission check result.
4. Source connectivity check result (`hostname` probe) with pass/fail status.
5. Target connectivity check result (`hostname` probe) with pass/fail status.
6. Final summary status and non-zero exit behavior when any check fails.

## S1-03: SSH check behavior

1. Validate source and target SSH connectivity.
2. Use non-interactive SSH options.
3. Validate optional key file existence/readability and strict permissions when key paths are provided.
4. Treat placeholder values containing `<...>` as unset.
5. Exit non-zero on failure.

## S1-04: Required input values

Required from `zdm-env.md`:

- `SOURCE_HOST`
- `TARGET_HOST`
- `SOURCE_SSH_USER`
- `TARGET_SSH_USER`

Optional:

- `SOURCE_SSH_KEY`
- `TARGET_SSH_KEY`

## S1-05: Execution output visibility

The Step1 prompt must produce a script that shows validation status directly in console output when the script is run, while also saving results to report files.

Minimum expectation:

1. During runtime, the script prints per-check status (pass/fail) for each major validation step (at minimum: source SSH probe and target SSH probe).
2. During runtime, the script prints a final overall summary status (pass/fail).
3. Script exit code remains aligned to outcome: `0` when all checks pass, non-zero when any check fails.
4. Step1 guidance should still include commands to display the saved reports from `Artifacts/Phase10-Migration/Step1/Validation` (for example, by using `cat` on the latest markdown and JSON report files) for post-run review.

## S1-06: Manual SSH single-line test commands

Step1 output must include single-line manual SSH test commands for both source and target endpoints so users can independently verify connectivity.

Required command variants per endpoint:

1. Default key/agent mode command (`ssh user@host ...`) when no key path is provided.
2. Explicit key mode command (`ssh -i <key> user@host ...`) when a key path is provided.

Command examples should use the same non-interactive options and probe behavior as the generated script (for example, `hostname` probe and batch/non-interactive SSH flags).
