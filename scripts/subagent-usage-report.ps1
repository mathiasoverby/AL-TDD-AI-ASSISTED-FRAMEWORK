<#
  subagent-usage-report.ps1 - actual token usage of the subagents one skill run spawned, read from
  Claude Code's own transcripts. Without -PdfPath it prints the chat table; with -PdfPath it writes
  an HTML cost report next to the PDF and prints it to PDF with headless Edge (or Chrome).

  Transcripts (this session only):
    <config>\projects\<project>\<session>\subagents\agent-<id>.jsonl                   Agent tool
    <config>\projects\<project>\<session>\subagents\workflows\<wf-id>\agent-<id>.jsonl  Workflow tool
  Beside each: agent-<id>.meta.json with agentType + description (Agent description / Workflow label).
#>
param(
    [Parameter(Mandatory)] [string] $StartFile,         # written just before the agents were spawned
    [string[]] $AgentTypes = @(),                       # agentType(s) as in .meta.json; empty = every subagent
    [string]   $GroupRegex = ('^(?<group>.+?)\s+' + [char]0x00B7),   # group key = label text before the middle dot
    [string]   $Title      = 'Subagent Cost Report',
    [string]   $Subtitle   = '',                        # e.g. 'App: Core'
    [int]      $UnitCount  = 0,                         # optional: work units done (entries, files, ...)
    [string]   $UnitLabel  = 'items processed',
    [string]   $PdfPath    = '',
    [string]   $SessionId  = $env:CLAUDE_CODE_SESSION_ID
)

# Anthropic API list prices in USD per million tokens, copied from
# https://platform.claude.com/docs/en/about-claude/pricing (checked 2026-10-07).
# Cache reads are not the same share of input on every model - copy every column from the page.
$PriceDate = '2026-10-07'
$Prices = [ordered]@{
    'claude-fable-5-1'  = @{ name = 'Claude Fable 5.1';  input = 10; w5m = 12.50; w1h = 20; read = 0.25; output = 50 }
    'claude-fable-5'    = @{ name = 'Claude Fable 5';    input = 10; w5m = 12.50; w1h = 20; read = 1.00; output = 50 }
    'claude-opus-5-5'   = @{ name = 'Claude Opus 5.5';   input = 4;  w5m = 5.00;  w1h = 8;  read = 0.20; output = 20 }
    'claude-opus-5'     = @{ name = 'Claude Opus 5';     input = 5;  w5m = 6.25;  w1h = 10; read = 0.50; output = 25 }
    'claude-opus-4-8'   = @{ name = 'Claude Opus 4.8';   input = 5;  w5m = 6.25;  w1h = 10; read = 0.50; output = 25 }
    'claude-opus-4-7'   = @{ name = 'Claude Opus 4.7';   input = 5;  w5m = 6.25;  w1h = 10; read = 0.50; output = 25 }
    'claude-opus-4-6'   = @{ name = 'Claude Opus 4.6';   input = 5;  w5m = 6.25;  w1h = 10; read = 0.50; output = 25 }
    'claude-opus-4-5'   = @{ name = 'Claude Opus 4.5';   input = 5;  w5m = 6.25;  w1h = 10; read = 0.50; output = 25 }
    'claude-sonnet-5-5' = @{ name = 'Claude Sonnet 5.5'; input = 2;  w5m = 2.50;  w1h = 4;  read = 0.20; output = 10 }
    'claude-sonnet-5'   = @{ name = 'Claude Sonnet 5';   input = 2;  w5m = 2.50;  w1h = 4;  read = 0.20; output = 10 }
    'claude-sonnet-4-6' = @{ name = 'Claude Sonnet 4.6'; input = 3;  w5m = 3.75;  w1h = 6;  read = 0.30; output = 15 }
    'claude-sonnet-4-5' = @{ name = 'Claude Sonnet 4.5'; input = 3;  w5m = 3.75;  w1h = 6;  read = 0.30; output = 15 }
    'claude-haiku-4-5'  = @{ name = 'Claude Haiku 4.5';  input = 1;  w5m = 1.25;  w1h = 2;  read = 0.10; output = 5 }
}
$inv    = [Globalization.CultureInfo]::InvariantCulture   # never the machine culture (da-DK prints 1.298 / 0,2870)
$fields = 'input', 'w5m', 'w1h', 'read', 'output'

