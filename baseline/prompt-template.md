# Baseline prompt template (direct prompting, zero-shot, no chain-of-thought)

Fixed in advance. The only things substituted are the `{{...}}` fields. Same text for every run.
No BC-specific skills, no scenario analysis step, no tools: the researcher pastes the compiler /
test-runner output back verbatim (no hints), up to K correction rounds.

---

## Turn 1 (RED)
You are working on a Microsoft Dynamics 365 Business Central extension written in AL.

Requirement:
{{REQUIREMENT_USER_STORY_AND_ACCEPTANCE_CRITERIA}}

Technical context (existing objects and signatures):
{{STUB_OBJECTS_AND_APP_JSON}}

Write an AL test codeunit (Subtype = Test) for this requirement. The test must compile against the
existing stub and fail against it, and pass once the behaviour is implemented. Do not change the stub.
Return only the AL code.

## Turn 2..K (correction)
{{COMPILER_OR_TESTRUNNER_OUTPUT_VERBATIM}}

## Turn G (GREEN, after red accepted)
The test is accepted. Now write the production code that replaces the stub so the test passes.
Do not modify the test. Return only the AL code for the production object.
