---
description: Run the AI-assisted TDD workflow (red -> green -> refactor) for one requirement file
argument-hint: <requirement-id e.g. R1>
---

You are the **orchestrator** of the AL TDD framework. Run the workflow below for the requirement
`requirements/$ARGUMENTS.md`. You coordinate; the subagents and scripts do the work.

Rules that hold for the whole run:
- Order is fixed: RED (test first) -> GREEN (implementation) -> REFACTOR (optional). Never skip RED.
- Verdicts come from the scripts in `scripts/`, never from your own judgement of the output.
- Correction budget: at most `MaxCorrectionRounds` (see `scripts/config.psd1`) per phase. Count every
  re-run of compile/run-tests that follows a failure as one round. Stop and report when exhausted.
- Pass subagents only what they need (paths + the last script output). Do not paste whole files.
- Append one line per step to `.tdd/run-log.jsonl` (step, round, verdict, UTC timestamp).
- Token reporting: every subagent call must set the Agent `description` to
  `<PHASE> · <agent> · round <n>`, where PHASE is `Analyse`, `STUB`, `RED`, `GREEN` or `REFACTOR`
  (e.g. `RED · test-writer · round 2`). The text before ` · ` is the group in the usage report.
  Keep descriptions unique: a correction round gets the next round number.

## Step 0 - Record start time
Run this once, right before the first subagent is spawned (shell state does not persist, so the time
goes in a file):
```powershell
$startFile = "$env:TEMP\claude-usage\tdd-$env:CLAUDE_CODE_SESSION_ID.txt"
New-Item -ItemType Directory -Force (Split-Path $startFile) | Out-Null
[DateTime]::UtcNow.ToString("o") | Set-Content $startFile -Encoding UTF8
```

## Phase 0 - Analyse
1. Delegate to the **requirement-analyst** agent with `requirements/$ARGUMENTS.md`.
   It returns a test-scenario list (positive, boundary, zero, negative/invalid, error behaviour)
   saved to `.tdd/$ARGUMENTS.scenarios.md`.

## Phase 0b - Stub (only when the requirement front matter has `stub: generate`)
Skip this phase when `stub: provided`: a human already added the stub.
1b. Run `scripts/check-stub.ps1 -Action Snapshot`.
1c. Delegate to **stub-writer** with `requirements/$ARGUMENTS.md` and `.tdd/$ARGUMENTS.scenarios.md`.
    It creates the objects and signatures from the `Interface` section, with no behaviour.
1d. Run `scripts/check-stub.ps1 -Action Check` and act on the verdict:
    - `VALID_STUB`  -> the stub is frozen (`.tdd/frozen-stub.json`); go to Phase 1.
    - `NO_STUB_FILES`, `STUB_COMPILE_ERROR`, `STUB_HAS_BEHAVIOUR`
                    -> send the verdict + script output to **stub-writer** (one correction round), repeat 1d.
    If the budget is exhausted, stop and report `STUB_NOT_VALID` with the last verdict.

## Phase 1 - RED
2. Delegate to **test-writer** with the scenario list. It writes the test codeunit.
3. Run `scripts/run-tests.ps1 -Requirement $ARGUMENTS -Phase red` (compiles, publishes, runs).
4. Run `scripts/classify-red.ps1 -Requirement $ARGUMENTS` and act on the verdict:
   - `VALID_RED`        -> go to step 6.
   - `COMPILE_ERROR`, `NOT_DISCOVERED`, `WRONG_REASON`, `PASSED_UNEXPECTEDLY`
                        -> send the verdict + script output to **test-writer** (one correction round), repeat 3-4.
   Compile errors are never a valid red result.
5. If the budget is exhausted, stop: report `RED_NOT_REACHED` with the last verdict.
6. Freeze the tests: `scripts/freeze-tests.ps1 -Action Freeze`. From now on tests are read-only.

## Phase 2 - GREEN
6b. Run `scripts/check-stub.ps1 -Action Unfreeze` (the stub must be editable now; the tests stay frozen).
7. Delegate to **implementer**: replace the stub with the minimal production code that satisfies the
   requirement. It may not touch frozen test files (a hook blocks it; step 9 verifies it).
8. Run `scripts/run-tests.ps1 -Requirement $ARGUMENTS -Phase green`.
   - All tests pass -> step 9.
   - Failures/compile errors -> send output to **implementer** (one correction round), repeat 8.
9. Run `scripts/freeze-tests.ps1 -Action Verify`. If any test file changed, the run is **invalid**:
   report `TEST_TAMPERED` and stop.

## Phase 3 - REFACTOR (controlled by `RunRefactor` in `scripts/config.psd1`)
Read `RunRefactor` from `scripts/config.psd1`. When it is `$false`, skip this phase and say so in the report.
Otherwise:
10a. Run `scripts/refactor-snapshot.ps1 -Requirement $ARGUMENTS -Action Snapshot` (saves the green code).
10b. Delegate to **refactorer** (description `REFACTOR · refactorer · round 1`).
10c. Re-run step 8 (`-Phase green`) and step 9 (`freeze-tests.ps1 -Action Verify`).
     - Tests pass and tests unchanged -> keep the refactoring.
     - Tests fail or a test file changed -> run `scripts/refactor-snapshot.ps1 -Requirement $ARGUMENTS -Action Restore`,
       re-run step 8 to confirm green again, and report `REFACTOR_REVERTED`. Do not send the failure back to the
       refactorer for a correction round.
10d. Run `scripts/refactor-snapshot.ps1 -Requirement $ARGUMENTS -Action Diff` and include its output path in the report.

## Report
Finish with a short table: phase, rounds used, final verdict, files created/changed, and the paths of
the run log and result JSON files. Do not restate file contents.

## Subagent token usage
Run this only after **all** subagents have finished, including correction rounds (a running agent's
transcript is incomplete):
```powershell
$startFile = "$env:TEMP\claude-usage\tdd-$env:CLAUDE_CODE_SESSION_ID.txt"
& ".\scripts\subagent-usage-report.ps1" -StartFile $startFile `
    -AgentTypes 'requirement-analyst','stub-writer','test-writer','implementer','refactorer' `
    -Title 'AL TDD - Subagent Cost Report' -Subtitle 'Requirement: $ARGUMENTS'
```
Paste the printed table into chat **verbatim in a code block**. Never recompute, re-round or replace
the numbers, and never use the harness's `subagent_tokens`. A row starting with `(unmatched)` means a
description does not follow `<PHASE> · <agent> · round <n>`: report it, do not hide it.

## Last step - Cost report (PDF)
Ask with exactly this `AskUserQuestion`, word for word:
```
question    : "Create a PDF cost report for this run? It breaks the subagents' token usage down per agent into cache writes, cache reads, uncached input and output, with the USD cost of each."
header      : "Cost report"
multiSelect : false
options     :
  { label: "Create PDF report",
    description: "Writes the PDF, plus the HTML it is printed from, to %TEMP%\claude-usage and shows the path." }
  { label: "✗ Skip",
    description: "Finish without a report. The token table above stays the record of this run." }
```
- **Create PDF report:** run the command from the previous section again with
  `-PdfPath "$env:TEMP\claude-usage\tdd-cost-report-$(Get-Date -Format yyyyMMdd-HHmm).pdf"` added,
  then show the `PDF report:` path it prints. If it prints a warning instead, show that.
- **✗ Skip:** finish.
