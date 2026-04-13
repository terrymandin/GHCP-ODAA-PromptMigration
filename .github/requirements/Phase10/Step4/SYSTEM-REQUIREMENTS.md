# Step4 System Requirements - Discovery Analysis Implementation

## Scope

This file defines implementation-level constraints for Step4 analysis behavior and questionnaire generation.

## S4-11: Questionnaire constraints

1. Include only items requiring manual decisions or operator-supplied identifiers.
2. Each question must include a recommended default and concise justification.
3. Never ask a question whose answer cannot influence an RSP parameter, a `zdmcli` argument, or runbook content.
4. Never present ONLINE_PHYSICAL branch questions during an OFFLINE_PHYSICAL interview, and vice versa. Branch questions are gated by the Phase A answer.
5. Never write `Migration-Decisions.md` until all interview phases are complete and all questions are answered. The output file is a Decisions Record, not a form.

## S4-12: Evidence selection and consistency rules

1. When multiple discovery files exist per component, use the most recent file set by timestamp.
2. Keep source, target, and server evidence references explicit in generated outputs.
3. Preserve mismatch traceability between configured intent (`zdm-env.md`) and observed discovery evidence.

## S4-13: Classification guardrails

1. If Step3 discovery completed successfully, do not classify "oracle SSH directory not found" as a blocker by itself.
2. Always evaluate ZDM version evidence from server discovery output.
3. If ZDM version is outdated or undetermined, generate a required action to verify/upgrade before Step6.

## S4-14: Decisions Record integrity

1. Every row in the Decisions Record table must have a non-blank, non-placeholder value before the file is written.
2. Each row must carry an explicit Source tag: `discovered`, `from zdm-env.md`, or `manual`.
3. The Decisions Record replaces `zdm-env.md` as Step6's primary source for RSP parameter values. It must contain every RSP parameter required for the confirmed migration method.
4. If the operator cannot answer a required question, record the parameter as `BLOCKED` with a note, and surface it as a Critical blocker in the Step4 README.
