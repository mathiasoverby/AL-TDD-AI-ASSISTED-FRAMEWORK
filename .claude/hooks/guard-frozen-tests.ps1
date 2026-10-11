# PreToolUse hook (Edit|Write): block changes to files frozen in .tdd/frozen.json (tests, from RED onwards)
# and .tdd/frozen-stub.json (stub, during RED only; check-stub.ps1 -Action Unfreeze lifts it before GREEN).
# Exit code 2 = block; stderr is shown to the model.
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$target = $payload.tool_input.file_path
if (-not $target) { exit 0 }

$full = [System.IO.Path]::GetFullPath($target)
$guards = @(
    @{ file = '.tdd\frozen.json';      msg = "BLOCKED: '$target' is a frozen test file (GREEN phase). Change production code instead." }
    @{ file = '.tdd\frozen-stub.json'; msg = "BLOCKED: '$target' is the frozen stub (RED phase). Tests must be written against the stub, not change it." }
)
foreach ($g in $guards) {
    $frozenFile = Join-Path $payload.cwd $g.file
    if (-not (Test-Path $frozenFile)) { continue }
    $frozen = Get-Content $frozenFile -Raw | ConvertFrom-Json
    foreach ($p in $frozen.PSObject.Properties) {
        if ([string]::Equals([System.IO.Path]::GetFullPath($p.Name), $full, 'OrdinalIgnoreCase')) {
            [Console]::Error.WriteLine($g.msg)
            exit 2
        }
    }
}
exit 0
