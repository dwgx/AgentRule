#requires -Version 5.1
<#
  install.ps1 — AgentRule 规则书安装器（Windows / PowerShell 5.1+）

  设计原则（和 install.sh 完全一致，输出格式也一样）：
    - 不猜：harness / 目标目录 / 冲突，任一不确定就停下来打印 ASK 并退非 0
    - 不覆盖：默认遇到同名文件只列出，不写
    - 可回滚：任何覆盖前先备份到 <target>/.backup-<timestamp>/
    - 不联网：本脚本没有任何下载 / 网络调用
    - 可验收：--verify 逐文件比对 sha256

  退出码：
    0  成功 / 无冲突 / --verify 全对
    2  有冲突，需要用户决定（此时一个文件都没写）
    3  无法确定 harness（没给 --harness）
    4  前置条件缺失（target 不存在、harness 目录不存在、源目录找不到）
    1  用法错误或运行错误
#>

[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RawArgs)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$Script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Script:NL = "`r`n"
$Script:BlockId = 'entry'
$Script:BeginMark = '<!-- BEGIN agentrule:entry v1 -->'
$Script:EndMark = '<!-- END agentrule:entry v1 -->'

# ---------------------------------------------------------------- 输出
function Say([string]$Text = '') { Write-Output $Text }
function Pad([string]$Text, [int]$Width) {
  if ($Text.Length -ge $Width) { return $Text }
  return $Text + (' ' * ($Width - $Text.Length))
}

function Show-Usage {
  Say @'
AgentRule installer (Windows)

用法:
  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 --dry-run
  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 --harness all
  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 --harness omp --target "C:\Users\me"

参数:
  --dry-run          只报告要做什么，不写任何文件（不建目录、不建备份）
  --harness <h>      omp | codex | claude | all（不给就探测：只命中一套就用它，0 套或多套会停下来问你）
  --target <dir>     安装根目录，默认 = 你的家目录；harness 目录在它下面找
  --force            允许覆盖已有文件（覆盖前先备份）；也允许新建缺失的 harness 目录
  --source <dir>     规则书仓库根目录；默认从脚本所在目录向上找（认 README.md + protocol/ 或 library/）
  --verify           检查已安装内容与源是否一致（sha256 逐文件比对），不写文件
  --help, -h         显示本页

本脚本从不交互提问。需要决定的地方打印 ASK 并退非 0，由 agent 去问用户。

退出码:
  0 成功 / 2 有冲突待决定 / 3 无法确定 harness / 4 前置条件缺失 / 1 用法或运行错误

安装位置（--harness 决定）:
  omp     <target>/.omp/agent/AgentRule/     入口 <target>/.omp/agent/AGENTS.md
  codex   <target>/.codex/AgentRule/         入口 <target>/.codex/AGENTS.md
  claude  <target>/.claude/AgentRule/        入口 <target>/.claude/CLAUDE.md
'@
}

# ---------------------------------------------------------------- 参数
$Opt = @{
  DryRun  = $false
  Harness = $null
  Target  = $null
  Force   = $false
  Source  = $null
  Verify  = $false
  Help    = $false
}

$i = 0
while ($i -lt $RawArgs.Count) {
  $raw = $RawArgs[$i]
  $tok = $raw
  $val = $null
  if ($tok -match '^--?([^=]+)=(.*)$') {
    $tok = $Matches[1]
    $val = $Matches[2]
  }
  else {
    $tok = $tok -replace '^--?', ''
  }
  $name = $tok.ToLowerInvariant()

  if (@('harness', 'target', 'source') -contains $name -and $null -eq $val) {
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
    { $_ -in @('dry-run', 'n', 'dryrun') } { $Opt.DryRun = $true }
    'harness' { $Opt.Harness = $val }
    'target' { $Opt.Target = $val }
    'force' { $Opt.Force = $true }
    'source' { $Opt.Source = $val }
    'verify' { $Opt.Verify = $true }
    { $_ -in @('help', 'h') } { $Opt.Help = $true }
    default {
      Say "错误: 不认识的参数 '$raw'"
      Say ''
      Show-Usage
      exit 1
    }
  }
  $i++
}

if ($Opt.Help) { Show-Usage; exit 0 }

if ($null -ne $Opt.Harness) {
  $Opt.Harness = $Opt.Harness.ToLowerInvariant()
  if (@('omp', 'codex', 'claude', 'all') -notcontains $Opt.Harness) {
    Say "错误: --harness 只接受 omp|codex|claude|all，收到 '$($Opt.Harness)'"
    Say ''
    Show-Usage
    exit 1
  }
}

