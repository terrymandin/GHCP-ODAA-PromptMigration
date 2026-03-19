---
mode: agent
description: Restore migration context in a new VS Code session (Remote SSH, Dev Container, or new window)
---

# Oracle Database@Azure Migration — New Session Context Restore

## Why Chat History Is Not Available

GitHub Copilot chat history is stored **per VS Code instance**. When you open this repository in a new VS Code window — for example, via **Remote SSH** to an Azure VM jumpbox, inside a Dev Container, or on a different machine — the new instance starts with an empty chat history.

Your previous conversations are **not accessible** in the new instance. This is expected VS Code behaviour.

## How This Prompt Restores Your Session

This prompt reads `reports/Report-Status.md` to reconstruct the migration context without relying on chat history.

### Step 1 — Read the Status File

Read `reports/Report-Status.md`.

- If the file **does not exist**: inform the user that no prior migration state was found and ask them to run `@00-Start-Here` to begin.
- If the file **exists**: proceed to Step 2.

### Step 2 — Summarise and Restore Context

Display the following from the status file:

1. **Where we are** — which phases are complete, which is in progress
2. **Key environment details** — source host, target host, database name, migration method
3. **Open blockers** — any unresolved issues with severity
4. **Next recommended step** — the exact `@PromptName` and any `#file:` attachments needed

### Step 3 — Check for Environment File

Check whether `zdm-env.md` exists in the repository root.

- If it exists: remind the user to attach `#file:zdm-env.md` when running ZDM-related prompts.
- If it does not exist: remind the user to copy `zdm-env.example.md` to `zdm-env.md` and fill in their values before running ZDM prompts.

### Step 4 — Confirm Readiness

Ask the user:

> "I have restored context from your status file. Would you like to continue with **[next recommended step]**, or is there something else you need help with?"

## Quick Reference — Resuming Each Phase

| Situation | Command |
|-----------|---------|
| Just opened a new VS Code window | `@NewSession` (this prompt) |
| Connected via Remote SSH to jumpbox | `@NewSession` (this prompt) |
| Want full status detail | `@GetStatus` |
| Need to re-run a specific phase | Use the phase prompt with `#file:reports/Report-Status.md` attached |
| Need to resume ZDM work | Use the ZDM step prompt with `#file:zdm-env.md` attached |
