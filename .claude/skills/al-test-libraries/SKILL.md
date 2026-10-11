---
name: al-test-libraries
description: How to create valid test data in Business Central tests with the standard test libraries (Library - Sales, Library - Random, Library - Utility, etc.) instead of hand-inserting records.
---

# Test data with standard libraries

BC tests run against a real database, so valid data usually depends on setup (number series, posting
groups). The standard test libraries create that setup for you. **Prefer them over `Record.Insert`.**

| Need | Library codeunit (verify name in symbols) |
|---|---|
| Customers, sales headers/lines, posting | `Library - Sales` |
| Items, inventory | `Library - Inventory` |
| Vendors, purchase documents | `Library - Purchase` |
| Random text/decimal/dates (avoids clashes) | `Library - Random` |
| Misc. (`GenerateGUID`, no. series) | `Library - Utility` |
| Cross-handler values | `Library - Variable Storage` |
| Test with restricted permissions | `Library - Lower Permissions` |

## Procedure
1. Check which libraries are available: search `.alpackages` / the symbols of the test library app
   (`Grep` the object names) - do not guess procedure names.
2. Use random values (`LibraryRandom.RandDec(100, 2)`) for inputs whose exact value does not matter, and
   fixed values only for boundary cases.
3. If a library procedure does not exist in the installed version, build the minimum record by hand and
   say so in a comment. Do not invent procedures.
