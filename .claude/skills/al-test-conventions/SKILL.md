---
name: al-test-conventions
description: Structure and conventions for Business Central AL test codeunits (Subtype = Test, [Test], Given-When-Then, Assert, asserterror, isolation, handlers). Load before writing any AL test.
---

# AL test conventions

## Skeleton
```al
codeunit 50200 "My Feature Test"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit Assert;

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
- Isolation: set `TestIsolation = Codeunit` (or `Function`) on the test codeunit when tests write to the database,
  so changes roll back. Leave it unset only if the tests are read-only.
- UI interaction needs handlers: `[HandlerFunctions('MyMessageHandler')]` on the test and a matching
  `[MessageHandler]` / `[ConfirmHandler]` / `[PageHandler]` procedure. An unhandled message or confirm fails the test.
- Compare error/message text exactly as in the requirement; do not paraphrase.

## Compile prerequisites
- `app.json` must depend on the test libraries used (Library Assert / Tests-TestLibraries). Read `app.json`
  and `.alpackages` before assuming a library is available.
- Test object ids must stay inside `idRanges`.
