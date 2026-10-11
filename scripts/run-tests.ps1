<#
.SYNOPSIS  Compile, publish to the BC container and run the requirement's test codeunit.
.PARAMETER Requirement  Requirement id (R1, R2, ...). Front matter must define test_codeunit_id.
.PARAMETER Phase        red | green
.OUTPUT    .tdd/<Requirement>.<Phase>.result.json
           { phase, compiled, discovered, total, passed, failed, failures[{name,message}], compileErrors[] }
#>
param(
    [Parameter(Mandatory)][string]$Requirement,
    [Parameter(Mandatory)][ValidateSet('red', 'green')][string]$Phase
)
. "$PSScriptRoot\common.ps1"

$req = Get-Requirement $Requirement
$resultPath = Join-Path $TddDir "$Requirement.$Phase.result.json"
$result = [ordered]@{ phase = $Phase; compiled = $false; discovered = $false; total = 0; passed = 0; failed = 0; failures = @(); compileErrors = @() }

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

Publish-BcContainerApp -containerName $Config.ContainerName -appFile $c.appFile -skipVerification `
    -sync -install -upgrade -syncMode ForceSync -tenant $Config.Tenant -credential $cred | Out-Null

$xunit = Join-Path $TddDir "$Requirement.$Phase.xunit.xml"
if (Test-Path $xunit) { Remove-Item $xunit }
Run-TestsInBcContainer -containerName $Config.ContainerName -credential $cred -tenant $Config.Tenant `
    -testCodeunit $req.test_codeunit_id -XUnitResultFileName $xunit -detailed | Out-Null

# 3. parse XUnit
if (Test-Path $xunit) {
    [xml]$x = Get-Content $xunit
    foreach ($t in $x.SelectNodes('//test')) {
        $result.total++
        if ($t.result -eq 'Pass') { $result.passed++ }
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
