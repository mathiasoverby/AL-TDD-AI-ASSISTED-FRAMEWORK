<#
.SYNOPSIS  Reset a requirement to its pre-run state so /tdd can be run again from scratch.
           Nothing is lost: the previous run is first copied to .tdd-archive\<requirement>\<timestamp>\ (created only
           when there is something to archive; one folder per requirement, one subfolder per run).
.PARAMETER Requirement  Requirement id (R1, ...).
.DESCRIPTION
  Uses these front-matter keys of requirements\<Requirement>.md:
    test_folder        tests of this requirement (*Test*.al below it are archived and deleted)
    production_folder  production code of this requirement (*.al below it are archived and deleted)
  and, when present, stubs\<Requirement>\ : every file ending in .stub is restored to the same path under the repo
  root without the .stub suffix (for `stub: provided` requirements, where a human supplies the stub).
  Also clears .tdd\ (archived first) and .output\.
  Archived AL files get the suffix .archived: the archive lives inside the project, and alc.exe / the AL extension
  compile every *.al below the project root (duplicate object ids otherwise).
  Use -WhatIf to see what would happen.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Requirement)
. "$PSScriptRoot\common.ps1"

$req = Get-Requirement $Requirement
$stubRoot = Join-Path $RepoRoot "stubs\$Requirement"
$stubs = @(if (Test-Path $stubRoot) { Get-ChildItem $stubRoot -Recurse -File -Filter '*.stub' })

function Get-AlFiles([string]$RelFolder, [string]$NameLike) {
    if (-not $RelFolder) { return @() }
    $dir = Join-Path $RepoRoot $RelFolder
    @(if (Test-Path $dir) { Get-ChildItem $dir -Recurse -File -Filter *.al | Where-Object { $_.Name -like $NameLike } })
}
$testFiles = Get-AlFiles $req.test_folder '*Test*'
$prodFiles = Get-AlFiles $req.production_folder '*'
if (-not $stubs.Count -and -not $prodFiles.Count -and -not $testFiles.Count -and -not (Test-Path $TddDir)) {
    throw "Nothing to reset for $Requirement (no stubs\$Requirement, no files in test_folder/production_folder)."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$archive = Join-Path $RepoRoot ".tdd-archive\$Requirement\$stamp"
# Archive only when there is something to keep: files of this requirement or a non-empty .tdd (common.ps1 always creates it).
$hasTddContent = (Test-Path $TddDir) -and [bool](Get-ChildItem $TddDir -Force | Select-Object -First 1)
$hasContent = $testFiles.Count -or $prodFiles.Count -or $hasTddContent

function Save-ToArchive([System.IO.FileInfo]$File) {
    $rel = $File.FullName.Substring($RepoRoot.Length).TrimStart('\')
    $dest = Join-Path $archive "$rel.archived"
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Copy-Item $File.FullName $dest -Force
}

if ($hasContent -and $PSCmdlet.ShouldProcess($archive, 'archive previous run (.tdd, tests, production files)')) {
    New-Item -ItemType Directory -Force $archive | Out-Null
    if (Test-Path $TddDir) { Copy-Item $TddDir (Join-Path $archive '.tdd') -Recurse -Force }
    foreach ($f in @($testFiles) + @($prodFiles)) { Save-ToArchive $f }
    foreach ($s in $stubs) {
        $dest = Join-Path $RepoRoot ($s.FullName.Substring($stubRoot.Length).TrimStart('\') -replace '\.stub$', '')
        if ((Test-Path $dest) -and ($prodFiles.FullName -notcontains $dest)) { Save-ToArchive (Get-Item $dest) }
    }
}

foreach ($f in @($testFiles) + @($prodFiles)) {
    if ($PSCmdlet.ShouldProcess($f.FullName, 'delete')) { Remove-Item $f.FullName -Force }
}

foreach ($s in $stubs) {
    $dest = Join-Path $RepoRoot ($s.FullName.Substring($stubRoot.Length).TrimStart('\') -replace '\.stub$', '')
    if ($PSCmdlet.ShouldProcess($dest, 'restore stub')) {
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Copy-Item $s.FullName $dest -Force
    }
}

foreach ($d in $TddDir, (Join-Path (Get-AppFolder) '.output')) {
    if ((Test-Path $d) -and $PSCmdlet.ShouldProcess($d, 'clear')) { Get-ChildItem $d -Force | Remove-Item -Recurse -Force }
}

if (-not $WhatIfPreference) {
    if ($hasContent) { "Reset $Requirement. Previous run archived in $archive" } else { "Reset $Requirement. Nothing to archive." }
}