# ---------------------------------------------------------------- 路径工具
function Expand-HomePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
  if ($Path -eq '~') { return $HOME }
  if ($Path -match '^~[\\/](.*)$') { return (Join-Path $HOME $Matches[1]) }
  return $Path
}

function Full-Path([string]$Path) {
  return [IO.Path]::GetFullPath((Expand-HomePath $Path))
}

function Ensure-Dir([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
  }
}

function Get-Sha([string]$Path) {
  try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
  catch { return '' }
}

function Find-SourceRoot([string]$Start) {
  $cands = New-Object System.Collections.ArrayList
  [void]$cands.Add($Start)
  $p1 = Split-Path -Parent $Start
  if ($p1) { [void]$cands.Add($p1) }
  $p2 = Split-Path -Parent $p1
  if ($p2) { [void]$cands.Add($p2) }
  $markers = @(
    'protocol/00-floor.md',
    'library/floor/hard-floor.md',
    '01-floor/hard-floor.md',
    '01-floor/硬地板.md',
    'docs/hard-floor.md',
    'docs/硬地板.md'
  )
  $best = $null
  $bestScore = -1
  foreach ($c in $cands) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    if (-not (Test-Path -LiteralPath $c -PathType Container)) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $c 'README.md'))) { continue }
    $hasMarker = $false
    foreach ($m in $markers) {
      if (Test-Path -LiteralPath (Join-Path $c $m)) { $hasMarker = $true; break }
    }
    if (-not $hasMarker) { continue }
    # 第三个交叉证据：CHANGELOG.md 在仓库根，有它就优先（老 staging 树没有）
    $score = 1
    if (Test-Path -LiteralPath (Join-Path $c 'CHANGELOG.md')) { $score = 2 }
    if ($score -gt $bestScore) { $bestScore = $score; $best = $c }
  }
  if ($best) { return (Resolve-Path -LiteralPath $best).Path }
  return $null
}

# ---------------------------------------------------------------- harness 表
$HarnessOrder = @('omp', 'codex', 'claude')
$HarnessDef = @{
  omp    = @{ Home = '.omp/agent'; Entry = 'AGENTS.md'; Label = 'omp' }
  codex  = @{ Home = '.codex'; Entry = 'AGENTS.md'; Label = 'codex' }
  claude = @{ Home = '.claude'; Entry = 'CLAUDE.md'; Label = 'claude' }
}

# ---------------------------------------------------------------- 定位
$scriptPath = $PSCommandPath
if (-not $scriptPath) { $scriptPath = Join-Path (Get-Location).Path 'install.ps1' }
$scriptDir = Split-Path -Parent $scriptPath

if ($Opt.Source) {
  $sourceRoot = Full-Path $Opt.Source
  if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    Say "错误: --source 指向的目录不存在: $sourceRoot"
    exit 4
  }
}
else {
  $sourceRoot = Find-SourceRoot $scriptDir
  if (-not $sourceRoot) {
    Say '错误: 找不到规则书源目录（脚本所在目录及其上两级都没有 README.md + protocol/ 或 library/）。'
    Say '     用 --source <仓库根目录> 指定。'
    Say ''
    Say 'ASK（问用户，不要猜）:'
    Say '  这个仓库解压/克隆到哪个目录了？把那个目录用 --source 传给我。'
    exit 4
  }
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
  Say ''
  Say 'ASK（问用户，不要猜）:'
  Say "  你的家目录是 $targetRoot 吗？不是的话用 --target <家目录> 指定；"
  Say '  如果这个目录还不存在，先建它（本脚本不替你造家目录）。'
  exit 4
}

if ($targetRoot.StartsWith($sourceRoot + [IO.Path]::DirectorySeparatorChar)) {
  Say "错误: --target 落在源目录里面（$targetRoot）。会把装好的文件再当成源复制一遍。"
  exit 4
}

