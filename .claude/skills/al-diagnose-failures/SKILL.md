---
name: al-diagnose-failures
description: Interpret AL compiler errors and Business Central test-runner output (AL0118, AL0132, not discovered, handler errors, setup errors) and decide the minimal fix.
---

# Diagnosing failures

Work from the script JSON (`errors[]` / `failures[]`), not from guesses. Fix the first error first; later
errors are often consequences.

## Compiler
| Code / symptom | Usual cause | Fix |
|---|---|---|
| AL0118 name does not exist | typo, missing `using`/dependency, wrong library name | check object/variable name in symbols; add dependency in `app.json` only if the requirement allows |
| AL0132 member does not exist | procedure not on the object (or not public) | read the object; use the real signature |
| AL0133 / AL0135 argument mismatch | wrong parameter types/count | read signature, adjust call |
| AL0185 object not found | object id/name wrong or app not in `.alpackages` | check name; do not invent objects |
| AL0275 duplicate id | object id already used | choose a free id in `idRanges` |

## Test runner
- **Not discovered**: codeunit lacks `Subtype = Test`, procedure lacks `[Test]`, wrong id passed to the runner,
  or the app was not published. Check those four, in that order.
- **Unhandled UI**: message/confirm/page opened without a handler -> add `[HandlerFunctions(...)]` + handler.
- **Record already exists / field required**: test data collision or missing mandatory fields -> create data via
  libraries with random values.
- **Assert failed with unexpected values**: compare against the requirement text; fix the *expectation* only if
  the requirement says so, otherwise the behaviour is missing (that is the intended red).

Make the smallest change that addresses the reported error. One fix per round when the errors are unrelated
to each other is not required - fix all independent errors in the output at once to save rounds.
