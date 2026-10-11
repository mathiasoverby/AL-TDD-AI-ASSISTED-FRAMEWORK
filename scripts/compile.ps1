<#
.SYNOPSIS  Compile the AL app with alc.exe and emit a JSON summary (no Docker needed).
.OUTPUT    .tdd/compile-result.json : { success, appFile, errors[{file,line,code,message}] }
#>
param()
. "$PSScriptRoot\common.ps1"

$app = Get-AppFolder
$alc = $Config.AlcPath
if (-not $alc) {
    $alc = Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Directory -Filter 'ms-dynamics-smb.al-*' |
        Sort-Object { [version](($_.Name -replace '^ms-dynamics-smb\.al-', '') -replace '[^\d\.].*$', '') } -Descending |
        ForEach-Object { Join-Path $_.FullName 'bin\win32\alc.exe' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $alc) {   # older layouts
        $alc = Get-ChildItem "$env:USERPROFILE\.vscode\extensions\ms-dynamics-smb.al-*\bin" -Recurse -Filter alc.exe | Select-Object -Last 1 -ExpandProperty FullName
    }
}
if (-not $alc) { throw 'alc.exe not found. Set AlcPath in scripts\config.psd1.' }

$out = Join-Path $app '.output'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$raw = & $alc "/project:$app" "/packagecachepath:$(Join-Path $app '.alpackages')" "/out:$out" 2>&1 | Out-String

# Diagnostic format: path(line,col): error AL0118: message
$errors = @()
foreach ($m in [regex]::Matches($raw, '(?m)^(?:(?<file>.+?)\((?<line>\d+),\d+\):\s*)?error\s+(?<code>\w+):\s*(?<msg>.*)$')) {
    $line = if ($m.Groups['line'].Success) { [int]$m.Groups['line'].Value } else { 0 }
    $errors += [ordered]@{ file = $m.Groups['file'].Value; line = $line; code = $m.Groups['code'].Value; message = $m.Groups['msg'].Value.Trim() }
}
$appFile = Get-ChildItem $out -Filter *.app -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$success = ($errors.Count -eq 0) -and ($null -ne $appFile)

$result = [ordered]@{ success = $success; appFile = $(if ($appFile) { $appFile.FullName } else { $null }); errors = $errors }
Write-Json $result (Join-Path $TddDir 'compile-result.json')
Write-RunLog 'compile' $(if ($success) { 'OK' } else { 'COMPILE_ERROR' })
$result | ConvertTo-Json -Depth 6
if (-not $success) { exit 1 }
