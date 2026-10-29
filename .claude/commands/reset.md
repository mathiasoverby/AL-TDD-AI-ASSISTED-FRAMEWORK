---
description: Reset a requirement to its pre-run state (stub restored, tests removed, .tdd cleared) so /tdd can be run again
argument-hint: <requirement-id e.g. R1>
---

Reset the requirement `$ARGUMENTS` so `/tdd $ARGUMENTS` can be run again from scratch.

1. Run a dry run first and show the user what it will do:
   ```powershell
   powershell -NoProfile -File scripts/reset-run.ps1 -Requirement $ARGUMENTS -WhatIf
   ```
2. Then run the real reset (the script archives the previous run in `.tdd-archive\` before changing anything):
   ```powershell
   powershell -NoProfile -File scripts/reset-run.ps1 -Requirement $ARGUMENTS
   ```
3. Report in two or three lines: that the stub was restored, which test files were removed, and the archive path
   the script printed. If the script fails (for example because `stubs/$ARGUMENTS/` does not exist), show the
   error and stop. Do not delete files by hand as a fallback.

Do not start `/tdd` afterwards unless the user asks for it.
