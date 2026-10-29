<#
.SYNOPSIS  One-time setup: creates the BC container named in config.psd1 (with test toolkit) and syncs app.json.
           Run from an ELEVATED PowerShell. Needs Docker Desktop running in Windows-containers mode.
.PARAMETER Version  BC major version to install (default 28, matches the container name BC28-DK).
.PARAMETER Country  Localisation (default dk).
.NOTES     Credentials: uses $env:BC_USERNAME / $env:BC_PASSWORD, or prompts for them (and sets them for this session).
           Symbols (.alpackages) are NOT downloaded here: in VS Code run "AL: Download Symbols"
           (.vscode/launch.json already points at the container).
#>
param(
    [int]$Version = 28,
    [string]$Country = 'dk'
)
. "$PSScriptRoot\common.ps1"
$name = $Config.ContainerName

# --- preconditions ---------------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this script from an elevated (Administrator) PowerShell.' }

$os = docker version --format '{{.Server.Os}}' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $os) { throw 'Docker daemon not reachable. Start Docker Desktop and wait until it says "running".' }
if ($os -ne 'windows') {
    throw "Docker is in '$os' containers mode. Right-click the Docker tray icon -> 'Switch to Windows containers...', then rerun."
}

Import-Module BcContainerHelper -DisableNameChecking 3>$null 4>$null
Check-BcContainerHelperPermissions -Fix

# --- credentials -----------------------------------------------------------------------------------
if (-not $env:BC_USERNAME -or -not $env:BC_PASSWORD) {
    $c = Get-Credential -Message 'Admin user for the BC container (also used by the framework)' -UserName 'admin'
    $env:BC_USERNAME = $c.UserName
    $env:BC_PASSWORD = $c.GetNetworkCredential().Password
}
$cred = New-Object pscredential($env:BC_USERNAME, (ConvertTo-SecureString $env:BC_PASSWORD -AsPlainText -Force))

# --- container -------------------------------------------------------------------------------------
if (Get-BcContainers | Where-Object { $_ -eq $name }) {
    "Container '$name' already exists - skipping creation."
}
else {
    $artifactUrl = Get-BcArtifactUrl -type Sandbox -country $Country -version $Version -select Latest
    if (-not $artifactUrl) { throw "No sandbox artifact found for BC $Version / $Country." }
    "Creating container '$name' from $artifactUrl (first run downloads several GB, 15-30 min)..."
    New-BcContainer -accept_eula -containerName $name -artifactUrl $artifactUrl `
        -auth UserPassword -Credential $cred `
        -includeTestToolkit -includeTestLibrariesOnly `
        -updateHosts
}

# --- sync app.json with the real container version -------------------------------------------------
$base = Get-BcContainerAppInfo -containerName $name | Where-Object { $_.Name -eq 'Base Application' } | Select-Object -First 1
if ($base) {
    $major = ([version]$base.Version).Major
    $appJsonPath = Join-Path (Get-AppFolder) 'app.json'
    $app = Get-Content $appJsonPath -Raw | ConvertFrom-Json
    $app.platform = "$major.0.0.0"
    $app.application = "$major.0.0.0"
    $app.runtime = "$($major - 11).0"
    foreach ($d in $app.dependencies) { $d.version = "$major.0.0.0" }
    $app | ConvertTo-Json -Depth 8 | Set-Content $appJsonPath -Encoding UTF8
    "app.json set to BC $major (runtime $($major - 11).0)."
}
else { Write-Warning 'Could not read Base Application version from the container; check app.json manually.' }

@"

Done. Next:
  1. VS Code: open this folder, run 'AL: Download Symbols' (F1) -> fills .alpackages.
  2. In the terminal you start Claude Code from, set (container password is the one you just chose):
       `$env:BC_USERNAME = '$($env:BC_USERNAME)'
       `$env:BC_PASSWORD = '<password>'
  3. Claude Code, repo root:  /tdd R1
"@
