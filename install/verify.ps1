#requires -Version 5.1
<#
  verify.ps1 — AgentRule 部署后自检（Windows / PowerShell 5.1+）

  和 install.ps1 的分工：
    install.ps1 --verify   逐文件 sha256 比对（装得是不是逐字节一样）
    verify.ps1             部署后健康检查（装进去的东西 harness 到底能不能用）
                            —— 文件存在且非空 / 规则可加载 / hooks 语法 / 总量在 ±10% 内

  检查项（每个 harness 各跑一遍）：
    1  docs      规则书目录 <home>/AgentRule/ 存在
    2  files     源仓库里的每个文件都在目标位置且非空（给了 --source 时）
    3  empty     已部署的规则书里没有 0 字节文件
    4  entry     入口文件（AGENTS.md / CLAUDE.md）非空，且有 managed block 或 AgentRule 引用
    5  load      omp: RULES.md 行数 ≥ --omp-min-lines
                 codex: config.toml 能被 TOML 解析器 parse
                 claude: CLAUDE.md 非空且可加载（与 entry 同判据）
    6  hooks     hooks/ 存在时：里面至少一个 hook 脚本、非空、语法能过
    7  totals    总行数 / 总字节与预期（--source 或 --expect-*）相差不超过 --tolerance%

  本脚本只读：不写任何文件、不建目录、不联网。

  退出码：
    0  全部检查通过
    1  至少一项 FAIL
    2  没有 FAIL，但至少一项 SKIP（缺工具或缺基线）

  用法：
    powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1 --target "C:\Users\me"
    powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1 --harness omp --source "C:\src\agentrule"
    powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1 --expect-lines 2100 --expect-bytes 240000
#>

[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RawArgs)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$Script:BeginMark = '<!-- BEGIN agentrule:entry v1 -->'
$Script:LegacyBeginMark = '<!-- BEGIN AgentRule managed block -->'

$Script:PassN = 0
$Script:FailN = 0
$Script:SkipN = 0
$Script:NaN = 0
$Script:FailedList = New-Object System.Collections.ArrayList
$Script:PyCmd = $null
$Script:HaveNode = $null
$Script:HaveBun = $null
$Script:HaveTsc = $null

$HarnessOrder = @('omp', 'codex', 'claude')
$HarnessDef = @{
  omp    = @{ Home = '.omp/agent'; Entry = 'AGENTS.md'; Label = 'omp' }
  codex  = @{ Home = '.codex'; Entry = 'AGENTS.md'; Label = 'codex' }
  claude = @{ Home = '.claude'; Entry = 'CLAUDE.md'; Label = 'claude' }
}

# ---------------------------------------------------------------- 输出
function Say([string]$Text = '') { Write-Output $Text }

function Show-Usage {
  Say @'
AgentRule 部署后自检 (Windows)

用法:
  powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1 --target "C:\Users\me"
  powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1 --harness omp --source "C:\src\agentrule"

参数:
  --target <dir>        安装根目录，默认 = 你的家目录；harness 目录在它下面找
  --harness <h>         omp | codex | claude | all；默认 = 探测到的全部（一个都没有则退出 2）
  --source <dir>        规则书仓库根目录；给了就逐文件核对「存在且非空」并比对总量
  --expect-lines <n>    不给 --source 时，用这个数字当总行数预期
  --expect-bytes <n>    不给 --source 时，用这个数字当总字节预期
  --tolerance <pct>     总量允许偏差，默认 10（即 ±10%）
  --omp-min-lines <n>   omp 的 RULES.md 至少多少行才算「可加载」，默认 10
  --quiet               只打印 FAIL / SKIP 和汇总
  --help, -h            显示本页

退出码:
  0 全部通过 / 1 有 FAIL / 2 没有 FAIL 但有 SKIP（缺工具或缺基线）

本脚本只读：不写文件、不建目录、不联网。
不证明什么：hooks 只查「文件在 / 非空 / 语法过」，不证明它已被 harness 加载或真能拦人；
          规则文件只查「可解析 / 行数」，不证明 harness 已经热加载。
'@
}

