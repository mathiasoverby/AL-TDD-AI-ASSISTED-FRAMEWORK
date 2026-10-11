# AL TDD Framework (Claude Code)

AI-assisted test-driven development for Business Central AL. Copy this folder's contents
(`.claude/`, `scripts/`, `requirements/`) into the root of an AL repo.

## Workflow (`/tdd R1`)

```
requirements/R1.md
   |
   v
requirement-analyst --> .tdd/R1.scenarios.md
   |
   v   only if `stub: generate` (<= K rounds)
stub-writer --> check-stub.ps1 --VALID_STUB--> stub frozen during RED
   |
   v   RED (<= K rounds)
test-writer --> run-tests.ps1 -Phase red --> classify-red.ps1 --VALID_RED--> freeze-tests.ps1 Freeze
   ^                                              | other verdict: output goes back to test-writer
   |__________________________________________|
   v   GREEN (<= K rounds)
implementer --> run-tests.ps1 -Phase green --> freeze-tests.ps1 Verify (TEST_TAMPERED => run invalid)
   v   REFACTOR (optional, not measured)
refactorer --> re-run green + verify
```

| Piece | Where | Role |
|---|---|---|
| Orchestrator | `.claude/commands/tdd.md` | fixed workflow (prompt chaining + evaluator-optimizer) |
| Agents | `.claude/agents/` | requirement-analyst, stub-writer (only `stub: generate`), test-writer, implementer, refactorer |
| Skills | `.claude/skills/` | BC knowledge, loaded on demand: conventions, libraries, red phase, diagnosis |
| Tools | `scripts/*.ps1` | compile (alc.exe), publish+run (BcContainerHelper), red verdict, freeze/verify |
| Guard | `.claude/hooks/guard-frozen-tests.ps1` | blocks Edit/Write on frozen tests (role separation, Mock et al.) |

Design choices tied to the thesis: verdicts are deterministic (scripts, not the model); the implementer
cannot modify frozen tests; skills are loaded only when a step needs them (token cost, RQ2);
the same K (`MaxCorrectionRounds`) applies to the baseline.

## Setup
1. `scripts/config.psd1`: container name, tenant, `AppFolder`, K, model.
2. `$env:BC_USERNAME` / `$env:BC_PASSWORD` for the container (never committed).
3. Docker running and BcContainerHelper permissions fixed (`Check-BcContainerHelperPermissions -Fix`, admin).
4. Copy `requirements/_template.md` to `R1.md`, fill it in, **including `expected_failure_pattern`**, and either add the stub to the app (`stub: provided`) or fill in the `Interface` section and set
   `stub: generate` so the stub-writer creates it (new features where nothing exists yet).
5. In Claude Code, from the repo root: `/tdd R1`. For experiments: `scripts/run-framework.ps1 -Requirement R1 -RunId fw-01`.

## Not done yet
- **Code coverage** (RQ1): `run-tests.ps1` records pass/fail only. Add coverage via the AL Test Runner
  extension (`codeCoveragePath` in `.altestrunner/config.json`) or a coverage-enabled test runner codeunit.
- **Baseline runner**: `baseline/prompt-template.md` is fixed; the manual/semi-automated loop is not scripted.
- Token capture assumes `claude -p --output-format json` includes subagent usage; verify in the pilot run.
- `run-tests.ps1` and `/tdd` are untested end-to-end (Docker was not running); compile, freeze/verify,
  hook and red-classifier were tested in isolation.
