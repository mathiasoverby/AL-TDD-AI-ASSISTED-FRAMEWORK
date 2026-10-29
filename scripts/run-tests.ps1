<#
.SYNOPSIS  Compile, publish to the BC container and run the requirement's test codeunit.
.PARAMETER Requirement  Requirement id (R1, R2, ...). Front matter must define test_codeunit_id.
.PARAMETER Phase        red | green
.OUTPUT    .tdd/<Requirement>.<Phase>.result.json
           { phase, compiled, discovered, total, passed, failed, passedTests[], failures[{name,message}], compileErrors[] }
#>
param(
    [Parameter(Mandatory)][string]$Requirement,
    [Parameter(Mandatory)][ValidateSet('red', 'green')][string]$Phase
)
. "$PSScriptRoot\common.ps1"

$req = Get-Requirement $Requirement
$resultPath = Join-Path $TddDir "$Requirement.$Phase.result.json"
Remove-Item $resultPath -ErrorAction SilentlyContinue   # never let classify-red read a stale result if this run aborts
$result = [ordered]@{ phase = $Phase; compiled = $false; discovered = $false; total = 0; passed = 0; failed = 0; passedTests = @(); failures = @(); compileErrors = @() }

# 1. compile
& "$PSScriptRoot\compile.ps1" | Out-Null
$c = Get-Content (Join-Path $TddDir 'compile-result.json') -Raw | ConvertFrom-Json
if (-not $c.success) {
    $result.compileErrors = @($c.errors)
    Write-Json $result $resultPath; Write-RunLog "run-tests.$Phase" 'COMPILE_ERROR'
    $result | ConvertTo-Json -Depth 6; exit 1
}
$result.compiled = $true

# 2. publish + run (BcContainerHelper)
if (-not $env:BC_USERNAME -or -not $env:BC_PASSWORD) { throw 'Set $env:BC_USERNAME and $env:BC_PASSWORD for the BC container.' }
Import-Module BcContainerHelper -DisableNameChecking 3>$null 4>$null
$cred = New-Object pscredential($env:BC_USERNAME, (ConvertTo-SecureString $env:BC_PASSWORD -AsPlainText -Force))

# The app version stays 1.0.0.0 between runs, and BC refuses to publish the same id+version twice (also when it was
# published from VS Code). Remove any existing copy first; test data is throwaway.
$appJson = Get-Content (Join-Path (Get-AppFolder) 'app.json') -Raw | ConvertFrom-Json
Get-BcContainerAppInfo -containerName $Config.ContainerName -tenantSpecificProperties 3>$null |
    Where-Object { $_.AppId -eq $appJson.id } | ForEach-Object {
        Unpublish-BcContainerApp -containerName $Config.ContainerName -name $_.Name -publisher $_.Publisher `
            -version $_.Version -tenant $Config.Tenant -unInstall -doNotSaveData -force 3>$null | Out-Null
    }

# Publish through the dev endpoint, like VS Code (F5 / AL Test Runner). Other scopes (global, per-tenant) cannot be
# overwritten by VS Code later: "already deployed as a global application or a per tenant application".
Publish-BcContainerApp -containerName $Config.ContainerName -appFile $c.appFile -skipVerification -useDevEndpoint `
    -syncMode ForceSync -tenant $Config.Tenant -credential $cred | Out-Null

# The XUnit file must be written to a folder shared with the container (not the repo folder), then copied to .tdd.
$xunit = Join-Path $TddDir "$Requirement.$Phase.xunit.xml"
$sharedDir = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$($Config.ContainerName)"
$sharedXunit = Join-Path $sharedDir "$Requirement.$Phase.xunit.xml"
foreach ($p in $xunit, $sharedXunit) { if (Test-Path $p) { Remove-Item $p } }
Run-TestsInBcContainer -containerName $Config.ContainerName -credential $cred -tenant $Config.Tenant `
    -testCodeunitRange $req.test_codeunit_id -testCodeunit $req.test_codeunit_id `
    -XUnitResultFileName $sharedXunit -detailed | Out-Null
if (Test-Path $sharedXunit) { Copy-Item $sharedXunit $xunit -Force }

# Also publish the result where the VS Code extension "AL Test Runner" looks for it (.altestrunner\Results\<id> <name>.xml,
# a bare <assembly> element), so its test tree shows the same pass/fail marks as this run. Only touches the folder
# when the extension has created it; the result is a convenience for the human, scripts never read it.
$atrResults = Join-Path $RepoRoot '.altestrunner\Results'
if ((Test-Path $xunit) -and (Test-Path (Split-Path $atrResults))) {
    [xml]$xr = Get-Content $xunit
    New-Item -ItemType Directory -Force $atrResults | Out-Null
    foreach ($asm in $xr.SelectNodes('//assembly')) {
        [System.IO.File]::WriteAllText((Join-Path $atrResults "$($asm.name).xml"), $asm.OuterXml, (New-Object System.Text.UTF8Encoding($false)))
    }
}

# 3. parse XUnit
if (Test-Path $xunit) {
    [xml]$x = Get-Content $xunit
    foreach ($t in $x.SelectNodes('//test')) {
        $result.total++
        if ($t.result -eq 'Pass') { $result.passed++; $result.passedTests += $t.name }
        else {
            $result.failed++
            $msg = if ($t.failure) { $t.failure.InnerText } else { '' }
            $result.failures += [ordered]@{ name = $t.name; message = ($msg -replace '\s+', ' ').Trim() }
        }
    }
    $result.discovered = $result.total -gt 0
}

Write-Json $result $resultPath
Write-RunLog "run-tests.$Phase" $(if ($result.discovered -and $result.failed -eq 0) { 'ALL_PASS' } elseif ($result.discovered) { 'FAILURES' } else { 'NOT_DISCOVERED' })
$result | ConvertTo-Json -Depth 6