function Add-Result([string]$Harness, [string]$Name, [string]$State, [string]$Detail) {
  switch ($State) {
    'PASS' { $Script:PassN++ }
    'FAIL' {
      $Script:FailN++
      [void]$Script:FailedList.Add(('[' + $Harness + '] ' + $Name + ' — ' + $Detail))
    }
    'SKIP' { $Script:SkipN++ }
    'N/A' { $Script:NaN++ }
  }
  if ($Script:Quiet -and ($State -eq 'PASS' -or $State -eq 'N/A')) { return }
  Write-Output ('  ' + $State.PadRight(4) + '  ' + $Name.PadRight(24) + ' ' + $Detail)
}

# ---------------------------------------------------------------- 参数
$Opt = @{
  Target = $null
  Harness = $null
  Source = $null
  ExpectLines = $null
  ExpectBytes = $null
  Tolerance = 10
  OmpMinLines = 10
  Quiet = $false
  Help = $false
}

$i = 0
while ($i -lt $RawArgs.Count) {
  $tok = $RawArgs[$i]
  $val = $null
  if ($tok -match '^--?([^=]+)=(.*)$') {
    $tok = $Matches[1]
    $val = $Matches[2]
  }
  else {
    $tok = $tok -replace '^--?', ''
  }
  $name = $tok.ToLowerInvariant()

  $needsValue = @('target', 'harness', 'source', 'expect-lines', 'expect-bytes', 'tolerance', 'omp-min-lines')
  if ($needsValue -contains $name -and $null -eq $val) {
    $i++
    if ($i -ge $RawArgs.Count) {
      Say "错误: --$name 需要一个值"
      Say ''
      Show-Usage
      exit 1
    }
    $val = $RawArgs[$i]
  }

  switch ($name) {
    'target' { $Opt.Target = $val }
    'harness' { $Opt.Harness = $val.ToLowerInvariant() }
    'source' { $Opt.Source = $val }
    'expect-lines' {
      $n = 0
      if (-not [int]::TryParse($val, [ref]$n) -or $n -lt 0) {
        Say "错误: --expect-lines 需要非负整数，收到 '$val'"; exit 1
      }
      $Opt.ExpectLines = $n
    }
    'expect-bytes' {
      $n = 0
      if (-not [int]::TryParse($val, [ref]$n) -or $n -lt 0) {
        Say "错误: --expect-bytes 需要非负整数，收到 '$val'"; exit 1
      }
      $Opt.ExpectBytes = $n
    }
    'tolerance' {
      $n = 0
      if (-not [int]::TryParse($val, [ref]$n) -or $n -lt 0 -or $n -gt 100) {
        Say "错误: --tolerance 需要 0..100 的整数，收到 '$val'"; exit 1
      }
      $Opt.Tolerance = $n
    }
    'omp-min-lines' {
      $n = 0
      if (-not [int]::TryParse($val, [ref]$n) -or $n -lt 1) {
        Say "错误: --omp-min-lines 需要正整数，收到 '$val'"; exit 1
      }
      $Opt.OmpMinLines = $n
    }
    'quiet' { $Opt.Quiet = $true }
    'help' { $Opt.Help = $true }
    'h' { $Opt.Help = $true }
    default {
      Say "错误: 不认识的参数 '$($RawArgs[$i])'"
      Say ''
      Show-Usage
      exit 1
    }
  }
  $i++
}

$Script:Quiet = $Opt.Quiet
if ($Opt.Help) { Show-Usage; exit 0 }

if ($Opt.Harness -and @('omp', 'codex', 'claude', 'all') -notcontains $Opt.Harness) {
  Say "错误: --harness 只接受 omp|codex|claude|all，收到 '$($Opt.Harness)'"
  Say ''
  Show-Usage
  exit 1
}

# ---------------------------------------------------------------- 路径工具
function Expand-HomePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
  if ($Path -eq '~') { return $HOME }
  if ($Path -like '~/*' -or $Path -like '~\*') { return (Join-Path $HOME $Path.Substring(2)) }
  return $Path
}