# --- 1. This run's agents -----------------------------------------------------------------------
if (-not (Test-Path $StartFile)) { Write-Warning "Start-time file not found: $StartFile"; return }
$base = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$subagentDir = Get-ChildItem (Join-Path $base "projects") -Directory |
    ForEach-Object { Join-Path $_.FullName "$SessionId\subagents" } |
    Where-Object { $SessionId -and (Test-Path $_) } |
    Select-Object -First 1
if (-not $subagentDir) { Write-Warning "No subagent transcripts found for session '$SessionId'."; return }
$startUtc  = [DateTimeOffset]::Parse((Get-Content $StartFile -Raw).Trim(), $inv).UtcDateTime
$metaFiles = Get-ChildItem $subagentDir -Filter "agent-*.meta.json" -Recurse |
    Where-Object { $_.CreationTimeUtc -ge $startUtc } |
    Sort-Object CreationTimeUtc

# --- 2. Usage per agent: every API call once, priced by the model that served it ---------------
$priceOf = @{}
$agents  = [System.Collections.Generic.List[object]]::new()
foreach ($metaFile in $metaFiles) {
    $meta = Get-Content $metaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($AgentTypes.Count -and $meta.agentType -notin $AgentTypes) { continue }
    $label = if ($meta.description) { [string]$meta.description } else { $metaFile.Name -replace '\.meta\.json$', '' }
    $a = [ordered]@{ group = "(unmatched) $label"; label = $label; calls = 0; unpriced = 0; models = @{}; flag = $false }
    if ($meta.description -match $GroupRegex -and $Matches['group']) { $a.group = $Matches['group'] }
    foreach ($f in $fields) { $a[$f] = [int64]0; $a["c_$f"] = 0.0 }

    # One API call is logged as several lines (one per thinking/text/tool_use block) and every line
    # repeats that call's usage. Count each call once: key on message.id + requestId, take the input
    # figures once and keep the highest output_tokens (earlier lines carry a partial count).
    $calls = [ordered]@{}
    foreach ($line in [System.IO.File]::ReadLines(($metaFile.FullName -replace '\.meta\.json$', '.jsonl'))) {
        if ($line -notmatch '"usage"') { continue }
        try { $rec = $line | ConvertFrom-Json } catch { continue }
        $u = $rec.message.usage
        if (-not $u) { continue }
        $key = "$($rec.message.id)|$($rec.requestId)"
        if (-not $calls.Contains($key)) {
            $w1h = [int64]$u.cache_creation.ephemeral_1h_input_tokens   # cache writes are priced by TTL
            $calls[$key] = @{
                model  = [string]$rec.message.model
                input  = [int64]$u.input_tokens
                w5m    = [int64]$u.cache_creation_input_tokens - $w1h
                w1h    = $w1h
                read   = [int64]$u.cache_read_input_tokens
                output = [int64]0
                # Fast mode bills 2x and US-only inference 1.1x, on every token class.
                mult   = $(if ($u.speed -eq 'fast') { 2.0 } else { 1.0 }) * $(if ($u.inference_geo -eq 'us') { 1.1 } else { 1.0 })
            }
        }
        $calls[$key].output = [Math]::Max($calls[$key].output, [int64]$u.output_tokens)
    }

    foreach ($c in $calls.Values) {
        if (($c.input + $c.w5m + $c.w1h + $c.read + $c.output) -eq 0) { continue }   # <synthetic> turns
        $a.calls++
        $a.models[$c.model] = $true
        foreach ($f in $fields) { $a[$f] += $c[$f] }
        if (-not $priceOf.ContainsKey($c.model)) {
            $k = $Prices.Keys | Where-Object { $c.model -like "*$_*" } | Sort-Object Length -Descending | Select-Object -First 1
            $priceOf[$c.model] = if ($k) { $Prices[$k] } else { $null }
        }
        $p = $priceOf[$c.model]
        if (-not $p) { $a.unpriced++; continue }
        foreach ($f in $fields) { $a["c_$f"] += $c[$f] * $p[$f] * $c.mult / 1e6 }
    }
    $a.tokIn = $a.input + $a.w5m + $a.w1h + $a.read
    $a.cost  = $a.c_input + $a.c_w5m + $a.c_w1h + $a.c_read + $a.c_output
    $agents.Add($a)
}
if (-not $agents.Count) { Write-Warning "No matching subagents started after $($startUtc.ToString('o'))."; return }

