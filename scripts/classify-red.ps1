<#
.SYNOPSIS  Deterministic RED-phase verdict: compares the red run with the requirement's expected_failure_pattern.
.VERDICTS  VALID_RED | COMPILE_ERROR | NOT_DISCOVERED | PASSED_UNEXPECTEDLY | WRONG_REASON
           VALID_RED requires: compiled, discovered, at least one failure, EVERY failing test message matches the
           regex, and no test passes (a passing test means the assertion is too weak).
#>
param([Parameter(Mandatory)][string]$Requirement)
. "$PSScriptRoot\common.ps1"

$req = Get-Requirement $Requirement
if (-not $req.expected_failure_pattern) { throw "Requirement $Requirement has no expected_failure_pattern." }
$r = Get-Content (Join-Path $TddDir "$Requirement.red.result.json") -Raw | ConvertFrom-Json

$passedTests = @($r.passedTests)

$verdict =
    if (-not $r.compiled) { 'COMPILE_ERROR' }
    elseif (-not $r.discovered) { 'NOT_DISCOVERED' }
    elseif ($r.failed -eq 0 -or $r.passed -gt 0) { 'PASSED_UNEXPECTEDLY' }   # every test must be red
    elseif (@($r.failures | Where-Object { $_.message -notmatch $req.expected_failure_pattern }).Count -gt 0) { 'WRONG_REASON' }
    else { 'VALID_RED' }

$out = [ordered]@{
    requirement = $Requirement; verdict = $verdict; expected = $req.expected_failure_pattern
    failures = @($r.failures); unexpectedPasses = @($passedTests)
    compileErrors = @($r.compileErrors)
}
Write-Json $out (Join-Path $TddDir "$Requirement.red.verdict.json")
Write-RunLog 'classify-red' $verdict
$out | ConvertTo-Json -Depth 6
if ($verdict -ne 'VALID_RED') { exit 1 }