function Full-Path([string]$Path) {
  return [IO.Path]::GetFullPath((Expand-HomePath $Path))
}

function Get-RelFiles([string]$Root) {
  $out = New-Object System.Collections.ArrayList
  if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  foreach ($f in (Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/')
    $seg = $rel -split '[\\/]'
    if ($seg -contains '.git' -or $seg -contains 'node_modules') { continue }
    if ($seg[0] -like '.backup*') { continue }
    [void]$out.Add([pscustomobject]@{ Rel = $rel; Full = $f.FullName; Bytes = $f.Length })
  }
  return @($out.ToArray())
}

function Get-LineCount([string]$Path) {
  try { $t = [IO.File]::ReadAllText($Path) } catch { return 0 }
  return ([regex]::Matches($t, "`n")).Count
}

function Invoke-Native([string]$Exe, [string[]]$ArgList) {
  # 原生程序往 stderr 写东西时，$ErrorActionPreference='Stop' 会把它变成终止错误并中断脚本。
  # 所有外部工具调用都走这里：临时切 Continue，拿退出码和合并输出。
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = @()
  $code = 1
  try {
    $out = & $Exe @ArgList 2>&1
    $code = $LASTEXITCODE
  }
  catch {
    $out = @($_.Exception.Message)
    $code = 1
  }
  finally {
    $ErrorActionPreference = $prev
  }
  $text = (@($out | ForEach-Object { [string]$_ }) -join "`n").Trim()
  return @{ Code = $code; Out = $text }
}

function Get-EntryMarker([string]$Text) {
  if ($Text.Contains($Script:BeginMark)) { return '入口块在（agentrule:entry）' }
  if ($Text.Contains($Script:LegacyBeginMark)) { return '入口块在（managed block，旧版）' }
  if ($Text -match '(?i)BEGIN agentrule:') { return '入口块在（agentrule:entry）' }
  return ''
}

function Test-RuleRef([string]$Path) {
  try { $t = [IO.File]::ReadAllText($Path) } catch { return $false }
  if (Get-EntryMarker $t) { return $true }
  if ($t -match '(?i)AgentRule') { return $true }
  if ($t -match '规则书') { return $true }
  return $false
}

function Format-Pct([double]$Actual, [double]$Expected) {
  if ($Expected -le 0) { return 'n/a' }
  $p = ($Actual - $Expected) * 100.0 / $Expected
  return ('{0:+0.0;-0.0;0.0}%' -f $p)
}

function Find-SourceRoot([string]$Start) {
  $d = $Start
  for ($k = 0; $k -lt 4; $k++) {
    if ([string]::IsNullOrWhiteSpace($d)) { break }
    if (Test-Path -LiteralPath (Join-Path $d 'protocol/README.md') -PathType Leaf) { return $d }
    if (Test-Path -LiteralPath (Join-Path $d 'library/README.md') -PathType Leaf) { return $d }
    if (Test-Path -LiteralPath (Join-Path $d 'docs/README.md') -PathType Leaf) { return $d }
    $parent = Split-Path -Parent $d
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $d) { break }
    $d = $parent
  }
  return $null
}

function Get-DestFor([string]$Rel, [string]$HarnessHome, [string]$DocsRoot) {
  if ($Rel -match '^skills[\\/](.+)$') {
    return (Join-Path (Join-Path $HarnessHome 'skills') $Matches[1])
  }
  return (Join-Path $DocsRoot $Rel)
}

# ---------------------------------------------------------------- 外部工具
function Find-Python {
  if ($null -ne $Script:PyCmd) { return , $Script:PyCmd }
  foreach ($cand in @(@('python'), @('python3'), @('py', '-3'))) {
    $exe = $cand[0]
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
    $pre = @()
    if ($cand.Count -gt 1) { $pre = @($cand[1..($cand.Count - 1)]) }
    $r = Invoke-Native $exe @($pre + @('-c', 'import tomllib'))
    if ($r.Code -eq 0) { $Script:PyCmd = @($cand); return , $cand }
  }
  $Script:PyCmd = @()
  return , @()
}

