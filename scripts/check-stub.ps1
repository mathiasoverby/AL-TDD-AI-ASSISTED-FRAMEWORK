<#
.SYNOPSIS  Stub phase (requirement front matter `stub: generate`): snapshot, deterministic stub verdict, freeze.
.PARAMETER Action  Snapshot : hash every non-test .al file before the stub-writer runs -> .tdd/pre-stub.json
                   Check    : compile, find new/changed non-test .al files, verify they hold no behaviour.
                              On VALID_STUB the stub files are frozen -> .tdd/frozen-stub.json (RED phase guard)
                   Unfreeze : delete frozen-stub.json (run before GREEN so the implementer may fill the stub in)
.VERDICTS  VALID_STUB | NO_STUB_FILES | STUB_COMPILE_ERROR | STUB_HAS_BEHAVIOUR
           Behaviour = control flow (if/case/loops), assignments, record/UI calls. Allowed: declarations and
           bodies that are empty or only `exit(<literal>)`.
#>
param([Parameter(Mandatory)][ValidateSet('Snapshot', 'Check', 'Unfreeze')][string]$Action)
. "$PSScriptRoot\common.ps1"

$pre    = Join-Path $TddDir 'pre-stub.json'
$frozen = Join-Path $TddDir 'frozen-stub.json'
if ($Action -eq 'Unfreeze') { Remove-Item $frozen -ErrorAction SilentlyContinue; Write-RunLog 'unfreeze-stub' 'OK'; 'Stub unfrozen.'; exit 0 }

function Get-ProductionFiles {
    Get-ChildItem (Get-AppFolder) -Recurse -Filter *.al |
        Where-Object { $_.Name -notmatch 'Test' -and $_.FullName -notmatch '\\\.(alpackages|output|tdd)\\' }
}

if ($Action -eq 'Snapshot') {
    $map = [ordered]@{}
    foreach ($f in Get-ProductionFiles) { $map[$f.FullName] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash }
    Write-Json $map $pre
    Write-RunLog 'stub-snapshot' "OK:$($map.Count)files"
    "Snapshot of $($map.Count) production file(s)."; exit 0
}

# Check
if (-not (Test-Path $pre)) { throw 'No snapshot. Run -Action Snapshot before the stub-writer.' }
$before = Get-Content $pre -Raw | ConvertFrom-Json
$stubFiles = @(Get-ProductionFiles | Where-Object {
    $old = $before.PSObject.Properties[$_.FullName]
    (-not $old) -or $old.Value -ne (Get-FileHash $_.FullName -Algorithm SHA256).Hash
})

# Strip comments and string literals so error texts and comments never count as behaviour.
$strip = { param($t) ($t -replace '(?s)/\*.*?\*/', '' -replace '//[^\r\n]*', '' -replace "'[^'\r\n]*(?:''[^'\r\n]*)*'", "''") }
$kw   = '(?i)\b(if|case|for|foreach|while|repeat|until|with)\b'
$call = '(?i)\b(Insert|Modify|Delete|DeleteAll|ModifyAll|Get|Find|FindFirst|FindLast|FindSet|Next|Validate|SetRange|SetFilter|Error|Message|Confirm|Evaluate|CalcFields|CalcSums|Commit|Copy|Init|TestField)\s*\('
$problems = @()
foreach ($f in $stubFiles) {
    $n = 0
    foreach ($line in (& $strip (Get-Content $f.FullName -Raw)) -split "\r?\n") {
        $n++
        if ($line -match '^\s*(local\s+|internal\s+|protected\s+)?(procedure|trigger)\b') { continue }   # declarations
        if ($line -match $kw -or $line -match $call -or $line -match ':=') {
            $problems += "$($f.Name):$n  $($line.Trim())"
        }
    }
}

$compile = $null
Remove-Item (Join-Path $TddDir 'compile-result.json') -ErrorAction SilentlyContinue   # never trust a stale result
if ($stubFiles.Count) { try { $compile = & "$PSScriptRoot\compile.ps1" | Out-String } catch { $compile = $_.Exception.Message } }
$compiled = $false
if (Test-Path (Join-Path $TddDir 'compile-result.json')) { $compiled = [bool](Get-Content (Join-Path $TddDir 'compile-result.json') -Raw | ConvertFrom-Json).success }

$verdict =
    if (-not $stubFiles.Count) { 'NO_STUB_FILES' }
    elseif (-not $compiled) { 'STUB_COMPILE_ERROR' }
    elseif ($problems.Count) { 'STUB_HAS_BEHAVIOUR' }
    else { 'VALID_STUB' }

if ($verdict -eq 'VALID_STUB') {
    $map = [ordered]@{}
    foreach ($f in $stubFiles) { $map[$f.FullName] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash }
    Write-Json $map $frozen
}
Write-RunLog 'check-stub' $verdict
$verdict
if ($verdict -eq 'STUB_HAS_BEHAVIOUR') { $problems }
if ($verdict -eq 'STUB_COMPILE_ERROR') { $compile }
if ($verdict -eq 'VALID_STUB') { "Frozen stub file(s):"; $stubFiles | ForEach-Object { $_.FullName } }
if ($verdict -ne 'VALID_STUB') { exit 1 }
exit 0
