# Step3 System Requirements - Discovery Analysis Implementation

## Scope

This file defines implementation-level constraints for Step3 analysis behavior and questionnaire generation.

## S3-05: Questionnaire constraints

1. Include only items requiring manual decisions/identifiers.
2. Each question must include a recommended default and concise justification.

## S3-08: Evidence selection and consistency rules

1. When multiple discovery files exist per component, use the most recent file set by timestamp.
2. Keep source, target, and server evidence references explicit in generated outputs.
3. Preserve mismatch traceability between configured intent (`zdm-env.md`) and observed discovery evidence.

## S3-09: Classification guardrails

1. If Step2 discovery completed successfully, do not classify "oracle SSH directory not found" as a blocker by itself.
2. Always evaluate ZDM version evidence from server discovery output.
3. If ZDM version is outdated or undetermined, generate a required action to verify/upgrade before Step5.
