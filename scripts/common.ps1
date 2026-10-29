# Shared helpers, dot-sourced by the other scripts.
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Config   = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
$script:TddDir   = Join-Path $RepoRoot '.tdd'
New-Item -ItemType Directory -Force -Path $TddDir | Out-Null

# Fallback for container credentials when the environment variables are not set: scripts\local.credentials.psd1
# (git-ignored), e.g. @{ BC_USERNAME = 'user'; BC_PASSWORD = 'secret' }
$credFile = Join-Path $PSScriptRoot 'local.credentials.psd1'
if ((-not $env:BC_USERNAME -or -not $env:BC_PASSWORD) -and (Test-Path $credFile)) {
    $c = Import-PowerShellDataFile $credFile
    if (-not $env:BC_USERNAME) { $env:BC_USERNAME = $c.BC_USERNAME }
    if (-not $env:BC_PASSWORD) { $env:BC_PASSWORD = $c.BC_PASSWORD }
}

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
