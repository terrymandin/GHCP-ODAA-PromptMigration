---
name: validate-zdm-eval
description: "Validate sanitized customer-run Oracle ZDM eval results and gate migration readiness."
---

# Validate ZDM Eval

## Procedure

1. Require a passing eval-command generation result. Never execute `zdmcli` for the
   customer.
2. Ask the customer to run the generated `-eval` command on the ZDM host and return
   only sanitized job status and findings. Do not request logs containing secrets,
   connection strings, wallet contents, private keys, or command arguments.
3. Accept and persist only:
   - ZDM job ID;
   - overall status and phase names;
   - allowlisted codes beginning `PRGZ-`, `PRCZ-`, `PRCG-`, or `ZDM-`;
   - sanitized messages with credentials, paths, hostnames, and addresses removed.
4. Return `pass` only for an observed successful eval result. Return `fail` for an
   observed failed result and `needs-review` when output is missing, incomplete, or
   cannot be sanitized confidently.
5. Route failures to the owning step. Authentication argument and `sudo_location`
   failures, including `PRCZ-4004`, return to `generate-eval-command`; endpoint and
   port failures return to `validate-network` or `validate-ssh`; RSP property failures
   return to `generate-rsp`; source database login failures return to
   `validate-source`; target Oracle-home patch discrepancy failures return to
   `validate-target`.
6. Require the corrected owner step and all dependent steps to pass before accepting
   another eval result. Never convert job creation alone into an eval pass.

## Result Contract

```yaml
zdm_eval_validation:
  status: pass | fail | needs-review
  observed: true | false
  job_id:
  phases: []
  findings:
    - code:
      message:
      owner:
  remediation: []
```

The absence of observed output always produces `needs-review` and caps readiness at
`ready for evaluation`.