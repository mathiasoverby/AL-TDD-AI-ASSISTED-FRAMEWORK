---
name: al-test-conventions
description: Structure and conventions for Business Central AL test codeunits (Subtype = Test, [Test], Given-When-Then, Assert, asserterror, isolation, handlers). Load before writing any AL test.
---

# AL test conventions

## Skeleton
```al
using System.TestLibraries.Utilities;

codeunit 50200 "My Feature Test"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure DiscountAboveLimitIsRejected()
    var
        DiscountCalc: Codeunit "Discount Calc";
    begin
        // [SCENARIO] A discount above 100 % is rejected
        // [GIVEN] nothing special
        // [WHEN] applying 101 %
        asserterror DiscountCalc.ApplyDiscount(101);
        // [THEN] the documented error is raised
        Assert.ExpectedError('Discount cannot exceed 100');
    end;
}
```

## Rules
- One behaviour per `[Test]` procedure; the name states the behaviour (`<Subject><Condition><Outcome>`).
- Use `// [SCENARIO]`, `// [GIVEN]`, `// [WHEN]`, `// [THEN]` comments.
- Assert **observable outcomes**: `Assert.AreEqual(Expected, Actual, 'message')`, `Assert.IsTrue/IsFalse`,
  `Assert.RecordCount`, `Assert.ExpectedError('exact text')`. Never end a test without an assertion.
- Expected errors: `asserterror <call>;` then `Assert.ExpectedError(...)` (or `ExpectedErrorCode`).
  Without `asserterror`, an error fails the test for a *different* reason than intended.
- Create all data inside the test (or a shared `Initialize()` guarded by an `IsInitialized` flag). Never rely on
  existing sandbox data.
- Isolation: **never** set the property `TestIsolation` on the test codeunit. It is only allowed on codeunits with
  `Subtype = TestRunner` (compile error AL0223, which is never a valid RED). The test runner already rolls back the
  database changes of a test codeunit. Tests inside one codeunit still share data, so give every record a unique key
  (`LibraryRandom`/`Any`, or a key that includes the test name) and, where a test changes shared setup (for example
  General Ledger Setup), set it explicitly inside that test.
- UI interaction needs handlers: `[HandlerFunctions('MyMessageHandler')]` on the test and a matching
  `[MessageHandler]` / `[ConfirmHandler]` / `[PageHandler]` procedure. An unhandled message or confirm fails the test.
- Compare error/message text exactly as in the requirement; do not paraphrase.

## Compile prerequisites
- `app.json` must depend on the test libraries used (Library Assert / Tests-TestLibraries). Read `app.json`
  and `.alpackages` before assuming a library is available.
- Test object ids must stay inside `idRanges`.
- Since BC 24+ the assert codeunit is `"Library Assert"` (id 130002) in namespace `System.TestLibraries.Utilities`:
  add `using System.TestLibraries.Utilities;` and declare `Assert: Codeunit "Library Assert";`. The old name
  `Codeunit Assert` gives AL0185 "Codeunit 'Assert' is missing". If unsure, check the namespace/name in the
  symbol package in `.alpackages` rather than guessing.
