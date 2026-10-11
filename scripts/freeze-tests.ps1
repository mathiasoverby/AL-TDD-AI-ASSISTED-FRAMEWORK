<#
.SYNOPSIS  Freeze / verify test files so the GREEN phase cannot change them.
.PARAMETER Action  Freeze : hash every test file listed by test_folder globbing (*.Test.al, *Test*.al) -> .tdd/frozen.json
                   Verify : compare current hashes with frozen.json; exit 1 and print TEST_TAMPERED on mismatch
                   Unfreeze : delete frozen.json
#>
param(
    [Parameter(Mandatory)][ValidateSet('Freeze', 'Verify', 'Unfreeze')][string]$Action,
    [string]$TestFolder = ''
)
. "$PSScriptRoot\common.ps1"

$frozen = Join-Path $TddDir 'frozen.json'
if ($Action -eq 'Unfreeze') { Remove-Item $frozen -ErrorAction SilentlyContinue; Write-RunLog 'unfreeze' 'OK'; exit 0 }

if ($Action -eq 'Freeze') {
    $folder = if ($TestFolder) { $TestFolder } else { Get-AppFolder }
    $files = Get-ChildItem $folder -Recurse -Filter *.al | Where-Object { $_.Name -match 'Test' -and $_.FullName -notmatch '\\\.(alpackages|output|tdd)\\' }
    $map = [ordered]@{}
    foreach ($f in $files) { $map[$f.FullName] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash }
    Write-Json $map $frozen
    Write-RunLog 'freeze' "OK:$($files.Count)files"
    "Frozen $($files.Count) test file(s)."; exit 0
}

# Verify
if (-not (Test-Path $frozen)) { throw 'Nothing frozen. Run -Action Freeze first.' }
$saved = Get-Content $frozen -Raw | ConvertFrom-Json
$bad = @()
foreach ($p in $saved.PSObject.Properties) {
    if (-not (Test-Path $p.Name) -or (Get-FileHash $p.Name -Algorithm SHA256).Hash -ne $p.Value) { $bad += $p.Name }
}
if ($bad.Count) { Write-RunLog 'verify-frozen' 'TEST_TAMPERED'; "TEST_TAMPERED:`n$($bad -join "`n")"; exit 1 }
Write-RunLog 'verify-frozen' 'OK'; 'OK: frozen tests unchanged.'
