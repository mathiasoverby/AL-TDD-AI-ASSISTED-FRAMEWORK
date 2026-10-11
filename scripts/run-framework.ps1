<#
.SYNOPSIS  Run the framework headless for one requirement and capture tokens + wall time (RQ2).
.OUTPUT    runs/<Requirement>/<RunId>/claude-result.json  and  meta.json (start/end/duration)
.NOTE      Pilot first: confirm that the usage block in claude-result.json includes subagent tokens.
#>
param(
    [Parameter(Mandatory)][string]$Requirement,
    [Parameter(Mandatory)][string]$RunId     # e.g. fw-01
)
. "$PSScriptRoot\common.ps1"

$dir = Join-Path $RepoRoot "runs\$Requirement\$RunId"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Remove-Item (Join-Path $TddDir '*') -Recurse -Force -ErrorAction SilentlyContinue   # clean slate

$start = Get-Date
Push-Location $RepoRoot
try {
    claude -p "/tdd $Requirement" --model $Config.Model --output-format json --permission-mode acceptEdits |
        Set-Content (Join-Path $dir 'claude-result.json') -Encoding UTF8
} finally { Pop-Location }
$end = Get-Date

Write-Json ([ordered]@{ requirement = $Requirement; runId = $RunId; start = $start.ToUniversalTime().ToString('o'); end = $end.ToUniversalTime().ToString('o'); seconds = [int]($end - $start).TotalSeconds; model = $Config.Model }) (Join-Path $dir 'meta.json')
Copy-Item (Join-Path $TddDir '*') $dir -Recurse -Force
