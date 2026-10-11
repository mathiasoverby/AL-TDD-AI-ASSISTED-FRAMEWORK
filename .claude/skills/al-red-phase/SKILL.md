---
name: al-red-phase
description: What counts as a valid RED result in AL TDD and how to fix a test whose failure has the wrong reason or that passes against the stub.
---

# Valid red phase

A test is a valid red only if all hold:
1. It **compiles** (compile errors are never red).
2. The test runner **discovers and executes** it.
3. It **fails**, and the failure message matches `expected_failure_pattern` from the requirement.

## Fixing verdicts
- `WRONG_REASON` - it fails, but for another reason. Typical causes: missing setup data, missing dependency,
  wrong assumption about a field, an error raised before the code under test is reached. Fix the *test*
  setup so execution reaches the stub and fails on the assertion/expected error from the requirement.
- `PASSED_UNEXPECTEDLY` - the test passes against the stub. The assertion is too weak or checks something
  the stub already does. Strengthen it to the requirement's observable outcome. Never "fix" this by
  editing the stub.
- Do not make a test fail artificially (e.g. `Error('x')`). The failure must come from the missing behaviour.

## Stubs
The stub has the right object and procedure signatures but no (or wrong) behaviour, so the test compiles
and fails at runtime. Leave the stub alone in the RED phase.