# ---------------------------------------------------------------- 源文件清单
$srcLen = $sourceRoot.TrimEnd('\', '/').Length + 1
$srcFiles = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)) {
  $full = $f.FullName
  if (-not $full.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
  $rel = $full.Substring($srcLen)
  $seg = $rel -split '[\\/]'
  if ($seg -contains '.git' -or $seg -contains 'node_modules') { continue }
  if ($seg[0] -like '.backup-*') { continue }
  [void]$srcFiles.Add($rel)
}
$srcFiles = @($srcFiles | Sort-Object)

if ($srcFiles.Count -eq 0) {
  Say "错误: 源目录里没有可安装的文件: $sourceRoot"
  exit 4
}

# ---------------------------------------------------------------- harness 探测
$probe = @()
foreach ($h in $HarnessOrder) {
  $harnessHome = [IO.Path]::GetFullPath((Join-Path $targetRoot $HarnessDef[$h].Home)).TrimEnd('\', '/')
  $probe += [pscustomobject]@{
    Name   = $h
    Home   = $harnessHome
    Exists = (Test-Path -LiteralPath $harnessHome -PathType Container)
    Entry  = [IO.Path]::GetFullPath((Join-Path $harnessHome $HarnessDef[$h].Entry))
  }
}
$found = @($probe | Where-Object { $_.Exists } | ForEach-Object { $_.Name })

# ---------------------------------------------------------------- 决定 harness
$autoPicked = $false
if (-not $Opt.Harness) {
  if ($found.Count -eq 1) {
    $Opt.Harness = $found[0]
    $autoPicked = $true
  }
  else {
    Say 'AgentRule installer'
    Say ('  mode    : ' + $(if ($Opt.DryRun) { 'DRY-RUN（不写任何文件）' } else { 'APPLY' }))
    Say ('  source  : ' + $sourceRoot)
    Say ('  target  : ' + $targetRoot)
    Say ''
    Say '[detect] harness 目录'
    foreach ($p in $probe) {
      Say ('  ' + (Pad $p.Name 8) + $(if ($p.Exists) { 'FOUND    ' } else { 'MISSING  ' }) + $p.Home)
    }
    Say ''
    Say '错误: 没给 --harness，而且探测不出唯一一套，我不替你挑。'
    Say ''
    Say 'ASK（把这些原样问用户，不要自己决定）:'
    Say '  1. 你的 agent 用哪套 harness？可选: omp / codex / claude / all'
    Say ('     探测结果: ' + $(if ($found.Count -gt 0) { $found -join ', ' } else { '一个都没找到（可能装在家目录以外的地方）' }))
    Say ('  2. 家目录是不是 ' + $targetRoot + '？不是就告诉我路径，我用 --target 传进去。')
    Say '  3. 要不要先看计划？先跑 --dry-run 再决定。'
    Say ''
    Say '确定后重跑，例如:'
    Say ('  powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" --harness all --target "' + $targetRoot + '" --dry-run')
    exit 3
  }
}

$selected = if ($Opt.Harness -eq 'all') { $HarnessOrder } else { @($Opt.Harness) }

# 防自嵌套：源 = 已安装的 AgentRule 目录时，重复运行必须是 no-op，不能长出 AgentRule/AgentRule
$sep = [IO.Path]::DirectorySeparatorChar
foreach ($h in $selected) {
  $p = $probe | Where-Object { $_.Name -eq $h } | Select-Object -First 1
  $docsFull = [IO.Path]::GetFullPath((Join-Path $p.Home 'AgentRule')).TrimEnd('\', '/')
  if ($sourceRoot.StartsWith($docsFull + $sep, [StringComparison]::OrdinalIgnoreCase)) {
    Say "错误: 源目录在目标里面（源 $sourceRoot，目标 $docsFull）。这样会复制出 AgentRule/AgentRule。"
    Say '     如果你是从已安装的副本重跑，--target 应该是家目录，不是 AgentRule 目录本身。'
    exit 4
  }
  if ($docsFull.StartsWith($sourceRoot + $sep, [StringComparison]::OrdinalIgnoreCase)) {
    Say "错误: 目标在源目录里面（源 $sourceRoot，目标 $docsFull）。"
    exit 4
  }
}

$missingHomes = @($probe | Where-Object { $selected -contains $_.Name -and -not $_.Exists })
if ($missingHomes.Count -gt 0 -and -not $Opt.Force) {
  Say 'AgentRule installer'
  Say ('  mode    : ' + $(if ($Opt.DryRun) { 'DRY-RUN（不写任何文件）' } else { 'APPLY' }))
  Say ('  source  : ' + $sourceRoot)
  Say ('  target  : ' + $targetRoot)
  Say ''
  Say '[detect] harness 目录'
  foreach ($p in $probe) {
    $sel = if ($selected -contains $p.Name) { ' *' } else { '' }
    Say ('  ' + (Pad $p.Name 8) + $(if ($p.Exists) { 'FOUND    ' } else { 'MISSING  ' }) + $p.Home + $sel)
  }
  Say ''
  Say '错误: 你指定的 harness 目录不存在，我不替你建（可能装在家目录以外）。'
  foreach ($p in $missingHomes) { Say ('  缺失: ' + $p.Name + ' -> ' + $p.Home) }
  Say ''
  Say 'ASK（把这些原样问用户，不要自己决定）:'
  Say '  1. 这个 harness 装在别的地方吗？给我那个目录，我用 --target 指过去。'
  Say '  2. 还是确实没装、先要这套规则书？确认后加 --force，我会新建目录。'
  exit 4
}

# ---------------------------------------------------------------- 入口块
function Get-EntryBlock([string]$Harness) {
  $def = $HarnessDef[$Harness]
  $homeRel = '~/' + ($def.Home -replace '\\', '/')
  $docRel = $homeRel + '/AgentRule'
  $extra = switch ($Harness) {
    'omp' { '- 这套 harness 的 hooks 在 `~/.omp/agent/hooks/`，skills 在 `~/.omp/agent/skills/`；本文件是全局 `AGENTS.md`。' }
    'codex' { '- 这套 harness 的全局配置是 `~/.codex/config.toml`，本文件是全局 `AGENTS.md`。' }
    'claude' { '- 这套 harness 的全局入口就是本文件 `CLAUDE.md`，项目级配置在 `.claude/`。' }
    default { '' }
  }
  return @(
    $Script:BeginMark
    '## AgentRule（已安装的规则书）'
    ''
    ('规则书在 `' + $docRel + '/`。**不要整目录预载**：先读 `AgentRule/README.md`，按里面的 W/S 档顺序按需开页。')
    ''
    '- 常驻只放铁律和入口；用到哪篇打开哪篇。'
    '- 这份规则书是 guidance，不是 enforcement；真正拦人的是本 harness 自己的 hook 和配置。'
    $extra
    '- 首行只写 `STATUS:`；没跑过的东西标 `[UNVERIFIED]`。'
    '- 部署/安装这类会改用户机器的活：不确定就问用户，不要猜。'
    ('- 装了哪些文件、怎么验收：`' + $docRel + '/README.md` 的文件地图。')
    $Script:EndMark
  ) -join $Script:NL
}

function Get-EntrySizeInfo([string]$Harness, [string]$EntryPath) {
  # 「文件存在」≠「模型看到了」。Codex 默认 project_doc_max_bytes=32768，超出静默截断尾部。
  # 只返回对象，不打印：打印会被 if 条件吞掉。
  $info = [pscustomobject]@{ Ok = $true; Size = 0; Note = '' }
  if (-not (Test-Path -LiteralPath $EntryPath -PathType Leaf)) {
    $info.Ok = $false
    $info.Note = '   MISSING'
    return $info
  }
  $size = (Get-Item -LiteralPath $EntryPath).Length
  $info.Size = $size
  if ($size -gt 32768) {
    if ($Harness -eq 'codex') {
      $limit = 0
      $limitFound = $false
      $cfg = Join-Path (($probe | Where-Object { $_.Name -eq 'codex' } | Select-Object -First 1).Home) 'config.toml'
      if (Test-Path -LiteralPath $cfg -PathType Leaf) {
        $m = Select-String -LiteralPath $cfg -Pattern '^\s*project_doc_max_bytes\s*=\s*(\d+)' | Select-Object -First 1
        if ($m) { $limit = [int]$m.Matches[0].Groups[1].Value; $limitFound = $true }
      }
      if ($limit -lt $size) {
        $info.Ok = $false
        if ($limitFound) {
          $info.Note = '   WARN: > 32768 B，Codex 会静默截断尾部（config.toml 的 project_doc_max_bytes=' + $limit + '）'
        }
        else {
          $info.Note = '   WARN: > 32768 B，Codex 会静默截断尾部（config.toml 未设 project_doc_max_bytes，默认 32768）'
        }
      }
      else {
        $info.Note = '   (config.toml 已放大到 ' + $limit + ' B)'
      }
    }
    else {
      $info.Note = '   (本 harness 无此上限，仅报告大小)'
    }
  }
  return $info
}

function Show-TruncationFix {
  Say '  WARN: 入口文件超过 32768 B，Codex 只会读前 32768 B，尾部消失且不报错。'
  Say '        修法一: 在 ~/.codex/config.toml 加 project_doc_max_bytes = 65536'
  Say '        修法二: 入口只留指针，规则分篇放 AgentRule/（本安装器就是这么做的）'
  Say '        注意: 项目级 .codex/config.toml 只在 trust_level 落盘后生效，别只改项目级。'
}


function Get-EntryText([string]$Existing, [string]$Block) {
  if ([string]::IsNullOrEmpty($Existing)) { return ($Block + $Script:NL) }
  $pattern = '(?s)\r?\n?<!-- BEGIN agentrule:entry v1 -->.*?<!-- END agentrule:entry v1 -->\r?\n?'
  $stripped = [regex]::Replace($Existing, $pattern, '')
  $stripped = $stripped.TrimEnd("`r", "`n", " ", "`t")
  if ($stripped.Length -gt 0) { return ($stripped + $Script:NL + $Script:NL + $Block + $Script:NL) }
  return ($Block + $Script:NL)
}

# ---------------------------------------------------------------- 计划
$plan = New-Object System.Collections.ArrayList
function Add-Plan([string]$Harness, [string]$Kind, [string]$Rel, [string]$Src, [string]$Dest, [string]$Note) {
  [void]$plan.Add([pscustomobject]@{
      Harness = $Harness; Kind = $Kind; Rel = $Rel; Src = $Src; Dest = $Dest; Note = $Note
    })
}

foreach ($h in $selected) {
  $p = $probe | Where-Object { $_.Name -eq $h } | Select-Object -First 1
  $docsDest = Join-Path $p.Home 'AgentRule'

  foreach ($rel in $srcFiles) {
    $srcFull = Join-Path $sourceRoot $rel
    $dest = [IO.Path]::GetFullPath((Join-Path $docsDest $rel))

    if (Test-Path -LiteralPath $dest -PathType Container) {
      Add-Plan $h 'CONFLICT' $rel $srcFull $dest '目标是目录'
      continue
    }
    if (-not (Test-Path -LiteralPath $dest)) {
      Add-Plan $h 'CREATE' $rel $srcFull $dest ''
      continue
    }
    if ((Get-Sha $srcFull) -eq (Get-Sha $dest)) {
      Add-Plan $h 'SAME' $rel $srcFull $dest ''
    }
    elseif ($Opt.Force) {
      Add-Plan $h 'BACKUP+WRITE' $rel $srcFull $dest '内容不同，先备份再覆盖'
    }
    else {
      Add-Plan $h 'CONFLICT' $rel $srcFull $dest '内容不同；默认不覆盖'
    }
  }

  # 入口文件
  $entryPath = $p.Entry
  $existing = ''
  if (Test-Path -LiteralPath $entryPath -PathType Leaf) {
    $existing = [IO.File]::ReadAllText($entryPath)
  }
  $newText = Get-EntryText $existing (Get-EntryBlock $h)

  if (-not (Test-Path -LiteralPath $entryPath)) {
    Add-Plan $h 'ENTRY_CREATE' $HarnessDef[$h].Entry '' $entryPath '新建入口文件'
  }
  elseif ($existing -eq $newText) {
    Add-Plan $h 'ENTRY_SAME' $HarnessDef[$h].Entry '' $entryPath ''
  }
  elseif ($Opt.Force) {
    Add-Plan $h 'ENTRY_UPDATE' $HarnessDef[$h].Entry '' $entryPath '先备份再写入口块'
  }
  else {
    Add-Plan $h 'ENTRY_CONFLICT' $HarnessDef[$h].Entry '' $entryPath '入口文件已有内容；需要 --force 才追加'
  }
}

# ---------------------------------------------------------------- 打印计划
$conflicts = @($plan | Where-Object { $_.Kind -in @('CONFLICT', 'ENTRY_CONFLICT') })
$writes = @($plan | Where-Object { $_.Kind -in @('CREATE', 'BACKUP+WRITE', 'ENTRY_CREATE', 'ENTRY_UPDATE') })
$sameCount = @($plan | Where-Object { $_.Kind -in @('SAME', 'ENTRY_SAME') }).Count

Say 'AgentRule installer'
Say ('  mode    : ' + $(if ($Opt.DryRun) { 'DRY-RUN（不写任何文件）' } elseif ($Opt.Verify) { 'VERIFY（只比对，不写）' } else { 'APPLY' }))
Say ('  script  : ' + $scriptPath)
Say ('  source  : ' + $sourceRoot)
Say ('  target  : ' + $targetRoot)
Say ('  harness : ' + ($selected -join ', '))
if ($autoPicked) {
  Say ('  note    : 没给 --harness；探测到唯一一套 ' + $Opt.Harness + '，按 install/ASK.md Q1 的默认值使用（要改就加 --harness）')
}
Say '  network : 不使用（脚本里没有任何下载调用）'
Say ''
Say '[detect] harness 目录'
foreach ($p in $probe) {
  $sel = if ($selected -contains $p.Name) { ' *' } else { '' }
  Say ('  ' + (Pad $p.Name 8) + $(if ($p.Exists) { 'FOUND    ' } else { 'MISSING  ' }) + $p.Home + $sel)
}
Say ''

if ($Opt.Verify) {
  Say ('[verify] 源 ' + $srcFiles.Count + ' 个文件')
  foreach ($h in $selected) {
    foreach ($item in @($plan | Where-Object { $_.Harness -eq $h })) {
      $state = switch ($item.Kind) {
        'SAME' { 'OK' }
        'ENTRY_SAME' { 'OK' }
        'CREATE' { 'MISSING' }
        'ENTRY_CREATE' { 'MISSING' }
        default { 'DRIFT' }
      }
      Say ('  ' + (Pad $h 7) + (Pad $state 8) + $item.Rel)
    }
  }
  Say ''
  $sizeOk = $true
  foreach ($h in $selected) {
    $e = ($probe | Where-Object { $_.Name -eq $h } | Select-Object -First 1).Entry
    $info = Get-EntrySizeInfo $h $e
    Say ('  [entry-size] ' + (Pad $h 7) + $info.Size + ' B  ' + $e + $info.Note)
    if (-not $info.Ok) { $sizeOk = $false }
  }
  if (-not $sizeOk) { Show-TruncationFix }
  Say ''
  $bad = @($plan | Where-Object { $_.Kind -notin @('SAME', 'ENTRY_SAME') }).Count
  if (-not $sizeOk) { $bad++ }
  Say ('[summary] ok ' + $sameCount + '  bad ' + $bad)
  if ($bad -eq 0) {
    Say '结果: 安装内容与源一致，入口文件没超截断线。'
    exit 0
  }
  Say '结果: 有缺失、不一致或入口超限。重跑安装（不带 --verify）可补齐；冲突项要 --force。'
  exit 2
}

Say ('[files] 每个 harness 要处理 ' + $srcFiles.Count + ' 个文件')
foreach ($h in $selected) {
  Say ('  -- ' + $h + ' --')
  foreach ($item in @($plan | Where-Object { $_.Harness -eq $h -and $_.Kind -notlike 'ENTRY_*' })) {
    $line = '  ' + (Pad $item.Kind 14) + $item.Rel
    if ($item.Note) { $line += '   (' + $item.Note + ')' }
    Say $line
  }
  $entryItem = $plan | Where-Object { $_.Harness -eq $h -and $_.Kind -like 'ENTRY_*' } | Select-Object -First 1
  if ($entryItem) {
    $entryRel = $entryItem.Dest.Substring($targetRoot.Length + 1)
    $line = '  ' + (Pad $entryItem.Kind 14) + $entryRel
    if ($entryItem.Note) { $line += '   (' + $entryItem.Note + ')' }
    Say $line
  }
}
Say ''

$newDirs = New-Object System.Collections.ArrayList
foreach ($w in $writes) {
  $d = Split-Path -Parent $w.Dest
  while ($d -and $d.Length -gt $targetRoot.Length -and -not (Test-Path -LiteralPath $d)) {
    if (-not $newDirs.Contains($d)) { [void]$newDirs.Add($d) }
    $d = Split-Path -Parent $d
  }
}
if ($newDirs.Count -gt 0) {
  Say '[dirs] 将新建'
  foreach ($d in ($newDirs | Sort-Object)) { Say ('  ' + $d.Substring($targetRoot.Length + 1)) }
  Say ''
}

Say '[summary]'
Say ('  create ' + @($plan | Where-Object { $_.Kind -eq 'CREATE' }).Count +
  '  overwrite ' + @($plan | Where-Object { $_.Kind -eq 'BACKUP+WRITE' }).Count +
  '  same ' + $sameCount +
  '  conflict ' + $conflicts.Count +
  '  entry ' + @($plan | Where-Object { $_.Kind -like 'ENTRY_*' }).Count)
Say ''

if ($conflicts.Count -gt 0) {
  Say '[conflict] 这些目标已存在且内容不同，默认不覆盖:'
  foreach ($c in $conflicts) { Say ('  ' + $c.Dest) }
  Say ''
  Say 'ASK（把这些原样问用户，不要自己决定）:'
  Say ('  有 ' + $conflicts.Count + ' 个文件会被覆盖。要覆盖吗？')
  Say '  覆盖 = 先把原文件备份到 <target>/.backup-<时间戳>/，再写新内容。'
  Say '  同意覆盖: 加 --force 重跑。'
  Say '  只想补齐缺的: 先手动挪走上面列出的文件，再重跑。'
  Say ''
  if ($Opt.DryRun) {
    Say ('结果: DRY-RUN，没有写任何文件；上面 ' + $conflicts.Count + ' 个冲突需要用户决定。')
  }
  else {
    Say '结果: 没有写任何文件（冲突待决定）。'
  }
  exit 2
}

if ($Opt.DryRun) {
  Say ('[manifest] 真跑时会写: ' + $targetRoot + '\.agentrule-deploy\<run-id>\manifest.json（卸载靠它）')
  Say ''
  Say '结果: DRY-RUN，没有写任何文件。去掉 --dry-run 即按上面执行。'
  Say ''
  Say '验收命令（装完后跑）:'
  Say ('  powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" --verify --harness ' + $Opt.Harness + ' --target "' + $targetRoot + '"')
  exit 0
}

# ---------------------------------------------------------------- 执行
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $targetRoot ('.backup-' + $timestamp)
$stateDir = Join-Path $targetRoot ('.agentrule-deploy\' + $timestamp)
$backupCount = 0
$written = 0
$fileRecords = New-Object System.Collections.ArrayList
$entryRecords = New-Object System.Collections.ArrayList
$backupMap = @{}
$beforeMap = @{}
$logLines = New-Object System.Collections.ArrayList

function Backup-One([string]$Path, [string]$RelToTarget) {
  $dest = Join-Path $backupRoot $RelToTarget
  Ensure-Dir (Split-Path -Parent $dest)
  Copy-Item -LiteralPath $Path -Destination $dest -Force
  $script:backupCount++
  return $dest
}

function Log-Line([string]$Id, [string]$Action, [string]$Path, [string]$Before, [string]$After) {
  $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  [void]$logLines.Add($ts + ' | ' + $Id + ' | ' + $Action + ' | ' + $Path + ' | before=' + $Before + ' | after=' + $After + ' | ok')
}

$stepNo = 0
foreach ($item in $writes) {
  $stepNo++
  $sid = 'S' + $stepNo

  if ($item.Kind -like 'ENTRY_*') {
    $entryPath = $item.Dest
    $before = ''
    $backupPath = ''
    if (Test-Path -LiteralPath $entryPath -PathType Leaf) {
      $before = Get-Sha $entryPath
      $backupPath = Backup-One $entryPath $entryPath.Substring($targetRoot.Length + 1)
    }
    Ensure-Dir (Split-Path -Parent $entryPath)
    $existing = ''
    if (Test-Path -LiteralPath $entryPath -PathType Leaf) { $existing = [IO.File]::ReadAllText($entryPath) }
    [IO.File]::WriteAllText($entryPath, (Get-EntryText $existing (Get-EntryBlock $item.Harness)), $Script:Utf8NoBom)
    $after = Get-Sha $entryPath
    $beforeMap[$entryPath] = $before
    if ($backupPath) { $backupMap[$entryPath] = $backupPath }
    Log-Line $sid 'append-block' $entryPath $before $after
    $written++
    continue
  }

  $dest = $item.Dest
  $before = ''
  $backupPath = ''
  if (Test-Path -LiteralPath $dest -PathType Leaf) {
    $before = Get-Sha $dest
    $backupPath = Backup-One $dest $dest.Substring($targetRoot.Length + 1)
  }
  Ensure-Dir (Split-Path -Parent $dest)
  Copy-Item -LiteralPath $item.Src -Destination $dest -Force
  $after = Get-Sha $dest
  $beforeMap[$dest] = $before
  if ($backupPath) { $backupMap[$dest] = $backupPath }
  Log-Line $sid 'write-file' $dest $before $after
  $written++
}

# manifest 描述的是「装完之后的完整状态」，不是「这一次写了哪几个」——
# 卸载要按它删/还原，只记增量会让后一次 --force 覆盖掉前一次的清单。
foreach ($item in $plan) {
  if ($item.Kind -in @('CONFLICT', 'ENTRY_CONFLICT')) { continue }
  if (-not (Test-Path -LiteralPath $item.Dest -PathType Leaf)) { continue }
  $sha = Get-Sha $item.Dest
  $bk = ''
  if ($backupMap.ContainsKey($item.Dest)) { $bk = $backupMap[$item.Dest] }
  if ($item.Kind -like 'ENTRY_*') {
    $beforeSha = ''
    if ($beforeMap.ContainsKey($item.Dest)) { $beforeSha = $beforeMap[$item.Dest] }
    [void]$entryRecords.Add([ordered]@{
        path = $item.Dest; block_id = $Script:BlockId; version = 'v1'
        before_sha256 = $beforeSha; after_sha256 = $sha; backup = $bk
      })
  }
  else {
    $action = switch ($item.Kind) {
      'CREATE' { 'create' }
      'BACKUP+WRITE' { 'overwrite' }
      default { 'unchanged' }
    }
    [void]$fileRecords.Add([ordered]@{
        path = $item.Dest; action = $action; sha256 = $sha; backup = $bk
      })
  }
}

# manifest + apply.log：卸载和回滚靠它，不靠记忆（协议 §6.1 / §6.3）
Ensure-Dir $stateDir
$manifest = [ordered]@{
  protocol     = 'ADP-1'
  tool         = 'install.ps1'
  run_id       = $timestamp
  installed_at = (Get-Date).ToString('o')
  source       = $sourceRoot
  target       = $targetRoot
  harnesses    = @($selected)
  backup_root  = $(if ($backupCount -gt 0) { $backupRoot } else { '' })
  files        = @($fileRecords)
  entries      = @($entryRecords)
  uninstall    = @(
    '1. entries[].path: 删掉 <!-- BEGIN agentrule:entry v1 --> 到 <!-- END agentrule:entry v1 --> 之间的内容（含两行标记）',
    '2. files[] 里 action=create 的 path: 直接删',
    '3. files[] 里 action=overwrite 的 path: 用同一条目的 backup 覆盖回去',
    '4. files[] 里 action=unchanged 的 path: 装之前就有，不要动',
    ('5. 删掉状态目录 ' + $stateDir)
  )
}
$manifestPath = Join-Path $stateDir 'manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), $Script:Utf8NoBom)
[IO.File]::WriteAllText((Join-Path $stateDir 'apply.log'), (($logLines -join $Script:NL) + $Script:NL), $Script:Utf8NoBom)

Say '[done]'
Say ('  写入 ' + $written + ' 个文件')
if ($backupCount -gt 0) { Say ('  备份 ' + $backupCount + ' 个文件 -> ' + $backupRoot) }
else { Say '  没有文件需要备份（没有覆盖任何已有内容）' }
Say ('  manifest -> ' + $manifestPath)
Say ''
$sizeOk = $true
foreach ($h in $selected) {
  $e = ($probe | Where-Object { $_.Name -eq $h } | Select-Object -First 1).Entry
  $info = Get-EntrySizeInfo $h $e
  Say ('  [entry-size] ' + (Pad $h 7) + $info.Size + ' B  ' + $e + $info.Note)
  if (-not $info.Ok) { $sizeOk = $false }
}
if (-not $sizeOk) { Show-TruncationFix }
Say ''
Say '验收命令（现在就能跑，应输出 bad 0）:'
Say ('  powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" --verify --harness ' + $Opt.Harness + ' --target "' + $targetRoot + '"')
Say ''
Say '下一步（给 agent）:'
$firstHome = ($probe | Where-Object { $_.Name -eq $selected[0] } | Select-Object -First 1).Home
Say ('  1. 打开入口文件确认标记块在（搜 agentrule:entry v1）: ' + $firstHome + '\' + $HarnessDef[$selected[0]].Entry)
Say '  2. 重启 harness 让入口文件生效；当前会话不变。'
if ($backupCount -gt 0) { Say ('  3. 回滚: 把 ' + $backupRoot + ' 里的文件按相对路径拷回去。') }
else { Say '  3. 回滚: 本次没有覆盖任何已有内容，删掉新建的 AgentRule/ 即可。' }
exit 0