$sum = {
    param($items)
    $t = [ordered]@{ agents = @($items).Count; calls = 0; unpriced = 0 }
    foreach ($f in $fields) { $t[$f] = [int64]0; $t["c_$f"] = 0.0 }
    foreach ($i in $items) { foreach ($k in @($t.Keys)) { if ($k -ne 'agents') { $t[$k] += $i[$k] } } }
    $t.tokIn = $t.input + $t.w5m + $t.w1h + $t.read
    $t.cost  = $t.c_input + $t.c_w5m + $t.c_w1h + $t.c_read + $t.c_output
    $t
}
$groups = [ordered]@{}
foreach ($g in @($agents | ForEach-Object { $_.group } | Select-Object -Unique)) {
    $groups[$g] = & $sum @($agents | Where-Object { $_.group -eq $g })
}
$total    = & $sum $agents
$unpriced = @($priceOf.Keys | Where-Object { -not $priceOf[$_] })

# --- 3. Chat table (default) ---------------------------------------------------------------------
if (-not $PdfPath) {
    $k    = { param($n) "$([math]::Round($n / 1000))k" }
    $row  = { param($name, $g) " {0,-20} {1,6} {2,7}   {3}" -f $name, $g.agents, $g.calls, "$(& $k $g.tokIn) / $(& $k $g.output) / $(& $k ($g.tokIn + $g.output))" }
    $line = ([string][char]0x2500) * 72
    "Subagent token usage"; $line
    " {0,-20} {1,6} {2,7}   {3}" -f "Group", "Agents", "Calls", "Tokens (in / out / total)"; $line
    foreach ($name in $groups.Keys) { & $row $name $groups[$name] }
    $line; & $row "TOTAL" $total; $line
    $usdTotal = '$' + $total.cost.ToString('N4', $inv)
    "in = input + cache writes + cache reads; cache reads are $([math]::Round(100 * $total.read / [math]::Max(1, $total.tokIn)))% of in."
    "API list-price equivalent: $usdTotal (prices checked $PriceDate)."
    if ($unpriced.Count) { Write-Warning "No price for $($unpriced -join ', ') - those calls are left out of the USD figure. Add the model to `$Prices." }
    return
}

# --- 4. PDF report (-PdfPath) ----------------------------------------------------------------------
$PdfPath  = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PdfPath)
$htmlPath = [IO.Path]::ChangeExtension($PdfPath, '.html')
New-Item -ItemType Directory -Force (Split-Path $PdfPath) | Out-Null

# Money is always built with '$' in single quotes: inside "..." PowerShell would read $1 / $0 as variables.
$e   = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
$n0  = { param($x) ([double]$x).ToString('N0', $inv) }
$usd = { param($x, $d = 4) '$' + ([double]$x).ToString("N$d", $inv) }
$pc  = { param($x, $of) if ($of) { (100.0 * $x / $of).ToString('0.0', $inv) + '%' } else { '-' } }

$modelIds  = @($agents | ForEach-Object { $_.models.Keys } | Sort-Object -Unique)
$modelName = { param($m) if ($priceOf[$m]) { $priceOf[$m].name } else { $m } }
$show1h    = $total.w1h -gt 0
$showModel = $modelIds.Count -gt 1

