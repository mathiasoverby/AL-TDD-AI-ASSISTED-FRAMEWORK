# Shared helpers, dot-sourced by the other scripts.
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Config   = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
$script:TddDir   = Join-Path $RepoRoot '.tdd'
New-Item -ItemType Directory -Force -Path $TddDir | Out-Null

function Get-AppFolder { (Resolve-Path (Join-Path $RepoRoot $Config.AppFolder)).Path }

function Get-Requirement([string]$Id) {
    # Minimal front-matter parser: "key: value" lines between the first two '---' lines.
    $path = Join-Path $RepoRoot "requirements\$Id.md"
    if (-not (Test-Path $path)) { throw "Requirement file not found: $path" }
    $lines = Get-Content $path
    $meta = @{}
    $inside = $false
    foreach ($l in $lines) {
        if ($l.Trim() -eq '---') { if ($inside) { break } else { $inside = $true; continue } }
        if ($inside -and $l -match '^\s*([A-Za-z_]+)\s*:\s*(.*?)\s*$') { $meta[$Matches[1]] = $Matches[2].Trim('"', "'") }
    }
    $meta
}

function Write-Json($Object, [string]$Path) {
    $Object | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
}

function Write-RunLog([string]$Step, [string]$Verdict, [int]$Round = 0) {
    $entry = [ordered]@{ ts = (Get-Date).ToUniversalTime().ToString('o'); step = $Step; round = $Round; verdict = $Verdict }
    Add-Content -Path (Join-Path $TddDir 'run-log.jsonl') -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
}
