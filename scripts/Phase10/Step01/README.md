# Step 1 PowerShell Runner

`Initialize-Step01Jumpbox.ps1` is the committed implementation for Phase 10 Step 1. It runs from a local Windows PowerShell terminal and supports SSH public-key authentication only.

Run the non-mutating plan first:

```powershell
.\scripts\Phase10\Step01\Initialize-Step01Jumpbox.ps1 `
  -Mode Plan `
  -VmMode ExistingVm `
  -JumpboxHost "203.0.113.10" `
  -JumpboxSshKey "$env:USERPROFILE\.ssh\zdm_jumpbox_key"
```

After reviewing the plan, run the same command with `-Mode Apply`. For a new VM, use `-VmMode CreateVm` and provide the approved VM, networking, and public-key parameters.

The script emits one JSON result to stdout. Human-readable diagnostics are emitted to stderr. It writes Step 1 reports only in apply mode and never reads Markdown configuration artifacts at runtime.