# Looped agents: at least twice the median number of API calls.
$cs     = @($agents | Where-Object { $_.calls -gt 0 } | ForEach-Object { $_.calls } | Sort-Object)
$median = if (-not $cs.Count) { 0 } elseif ($cs.Count % 2) { $cs[($cs.Count - 1) / 2] } else { ($cs[$cs.Count / 2 - 1] + $cs[$cs.Count / 2]) / 2 }
foreach ($a in $agents) { $a.flag = ($median -gt 0 -and $a.calls -ge 2 * $median) }
$flagged = @($agents | Where-Object { $_.flag })
$badge   = ' <span class="badge">&#x27F3; looped</span>'

$css = @'
@page { size: A4; margin: 14mm 12mm; }
* { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { font-family: system-ui, "Segoe UI", sans-serif; color: #1f2933; font-size: 10pt; margin: 0; }
h1 { color: #12305a; font-size: 19pt; margin: 0 0 4px; }
.sub { color: #52606d; font-size: 9pt; margin: 0 0 12px; }
.tiles { display: flex; gap: 10px; margin: 0 0 14px; }
.tile { flex: 1; background: #12305a; color: #fff; border-radius: 6px; padding: 10px 14px; }
.tile .v { font-size: 17pt; font-weight: 600; line-height: 1.2; }
.tile .l { font-size: 8.5pt; color: #d9e2ec; }
h2 { color: #12305a; font-size: 12.5pt; margin: 18px 0 6px; padding-bottom: 3px; border-bottom: 2px solid #d9e2ec; break-after: avoid; }
p.note { color: #52606d; font-size: 8.5pt; margin: 0 0 6px; }
table { width: 100%; border-collapse: collapse; font-size: 8.5pt; }
thead { display: table-header-group; }
tr { break-inside: avoid; }
th { background: #12305a; color: #fff; font-weight: 600; text-align: left; padding: 5px 6px; border: 1px solid #12305a; }
td { padding: 4px 6px; border: 1px solid #d9e2ec; }
.n { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
.id { color: #7b8794; font-size: 7.5pt; }
.nw { white-space: nowrap; }
tr.flag td { background: #fff3dc; }
tr.total td { background: #eef2f7; font-weight: 600; }
tr.sub td { background: #f5f7fa; color: #3e4c59; font-weight: 600; }
.keep { break-inside: avoid; }
.badge { color: #8a5300; font-weight: 600; white-space: nowrap; }
.warn { color: #9b1c1c; font-weight: 600; }
.takeaway { margin-top: 14px; padding: 8px 12px; border-left: 4px solid #12305a; background: #f5f7fa; font-size: 9pt; break-inside: avoid; }
.takeaway p { margin: 3px 0; }
.foot { margin-top: 16px; padding-top: 6px; border-top: 1px solid #d9e2ec; color: #7b8794; font-size: 7.5pt; }
'@

$o = [System.Collections.Generic.List[string]]::new()
$o.Add("<!doctype html><html lang=""en""><head><meta charset=""utf-8""><title>$(& $e $Title)</title><style>$css</style></head><body>")
$o.Add("<h1>$(& $e $Title)</h1>")
$sub = @()
if ($Subtitle) { $sub += & $e $Subtitle }
$sub += 'Groups: ' + (& $e ($groups.Keys -join ', '))
$sub += $(if ($modelIds.Count -gt 1) { 'Models: ' } else { 'Model: ' }) + (& $e (($modelIds | ForEach-Object { if ($priceOf[$_]) { "$($priceOf[$_].name) ($_)" } else { $_ } }) -join ', '))
$sub += 'Generated: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm', $inv)
$o.Add("<p class=""sub"">$($sub -join ' &bull; ')</p>")

# KPI tiles
$tiles = @()
if ($UnitCount -gt 0) { $tiles += , @((& $n0 $UnitCount), $UnitLabel) }
$tiles += , @((& $n0 $total.agents), 'subagents')
$tiles += , @((& $n0 $total.calls), 'API calls')
$tiles += , @((& $usd $total.cost $(if ($total.cost -ge 10) { 2 } else { 4 })), 'API cost (USD)')
$o.Add('<div class="tiles">' + (($tiles | ForEach-Object { "<div class=""tile""><div class=""v"">$(& $e $_[0])</div><div class=""l"">$(& $e $_[1])</div></div>" }) -join '') + '</div>')

# 1 - Prices used
$o.Add('<section class="keep"><h2>1 &mdash; Prices used</h2>')
$ratios = foreach ($m in $modelIds) {
    $p = $priceOf[$m]
    if ($p) { "$(& $e $p.name): a 5-minute cache write costs $(($p.w5m / $p.read).ToString('0.#', $inv))&times; a cache read; output costs $(($p.output / $p.input).ToString('0.#', $inv))&times; input." }
}
$o.Add("<p class=""note"">Anthropic API list prices in USD per million tokens, checked $PriceDate. Every API call is priced by the model that served it, and cache writes at the TTL the transcript records. $($ratios -join ' ')</p>")
$o.Add('<table><thead><tr><th>Model</th><th class="n">Input</th><th class="n">Cache write 5m</th><th class="n">Cache write 1h</th><th class="n">Cache read</th><th class="n">Output</th></tr></thead><tbody>')
foreach ($m in $modelIds) {
    $p = $priceOf[$m]
    if ($p) { $o.Add("<tr><td>$(& $e $p.name) <span class=""id"">$(& $e $m)</span></td>" + (($fields | ForEach-Object { "<td class=""n"">$(& $usd $p[$_] 2)</td>" }) -join '') + '</tr>') }
    else    { $o.Add("<tr><td>$(& $e $m)</td><td colspan=""5"" class=""warn"">No price in the script &mdash; its calls are left out of every USD figure.</td></tr>") }
}
$o.Add('</tbody></table></section>')

# 2 - Per-agent breakdown
$o.Add('<h2>2 &mdash; Per-agent breakdown</h2>')
$o.Add('<p class="note">' + $(if ($flagged.Count) { "Rows marked$badge made at least twice the median number of API calls (median: $median). Every extra call re-sends the agent's whole context." } else { "No agent made twice the median number of API calls (median: $median)." }) + ' Token columns are counts; the last column is the cost of all of them.</p>')
$o.Add('<table><thead><tr><th>Group</th><th>Agent</th>' + $(if ($showModel) { '<th>Model</th>' }) +
       '<th class="n">Calls</th><th class="n">' + $(if ($show1h) { 'Cache write 5m</th><th class="n">Cache write 1h' } else { 'Cache write' }) +
       '</th><th class="n">Cache read</th><th class="n">Input</th><th class="n">Output</th><th class="n">Cost (USD)</th></tr></thead><tbody>')
$tokCells = { param($x) "<td class=""n"">$(& $n0 $x.w5m)</td>" + $(if ($show1h) { "<td class=""n"">$(& $n0 $x.w1h)</td>" }) + "<td class=""n"">$(& $n0 $x.read)</td><td class=""n"">$(& $n0 $x.input)</td><td class=""n"">$(& $n0 $x.output)</td>" }
$span     = if ($showModel) { 3 } else { 2 }
$natural  = { [regex]::Replace($_.label, '\d+', { param($m) $m.Value.PadLeft(8, '0') }) }   # batch-2 before batch-10
foreach ($g in $groups.Keys) {
    foreach ($a in @($agents | Where-Object { $_.group -eq $g } | Sort-Object $natural)) {
        $o.Add($(if ($a.flag) { '<tr class="flag">' } else { '<tr>' }) +
               "<td>$(& $e $a.group)</td><td>$(& $e $a.label)$(if ($a.flag) { $badge })</td>" +
               $(if ($showModel) { "<td class=""nw"">$(& $e (($a.models.Keys | ForEach-Object { & $modelName $_ }) -join ', '))</td>" }) +
               "<td class=""n"">$($a.calls)</td>" + (& $tokCells $a) +
               "<td class=""n"">$(& $usd $a.cost)$(if ($a.unpriced) { ' <span class="warn">*</span>' })</td></tr>")
    }
    if ($groups.Count -gt 1) {
        $x = $groups[$g]
        $o.Add("<tr class=""sub""><td colspan=""$span"">$(& $e $g) subtotal &mdash; $($x.agents) agents</td><td class=""n"">$($x.calls)</td>" + (& $tokCells $x) + "<td class=""n"">$(& $usd $x.cost)</td></tr>")
    }
}
$o.Add("<tr class=""total""><td colspan=""$span"">TOTAL &mdash; $($total.agents) agents</td><td class=""n"">$($total.calls)</td>" + (& $tokCells $total) + "<td class=""n"">$(& $usd $total.cost)</td></tr>")
$o.Add('</tbody></table>')

# 3 - Per-group totals (USD)
$o.Add('<section class="keep"><h2>3 &mdash; Per-group totals (USD)</h2>')
$o.Add('<table><thead><tr><th>Group</th><th class="n">Agents</th><th class="n">Calls</th><th class="n">Cache write</th><th class="n">Cache read</th><th class="n">Input</th><th class="n">Output</th><th class="n">Total</th><th class="n">Share</th></tr></thead><tbody>')
$usdCells = { param($x) "<td class=""n"">$($x.agents)</td><td class=""n"">$($x.calls)</td><td class=""n"">$(& $usd ($x.c_w5m + $x.c_w1h))</td><td class=""n"">$(& $usd $x.c_read)</td><td class=""n"">$(& $usd $x.c_input)</td><td class=""n"">$(& $usd $x.c_output)</td><td class=""n"">$(& $usd $x.cost)</td><td class=""n"">$(& $pc $x.cost $total.cost)</td>" }
foreach ($g in $groups.Keys) { $o.Add("<tr><td>$(& $e $g)</td>" + (& $usdCells $groups[$g]) + '</tr>') }
$o.Add('<tr class="total"><td>GRAND TOTAL</td>' + (& $usdCells $total) + '</tr></tbody></table></section>')

# 4 - Cost by token class
$o.Add('<section class="keep"><h2>4 &mdash; Cost by token class</h2>')
$single  = if ($modelIds.Count -eq 1) { $priceOf[$modelIds[0]] } else { $null }
$classes = @(
    @{ name = 'Cache write (5-minute)'; f = 'w5m';    tok = $total.w5m;    cost = $total.c_w5m }
    @{ name = 'Cache write (1-hour)';   f = 'w1h';    tok = $total.w1h;    cost = $total.c_w1h }
    @{ name = 'Cache read';             f = 'read';   tok = $total.read;   cost = $total.c_read }
    @{ name = 'Output';                 f = 'output'; tok = $total.output; cost = $total.c_output }
    @{ name = 'Input (uncached)';       f = 'input';  tok = $total.input;  cost = $total.c_input }
) | Where-Object { $_.f -ne 'w1h' -or $_.tok -gt 0 } | Sort-Object { $_.cost } -Descending
$o.Add('<table><thead><tr><th>Token class</th><th class="n">Tokens</th><th class="n">Rate (USD / MTok)</th><th class="n">Cost (USD)</th><th class="n">Share of spend</th></tr></thead><tbody>')
foreach ($c in $classes) {
    $o.Add("<tr><td>$($c.name)</td><td class=""n"">$(& $n0 $c.tok)</td><td class=""n"">$(if ($single) { & $usd $single[$c.f] 2 } else { 'per model' })</td><td class=""n"">$(& $usd $c.cost)</td><td class=""n"">$(& $pc $c.cost $total.cost)</td></tr>")
}
$o.Add("<tr class=""total""><td>TOTAL</td><td class=""n"">$(& $n0 ($total.tokIn + $total.output))</td><td></td><td class=""n"">$(& $usd $total.cost)</td><td class=""n"">100%</td></tr></tbody></table></section>")

# Key takeaways - computed, not written by hand
$tk = [System.Collections.Generic.List[string]]::new()
$tk.Add('Share of spend: ' + (($classes | Where-Object { $_.cost -gt 0 } | ForEach-Object { "$($_.name.ToLower()) $(& $pc $_.cost $total.cost)" }) -join ', ') + '.')
$wTok = $total.w5m + $total.w1h; $wCost = $total.c_w5m + $total.c_w1h
if ($wTok -gt 0 -and $total.c_read -gt 0) {
    $tk.Add("By token count cache reads are $(($total.read / $wTok).ToString('0.0', $inv))&times; the cache writes ($(& $n0 $total.read) vs $(& $n0 $wTok)); in dollars the writes cost $(($wCost / $total.c_read).ToString('0.0', $inv))&times; the reads.")
}
if ($flagged.Count) {
    $fCost  = ($flagged | ForEach-Object { $_.cost }  | Measure-Object -Sum).Sum
    $fCalls = ($flagged | ForEach-Object { $_.calls } | Measure-Object -Sum).Sum
    $tk.Add("$($flagged.Count) looped agent$(if ($flagged.Count -ne 1) { 's' }) (" + (& $e (($flagged | ForEach-Object { $_.label }) -join ', ')) + ") made $fCalls of the $($total.calls) API calls and $(& $pc $fCost $total.cost) of the spend.")
}
if ($groups.Count -gt 1) {
    $top = $groups.Keys | Sort-Object { $groups[$_].cost } -Descending | Select-Object -First 1
    $tk.Add('Most expensive group: ' + (& $e $top) + " at $(& $usd $groups[$top].cost) ($(& $pc $groups[$top].cost $total.cost) of the spend).")
}
if ($UnitCount -gt 0) { $tk.Add("Effective cost: $(& $usd ($total.cost / $UnitCount) 5) per unit ($(& $n0 $UnitCount) " + (& $e $UnitLabel) + ').') }
if ($unpriced.Count) { $tk.Add('<span class="warn">Not priced: ' + (& $e ($unpriced -join ', ')) + ' &mdash; add the model to $Prices in the script; the USD figures above leave those calls out.</span>') }
$o.Add('<div class="takeaway"><p><b>Key takeaways</b></p>' + (($tk | ForEach-Object { "<p>$_</p>" }) -join '') + '</div>')

$o.Add("<div class=""foot"">Token usage from the Claude Code subagent transcripts (agent-*.jsonl) of session $(& $e $SessionId), agents started after $($startUtc.ToString('yyyy-MM-dd HH:mm:ss', $inv)) UTC" +
       $(if ($AgentTypes.Count) { ' of type ' + (& $e ($AgentTypes -join ', ')) }) +
       "; each API call counted once (deduplicated on message.id + requestId). Costs use Anthropic API list prices per model (platform.claude.com/docs/en/about-claude/pricing, checked $PriceDate). Claude subscription plans are not billed per token, so read the USD figures as the API-equivalent cost.</div>")
$o.Add('</body></html>')
[System.IO.File]::WriteAllText($htmlPath, ($o -join "`n"), [System.Text.UTF8Encoding]::new($false))

# Print to PDF with headless Edge (Chrome as fallback). No header/footer, so no local file path on the page.
$browser = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
             "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
             "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
             "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { Write-Warning "Edge/Chrome not found - open $htmlPath in a browser and print it to PDF."; return }
# Own profile folder (reused every run) so it never attaches to an Edge window that is already open.
$profileDir = Join-Path ([IO.Path]::GetTempPath()) 'claude-usage-report-browser'
$printStart = Get-Date
$argList = @('--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
             "--user-data-dir=`"$profileDir`"", '--no-pdf-header-footer', '--print-to-pdf-no-header',
             "--print-to-pdf=`"$PdfPath`"", ([Uri]$htmlPath).AbsoluteUri)
$proc = Start-Process -FilePath $browser -ArgumentList $argList -PassThru -WindowStyle Hidden
if (-not $proc.WaitForExit(120000)) { try { $proc.Kill($true) } catch { } }
$pdf = Get-Item $PdfPath -ErrorAction SilentlyContinue
if ($pdf -and $pdf.LastWriteTime -ge $printStart -and $pdf.Length -gt 0) { "PDF report: $PdfPath"; "HTML source: $htmlPath" }
else { Write-Warning "The PDF was not created - open $htmlPath in a browser and print it to PDF." }
