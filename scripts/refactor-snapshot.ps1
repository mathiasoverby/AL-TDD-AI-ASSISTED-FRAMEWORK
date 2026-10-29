<#
.SYNOPSIS  Safety net around the REFACTOR phase: keep the green production code, show what the refactoring changed,
           and roll it back when needed.
.PARAMETER Requirement  Requirement id (R1, ...).
.PARAMETER Action       Snapshot : copy the green production code to .tdd\green-snapshot\ (run before the refactorer)
                        Diff     : write .tdd\<Req>.refactor.diff (green code vs. refactored code)
                        Restore  : put the green code back (run when the refactoring broke the tests)
.DESCRIPTION
  Production files are the *.al files below production_folder of the requirement. Snapshot files get the suffix
  .snapshot: alc.exe compiles every *.al below the project root, so a copy named *.al would give duplicate objects.
#>
param(
    [Parameter(Mandatory)][string]$Requirement,
    [Parameter(Mandatory)][ValidateSet('Snapshot', 'Diff', 'Restore')][string]$Action
)
. "$PSScriptRoot\common.ps1"

$req = Get-Requirement $Requirement
if (-not $req.production_folder) { throw "$Requirement has no production_folder in its front matter." }
$prodDir = Join-Path $RepoRoot $req.production_folder
$snapDir = Join-Path $TddDir 'green-snapshot'

function Get-Rel([string]$Root, [string]$Path) { $Path.Substring($Root.Length).TrimStart('\') }

switch ($Action) {
    'Snapshot' {
        if (Test-Path $snapDir) { Remove-Item $snapDir -Recurse -Force }
        New-Item -ItemType Directory -Force $snapDir | Out-Null
        $files = @(if (Test-Path $prodDir) { Get-ChildItem $prodDir -Recurse -File -Filter *.al })
        if (-not $files.Count) { throw "No production files below $($req.production_folder) to snapshot." }
        foreach ($f in $files) {
            $dest = Join-Path $snapDir ((Get-Rel $prodDir $f.FullName) + '.snapshot')
            New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
            Copy-Item $f.FullName $dest -Force
        }
        Write-RunLog 'refactor-snapshot' "$($files.Count) files"
        "Snapshot of $($files.Count) production file(s) saved in $snapDir"
    }
    'Diff' {
        if (-not (Test-Path $snapDir)) { throw 'No snapshot found. Run -Action Snapshot before the refactorer.' }
        # git diff --no-index needs the original file names, so rebuild the green tree in a temp folder.
        # Both trees go side by side as green\ and refactored\ so the diff shows short relative paths.
        $work = Join-Path $env:TEMP "tdd-diff-$Requirement"
        if (Test-Path $work) { Remove-Item $work -Recurse -Force }
        New-Item -ItemType Directory -Force (Join-Path $work 'green'), (Join-Path $work 'refactored') | Out-Null
        foreach ($s in Get-ChildItem $snapDir -Recurse -File -Filter *.snapshot) {
            $dest = Join-Path $work ('green\' + ((Get-Rel $snapDir $s.FullName) -replace '\.snapshot$', ''))
            New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
            Copy-Item $s.FullName $dest -Force
        }
        if (Test-Path $prodDir) { Copy-Item (Join-Path $prodDir '*') (Join-Path $work 'refactored') -Recurse -Force }
        $diffFile = Join-Path $TddDir "$Requirement.refactor.diff"
        $text = (& git -C $work -c core.autocrlf=false -c core.safecrlf=false -c core.quotepath=false diff --no-index --no-color --stat --patch green refactored 2>$null | Out-String)
        Remove-Item $work -Recurse -Force
        if ([string]::IsNullOrWhiteSpace($text)) { $text = 'The refactorer changed nothing.' }
        Set-Content $diffFile $text -Encoding UTF8
        Write-RunLog 'refactor-diff' (@($text -split "`n" | Where-Object { $_ -match '^[+-][^+-]' }).Count.ToString() + ' changed lines')
        "Diff (green -> refactored) written to $diffFile"
        $text
    }
    'Restore' {
        if (-not (Test-Path $snapDir)) { throw 'No snapshot found. Nothing to restore.' }
        if (Test-Path $prodDir) { Get-ChildItem $prodDir -Recurse -File -Filter *.al | Remove-Item -Force }
        foreach ($s in Get-ChildItem $snapDir -Recurse -File -Filter *.snapshot) {
            $dest = Join-Path $prodDir ((Get-Rel $snapDir $s.FullName) -replace '\.snapshot$', '')
            New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
            Copy-Item $s.FullName $dest -Force
        }
        Write-RunLog 'refactor-restore' 'green code restored'
        "Green production code restored from $snapDir"
    }
}
