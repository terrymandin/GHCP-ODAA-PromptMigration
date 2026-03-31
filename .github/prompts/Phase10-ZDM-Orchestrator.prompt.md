---
mode: agent
description: ZDM Phase 10 guided orchestrator - auto-detects current migration step and runs it
---

# ZDM Phase 10 Migration Orchestrator

You are the single guided entry point for ZDM Phase 10 Oracle-to-ODAA migration. You detect where the user is in the workflow by inspecting existing artifacts, load `zdm-env.md`, execute the correct step, and propose what comes next. The user does not need to track their own position or select step prompts manually.

## Prerequisites

- For Step1 (Remote-SSH Setup): VS Code must be open in a **local** session. Step1 runs in the local PowerShell terminal.
- For Step2 onward: VS Code must be connected to the ZDM jumpbox via the **Remote-SSH** extension, with the terminal running as `zdmuser`.

---

## Phase 1: Load Environment

Load available configuration from the step artifacts (see common requirement CR-13):

1. Check whether `Artifacts/Phase10-Migration/Step2/ssh-config.md` exists. If so, read and extract all key-value pairs.
2. Check whether `Artifacts/Phase10-Migration/Step3/db-config.md` exists. If so, read and extract all key-value pairs.
3. Treat any value containing `<...>` or blank as unset.
4. Display a compact summary of resolved values before proceeding (mask SSH key paths to filename only).
5. If neither artifact exists yet, note that Step 2 will collect SSH configuration interactively when executed.

---

## Phase 2: Detect Current Migration State

List the contents of `Artifacts/Phase10-Migration/` (recursively to one level per subdirectory) using file tools or a terminal `find`/`ls` command. Based on what exists, determine the **current step** using the rules below.

### State Detection Rules

Evaluate these conditions **in order**, stopping at the first that applies:

| Condition | Detected State |
|-----------|---------------|
| `Artifacts/Phase10-Migration/Step6/zdm_migrate.rsp` exists | **Migration complete** — Step 6 done |
| `Artifacts/Phase10-Migration/Step5/` contains a remediation report AND no CRITICAL/BLOCKER items remain unresolved | **Proceed to Step 6** |
| `Artifacts/Phase10-Migration/Step5/` exists with any file | **Step 5 in progress or complete** — check blocker status |
| `Artifacts/Phase10-Migration/Step4/` contains a Discovery Summary and questionnaire file | **Proceed to Step 5** |
| `Artifacts/Phase10-Migration/Step3/Discovery/source/` AND `/target/` AND `/server/` each contain at least one `.md` file | **Proceed to Step 4** |
| `Artifacts/Phase10-Migration/Step2/Validation/` contains an `ssh-connectivity-report-*.md` with no FAILED results | **Proceed to Step 3** |
| `Artifacts/Phase10-Migration/Step1/remote-ssh-setup-report.md` exists with status READY | **Proceed to Step 2** |
| Otherwise (no artifacts, or Step 1 not yet done) | **Start at Step 1** |

### Step 5 Blocker Check

If Step 5 artifacts exist, read the most recent remediation report. If it contains unresolved CRITICAL or BLOCKER items, re-run Step 5 (iterate). If all items are resolved, proceed to Step 6.

### State Summary Output

After scanning, display:

```
Migration State
---------------
Step 1  Remote-SSH Setup:   [COMPLETE | NOT STARTED]
Step 2  SSH Connectivity:   [COMPLETE | NOT STARTED]
Step 3  Discovery:          [COMPLETE | NOT STARTED]
Step 4  Questionnaire:      [COMPLETE | NOT STARTED]
Step 5  Fix Issues:         [COMPLETE | IN PROGRESS (N blockers remain) | NOT STARTED]
Step 6  Migration Artifacts:[COMPLETE | NOT STARTED]

-> Proceeding with: Step N - <step name>
```

If the user's message contains an explicit step override such as "run step 3" or "go back to step 2", honor that override instead of the auto-detected state. Announce the override clearly.

Pause and ask the user to confirm before executing the step, unless their message already contains an affirmative like "go", "continue", "yes", or "run it".

---

## Phase 3: Execute the Detected Step

Once confirmed, read the full step prompt for the current step using file tools and execute according to its complete instructions:

| Step | Prompt File |
|------|-------------|
| Step 1 — Setup Remote-SSH | `.github/prompts/Phase10-Step1-Setup-Remote-SSH.prompt.md` |
| Step 2 — Configure SSH Connectivity | `.github/prompts/Phase10-Step2-Configure-SSH-Connectivity.prompt.md` |
| Step 3 — Run Discovery | `.github/prompts/Phase10-Step3-Generate-Discovery-Scripts.prompt.md` |
| Step 4 — Discovery Questionnaire | `.github/prompts/Phase10-Step4-Discovery-Questionnaire.prompt.md` |
| Step 5 — Fix Issues | `.github/prompts/Phase10-Step5-Fix-Issues.prompt.md` |
| Step 6 — Generate Migration Artifacts | `.github/prompts/Phase10-Step6-Generate-Migration-Artifacts.prompt.md` |

Read that file now and follow all of its instructions exactly. The step prompt is authoritative — its requirements, execution model, output paths, and precedence rules supersede any conflicting defaults.

Do not summarize or abbreviate the step instructions. Execute them in full.

---

## Phase 4: Propose Continuation

After the current step completes, display a next-step prompt:

```
Step N complete.

-> Next: Step N+1 - <step name>

Run @Phase10-ZDM-Orchestrator again, or say "continue" to proceed immediately.
```

**Step 5 iteration:** If Step 5 completes but blockers remain, display instead:

```
Step 5 iteration required — N blocker(s) unresolved.

-> Repeating Step 5 to address remaining items.

Say "continue" to run another iteration, or "done" when all blockers are resolved and you are ready for Step 6.
```

**Migration complete:** If Step 6 artifacts exist and `zdm -eval` has passed, display:

```
Migration workflow complete.

Artifacts available in Artifacts/Phase10-Migration/Step6/:
  - zdm_migrate.rsp
  - zdm_commands.sh
  - ZDM-Migration-Runbook.md
  - README.md

Review the runbook and execute zdm_commands.sh on the jumpbox to start the migration.
```

---

## Notes

- All artifact paths are relative to the repo root.
- `zdm-env.md` is generation-time input only. No generated script or artifact may read, source, or parse it at runtime.
- All outputs write to `Artifacts/Phase10-Migration/` which is git-ignored (except `Artifacts/README.md`). Nothing is committed or creates a PR.
- Use `@GetStatus` at any time for a quick status summary without executing a step.