function Test-Toml([string]$Path) {
  $py = Find-Python
  if ($py.Count -eq 0) { return @{ State = 'SKIP'; Detail = '找不到带 tomllib 的 python，config.toml 未解析' } }
  $exe = $py[0]
  $pre = @()
  if ($py.Count -gt 1) { $pre = @($py[1..($py.Count - 1)]) }
  $code = "import sys,tomllib;tomllib.load(open(sys.argv[1],'rb'))"
  $r = Invoke-Native $exe @($pre + @('-c', $code, $Path))
  if ($r.Code -eq 0) { return @{ State = 'PASS'; Detail = 'tomllib 解析通过（用户级 config.toml）' } }
  $last = @($r.Out -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -Last 1)
  $msg = if ($last.Count -gt 0) { $last[0].Trim() } else { '解析失败（无输出）' }
  return @{ State = 'FAIL'; Detail = ('tomllib 解析失败: ' + $msg) }
}

function Test-ScriptSyntax([string]$Path) {
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -eq '.ts') {
    if ($null -eq $Script:HaveBun) { $Script:HaveBun = [bool](Get-Command bun -ErrorAction SilentlyContinue) }
    if ($Script:HaveBun) {
      # 单引号包 'ts'：PowerShell 5.1 向原生程序传参时会吃掉双引号
      $js = "const p=process.argv[1];const t=await Bun.file(p).text();new Bun.Transpiler({loader:'ts'}).transformSync(t)"
      $r = Invoke-Native 'bun' @('-e', $js, $Path)
      if ($r.Code -eq 0) { return @{ State = 'PASS'; Detail = 'syntax ok (bun)' } }
      $first = @($r.Out -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
      $msg = if ($first.Count -gt 0) { $first[0].Trim() } else { 'syntax error' }
      return @{ State = 'FAIL'; Detail = ('syntax FAIL (bun): ' + $msg) }
    }
    if ($null -eq $Script:HaveTsc) { $Script:HaveTsc = [bool](Get-Command tsc -ErrorAction SilentlyContinue) }
    if ($Script:HaveTsc) {
      $r = Invoke-Native 'tsc' @('--noEmit', '--skipLibCheck', '--target', 'ES2022', '--module', 'ES2022', '--moduleResolution', 'bundler', $Path)
      if ($r.Code -eq 0) { return @{ State = 'PASS'; Detail = 'syntax ok (tsc)' } }
      if ($r.Out -match 'error TS1\d{3}') {
        $line = @($r.Out -split "`r?`n" | Where-Object { $_ -match 'error TS1\d{3}' } | Select-Object -First 1)
        return @{ State = 'FAIL'; Detail = ('syntax FAIL (tsc): ' + $line[0].Trim()) }
      }
      return @{ State = 'PASS'; Detail = 'tsc 无语法错误（有类型/模块告警，未计为失败）' }
    }
    return @{ State = 'SKIP'; Detail = '没有 bun 也没有 tsc，.ts 语法未检查' }
  }

  if ($null -eq $Script:HaveNode) { $Script:HaveNode = [bool](Get-Command node -ErrorAction SilentlyContinue) }
  if (-not $Script:HaveNode) { return @{ State = 'SKIP'; Detail = '找不到 node，.js 语法未检查' } }
  $r = Invoke-Native 'node' @('--check', $Path)
  if ($r.Code -eq 0) { return @{ State = 'PASS'; Detail = 'syntax ok (node --check)' } }
  $first = @($r.Out -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
  $msg = if ($first.Count -gt 0) { $first[0].Trim() } else { 'syntax error' }
  return @{ State = 'FAIL'; Detail = ('syntax FAIL (node): ' + $msg) }
}

# ---------------------------------------------------------------- 定位
$scriptPath = $PSCommandPath
if (-not $scriptPath) { $scriptPath = Join-Path (Get-Location).Path 'verify.ps1' }
$scriptDir = Split-Path -Parent $scriptPath

if ($Opt.Source) {
  $sourceRoot = Full-Path $Opt.Source
  if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    Say "错误: --source 指向的目录不存在: $sourceRoot"
    exit 4
  }
  $sourceRoot = $sourceRoot.TrimEnd('\', '/')
}
else {
  $found = Find-SourceRoot $scriptDir
  if ($found -and ((Split-Path -Leaf $found) -eq 'AgentRule')) {
    # 从已部署的副本里跑：这份树就是目标本身，不能拿它当基线
    $found = $null
  }
  $sourceRoot = $found
}

if ($Opt.Target) {
  $targetRoot = Full-Path $Opt.Target
}
else {
  $targetRoot = Full-Path $HOME
}
$targetRoot = $targetRoot.TrimEnd('\', '/')

if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
  Say "错误: 目标根目录不存在: $targetRoot"
  exit 4
}

if ($sourceRoot) {
  $srcFiles = @(Get-RelFiles $sourceRoot)
  if ($srcFiles.Count -eq 0) {
    Say "错误: --source 目录里没有文件: $sourceRoot"
    exit 4
  }
}
else {
  $srcFiles = @()
}

# ---------------------------------------------------------------- harness 选择
$probe = @()
foreach ($h in $HarnessOrder) {
  $hHome = [IO.Path]::GetFullPath((Join-Path $targetRoot $HarnessDef[$h].Home)).TrimEnd('\', '/')
  $probe += [pscustomobject]@{
    Name = $h
    Home = $hHome
    Exists = (Test-Path -LiteralPath $hHome -PathType Container)
    Entry = [IO.Path]::GetFullPath((Join-Path $hHome $HarnessDef[$h].Entry))
  }
}

if ($Opt.Harness -eq 'all') {
  $selected = @($HarnessOrder)
  $explicit = $true
}
elseif ($Opt.Harness) {
  $selected = @($Opt.Harness)
  $explicit = $true
}
else {
  $selected = @($probe | Where-Object { $_.Exists } | ForEach-Object { $_.Name })
  $explicit = $false
}

Say 'AgentRule post-deploy verify'
Say ('  script  : ' + $scriptPath)
Say ('  target  : ' + $targetRoot)
Say ('  source  : ' + $(if ($sourceRoot) { $sourceRoot } else { 'none（总量检查将 SKIP；用 --source 或 --expect-*）' }))
Say ('  harness : ' + $(if ($selected.Count -gt 0) { $selected -join ', ' } else { 'none' }))
Say ('  tol     : ±' + $Opt.Tolerance + '%')
$pyInfo = Find-Python
if ($pyInfo.Count -gt 0) { Say ('  python  : ' + ($pyInfo -join ' ')) } else { Say '  python  : MISSING（codex 的 TOML 解析会 SKIP）' }
$nv = Invoke-Native 'node' @('--version')
if ($nv.Code -eq 0) { Say ('  node    : ' + $nv.Out) } else { Say '  node    : MISSING（.js hooks 语法会 SKIP）' }
$bv = Invoke-Native 'bun' @('--version')
if ($bv.Code -eq 0) { Say ('  bun     : ' + $bv.Out) } else { Say '  bun     : MISSING' }
Say ''

if ($selected.Count -eq 0) {
  Say 'SKIP  没有发现任何 harness 目录（' + ($HarnessOrder -join ' / ') + ' 在 ' + $targetRoot + ' 下都不存在）'
  Say ''
  Say '[summary] PASS 0  FAIL 0  SKIP 1  N/A 0'
  Say 'VERDICT: PARTIAL (exit 2) — 没有可检查的 harness'
  exit 2
}

# ---------------------------------------------------------------- 每个 harness
foreach ($h in $selected) {
  $p = $probe | Where-Object { $_.Name -eq $h } | Select-Object -First 1
  $hHome = $p.Home
  $entryPath = $p.Entry
  $docsRoot = Join-Path $hHome 'AgentRule'

  Say ('[' + $h + '] ' + $hHome)

  if (-not $p.Exists) {
    Add-Result $h 'home' 'FAIL' ('harness 目录不存在: ' + $hHome)
    Say ''
    continue
  }

  # 1 docs
  $docsExists = Test-Path -LiteralPath $docsRoot -PathType Container
  if ($docsExists) {
    $deployed = @(Get-RelFiles $docsRoot)
    Add-Result $h 'docs' 'PASS' ($deployed.Count.ToString() + ' files in ' + $docsRoot)
  }
  else {
    Add-Result $h 'docs' 'FAIL' ('未找到规则书目录: ' + $docsRoot)
    $deployed = @()
  }

  # 2 files（有源时逐文件核对）
  if ($sourceRoot) {
    $missing = New-Object System.Collections.ArrayList
    $empty = New-Object System.Collections.ArrayList
    foreach ($sf in $srcFiles) {
      $dest = Get-DestFor $sf.Rel $hHome $docsRoot
      if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
        [void]$missing.Add($sf.Rel)
      }
      elseif ((Get-Item -LiteralPath $dest).Length -eq 0) {
        [void]$empty.Add($sf.Rel)
      }
    }
    if ($missing.Count -eq 0 -and $empty.Count -eq 0) {
      Add-Result $h 'files' 'PASS' ($srcFiles.Count.ToString() + '/' + $srcFiles.Count + ' 个源文件都在且非空')
    }
    else {
      $bits = New-Object System.Collections.ArrayList
      if ($missing.Count -gt 0) { [void]$bits.Add(($missing.Count.ToString() + ' 个缺失: ' + (($missing | Select-Object -First 3) -join ', '))) }
      if ($empty.Count -gt 0) { [void]$bits.Add(($empty.Count.ToString() + ' 个空文件: ' + (($empty | Select-Object -First 3) -join ', '))) }
      Add-Result $h 'files' 'FAIL' ($bits -join '; ')
    }
  }
  else {
    $readme = Join-Path $docsRoot 'README.md'
    if (-not (Test-Path -LiteralPath $readme -PathType Leaf)) {
      Add-Result $h 'files' 'FAIL' ('缺 ' + $readme)
    }
    elseif ((Get-Item -LiteralPath $readme).Length -eq 0) {
      Add-Result $h 'files' 'FAIL' ($readme + ' 是 0 字节')
    }
    else {
      Add-Result $h 'files' 'PASS' 'README.md 存在且非空（未给 --source，只查入口文件）'
    }
  }

  # 3 empty：已部署树里的 0 字节文件
  if ($docsExists) {
    $zero = @($deployed | Where-Object { $_.Bytes -eq 0 })
    if ($zero.Count -eq 0) {
      Add-Result $h 'empty' 'PASS' ('0 个 0 字节文件（检查了 ' + $deployed.Count + ' 个）')
    }
    else {
      $names = @($zero | Select-Object -First 5 | ForEach-Object { $_.Rel })
      Add-Result $h 'empty' 'FAIL' ($zero.Count.ToString() + ' 个 0 字节文件: ' + ($names -join ', '))
    }
  }

  # 4 entry
  $entryOk = $false
  if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
    Add-Result $h 'entry' 'FAIL' ('入口文件不存在: ' + $entryPath)
  }
  elseif ((Get-Item -LiteralPath $entryPath).Length -eq 0) {
    Add-Result $h 'entry' 'FAIL' ('入口文件是 0 字节: ' + $entryPath)
  }
  elseif (-not (Test-RuleRef $entryPath)) {
    Add-Result $h 'entry' 'FAIL' ('入口文件在，但没有 managed block / AgentRule 引用: ' + $entryPath)
  }
  else {
    $entryOk = $true
    $el = Get-LineCount $entryPath
    $eb = (Get-Item -LiteralPath $entryPath).Length
    $how = Get-EntryMarker ([IO.File]::ReadAllText($entryPath))
    if (-not $how) { $how = '有 AgentRule 引用' }
    Add-Result $h 'entry' 'PASS' ($eb.ToString() + ' bytes / ' + $el + ' lines，' + $how)
  }

  # 5 load：harness 能不能真的加载规则
  switch ($h) {
    'omp' {
      $rules = Join-Path $hHome 'RULES.md'
      if (Test-Path -LiteralPath $rules -PathType Leaf) {
        $rb = (Get-Item -LiteralPath $rules).Length
        $rl = Get-LineCount $rules
        if ($rb -eq 0) {
          Add-Result $h 'load' 'FAIL' 'RULES.md 是 0 字节（omp 没有常驻规则可加载）'
        }
        elseif ($rl -lt $Opt.OmpMinLines) {
          Add-Result $h 'load' 'FAIL' ('RULES.md 只有 ' + $rl + ' 行，低于 --omp-min-lines ' + $Opt.OmpMinLines)
        }
        else {
          Add-Result $h 'load' 'PASS' ('RULES.md ' + $rl + ' 行 / ' + $rb + ' bytes')
        }
      }
      elseif ($entryOk) {
        Add-Result $h 'load' 'PASS' 'RULES.md 缺失，但 AGENTS.md 入口块在（omp 会加载 AGENTS.md）'
      }
      else {
        Add-Result $h 'load' 'FAIL' '既没有 RULES.md，也没有可加载的 AGENTS.md 入口块'
      }
    }
    'codex' {
      $cfg = Join-Path $hHome 'config.toml'
      if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) {
        Add-Result $h 'load' 'FAIL' ('config.toml 不存在: ' + $cfg)
      }
      elseif ((Get-Item -LiteralPath $cfg).Length -eq 0) {
        Add-Result $h 'load' 'FAIL' ('config.toml 是 0 字节: ' + $cfg)
      }
      else {
        $r = Test-Toml $cfg
        Add-Result $h 'load' $r.State $r.Detail
      }
    }
    'claude' {
      if ($entryOk) {
        $cl = Get-LineCount $entryPath
        Add-Result $h 'load' 'PASS' ('CLAUDE.md ' + $cl + ' 行，可作为全局入口加载')
      }
      else {
        Add-Result $h 'load' 'FAIL' 'CLAUDE.md 不可加载（缺失 / 空 / 没有 AgentRule 引用）'
      }
    }
  }

  # 6 hooks（有才查）
  $hooksDir = Join-Path $hHome 'hooks'
  if (-not (Test-Path -LiteralPath $hooksDir -PathType Container)) {
    Add-Result $h 'hooks' 'N/A' '没有 hooks 目录（未安装 hook，无检查项）'
  }
  else {
    $hookFiles = @(Get-ChildItem -LiteralPath $hooksDir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)\.(ts|js|mjs|cjs)$' -and $_.Name -notmatch '(?i)\.(bak|before|orig|old)[-.]' })
    if ($hookFiles.Count -eq 0) {
      Add-Result $h 'hooks' 'FAIL' ('hooks 目录在，但里面没有 .ts/.js hook 脚本: ' + $hooksDir)
    }
    else {
      $bad = New-Object System.Collections.ArrayList
      $skipped = New-Object System.Collections.ArrayList
      $zeroHook = @($hookFiles | Where-Object { $_.Length -eq 0 })
      foreach ($hf in $zeroHook) { [void]$bad.Add(($hf.Name + ' 是 0 字节')) }
      foreach ($hf in @($hookFiles | Where-Object { $_.Length -gt 0 })) {
        $r = Test-ScriptSyntax $hf.FullName
        if ($r.State -eq 'FAIL') { [void]$bad.Add(($hf.Name + ': ' + $r.Detail)) }
        elseif ($r.State -eq 'SKIP') { [void]$skipped.Add($hf.Name) }
      }
      if ($bad.Count -gt 0) {
        Add-Result $h 'hooks' 'FAIL' (($bad | Select-Object -First 3) -join '; ')
      }
      elseif ($skipped.Count -gt 0) {
        Add-Result $h 'hooks' 'SKIP' ($hookFiles.Count.ToString() + ' 个 hook 脚本存在且非空，但语法未检查（' + ($skipped -join ', ') + '）')
      }
      else {
        Add-Result $h 'hooks' 'PASS' ($hookFiles.Count.ToString() + ' 个 hook 脚本：存在 / 非空 / 语法过（未证明已被加载；生效探针设计见 adapters/matrix.md §5.3）')
      }
    }
  }

  # 7 totals
  if ($sourceRoot) {
    $srcLines = 0; $srcBytes = 0; $depLines = 0; $depBytes = 0
    foreach ($sf in $srcFiles) {
      $dest = Get-DestFor $sf.Rel $hHome $docsRoot
      $srcBytes += $sf.Bytes
      $srcLines += (Get-LineCount $sf.Full)
      if (Test-Path -LiteralPath $dest -PathType Leaf) {
        $depBytes += (Get-Item -LiteralPath $dest).Length
        $depLines += (Get-LineCount $dest)
      }
    }
    if ($srcBytes -le 0 -or $srcLines -le 0) {
      Add-Result $h 'totals' 'SKIP' '源树为空，无法比对总量'
    }
    else {
      $tol = $Opt.Tolerance / 100.0
      $lineDelta = [Math]::Abs($depLines - $srcLines) / $srcLines
      $byteDelta = [Math]::Abs($depBytes - $srcBytes) / $srcBytes
      $detail = 'lines ' + $depLines + '/' + $srcLines + ' (' + (Format-Pct $depLines $srcLines) + ')  bytes ' + $depBytes + '/' + $srcBytes + ' (' + (Format-Pct $depBytes $srcBytes) + ')  tol ±' + $Opt.Tolerance + '%'
      if ($lineDelta -le $tol -and $byteDelta -le $tol) {
        Add-Result $h 'totals' 'PASS' $detail
      }
      else {
        Add-Result $h 'totals' 'FAIL' $detail
      }
    }
  }
  elseif ($null -ne $Opt.ExpectLines -or $null -ne $Opt.ExpectBytes) {
    $depFiles = @(Get-RelFiles $docsRoot)
    $depLines = 0; $depBytes = 0
    foreach ($f in $depFiles) { $depBytes += $f.Bytes; $depLines += (Get-LineCount $f.Full) }
    $tol = $Opt.Tolerance / 100.0
    $ok = $true
    $bits = New-Object System.Collections.ArrayList
    if ($null -ne $Opt.ExpectLines) {
      $d = if ($Opt.ExpectLines -gt 0) { [Math]::Abs($depLines - $Opt.ExpectLines) / $Opt.ExpectLines } else { 1.0 }
      if ($d -gt $tol) { $ok = $false }
      [void]$bits.Add('lines ' + $depLines + '/' + $Opt.ExpectLines + ' (' + (Format-Pct $depLines $Opt.ExpectLines) + ')')
    }
    if ($null -ne $Opt.ExpectBytes) {
      $d = if ($Opt.ExpectBytes -gt 0) { [Math]::Abs($depBytes - $Opt.ExpectBytes) / $Opt.ExpectBytes } else { 1.0 }
      if ($d -gt $tol) { $ok = $false }
      [void]$bits.Add('bytes ' + $depBytes + '/' + $Opt.ExpectBytes + ' (' + (Format-Pct $depBytes $Opt.ExpectBytes) + ')')
    }
    Add-Result $h 'totals' $(if ($ok) { 'PASS' } else { 'FAIL' }) (($bits -join '  ') + '  tol ±' + $Opt.Tolerance + '%')
  }
  else {
    Add-Result $h 'totals' 'SKIP' '没有基线（给 --source 或 --expect-lines/--expect-bytes）'
  }

  Say ''
}

# ---------------------------------------------------------------- 汇总
Say ('[summary] PASS ' + $Script:PassN + '  FAIL ' + $Script:FailN + '  SKIP ' + $Script:SkipN + '  N/A ' + $Script:NaN)
if ($Script:FailN -gt 0) {
  foreach ($line in $Script:FailedList) { Say ('  FAILED  ' + $line) }
  Say ('VERDICT: FAIL (exit 1) — ' + $Script:FailN + ' 项检查未通过')
  exit 1
}
if ($Script:SkipN -gt 0) {
  Say ('VERDICT: PARTIAL (exit 2) — ' + $Script:SkipN + ' 项检查被跳过（缺工具或缺基线）')
  exit 2
}
Say 'VERDICT: PASS (exit 0) — 全部检查通过'
exit 0
