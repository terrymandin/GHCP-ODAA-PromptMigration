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
