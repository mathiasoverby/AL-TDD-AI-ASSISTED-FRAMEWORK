---
id: R1
# provided : a human has already added the stub (see "Stub" below).
# generate : the stub-writer agent creates it from the "Interface" section (new feature, nothing exists yet).
stub: provided
test_codeunit_id: 50200
test_folder: test
# Regex matched against EVERY failing test's message in the red run. Write it BEFORE any experiment run.
expected_failure_pattern: "Expected.*but.*was"
complexity: low
case_types: positive, boundary, zero, negative
---

# R1 - <short title>

## User story
As a <role> I want <capability> so that <benefit>.

## Acceptance criteria
1. Given ..., when ..., then ... (exact error text / field value).
2. ...

## Interface (required when `stub: generate`)
The exact contract the stub-writer turns into AL objects. Names and signatures are binding; the tests
and the implementation use them unchanged. Free production object id range: 50100-50199.
- Object: `codeunit 50100 "My Feature"` in `src/MyFeature.al`
- Procedure: `procedure DoThing(Input: Decimal): Decimal`

## Stub (what exists before the red phase)
When `stub: provided`, a human adds this to the app. When `stub: generate`, the stub-writer creates it
from the Interface section; keep this list as the expected result.
- Object: `codeunit 50100 "My Feature"` in `src/MyFeature.al`
- Procedure: `procedure DoThing(Input: Decimal): Decimal` - currently returns 0 / does nothing.

## Expected red-phase failure (human-readable)
The tests compile and run, and fail on the assertion because the stub returns 0 instead of <value>.

## Notes
Anonymised from a BDL requirement. Free test object id range: 50200-50249.
