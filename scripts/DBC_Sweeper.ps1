<#
.SYNOPSIS
    DBC Sweeper —— 大白菜 PE 装机广告 / 流氓软件 / 浏览器牛皮癣 专项排查与可逆清理工具

.DESCRIPTION
    按公开情报重建的五层取证模型：
      A 源头    U 盘 / PE 镜像 / 制作工具本体 / 推广渠道号
      B 部署期  unattended.xml / 随机名启动器 + IMG 分包 / UAC
      C 落地    推广软件目录、注册表、服务、驱动、启动项、计划任务、快捷方式、hosts、收藏夹、文件关联
      D 浏览器  initial_preferences / Preferences / Sessions / Policies / 通知权限 / 扩展 / 缓存
      E 残留    Windows.old、PE 目录、临时文件体积

    默认纯只读：只有 -Scan 行为，不删、不改、不禁用，只产报告。
    写操作必须同时满足：-Fix / -Quarantine / -PurgeReg 之一 + -IAcknowledge + 管理员 + 交互式控制台，
    并且每一项都要人工输入 YES。所有改动先备份到 Quarantine_* / Backup_* 目录，可完整回滚。

.PARAMETER Scan
    只读排查（默认行为，可省略）。

.PARAMETER Fix
    可逆修复：改名被劫持的浏览器首次运行配置、隔离旧会话、隔离缓存、
    删除推广启动项值、禁用推广计划任务、修快捷方式尾巴、注释 hosts 行、修正通知权限。
    全部先备份。

.PARAMETER Quarantine
    把确认为推广软件的目录 / PE 部署期载荷目录 / unattended.xml 移入隔离区（移动，不删除）。

.PARAMETER PurgeReg
    删除明确属于推广渠道的注册表键，删除前逐个导出 .reg 备份。

.PARAMETER IAcknowledge
    写操作的显式确认开关。没有它，任何写模式都会直接退出。

.PARAMETER Measure
    统计相关目录体积（会慢一些）。

.PARAMETER SkipBrowser
    跳过 D 层浏览器检查（例如只想看系统层）。

.PARAMETER OutDir
    报告输出目录，默认 <脚本目录>\DBC_Sweeper_Report。

.PARAMETER MaxBatch
    -Quarantine 单批最多处理的目录数，默认 10。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\DBC_Sweeper.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\DBC_Sweeper.ps1 -Fix -IAcknowledge

.NOTES
    工具只做「可验证、可回滚」的动作。系统目录、注册表策略键、驱动、UAC、Windows.old
    一律只报告不处理，交人工判断。
#>

[CmdletBinding()]
param(
    [switch]$Scan,
    [switch]$Fix,
    [switch]$Quarantine,
    [switch]$PurgeReg,
    [switch]$IAcknowledge,
    [switch]$Measure,
    [switch]$SkipBrowser,
    [string]$OutDir = '',
    [int]$MaxBatch = 10
)

# 注意：这里刻意不用 $ErrorActionPreference='SilentlyContinue'。
# PS 5.1 下它会连 throw 一起吞掉，导致安全闸失效（历史踩坑）。
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ============================================================
# 0. 安全闸（必须在任何扫描之前）
# ============================================================
$script:IsWrite = [bool]($Fix -or $Quarantine -or $PurgeReg)

if ($script:IsWrite -and -not $IAcknowledge) {
    Write-Host ''
    Write-Host '  [已拒绝] 写操作必须显式确认。' -ForegroundColor Yellow
    Write-Host '           请双击 RUN_2_Fix.cmd（会自动带上确认参数），' -ForegroundColor Gray
    Write-Host '           或手动追加 -IAcknowledge。' -ForegroundColor Gray
    Write-Host '           本次未做任何改动。' -ForegroundColor Gray
    Write-Host ''
    exit 1
}

if ($script:IsWrite) {
    $cliRaw = ([Environment]::GetCommandLineArgs() -join ' ')
    if ([Console]::IsInputRedirected -or ($cliRaw -match '(?i)-noninteractive|-encodedcommand')) {
        Write-Host ''
        Write-Host '  [已拒绝] 检测到非交互会话或脚本化调用。' -ForegroundColor Yellow
        Write-Host '           写操作必须人工在控制台逐项确认。本次未做任何改动。' -ForegroundColor Gray
        Write-Host ''
        exit 1
    }
    $prin = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ''
        Write-Host '  [已拒绝] 写操作需要管理员权限。' -ForegroundColor Yellow
        Write-Host '           请右键 RUN_2_Fix.cmd → 以管理员身份运行。本次未做任何改动。' -ForegroundColor Gray
        Write-Host ''
        exit 1
    }
}

# ============================================================
# 1. 基础设施
# ============================================================
$script:Stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Actions  = New-Object System.Collections.Generic.List[object]
$script:StartAt  = Get-Date

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $base = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($base)) { $base = (Get-Location).Path }
    $OutDir = Join-Path $base 'DBC_Sweeper_Report'
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    $null = New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction SilentlyContinue
}
$script:OutDir      = $OutDir
$script:BackupDir   = Join-Path $OutDir ('Backup_' + $script:Stamp)
$script:Quarantine  = Join-Path $OutDir ('Quarantine_' + $script:Stamp)
$script:Lat         = [System.Text.Encoding]::GetEncoding(28591)

function Write-Head([string]$Text) {
    Write-Host ''
    Write-Host ('  ' + ('=' * 66)) -ForegroundColor DarkCyan
    Write-Host ('  ' + $Text) -ForegroundColor Cyan
    Write-Host ('  ' + ('=' * 66)) -ForegroundColor DarkCyan
}
function Write-Sub([string]$Text) { Write-Host ('  -- ' + $Text) -ForegroundColor DarkGray }
function Write-Ok([string]$Text)  { Write-Host ('  [OK]   ' + $Text) -ForegroundColor Green }
function Write-Info([string]$Text){ Write-Host ('  [i]    ' + $Text) -ForegroundColor Gray }
function Write-Warn2([string]$Text){ Write-Host ('  [!]    ' + $Text) -ForegroundColor Yellow }
function Write-Bad([string]$Text) { Write-Host ('  [HIT]  ' + $Text) -ForegroundColor Red }

function Add-F {
    param(
        [string]$Stage,
        [ValidateSet('Safe','Review','Protect')][string]$Level,
        [string]$Category,
        [string]$Name,
        [string]$Detail = '',
        [string]$Path = '',
        [string]$Action = '',
        [string]$SizeMB = ''
    )
    $script:Findings.Add([pscustomobject]@{
        Stage    = $Stage
        Level    = $Level
        Category = $Category
        Name     = $Name
        Detail   = $Detail
        Path     = $Path
        Action   = $Action
        SizeMB   = $SizeMB
    })
    $tag = '[' + $Level.Substring(0,1) + ']'
    if ($Level -eq 'Safe')    { Write-Bad ($tag + ' ' + $Category + ' | ' + $Name) }
    elseif ($Level -eq 'Review') { Write-Warn2 ($tag + ' ' + $Category + ' | ' + $Name) }
    else { Write-Info ($tag + ' ' + $Category + ' | ' + $Name) }
}

function Rec-Act([string]$Step, [string]$Target, [string]$Result) {
    $script:Actions.Add([pscustomobject]@{
        Step   = $Step
        Target = $Target
        Result = $Result
        Time   = (Get-Date -Format 'HH:mm:ss')
    })
}

function Confirm-Step([string]$Title, [string]$Detail) {
    if (-not $script:IsWrite) { return $false }
    Write-Host ''
    Write-Host ('  >> ' + $Title) -ForegroundColor Cyan
    if ($Detail) { Write-Host ('     ' + $Detail) -ForegroundColor DarkGray }
    $ans = Read-Host '     输入 YES 执行 / 直接回车跳过'
    return ($ans -ceq 'YES')
}

function Get-DirSizeMB([string]$Path) {
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [math]::Round($sum / 1MB, 1)
    } catch { return 0 }
}

function Test-AnyPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath $Path)
}

# ============================================================
# 2. 特征库（全部来自公开情报，见 ioc_db.json / references/02-ioc-library.md）
# ============================================================
$script:IOC = [ordered]@{
    # 推广 / 劫持域名（大小写不敏感，用于内容匹配）
    DomainRx = '(?i)(2345\.com|2354mt\.com|hao123\.com|hao\.360\.cn|999\.com|dabaicai\.(com|cn)|winbaicai\.com|laomaotao\.(net|com)|diannaodian\.com|2345\.cn|wangpai\.2345\.cn|\bby\.[0-9a-z]{4,8}\.(com|cn|net)\b)'

    # 浏览器里出现的推广落地页（含渠道号）
    BrowserUrlRx = '(?i)(2345\.com|2354mt\.com|hao123\.com|999\.com|by\.[0-9a-z]{4,8}\.)'

    # 明确的推广软件进程 / 文件名（强特征）
    ProcRx = '(?i)(^|\\)(2345Update|2345Svc|2345Explorer|2345PCSafe|360Safe|360se|360sd|360Chrome|QHSafe|QHActiveDefense|QQPCMgr|kuwo|iqiyi|QiyiPlayer|laohuangli|wannianli|Ludashi|DrvInst|DriverGenius|kuaizip|NUML0CK)(\.exe)?$'

    # 推广软件目录（显式签名，避免用 '360' 泛匹配误伤）
    PromoDirNames = @(
        '360', '360Safe', '360sd', '360Chrome', '360se', '360Soft',
        '2345Soft', '2345PCSafe', '2345Explorer', '2345',
        'Tencent\QQPCMgr', 'kuwo', 'iqiyi', 'QiyiPlayer',
        'laohuangli', 'wannianli', 'Ludashi', 'DriverGenius', 'DrvInst', 'kuaizip'
    )

    # 推广软件注册表根键
    RegRoots = @(
        'HKCU:\Software\2345.com',
        'HKCU:\Software\2345',
        'HKLM:\SOFTWARE\2345',
        'HKLM:\SOFTWARE\WOW6432Node\2345',
        'HKLM:\SOFTWARE\360Safe',
        'HKLM:\SOFTWARE\WOW6432Node\360Safe',
        'HKLM:\SOFTWARE\360',
        'HKLM:\SOFTWARE\WOW6432Node\360'
    )

    # 大白菜 / 同门工具本体
    ToolNames = @('DaBaiCai', '大白菜', 'LaoMaoTao', '老毛桃', 'DianNaoDian', '电脑店', 'ChenFeng', '晨枫')

    # U 盘 / PE 镜像特征文件
    UsbMarks = @('DBC8x64.ISO', 'DBC8x64.WIM', 'DBCMenu', 'PETools', 'DBC.INI', 'DBC', 'grldr', 'fb.cfg', 'DBC32.ISO')

    # 部署期载荷扩展名
    PayloadExt = @('.img', '.ext')

    # 浏览器首次运行配置文件
    FirstRunFiles = @('initial_preferences', 'master_preferences')

    # 浏览器策略键
    PolicyKeys = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
        'HKCU:\SOFTWARE\Policies\Microsoft\Edge',
        'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge',
        'HKLM:\SOFTWARE\Policies\Google\Chrome',
        'HKCU:\SOFTWARE\Policies\Google\Chrome',
        'HKLM:\SOFTWARE\WOW6432Node\Policies\Google\Chrome'
    )

    # 系统 / 开发工具白名单（不判 Safe，最多 Review）
    WhiteList = @(
        'Microsoft', 'Windows', 'WindowsApps', 'WinSxS', 'System32', 'SysWOW64',
        'Python', 'PlatformIO', 'Arduino', 'Code', 'Git', 'nodejs', 'Java',
        'CH340', 'CP210', 'FTDI', 'Silicon Labs', 'Espressif', 'Realtek', 'Intel', 'NVIDIA', 'AMD'
    )
}

# ============================================================
# 3. 环境基线
# ============================================================
$os        = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$osInstall = if ($os) { $os.InstallDate } else { $null }
$isAdmin   = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$userName  = [Security.Principal.WindowsIdentity]::GetCurrent().Name

function Invoke-Env {
    Write-Head '0 / 环境基线'
    $build = if ($os) { $os.BuildNumber } else { '?' }
    Write-Info ('系统       : ' + $(if($os){$os.Caption}else{'?'}) + '  Build ' + $build)
    Write-Info ('安装日期   : ' + $(if($osInstall){$osInstall.ToString('yyyy-MM-dd HH:mm')}else{'未知'}))
    Write-Info ('当前用户   : ' + $userName + '   管理员令牌: ' + $isAdmin)
    Write-Info ('PowerShell : ' + $PSVersionTable.PSVersion.ToString())
    $mode = if ($script:IsWrite) { '写模式（逐项确认）' } else { '纯只读' }
    Write-Info ('运行模式   : ' + $mode)

    # UAC
    $uacKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    if (Test-Path $uacKey) {
        $u = Get-Item $uacKey -ErrorAction SilentlyContinue
        $lua = $u.GetValue('EnableLUA')
        $cpa = $u.GetValue('ConsentPromptBehaviorAdmin')
        Write-Sub ('UAC: EnableLUA=' + $lua + '  ConsentPromptBehaviorAdmin=' + $cpa)
        if ($lua -eq 0) {
            Add-F 'B 部署期' 'Review' 'UAC 状态' 'UAC 已被完全关闭' `
                'EnableLUA=0。PE 无人值守脚本常用这个设置让推广启动器免提示运行；也可能是你自己关的' `
                $uacKey '人工确认后恢复为 EnableLUA=1 / ConsentPromptBehaviorAdmin=5，改前导出注册表'
        } elseif ($cpa -eq 0 -and $lua -eq 1) {
            Add-F 'B 部署期' 'Review' 'UAC 状态' '管理员提权不弹窗' `
                'ConsentPromptBehaviorAdmin=0，提权静默通过。常与 PE 无人值守脚本同现' `
                $uacKey '确认后可改为 5（默认：提示同意）'
        } else {
            Write-Ok 'UAC 配置正常'
        }
    }

    # 磁盘
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
        $freeGB = [math]::Round($_.FreeSpace / 1GB, 1)
        $totGB  = [math]::Round($_.Size / 1GB, 1)
        Write-Info ('磁盘 ' + $_.DeviceID + ' 可用 ' + $freeGB + ' GB / 共 ' + $totGB + ' GB')
        if ($freeGB -lt 10) {
            Add-F 'E 残留' 'Review' '磁盘空间' ($_.DeviceID + ' 剩余 ' + $freeGB + ' GB') `
                '空间紧张，清理前建议先释放空间，但不要用第三方「一键优化」' $_.DeviceID '优先处理 E 层残留，不要手删 Windows.old'
        }
    }

    # PE 环境自检
    $inPE = $false
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { $inPE = $true }
    if ($env:SystemDrive -eq 'X:') { $inPE = $true }
    if ($inPE) { Write-Warn2 '当前运行在 PE 环境，部分注册表 / 用户目录检查不适用' }
    $script:InPE = $inPE
}

# ============================================================
# A / 源头层
# ============================================================
function Invoke-StageA {
    Write-Head 'A / 源头层：U 盘、PE 镜像、制作工具本体'

    # A1 制作工具安装痕迹
    Write-Sub 'A1 大白菜制作工具本体'
    $toolDirs = New-Object System.Collections.Generic.List[string]
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, $env:APPDATA)) {
        if ([string]::IsNullOrWhiteSpace($pf)) { continue }
        $toolDirs.Add((Join-Path $pf 'DaBaiCai'))
    }
    foreach ($d0 in @('D:\大白菜PE', 'D:\DaBaiCai', 'D:\DBC', 'E:\大白菜PE')) { $toolDirs.Add($d0) }
    $foundTool = $false
    foreach ($d in $toolDirs) {
        if (Test-AnyPath $d) {
            $foundTool = $true
            $mb = if ($Measure) { Get-DirSizeMB $d } else { '' }
            Add-F 'A 源头' 'Review' '制作工具' '大白菜制作工具目录存在' `
                '这是「制作端」而不是「被装机端」。若不再需要制作启动盘，可正常卸载' $d '在「设置 → 应用」里卸载；本工具不代删'
        }
    }
    if (-not $foundTool) { Write-Ok '未发现大白菜制作工具安装目录' }

    # 卸载项
    $uninstRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p) { continue }
            $dn = [string]$p.DisplayName
            foreach ($t in $script:IOC.ToolNames) {
                if ($dn -like ('*' + $t + '*')) {
                    Add-F 'A 源头' 'Review' '制作工具' ('已安装：' + $dn) `
                        ('发布者=' + [string]$p.Publisher + '  版本=' + [string]$p.DisplayVersion) `
                        $k.PSPath '确认不再使用后，走系统卸载'
                }
            }
        }
    }

    # A2 大白菜写入的装机记录（最硬的溯源证据）
    Write-Sub 'A2 装机记录 HKLM\SOFTWARE\DaBaiCai'
    $dbcKeys = @('HKLM:\SOFTWARE\DaBaiCai', 'HKLM:\SOFTWARE\WOW6432Node\DaBaiCai')
    $hitDbc = $false
    foreach ($k in $dbcKeys) {
        if (-not (Test-Path $k)) { continue }
        $hitDbc = $true
        $i = Get-Item $k -ErrorAction SilentlyContinue
        $ver  = [string]$i.GetValue('Version')
        $file = [string]$i.GetValue('FileName')
        $uid  = [string]$i.GetValue('UniqueCode')
        Write-Bad ('发现装机记录键 ' + $k)
        if ($ver)  { Write-Info ('    Version  = ' + $ver) }
        if ($file) { Write-Info ('    FileName = ' + $file) }
        if ($uid)  { Write-Info ('    UniqueCode = ' + $uid) }

        $channels = @()
        $softKey = Join-Path $k 'Soft'
        if (Test-Path $softKey) {
            $si = Get-Item $softKey -ErrorAction SilentlyContinue
            foreach ($n in $si.GetValueNames()) {
                $channels += ($n + '=' + [string]$si.GetValue($n))
            }
        }
        if ($channels.Count -gt 0) {
            Write-Info ('    推广渠道号：' + ($channels -join ' , '))
        }
        Add-F 'A 源头' 'Review' '装机记录' '存在大白菜装机记录键' `
            ('Version=' + $ver + '；镜像=' + $file + '；渠道号 ' + $channels.Count + ' 项：' + ($channels -join ' , ')) `
            $k '这是溯源证据。删除它不会清除任何广告，但能确认系统来源；建议保留以备查'
    }
    if (-not $hitDbc) { Write-Ok '未发现 DaBaiCai 装机记录键' }

    # A3 可移动盘扫描
    Write-Sub 'A3 可移动盘 / U 盘载荷'
    $vols = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction SilentlyContinue)
    if ($vols.Count -eq 0) { Write-Info '当前没有插入可移动盘' }
    foreach ($v in $vols) {
        $root = $v.DeviceID + '\'
        Write-Info ('检查 ' + $root + '  卷标=' + $v.VolumeName + '  可用=' + [math]::Round($v.FreeSpace/1GB,1) + 'GB')
        $marks = @()
        foreach ($m in $script:IOC.UsbMarks) {
            if (Test-Path -LiteralPath (Join-Path $root $m)) { $marks += $m }
        }
        $peDir = Join-Path $root 'PE'
        if (Test-Path -LiteralPath $peDir) {
            foreach ($m in @('DBC8x64.ISO','DBC8x64.WIM','DBC32.ISO','DBC8x86.ISO')) {
                if (Test-Path -LiteralPath (Join-Path $peDir $m)) { $marks += ('PE\' + $m) }
            }
        }
        if ($marks.Count -gt 0) {
            Add-F 'A 源头' 'Safe' 'U 盘载荷' ('疑似大白菜启动盘：' + $v.DeviceID) `
                ('命中特征：' + (($marks | Select-Object -Unique) -join '、') + '。镜像内 Windows\Packages\System32.7z 是推广部署母体') `
                $root '治本做法：重做纯净启动盘；或按 references/03-manual-guide.md 在 PE 镜像里删掉 System32.7z / PF.7z'
        } else {
            Add-F 'A 源头' 'Protect' 'U 盘载荷' ('可移动盘 ' + $v.DeviceID + ' 未命中特征') '正常盘或已清理过的盘' $root ''
        }
    }

    # A4 硬盘上的镜像 / PE 目录残留
    Write-Sub 'A4 硬盘上的镜像与 PE 目录'
    $imgNames = @()
    if ($hitDbc) {
        foreach ($k in $dbcKeys) {
            if (-not (Test-Path $k)) { continue }
            $fn = [string](Get-Item $k).GetValue('FileName')
            if ($fn) { $imgNames += $fn }
        }
    }
    $scanRoots = @('C:\', 'D:\', 'E:\')
    foreach ($r in $scanRoots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        # 只扫根目录一层 + 常见存放目录，避免全盘遍历
        foreach ($f in @(Get-ChildItem -LiteralPath $r -File -Filter '*.iso' -ErrorAction SilentlyContinue)) {
            $isDbc = $false
            foreach ($n in $imgNames) { if ($f.Name -eq $n) { $isDbc = $true } }
            if ($f.Name -match '(?i)dabai|dbc|winbaicai|laomaotao|pe_|pe\.') { $isDbc = $true }
            if ($isDbc) {
                Add-F 'A 源头' 'Review' '镜像残留' ('疑似装机镜像：' + $f.Name) `
                    ([math]::Round($f.Length/1MB,0).ToString() + ' MB；就是这次装机的源文件') $f.FullName `
                    '确认系统已装好、不需要回滚后再删；也可留作证据'
            }
        }
    }
    $peDirs = @('D:\大白菜PE', 'D:\DBC', 'D:\PETools', 'E:\大白菜PE')
    foreach ($d in $peDirs) {
        if (Test-AnyPath $d) {
            $mb = if ($Measure) { Get-DirSizeMB $d } else { '' }
            Add-F 'A 源头' 'Review' 'PE 目录' ('硬盘上残留 PE 目录：' + $d) '装机工具释放的 PE 主程序目录' $d '确认无用后移入回收站'
        }
    }
    Write-Ok 'A 层完成'
}

# ============================================================
# B / 部署期层
# ============================================================
function Invoke-StageB {
    Write-Head 'B / 部署期层：无人值守文件、随机名启动器、载荷分包'

    # B1 无人值守文件
    Write-Sub 'B1 unattend.xml / unattended.xml'
    $panther = Join-Path $env:windir 'Panther'
    $uaFiles = @(
        (Join-Path $panther 'unattend.xml'),
        (Join-Path $panther 'unattended.xml'),
        (Join-Path $panther 'Unattend\unattend.xml')
    )
    $uaHit = $false
    foreach ($ua in $uaFiles) {
        if (-not (Test-Path -LiteralPath $ua)) { continue }
        $uaHit = $true
        $fi = Get-Item -LiteralPath $ua -ErrorAction SilentlyContinue
        $raw = Get-Content -LiteralPath $ua -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        $marks = @()
        if ($raw -match 'RunSynchronousCommand') { $marks += ('RunSynchronousCommand x' + ([regex]::Matches($raw,'RunSynchronousCommand')).Count) }
        if ($raw -match 'FirstLogonCommands')    { $marks += ('FirstLogonCommands x' + ([regex]::Matches($raw,'FirstLogonCommands')).Count) }
        if ($raw -match 'ConsentPromptBehaviorAdmin') { $marks += '关闭 UAC 提示' }
        if ($raw -match 'EnableLUA')             { $marks += 'EnableLUA' }
        if ($raw -match '(?i)net user\s+Administrator') { $marks += '启用 Administrator' }
        if ($raw -match '(?i)Administrator.?ploc')      { $marks += '启用 ploc 账户' }
        if ($raw -cmatch '\\Windows\\[A-Z][a-z]{5,15}\\[A-Z][a-z]{5,15}\.exe') { $marks += '指向随机名启动器' }
        if ($raw -match '(?i)2345|hao123|dabaicai') { $marks += '含推广域名' }

        if ($marks.Count -ge 2) {
            Add-F 'B 部署期' 'Safe' '无人值守文件' 'unattend.xml 命中大白菜装机特征' `
                ('命中 ' + ($marks -join '、') + '；大小 ' + $fi.Length + ' 字节；写入时间 ' + $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) `
                $ua '确认是 PE 装机残留后隔离（工具 -Quarantine 会移入隔离区）；OEM/企业部署也会写此文件，先看内容'
        } elseif ($marks.Count -eq 1) {
            Add-F 'B 部署期' 'Review' '无人值守文件' 'unattend.xml 存在但特征较弱' `
                ('仅命中：' + ($marks -join '、')) $ua '人工核对内容再决定'
        } else {
            Add-F 'B 部署期' 'Review' '无人值守文件' 'unattend.xml 存在，未命中已知特征' `
                ('大小 ' + $fi.Length + ' 字节') $ua '可能是正常的 OEM / 企业自动部署文件，保留'
        }
    }
    if (-not $uaHit) { Write-Ok '未发现无人值守文件' }

    # B2 随机名目录 + 加密载荷
    Write-Sub 'B2 随机名目录与 .img / .ext 载荷'
    $winDirSkip = @(
        'System32','SysWOW64','WinSxS','Panther','Temp','Fonts','Media','Help','inf','Logs','Prefetch',
        'assembly','Boot','CSC','Diagnostics','Globalization','IME','InputMethod','Migration','ModemLogs',
        'Offline','PolicyDefinitions','Registration','Schema','Setup','Speech','Speech_OneCore','SystemApps',
        'SystemResources','TAPI','Tasks','Web','WinBioPlugIns','containers','ServiceProfiles','servicing',
        'SoftwareDistribution','security','appcompat','AppPatch','Cursors','DiagTrack','BrowserCore','debug',
        'Desktop','Resources','ShellExperiences','ShellComponents','ImmersiveControlPanel','SystemTemp',
        'System32','SysWOW64','WaaS','WinRM','Xbox','bcastdvr','CbsTemp','LogFiles','Performance','PLA',
        'RemotePackages','SchCache','security','ServiceProfiles','System32','Temp','tracing','twain_32','WDI'
    )
    $finderCache = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $env:windir) {
        foreach ($d in @(Get-ChildItem -LiteralPath $env:windir -Directory -Force -ErrorAction SilentlyContinue)) {
            $n = $d.Name
            if ($winDirSkip -contains $n) { continue }
            if ($n -notmatch '^[A-Z][A-Za-z]{5,15}$') { continue }
            if ($script:IOC.WhiteList -contains $n) { continue }

            $kids = @(Get-ChildItem -LiteralPath $d.FullName -File -Force -ErrorAction SilentlyContinue | Select-Object -First 60)
            if ($kids.Count -eq 0) { continue }

            $payload = @($kids | Where-Object {
                ($script:IOC.PayloadExt -contains $_.Extension.ToLower()) -or ($_.Name -match '(?i)^(img|support\.img)\d*$')
            })
            $exe = @($kids | Where-Object { $_.Extension -eq '.exe' })

            if ($payload.Count -gt 0) {
                $totalMB = 0
                foreach ($p in $payload) { $totalMB += ($p.Length / 1MB) }
                Add-F 'B 部署期' 'Safe' '随机名载荷目录' ($d.Name + '（含加密分包）') `
                    ('命中 ' + $payload.Count + ' 个 .img/.ext 分包，合计 ' + [math]::Round($totalMB,1) + ' MB；exe ' + $exe.Count + ' 个') `
                    $d.FullName '与公开逆向样本一致（随机名目录 + 11 个加密安装包）。系统目录，工具不代删；确认后建议在 PE 下处理或手动隔离'
                $finderCache.Add($d.FullName)
            } elseif ($exe.Count -gt 0 -and $exe.Count -le 3) {
                $names = ($exe | ForEach-Object { $_.Name }) -join '、'
                Add-F 'B 部署期' 'Review' '疑似随机名目录' ($d.Name + '（含 exe）') `
                    ('顶层有 exe：' + $names + '；无 .img 分包') $d.FullName '低置信度，人工看一眼文件用途再决定'
            }
        }
    }
    if ($finderCache.Count -eq 0) { Write-Ok '未发现带加密分包的随机名目录' }

    # B3 系统盘根目录随机名
    Write-Sub 'B3 系统盘根目录随机名目录'
    $sysRoot = $env:SystemDrive + '\'
    if (Test-Path -LiteralPath $sysRoot) {
        foreach ($d in @(Get-ChildItem -LiteralPath $sysRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            $n = $d.Name
            if ($script:IOC.WhiteList -contains $n) { continue }
            if ($n -notmatch '^[A-Z][A-Za-z]{5,15}$') { continue }
            $kids = @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 20)
            if ($kids.Count -eq 0) { continue }
            $exe = @($kids | Where-Object { $_.Extension -eq '.exe' })
            if ($exe.Count -gt 0) {
                Add-F 'B 部署期' 'Review' '根目录随机名目录' ($sysRoot + $n) `
                    ('含 exe：' + (($exe | ForEach-Object { $_.Name }) -join '、') + '。公开样本中出现过 C:\Uexqgrydo\Wmdnbc.exe') `
                    $d.FullName '人工确认；不认识的建议先改名为 .bak 观察两天'
            }
        }
    }

    # B4 NUML0CK / 部署程序残留
    Write-Sub 'B4 NUML0CK 与部署程序残留'
    $numl = @()
    foreach ($p in @((Join-Path $env:windir 'System32'), (Join-Path $env:windir 'SysWOW64'))) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $numl += @(Get-ChildItem -LiteralPath $p -File -Filter 'NUML0CK*' -Force -ErrorAction SilentlyContinue)
    }
    # 再按注册表 Uninstall 里搜 NUML0CK 命名
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path $root)) { continue }
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -match '(?i)NUML0CK') { $numl += $k.PSPath }
        }
    }
    if ($numl.Count -gt 0) {
        foreach ($x in $numl) {
            Add-F 'B 部署期' 'Safe' '部署程序' 'NUML0CK 部署器残留' 'PE 阶段解压执行的部署程序（AutoIt 编译，混淆）' ([string]$x) '确认后隔离；它是 PE 期临时程序，重启后一般不该存在'
        }
    } else { Write-Ok '未发现 NUML0CK 残留' }

    # B5 伪装计划任务
    Write-Sub 'B5 计划任务（伪装成系统组件）'
    $taskHit = 0
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        $acts = @($t.Actions | ForEach-Object { ([string]$_.Execute + ' ' + [string]$_.Arguments) })
        $joined = ($acts -join ' ')
        if ([string]::IsNullOrWhiteSpace($joined)) { continue }

        $why = ''
        if ($joined -match $script:IOC.DomainRx) { $why = '动作含推广域名' }
        elseif ($joined -cmatch '\\Windows\\[A-Z][a-z]{5,15}\\[A-Z][a-z]{5,15}\.exe') { $why = '动作指向随机名启动器' }
        elseif ($joined -match '(?i)\\AppData\\(Local|Roaming)\\Temp\\|\\Windows\\Temp\\') { $why = '动作在临时目录' }
        elseif ($joined -match $script:IOC.ProcRx) { $why = '动作是可识别推广程序' }

        if ($why) {
            $taskHit++
            Add-F 'B 部署期' 'Safe' '计划任务' ($t.TaskPath + $t.TaskName) `
                ($why + '；状态=' + $t.State + '；动作=' + $joined.Substring(0, [math]::Min(200, $joined.Length))) `
                ($t.TaskPath + $t.TaskName) '-Fix 会导出 XML 后禁用（不删除），可随时重新启用'
        }
    }
    if ($taskHit -eq 0) { Write-Ok '未发现伪装计划任务' }
    Write-Ok 'B 层完成'
}

# ============================================================
# C / 落地层
# ============================================================
function Get-InstalledApps {
    $out = New-Object System.Collections.Generic.List[object]
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p) { continue }
            $dn = [string]$p.DisplayName
            if ([string]::IsNullOrWhiteSpace($dn)) { continue }
            $d = [string]$p.InstallDate
            $dt = $null
            if ($d -match '^\d{8}$') {
                try { $dt = [datetime]::ParseExact($d, 'yyyyMMdd', $null) } catch { $dt = $null }
            }
            $out.Add([pscustomobject]@{
                Name        = $dn
                Publisher   = [string]$p.Publisher
                Version     = [string]$p.DisplayVersion
                InstallDate = $dt
                Location    = [string]$p.InstallLocation
                RegPath     = $k.PSPath
            })
        }
    }
    return $out
}

function Invoke-StageC {
    Write-Head 'C / 落地层：推广软件、注册表、服务、启动项、快捷方式'

    $apps = Get-InstalledApps
    Write-Info ('已安装程序共 ' + $apps.Count + ' 项')

    # C1 按安装日期比对
    Write-Sub 'C1 装机时间窗口内的新装软件（±3 天）'
    if ($osInstall) {
        $lo = $osInstall.Date.AddDays(-3)
        $hi = $osInstall.Date.AddDays(3)
        $recent = @($apps | Where-Object { $_.InstallDate -ne $null -and $_.InstallDate -ge $lo -and $_.InstallDate -le $hi })
        Write-Info ('窗口 ' + $lo.ToString('yyyy-MM-dd') + ' ~ ' + $hi.ToString('yyyy-MM-dd') + '，窗口内 ' + $recent.Count + ' 项')

        # 系统组件 / 运行库 / 已知大厂：不算可疑，避免报告被 Visual C++ 之类刷满
        $vendorOk = '(?i)^(Microsoft|Intel|NVIDIA|AMD|Advanced Micro Devices|Realtek|Apple|Google|Python Software Foundation|Oracle|Adobe)'
        $runtimeOk = '(?i)(Visual C\+\+|\.NET|Windows SDK|Runtime|Redistributable|WebView2|DirectX|Update for|Security Update|Hotfix|Launcher$)'

        $suspect = New-Object System.Collections.Generic.List[object]
        $benign  = New-Object System.Collections.Generic.List[object]
        foreach ($a in $recent) {
            if (($a.Publisher -match $vendorOk) -or ($a.Name -match $runtimeOk)) { $benign.Add($a) }
            else { $suspect.Add($a) }
        }
        Write-Info ('其中系统组件/运行库 ' + $benign.Count + ' 项（正常），待确认 ' + $suspect.Count + ' 项')

        $shown = 0
        foreach ($a in $suspect) {
            if ($shown -ge 30) { break }
            $shown++
            Add-F 'C 落地' 'Review' '近期安装' $a.Name `
                ('安装日期=' + $a.InstallDate.ToString('yyyy-MM-dd') + '；发布者=' + $a.Publisher + '；版本=' + $a.Version) `
                $a.RegPath '对照清单确认是否自己装的；不是就走系统卸载，再用 Geek Uninstaller 扫残留'
        }
        if ($suspect.Count -gt $shown) {
            Add-F 'C 落地' 'Review' '近期安装' ('另有 ' + ($suspect.Count - $shown) + ' 项未逐条列出') `
                '完整列表见 findings.json 之外的注册表卸载项' '' '打开「设置 → 应用」按安装日期排序自行核对'
        }
        if ($benign.Count -gt 0) {
            Add-F 'C 落地' 'Protect' '近期安装' ('系统组件 / 运行库 ' + $benign.Count + ' 项') `
                '发布者为微软等大厂，或属于 VC++ / .NET / WebView2 等运行库' '' '正常，无需处理'
        }
    } else {
        Write-Warn2 '取不到系统安装日期，跳过 C1'
    }

    # C2 推广软件目录
    Write-Sub 'C2 推广软件目录'
    $dirRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA)
    foreach ($dr in $dirRoots) {
        if ([string]::IsNullOrWhiteSpace($dr) -or -not (Test-Path -LiteralPath $dr)) { continue }
        foreach ($sig in $script:IOC.PromoDirNames) {
            $p = Join-Path $dr $sig
            if (Test-Path -LiteralPath $p) {
                $mb = if ($Measure) { Get-DirSizeMB $p } else { '' }
                Add-F 'C 落地' 'Safe' '推广目录' ($sig + '  @ ' + $dr) `
                    ('确认属于 2345/360 等推广软件' + $(if($mb){'；体积 ' + $mb + ' MB'})) $p `
                    '-Quarantine 可移入隔离区（不是直接删除），确认无用后再清空隔离区释放空间'
            }
        }
    }

    # C3 注册表推广根键
    Write-Sub 'C3 推广软件注册表键'
    foreach ($k in $script:IOC.RegRoots) {
        if (Test-Path -LiteralPath $k) {
            $i = Get-Item -LiteralPath $k -ErrorAction SilentlyContinue
            $vals = ''
            if ($i) { $vals = (($i.GetValueNames() | Select-Object -First 6 | ForEach-Object { $_ + '=' + [string]$i.GetValue($_) }) -join ' , ') }
            Add-F 'C 落地' 'Safe' '注册表' ('推广注册表键 ' + $k) $vals $k '-PurgeReg 会先导出 .reg 备份再删除'
        }
    }

    # C4 服务与驱动
    Write-Sub 'C4 服务 / 驱动'
    $svcHit = 0
    foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        $pn = [string]$s.PathName
        if ($pn -match $script:IOC.ProcRx -or $pn -match '(?i)2345|360Safe|360sd|QQPCMgr|kuwo|laomatao|dabaicai') {
            $svcHit++
            Add-F 'C 落地' 'Review' '服务' ($s.Name + ' (' + $s.State + ')') `
                ('路径=' + $pn + '；启动=' + $s.StartMode) ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $s.Name) `
                '确认属于推广软件后：先 stop 再 disable，别急着 delete；删除前导出注册表'
        }
    }
    $drvHit = 0
    $drvDir = Join-Path $env:windir 'System32\drivers'
    if (Test-Path -LiteralPath $drvDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $drvDir -File -Filter '*.sys' -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '(?i)^(360|2345|tao|bd00|kisknl)') {
                $drvHit++
                Add-F 'C 落地' 'Review' '驱动' ('疑似推广驱动 ' + $f.Name) `
                    ('大小 ' + [math]::Round($f.Length/1KB,0) + ' KB；修改时间 ' + $f.LastWriteTime.ToString('yyyy-MM-dd')) $f.FullName `
                    '驱动级残留建议先在「设备管理器 → 显示隐藏的设备」里卸载对应设备，再处理文件；不要直接删 .sys'
            }
        }
    }
    if ($svcHit -eq 0 -and $drvHit -eq 0) { Write-Ok '未发现推广服务/驱动' }

    # C5 启动项
    Write-Sub 'C5 注册表启动项'
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    $runHit = 0
    foreach ($k in $runKeys) {
        if (-not (Test-Path $k)) { continue }
        $i = Get-Item -LiteralPath $k -ErrorAction SilentlyContinue
        if (-not $i) { continue }
        foreach ($n in @($i.GetValueNames())) {
            $v = [string]$i.GetValue($n)
            $why = ''
            if ($v -match $script:IOC.DomainRx) { $why = '启动命令含推广域名' }
            elseif ($v -match $script:IOC.ProcRx) { $why = '启动可识别推广程序' }
            elseif ($v -cmatch '\\Windows\\[A-Z][a-z]{5,15}\\[A-Z][a-z]{5,15}\.exe') { $why = '指向随机名启动器' }
            if ($why) {
                $runHit++
                Add-F 'C 落地' 'Safe' '启动项' $n $why ($k + ' \ ' + $n) '-Fix 会导出 .reg 备份后删除该值'
            }
        }
    }
    if ($runHit -eq 0) { Write-Ok '未发现推广启动项' }

    # C6 启动文件夹
    Write-Sub 'C6 启动文件夹'
    $startupDirs = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup')
    )
    foreach ($d in $startupDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)) {
            if ($f.Name -ieq 'desktop.ini') { continue }
            Add-F 'C 落地' 'Review' '启动文件夹' $f.Name `
                ('大小 ' + $f.Length + ' 字节；写入 ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) $f.FullName `
                '逐个确认来源；不认识的先移出启动文件夹观察'
        }
    }

    # C7 快捷方式尾巴
    Write-Sub 'C7 快捷方式目标是否被追加网址'
    $sh = New-Object -ComObject WScript.Shell
    $lnkDirs = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        'C:\Users\Public\Desktop',
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    )
    $broken = 0
    foreach ($d in $lnkDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $l = $sh.CreateShortcut($f.FullName)
                $a = [string]$l.Arguments
                if ($a -match $script:IOC.DomainRx) {
                    $broken++
                    Add-F 'C 落地' 'Safe' '快捷方式劫持' $f.Name ('参数里被追加了网址：' + $a) $f.FullName `
                        '-Fix 会备份 .lnk 后清掉参数里的网址（只改参数，不动目标程序）'
                }
            } catch { }
        }
    }
    if ($broken -eq 0) { Write-Ok '未发现快捷方式被追加网址' }

    # C8 hosts
    Write-Sub 'C8 hosts'
    $hosts = Join-Path $env:windir 'System32\drivers\etc\hosts'
    if (Test-Path -LiteralPath $hosts) {
        $lines = @(Get-Content -LiteralPath $hosts -ErrorAction SilentlyContinue)
        $bad = @()
        foreach ($ln in $lines) {
            $t = $ln.Trim()
            if ($t.StartsWith('#') -or $t.Length -eq 0) { continue }
            if ($t -match $script:IOC.DomainRx) { $bad += $t }
        }
        if ($bad.Count -gt 0) {
            Add-F 'C 落地' 'Safe' 'hosts' ('hosts 里有 ' + $bad.Count + ' 条推广域名') ($bad -join ' | ') $hosts `
                '-Fix 会先把 hosts 备份成 hosts.dbc_bak，再把这些行注释掉（不删行，可回滚）'
        } else {
            Add-F 'C 落地' 'Protect' 'hosts' 'hosts 未发现推广域名' ('共 ' + $lines.Count + ' 行') $hosts ''
        }
    }

    # C9 代理（只报告）
    Write-Sub 'C9 系统代理'
    $ieKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if (Test-Path $ieKey) {
        $ie = Get-ItemProperty -LiteralPath $ieKey -ErrorAction SilentlyContinue
        if ($ie.ProxyEnable -eq 1) {
            Add-F 'C 落地' 'Review' '代理设置' '系统代理处于启用状态' `
                ('ProxyServer=' + [string]$ie.ProxyServer + '；Override=' + [string]$ie.ProxyOverride) $ieKey `
                '大概率是你自己的代理工具。工具不会改代理；确认不是自己的再手动关'
        } else {
            Write-Ok '未启用系统代理'
        }
    }

    # C10 收藏夹 / 书签
    Write-Sub 'C10 收藏夹里的预置推广链接'
    $favDirs = @(
        (Join-Path $env:USERPROFILE 'Favorites'),
        'C:\Users\Public\Favorites',
        (Join-Path $env:windir '..\Users\Default\Favorites')
    )
    $favHit = 0
    foreach ($d in $favDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Recurse -ErrorAction SilentlyContinue)) {
            $txt = ''
            try { $txt = [System.IO.File]::ReadAllText($f.FullName) } catch { continue }
            if ($txt -match $script:IOC.DomainRx) {
                $favHit++
                Add-F 'C 落地' 'Safe' '收藏夹' $f.Name '收藏内容含推广域名（PE 会预置收藏夹文件）' $f.FullName `
                    '-Fix 会把这些 .url 移入隔离区，不是删除'
            }
        }
    }
    if ($favHit -eq 0) { Write-Ok '收藏夹未发现推广链接' }

    # C11 文件关联
    Write-Sub 'C11 文件与协议关联'
    $assoc = @(
        @{ K = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.html\UserChoice'; N = '.html' },
        @{ K = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'; N = 'http' },
        @{ K = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'; N = 'https' }
    )
    foreach ($a in $assoc) {
        if (-not (Test-Path $a.K)) { continue }
        $prog = [string](Get-ItemProperty -LiteralPath $a.K -ErrorAction SilentlyContinue).ProgId
        if ($prog -match '(?i)360|2345|hao123') {
            Add-F 'C 落地' 'Review' '文件关联' ($a.N + ' 被指向 ' + $prog) `
                'UserChoice 带哈希校验，直接改注册表会被系统重置' $a.K `
                '走「设置 → 应用 → 默认应用」改回 Edge/Chrome，工具不碰'
        } else {
            Write-Info ($a.N + ' => ' + $prog)
        }
    }

    # C12 WMI 事件订阅
    Write-Sub 'C12 WMI 事件订阅（复活机制）'
    $wmiHit = 0
    foreach ($cls in @('CommandLineEventConsumer','ActiveScriptEventConsumer')) {
        foreach ($x in @(Get-CimInstance -Namespace 'root\subscription' -ClassName $cls -ErrorAction SilentlyContinue)) {
            $txt = [string]$x.CommandLineTemplate + ' ' + [string]$x.ScriptText
            if ($txt -match $script:IOC.DomainRx -or $txt -match '(?i)AppData|Temp') {
                $wmiHit++
                Add-F 'C 落地' 'Safe' 'WMI 订阅' ('可疑永久事件订阅：' + $x.Name) `
                    ($txt.Substring(0, [math]::Min(180, $txt.Length))) 'root\subscription' `
                    '删除订阅要连 __FilterToConsumerBinding 一起删；建议用 Autoruns 的 WMI 页签处理'
            }
        }
    }
    if ($wmiHit -eq 0) { Write-Ok 'WMI 订阅未发现异常' }
    Write-Ok 'C 层完成'
}

# ============================================================
# D / 浏览器层
# ============================================================
function Get-BrowserProfiles {
    $list = New-Object System.Collections.Generic.List[object]
    $defs = @(
        @{ Name = 'Edge';   Install = @('C:\Program Files (x86)\Microsoft\Edge\Application', 'C:\Program Files\Microsoft\Edge\Application'); Data = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') },
        @{ Name = 'Chrome'; Install = @('C:\Program Files\Google\Chrome\Application', 'C:\Program Files (x86)\Google\Chrome\Application'); Data = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') }
    )
    foreach ($d in $defs) {
        $inst = $null
        foreach ($p in $d.Install) { if (Test-Path -LiteralPath $p) { $inst = $p; break } }
        $list.Add([pscustomobject]@{ Name = $d.Name; InstallDir = $inst; DataDir = $d.Data })
    }
    return $list
}

function Invoke-StageD {
    if ($SkipBrowser) { Write-Head 'D / 浏览器层（已按要求跳过）'; return }
    Write-Head 'D / 浏览器层：启动配置、会话、策略、通知、缓存'

    foreach ($b in (Get-BrowserProfiles)) {
        Write-Sub ($b.Name + ' 检查')
        $dataExists = Test-Path -LiteralPath $b.DataDir
        if (-not $dataExists -and -not $b.InstallDir) { Write-Info ('未安装 ' + $b.Name); continue }

        # D1 首次运行配置
        if ($b.InstallDir) {
            foreach ($fn in $script:IOC.FirstRunFiles) {
                $p = Join-Path $b.InstallDir $fn
                if (-not (Test-Path -LiteralPath $p)) { continue }
                $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
                $raw = Get-Content -LiteralPath $p -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if (-not $raw) { continue }
                $hitDom = ($raw -match '(?i)2345|2354mt|hao123|999\.com')
                $hitSess = ($raw -match '(?i)"restore_on_startup"\s*:\s*4|"startup_urls"\s*:\s*\[[^\]]+\]')
                if ($hitDom -or $hitSess) {
                    $home = ''
                    try { $home = [string](($raw | ConvertFrom-Json).homepage) } catch { }
                    Add-F 'D 浏览器' 'Safe' '首次运行配置' ($b.Name + ' 的 ' + $fn + ' 被植入推广') `
                        ('homepage=' + $home + '；含启动页列表；写入时间 ' + $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + '。官方安装不带这个文件') `
                        $p '-Fix 优先改名为 .dbc_bak（需管理员）；没有权限时改为重写 4 个字段'
                } else {
                    Add-F 'D 浏览器' 'Review' '首次运行配置' ($b.Name + ' 存在 ' + $fn) ('大小 ' + $fi.Length + ' 字节，未命中推广特征') $p '大概率是 OEM 定制，可保留'
                }
            }
        }

        if (-not $dataExists) { continue }

        # D2 默认 Profile 的 Preferences
        $profiles = @(Get-ChildItem -LiteralPath $b.DataDir -Directory -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        foreach ($pf in $profiles) {
            $prefPath = Join-Path $pf.FullName 'Preferences'
            if (Test-Path -LiteralPath $prefPath) {
                $raw = Get-Content -LiteralPath $prefPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($raw) {
                    $j = $null
                    try { $j = $raw | ConvertFrom-Json } catch { }
                    if ($j) {
                        $su = ''
                        if ($j.session -and $j.session.startup_urls) { $su = (@($j.session.startup_urls) -join ' | ') }
                        $hp = [string]$j.homepage
                        if ($su -match $script:IOC.BrowserUrlRx -or $hp -match $script:IOC.BrowserUrlRx) {
                            Add-F 'D 浏览器' 'Safe' '启动页配置' ($b.Name + ' / ' + $pf.Name + ' 启动页被劫持') `
                                ('startup_urls=' + $su + '；homepage=' + $hp + '；restore_on_startup=' + [string]$j.session.restore_on_startup) `
                                $prefPath '人工在「启动时」改回新标签页，或浏览器内「恢复设置到原始默认值」'
                        }
                        # 通知权限
                        $notif = $j.profile.content_settings.exceptions.notifications
                        if ($notif) {
                            foreach ($pr in $notif.PSObject.Properties) {
                                if ($pr.Name -match $script:IOC.BrowserUrlRx) {
                                    Add-F 'D 浏览器' 'Safe' '站点通知权限' ($b.Name + ' 允许 ' + $pr.Name + ' 发通知') `
                                        ('setting=' + [string]$pr.Value.setting) ($prefPath + ' → content_settings.exceptions.notifications') `
                                        '-Fix 会把该站点通知权限改成 block（不删站点数据）'
                                }
                            }
                        }
                        # 扩展
                        if ($j.extensions -and $j.extensions.settings) {
                            foreach ($pr in $j.extensions.settings.PSObject.Properties) {
                                $mn = [string]$pr.Value.manifest.name
                                $mu = [string]$pr.Value.manifest.homepage_url
                                if (($mn + ' ' + $mu) -match $script:IOC.BrowserUrlRx) {
                                    Add-F 'D 浏览器' 'Review' '扩展' ($b.Name + ' 可疑扩展：' + $mn) ('state=' + [string]$pr.Value.state + ' url=' + $mu) $prefPath '在 edge://extensions / chrome://extensions 里移除，别只停用'
                                }
                            }
                        }
                        # 默认搜索引擎
                        $dse = $j.default_search_provider_data
                        if ($dse -and ([string]$dse | Out-String) -match $script:IOC.BrowserUrlRx) {
                            Add-F 'D 浏览器' 'Safe' '默认搜索引擎' ($b.Name + ' 默认搜索被改成推广源') '包含推广域名' $prefPath '在浏览器设置里改回（如 Bing / 百度 / 谷歌）'
                        }
                    }
                }
            }

            # D3 会话文件
            $sessDir = Join-Path $pf.FullName 'Sessions'
            if (Test-Path -LiteralPath $sessDir) {
                $hit = 0
                foreach ($f in @(Get-ChildItem -LiteralPath $sessDir -File -ErrorAction SilentlyContinue)) {
                    if ($f.Name -notmatch '^(Session_|Tabs_)') { continue }
                    try {
                        $s = $script:Lat.GetString([System.IO.File]::ReadAllBytes($f.FullName))
                        $c = ([regex]::Matches($s, $script:IOC.BrowserUrlRx)).Count
                        if ($c -gt 0) {
                            $hit++
                            Add-F 'D 浏览器' 'Safe' '会话恢复' ($b.Name + ' 会话文件含推广标签：' + $f.Name) `
                                ('命中 ' + $c + ' 处；写入 ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + '。这是「改了设置还复活」的真正原因') `
                                $f.FullName '-Fix 会把文件移入隔离区（移动不是删除）；必须先把浏览器完全退出'
                        }
                    } catch { }
                }
                if ($hit -eq 0) { Write-Info ($b.Name + ' / ' + $pf.Name + ' 会话文件干净') }
            }

            # D4 缓存里的推广脚本
            $ccDir = Join-Path $pf.FullName 'Code Cache\js'
            if (Test-Path -LiteralPath $ccDir) {
                $n = 0
                foreach ($f in @(Get-ChildItem -LiteralPath $ccDir -File -ErrorAction SilentlyContinue)) {
                    try {
                        $s = $script:Lat.GetString([System.IO.File]::ReadAllBytes($f.FullName))
                        if ($s -match $script:IOC.BrowserUrlRx) { $n++ }
                    } catch { }
                }
                if ($n -gt 0) {
                    Add-F 'D 浏览器' 'Safe' '脚本缓存' ($b.Name + ' 缓存里含推广脚本 ' + $n + ' 个') 'Code Cache\js 中的编译缓存' $ccDir '-Fix 会把这些文件移入隔离区；浏览器会自动重建缓存'
                }
            }
        }

        # D5 组策略
        foreach ($pk in $script:IOC.PolicyKeys) {
            if (-not (Test-Path $pk)) { continue }
            $i = Get-Item -LiteralPath $pk -ErrorAction SilentlyContinue
            if (-not $i) { continue }
            $names = @($i.GetValueNames())
            $susp = @()
            foreach ($n in $names) {
                $v = [string]$i.GetValue($n)
                if ($n -match '(?i)Homepage|RestoreOnStartup|StartupURLs|NewTabPageLocation' -and $v -match $script:IOC.BrowserUrlRx) {
                    $susp += ($n + '=' + $v)
                }
            }
            $sub = Join-Path $pk 'RestoreOnStartupURLs'
            if (Test-Path $sub) {
                $si = Get-Item -LiteralPath $sub -ErrorAction SilentlyContinue
                foreach ($n in @($si.GetValueNames())) {
                    $v = [string]$si.GetValue($n)
                    if ($v -match $script:IOC.BrowserUrlRx) { $susp += ('RestoreOnStartupURLs\' + $n + '=' + $v) }
                }
            }
            if ($susp.Count -gt 0) {
                Add-F 'D 浏览器' 'Safe' '组策略锁定' ($b.Name + ' 被策略键锁定首页') ($susp -join ' | ') $pk `
                    '这是「设置项灰掉改不了」的原因。工具只报告：策略键由安全软件或系统管理写，删错可能影响其他策略'
            }
        }
    }
    Write-Ok 'D 层完成'
}

# ============================================================
# E / 残留层
# ============================================================
function Invoke-StageE {
    Write-Head 'E / 残留层：旧系统、PE 目录、临时文件'
    $sysDrive = $env:SystemDrive

    $old = @(
        (Join-Path $sysDrive '\Windows.old'),
        (Join-Path $sysDrive '\$Windows.~BT'),
        (Join-Path $sysDrive '\$Windows.~WS'),
        (Join-Path $sysDrive '\$WinREAgent')
    )
    foreach ($p in $old) {
        if (Test-AnyPath $p) {
            $mb = if ($Measure) { Get-DirSizeMB $p } else { 0 }
            Add-F 'E 残留' 'Review' '旧系统' ([System.IO.Path]::GetFileName($p)) `
                ('体积约 ' + $mb + ' MB。旧系统完整残留，常是 C 盘爆满主因') $p `
                '必须走「设置 → 系统 → 存储 → 临时文件 → 删除以前版本的 Windows」，不要手删；删后无法回滚旧系统'
        }
    }

    $tmp = Join-Path $env:windir 'Temp'
    if (Test-Path -LiteralPath $tmp) {
        $mb = if ($Measure) { Get-DirSizeMB $tmp } else { 0 }
        $cnt = @(Get-ChildItem -LiteralPath $tmp -Force -ErrorAction SilentlyContinue).Count
        Add-F 'E 残留' 'Protect' '临时目录' ('Windows\Temp 共 ' + $cnt + ' 项') ('体积约 ' + $mb + ' MB') $tmp '系统临时目录，工具不碰；要清就走「存储 → 临时文件」'
    }

    $drvPack = @('C:\Drivers', 'D:\Drivers', 'C:\万能驱动', 'D:\万能驱动')
    foreach ($d in $drvPack) {
        if (Test-AnyPath $d) {
            $mb = if ($Measure) { Get-DirSizeMB $d } else { 0 }
            Add-F 'E 残留' 'Review' '驱动包' ('PE 带的驱动包：' + $d) ('体积约 ' + $mb + ' MB') $d '确认驱动已装好后可删；但重装系统可能还要用，建议先移到移动硬盘'
        }
    }

    # 回收站体积
    $rb = Join-Path $sysDrive '\$Recycle.Bin'
    if (Test-Path -LiteralPath $rb) {
        $mb = if ($Measure) { Get-DirSizeMB $rb } else { 0 }
        if ($mb -gt 100) {
            Add-F 'E 残留' 'Review' '回收站' '回收站占用较大' ('约 ' + $mb + ' MB；清空前确认里面没有被隔离的重要文件') $rb '本工具移入隔离区的文件不在回收站，需要你手动清理隔离目录才释放空间'
        }
    }
    Write-Ok 'E 层完成'
}

# ============================================================
# 4. 写操作
# ============================================================
function New-BackupDir {
    if (-not (Test-Path -LiteralPath $script:BackupDir)) {
        $null = New-Item -ItemType Directory -Path $script:BackupDir -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $script:Quarantine)) {
        $null = New-Item -ItemType Directory -Path $script:Quarantine -Force -ErrorAction SilentlyContinue
    }
}

function Move-ToQuarantine([string]$Source, [string]$Sub = '') {
    New-BackupDir
    $destDir = $script:Quarantine
    if ($Sub) {
        $destDir = Join-Path $script:Quarantine $Sub
        if (-not (Test-Path -LiteralPath $destDir)) { $null = New-Item -ItemType Directory -Path $destDir -Force -ErrorAction SilentlyContinue }
    }
    $leaf = Split-Path -Leaf $Source
    $dest = Join-Path $destDir $leaf
    if (Test-Path -LiteralPath $dest) { $dest = $dest + '.' + (Get-Date -Format 'HHmmss') }
    try {
        Move-Item -LiteralPath $Source -Destination $dest -Force -ErrorAction Stop
        return @{ Ok = $true; Dest = $dest }
    } catch {
        return @{ Ok = $false; Dest = ''; Msg = $_.Exception.Message }
    }
}

function Invoke-Fix {
    Write-Head '写操作 / 可逆修复'
    New-BackupDir
    Write-Info ('隔离区：' + $script:Quarantine)

    # F1 浏览器首次运行配置
    foreach ($b in (Get-BrowserProfiles)) {
        if (-not $b.InstallDir) { continue }
        foreach ($fn in $script:IOC.FirstRunFiles) {
            $p = Join-Path $b.InstallDir $fn
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $raw = Get-Content -LiteralPath $p -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $raw) { continue }
            if (-not ($raw -match '(?i)2345|2354mt|hao123|999\.com|"restore_on_startup"\s*:\s*4')) { continue }

            if (Confirm-Step ('改名被植入的 ' + $b.Name + ' 首次运行配置') ($p + '  →  ' + $p + '.dbc_bak')) {
                $bak = $p + '.dbc_bak'
                try {
                    if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue }
                    Rename-Item -LiteralPath $p -NewName ($fn + '.dbc_bak') -Force -ErrorAction Stop
                    Write-Ok '已改名，反安装不会重建'
                    Rec-Act 'RenameFirstRunPrefs' $p 'OK'
                } catch {
                    Write-Warn2 ('改名失败（权限）：' + $_.Exception.Message)
                    Write-Info '改为重写 4 个劫持字段（不改变文件的其余内容）'
                    try {
                        $copy = Join-Path $script:BackupDir ($fn + '.' + $b.Name)
                        Copy-Item -LiteralPath $p -Destination $copy -Force -ErrorAction SilentlyContinue
                        $j = $raw | ConvertFrom-Json
                        $j.homepage = ''
                        $j.homepage_is_newtabpage = $true
                        if ($j.session) {
                            $j.session.restore_on_startup = 5
                            $j.session.startup_urls = @()
                        }
                        $out = $j | ConvertTo-Json -Depth 14 -Compress
                        [System.IO.File]::WriteAllText($p, $out, (New-Object System.Text.UTF8Encoding($false)))
                        Write-Ok '已重写劫持字段'
                        Rec-Act 'RewriteFirstRunPrefs' $p 'OK(rewrite)'
                    } catch {
                        Write-Bad ('重写也失败：' + $_.Exception.Message)
                        Rec-Act 'RewriteFirstRunPrefs' $p ('FAIL: ' + $_.Exception.Message)
                    }
                }
            }
        }
    }

    # F2 浏览器会话 + 缓存
    foreach ($b in (Get-BrowserProfiles)) {
        if (-not (Test-Path -LiteralPath $b.DataDir)) { continue }
        $procs = @(Get-Process -Name ($b.Name.ToLower()) -ErrorAction SilentlyContinue)
        if ($procs.Count -gt 0) {
            Write-Warn2 ($b.Name + ' 还在运行（' + $procs.Count + ' 个进程），跳过会话与缓存清理，否则退出时会把标签写回去')
            Rec-Act 'SkipBrowserSessions' $b.Name ('RUNNING:' + $procs.Count)
            continue
        }
        $profiles = @(Get-ChildItem -LiteralPath $b.DataDir -Directory -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        foreach ($pf in $profiles) {
            $sessDir = Join-Path $pf.FullName 'Sessions'
            if (Test-Path -LiteralPath $sessDir) {
                $targets = @()
                foreach ($f in @(Get-ChildItem -LiteralPath $sessDir -File -ErrorAction SilentlyContinue)) {
                    if ($f.Name -notmatch '^(Session_|Tabs_)') { continue }
                    try {
                        $s = $script:Lat.GetString([System.IO.File]::ReadAllBytes($f.FullName))
                        if ($s -match $script:IOC.BrowserUrlRx) { $targets += $f.FullName }
                    } catch { }
                }
                if ($targets.Count -gt 0) {
                    if (Confirm-Step ('隔离 ' + $b.Name + ' 含推广标签的会话文件（' + $targets.Count + ' 个）') (($targets | ForEach-Object { Split-Path -Leaf $_ }) -join '、')) {
                        foreach ($t in $targets) {
                            $r = Move-ToQuarantine $t 'Sessions'
                            if ($r.Ok) { Write-Ok ('已隔离 ' + (Split-Path -Leaf $t)); Rec-Act 'QuarantineSession' $t 'OK' }
                            else { Write-Bad ('失败 ' + (Split-Path -Leaf $t) + '：' + $r.Msg); Rec-Act 'QuarantineSession' $t ('FAIL: ' + $r.Msg) }
                        }
                    }
                }
            }
            $ccDir = Join-Path $pf.FullName 'Code Cache\js'
            if (Test-Path -LiteralPath $ccDir) {
                $targets = @()
                foreach ($f in @(Get-ChildItem -LiteralPath $ccDir -File -ErrorAction SilentlyContinue)) {
                    try {
                        $s = $script:Lat.GetString([System.IO.File]::ReadAllBytes($f.FullName))
                        if ($s -match $script:IOC.BrowserUrlRx) { $targets += $f.FullName }
                    } catch { }
                }
                if ($targets.Count -gt 0) {
                    if (Confirm-Step ('隔离 ' + $b.Name + ' 缓存中的推广脚本（' + $targets.Count + ' 个）') 'Code Cache\js，浏览器会自动重建') {
                        $okN = 0
                        foreach ($t in $targets) {
                            $r = Move-ToQuarantine $t 'CodeCache'
                            if ($r.Ok) { $okN++ }
                        }
                        Write-Ok ('已隔离 ' + $okN + ' / ' + $targets.Count)
                        Rec-Act 'QuarantineCodeCache' $ccDir ('moved ' + $okN + '/' + $targets.Count)
                    }
                }
            }
        }
    }

    # F3 启动项
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    $hitVals = @()
    foreach ($k in $runKeys) {
        if (-not (Test-Path $k)) { continue }
        $i = Get-Item -LiteralPath $k -ErrorAction SilentlyContinue
        if (-not $i) { continue }
        foreach ($n in @($i.GetValueNames())) {
            $v = [string]$i.GetValue($n)
            if ($v -match $script:IOC.DomainRx -or $v -match $script:IOC.ProcRx -or $v -cmatch '\\Windows\\[A-Z][a-z]{5,15}\\[A-Z][a-z]{5,15}\.exe') {
                $hitVals += [pscustomobject]@{ Key = $k; Name = $n; Value = $v }
            }
        }
    }
    if ($hitVals.Count -gt 0) {
        if (Confirm-Step ('删除 ' + $hitVals.Count + ' 个推广启动项值') (($hitVals | ForEach-Object { $_.Name }) -join '、')) {
            foreach ($h in $hitVals) {
                try {
                    $regFile = Join-Path $script:BackupDir ('Run_' + ($h.Name -replace '[^\w]', '_') + '.reg')
                    $lines = @('Windows Registry Editor Version 5.00', '', '[' + ($h.Key -replace '^HKCU:', 'HKEY_CURRENT_USER' -replace '^HKLM:', 'HKEY_LOCAL_MACHINE') + ']', ('"' + $h.Name + '"="' + ($h.Value -replace '\\', '\\') + '"'), '')
                    [System.IO.File]::WriteAllText($regFile, ($lines -join "`r`n"), [System.Text.Encoding]::Unicode)
                    Remove-ItemProperty -LiteralPath $h.Key -Name $h.Name -Force -ErrorAction Stop
                    Write-Ok ('已删除启动项 ' + $h.Name)
                    Rec-Act 'DeleteRunValue' ($h.Key + ' \ ' + $h.Name) 'OK'
                } catch {
                    Write-Bad ('删除失败 ' + $h.Name + '：' + $_.Exception.Message)
                    Rec-Act 'DeleteRunValue' $h.Name ('FAIL: ' + $_.Exception.Message)
                }
            }
        }
    } else { Write-Info '没有需要处理的启动项' }

    # F4 计划任务
    $taskHits = @()
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        $acts = @($t.Actions | ForEach-Object { ([string]$_.Execute + ' ' + [string]$_.Arguments) })
        $joined = ($acts -join ' ')
        if ([string]::IsNullOrWhiteSpace($joined)) { continue }
        $bad = ($joined -match $script:IOC.DomainRx) -or ($joined -cmatch '\\Windows\\[A-Z][a-z]{5,15}\\[A-Z][a-z]{5,15}\.exe') -or ($joined -match $script:IOC.ProcRx)
        if ($bad -and $t.State -ne 'Disabled') { $taskHits += $t }
    }
    if ($taskHits.Count -gt 0) {
        if (Confirm-Step ('禁用 ' + $taskHits.Count + ' 个推广计划任务') '禁用不是删除，可随时重新启用；XML 会导出备份') {
            foreach ($t in $taskHits) {
                try {
                    $xml = Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop
                    $safe = ($t.TaskName -replace '[^\w]', '_')
                    $bk = Join-Path $script:BackupDir ('Task_' + $safe + '.xml')
                    [System.IO.File]::WriteAllText($bk, $xml, (New-Object System.Text.UTF8Encoding($true)))
                    Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null
                    Write-Ok ('已禁用 ' + $t.TaskPath + $t.TaskName)
                    Rec-Act 'DisableTask' ($t.TaskPath + $t.TaskName) 'OK'
                } catch {
                    Write-Bad ('禁用失败 ' + $t.TaskName + '：' + $_.Exception.Message)
                    Rec-Act 'DisableTask' ($t.TaskPath + $t.TaskName) ('FAIL: ' + $_.Exception.Message)
                }
            }
        }
    } else { Write-Info '没有需要禁用的计划任务' }

    # F5 快捷方式
    $sh = New-Object -ComObject WScript.Shell
    $lnkDirs = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        'C:\Users\Public\Desktop',
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    )
    $broken = @()
    foreach ($d in $lnkDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $l = $sh.CreateShortcut($f.FullName)
                if (([string]$l.Arguments) -match $script:IOC.DomainRx) { $broken += $f.FullName }
            } catch { }
        }
    }
    if ($broken.Count -gt 0) {
        if (Confirm-Step ('修复 ' + $broken.Count + ' 个被追加网址的快捷方式') '先备份 .lnk，再清掉参数里的网址') {
            foreach ($p in $broken) {
                try {
                    Copy-Item -LiteralPath $p -Destination (Join-Path $script:BackupDir (Split-Path -Leaf $p)) -Force -ErrorAction SilentlyContinue
                    $l = $sh.CreateShortcut($p)
                    $argStr = [string]$l.Arguments
                    $new = ($argStr -replace '\s*https?://\S+', '').Trim()
                    $l.Arguments = $new
                    $l.Save()
                    Write-Ok ('已修复 ' + (Split-Path -Leaf $p))
                    Rec-Act 'FixShortcut' $p 'OK'
                } catch {
                    Write-Bad ('修复失败 ' + (Split-Path -Leaf $p) + '：' + $_.Exception.Message)
                    Rec-Act 'FixShortcut' $p ('FAIL: ' + $_.Exception.Message)
                }
            }
        }
    } else { Write-Info '没有需要修复的快捷方式' }

    # F6 收藏夹
    $favDirs = @((Join-Path $env:USERPROFILE 'Favorites'), 'C:\Users\Public\Favorites')
    $favTargets = @()
    foreach ($d in $favDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $txt = [System.IO.File]::ReadAllText($f.FullName)
                if ($txt -match $script:IOC.DomainRx) { $favTargets += $f.FullName }
            } catch { }
        }
    }
    if ($favTargets.Count -gt 0) {
        if (Confirm-Step ('隔离 ' + $favTargets.Count + ' 个含推广链接的收藏项') (($favTargets | ForEach-Object { Split-Path -Leaf $_ }) -join '、')) {
            foreach ($p in $favTargets) {
                $r = Move-ToQuarantine $p 'Favorites'
                if ($r.Ok) { Write-Ok ('已隔离 ' + (Split-Path -Leaf $p)); Rec-Act 'QuarantineFavorite' $p 'OK' }
                else { Write-Bad ('失败：' + $r.Msg); Rec-Act 'QuarantineFavorite' $p ('FAIL: ' + $r.Msg) }
            }
        }
    } else { Write-Info '收藏夹没有需要处理的项' }

    # F7 hosts
    $hosts = Join-Path $env:windir 'System32\drivers\etc\hosts'
    if (Test-Path -LiteralPath $hosts) {
        $lines = @(Get-Content -LiteralPath $hosts -ErrorAction SilentlyContinue)
        $bad = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].Trim()
            if ($t.StartsWith('#') -or $t.Length -eq 0) { continue }
            if ($t -match $script:IOC.DomainRx) { $bad += $i }
        }
        if ($bad.Count -gt 0) {
            if (Confirm-Step ('注释掉 hosts 里 ' + $bad.Count + ' 条推广域名') '先整份备份为 hosts.dbc_bak，只加 # 注释不删行') {
                try {
                    Copy-Item -LiteralPath $hosts -Destination (Join-Path $script:BackupDir 'hosts.dbc_bak') -Force -ErrorAction SilentlyContinue
                    foreach ($i in $bad) { $lines[$i] = '# [DBC-Sweeper] ' + $lines[$i] }
                    Set-Content -LiteralPath $hosts -Value $lines -Encoding ASCII -Force -ErrorAction Stop
                    Write-Ok 'hosts 已处理'
                    Rec-Act 'FixHosts' $hosts ('commented ' + $bad.Count)
                } catch {
                    Write-Bad ('hosts 写入失败：' + $_.Exception.Message)
                    Rec-Act 'FixHosts' $hosts ('FAIL: ' + $_.Exception.Message)
                }
            }
        } else { Write-Info 'hosts 无需处理' }
    }

    # F8 通知权限
    foreach ($b in (Get-BrowserProfiles)) {
        if (-not (Test-Path -LiteralPath $b.DataDir)) { continue }
        if (@(Get-Process -Name ($b.Name.ToLower()) -ErrorAction SilentlyContinue).Count -gt 0) { continue }
        $profiles = @(Get-ChildItem -LiteralPath $b.DataDir -Directory -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        foreach ($pf in $profiles) {
            $prefPath = Join-Path $pf.FullName 'Preferences'
            if (-not (Test-Path -LiteralPath $prefPath)) { continue }
            $raw = Get-Content -LiteralPath $prefPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $raw) { continue }
            $j = $null
            try { $j = $raw | ConvertFrom-Json } catch { continue }
            if (-not $j) { continue }
            $notif = $j.profile.content_settings.exceptions.notifications
            if (-not $notif) { continue }
            $tgt = @()
            foreach ($pr in $notif.PSObject.Properties) {
                if ($pr.Name -match $script:IOC.BrowserUrlRx) { $tgt += $pr.Name }
            }
            if ($tgt.Count -eq 0) { continue }
            if (Confirm-Step ('把 ' + $b.Name + ' 里 ' + $tgt.Count + ' 个推广站点的通知权限改为「阻止」') ($tgt -join '、')) {
                try {
                    Copy-Item -LiteralPath $prefPath -Destination (Join-Path $script:BackupDir ($b.Name + '_Preferences.bak')) -Force -ErrorAction SilentlyContinue
                    foreach ($pr in $notif.PSObject.Properties) {
                        if ($pr.Name -match $script:IOC.BrowserUrlRx) { $pr.Value.setting = 2 }
                    }
                    $out = $j | ConvertTo-Json -Depth 40 -Compress
                    [System.IO.File]::WriteAllText($prefPath, $out, (New-Object System.Text.UTF8Encoding($false)))
                    Write-Ok '通知权限已改为阻止'
                    Rec-Act 'BlockNotifications' $prefPath ('sites ' + $tgt.Count)
                } catch {
                    Write-Bad ('写入失败：' + $_.Exception.Message)
                    Rec-Act 'BlockNotifications' $prefPath ('FAIL: ' + $_.Exception.Message)
                }
            }
        }
    }

    Write-Ok '可逆修复结束'
}

function Invoke-QuarantineTargets {
    Write-Head '写操作 / 隔离推广目录与部署期载荷'
    New-BackupDir

    $cands = New-Object System.Collections.Generic.List[object]

    # 推广软件目录
    $dirRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA)
    foreach ($dr in $dirRoots) {
        if ([string]::IsNullOrWhiteSpace($dr) -or -not (Test-Path -LiteralPath $dr)) { continue }
        foreach ($sig in $script:IOC.PromoDirNames) {
            $p = Join-Path $dr $sig
            if (Test-Path -LiteralPath $p) {
                $cands.Add([pscustomobject]@{ Path = $p; Label = ('推广目录 ' + $sig); Sub = 'Promo' })
            }
        }
    }

    # 部署期随机名目录（含 img 分包）
    if (Test-Path -LiteralPath $env:windir) {
        foreach ($d in @(Get-ChildItem -LiteralPath $env:windir -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($d.Name -notmatch '^[A-Z][A-Za-z]{5,15}$') { continue }
            if ($script:IOC.WhiteList -contains $d.Name) { continue }
            $kids = @(Get-ChildItem -LiteralPath $d.FullName -File -Force -ErrorAction SilentlyContinue | Select-Object -First 60)
            $payload = @($kids | Where-Object { ($script:IOC.PayloadExt -contains $_.Extension.ToLower()) -or ($_.Name -match '(?i)^(img|support\.img)\d*$') })
            if ($payload.Count -gt 0) {
                $cands.Add([pscustomobject]@{ Path = $d.FullName; Label = ('部署期载荷 ' + $d.Name); Sub = 'Payload' })
            }
        }
    }

    # unattend.xml
    foreach ($p in @((Join-Path $env:windir 'Panther\unattend.xml'), (Join-Path $env:windir 'Panther\unattended.xml'))) {
        if (Test-Path -LiteralPath $p) {
            $raw = Get-Content -LiteralPath $p -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($raw -and ($raw -match 'ConsentPromptBehaviorAdmin' -or $raw -cmatch '\\Windows\\[A-Z][a-z]{5,15}\\[A-Z][a-z]{5,15}\.exe')) {
                $cands.Add([pscustomobject]@{ Path = $p; Label = '无人值守文件'; Sub = 'Panther' })
            }
        }
    }

    if ($cands.Count -eq 0) {
        Write-Ok '没有可隔离的目标'
        return
    }

    Write-Warn2 ('共发现 ' + $cands.Count + ' 个可隔离目标，单批上限 ' + $MaxBatch + ' 个')
    $batch = @($cands | Select-Object -First $MaxBatch)

    foreach ($c in $batch) {
        $mb = if ($Measure) { Get-DirSizeMB $c.Path } else { 0 }
        $desc = $c.Path
        if ($mb -gt 0) { $desc = $desc + '（约 ' + $mb + ' MB）' }
        if (Confirm-Step ('隔离：' + $c.Label) ($desc + ' → 移入 ' + $script:Quarantine + '\' + $c.Sub)) {
            # 目标目录里有进程占用时先提示
            $r = Move-ToQuarantine $c.Path $c.Sub
            if ($r.Ok) {
                Write-Ok ('已隔离 ' + $c.Path)
                Rec-Act 'QuarantinePath' $c.Path ('OK -> ' + $r.Dest)
            } else {
                Write-Bad ('隔离失败：' + $r.Msg)
                Write-Info '常见原因：文件被占用（先结束进程）、权限不足（Program Files 需要管理员）、或受系统保护'
                Rec-Act 'QuarantinePath' $c.Path ('FAIL: ' + $r.Msg)
            }
        }
    }

    if ($cands.Count -gt $MaxBatch) {
        Write-Warn2 ('还有 ' + ($cands.Count - $MaxBatch) + ' 个目标未处理，再次运行可继续')
    }
}

function Invoke-PurgeReg {
    Write-Head '写操作 / 删除推广注册表键'
    New-BackupDir
    foreach ($k in $script:IOC.RegRoots) {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        if (Confirm-Step ('删除注册表键 ' + $k) '先导出 .reg 备份，删除后双击 .reg 可恢复') {
            try {
                $hive = $k -replace '^HKCU:', 'HKEY_CURRENT_USER' -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
                $regFile = Join-Path $script:BackupDir (($hive -replace '[\\:]', '_') + '.reg')
                $sb = New-Object System.Text.StringBuilder
                $null = $sb.AppendLine('Windows Registry Editor Version 5.00')
                $null = $sb.AppendLine('')
                $keys = @($k) + @(Get-ChildItem -LiteralPath $k -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.PSPath })
                foreach ($kk in $keys) {
                    $hi = Get-Item -LiteralPath $kk -ErrorAction SilentlyContinue
                    if (-not $hi) { continue }
                    $hn = $hi.Name -replace '^HKEY_CURRENT_USER', 'HKEY_CURRENT_USER' -replace '^HKEY_LOCAL_MACHINE', 'HKEY_LOCAL_MACHINE'
                    $null = $sb.AppendLine('[' + $hn + ']')
                    foreach ($vn in $hi.GetValueNames()) {
                        $vv = $hi.GetValue($vn)
                        if ($vv -is [byte[]]) { continue }
                        $s = [string]$vv
                        $null = $sb.AppendLine('"' + $vn + '"="' + ($s -replace '\\', '\\' -replace '"', '\"') + '"')
                    }
                    $null = $sb.AppendLine('')
                }
                [System.IO.File]::WriteAllText($regFile, $sb.ToString(), [System.Text.Encoding]::Unicode)
                Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop
                Write-Ok ('已删除 ' + $k)
                Rec-Act 'PurgeRegKey' $k ('OK, backup=' + (Split-Path -Leaf $regFile))
            } catch {
                Write-Bad ('删除失败 ' + $k + '：' + $_.Exception.Message)
                Rec-Act 'PurgeRegKey' $k ('FAIL: ' + $_.Exception.Message)
            }
        }
    }
}

# ============================================================
# 5. 报告
# ============================================================
function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Get-Verdict {
    $safe    = @($script:Findings | Where-Object Level -eq 'Safe').Count
    $review  = @($script:Findings | Where-Object Level -eq 'Review').Count
    $protect = @($script:Findings | Where-Object Level -eq 'Protect').Count
    if ($safe -ge 4) { return @{ Level = '高'; Text = '多项强特征吻合，系统确实被大白菜 PE 植入了推广/劫持'; Safe = $safe; Review = $review; Protect = $protect } }
    if ($safe -ge 1) { return @{ Level = '中'; Text = '存在明确推广/劫持特征，建议按报告逐项处理'; Safe = $safe; Review = $review; Protect = $protect } }
    return @{ Level = '低'; Text = '未发现强特征；若有残留广告，重点看 Review 项与浏览器层'; Safe = $safe; Review = $review; Protect = $protect }
}

function Write-Report {
    Write-Head '生成报告'
    $v = Get-Verdict

    # findings.json
    $fj = Join-Path $script:OutDir 'findings.json'
    $script:Findings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fj -Encoding UTF8
    Write-Info ('findings.json  ' + $script:Findings.Count + ' 项')

    # ioc_db.json
    $iocOut = [ordered]@{
        GeneratedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Tool        = 'DBC Sweeper'
        Stage       = @{
            A = '源头：U 盘 / PE 镜像 / 制作工具'
            B = '部署期：无人值守文件 / 随机名启动器 / 载荷分包 / UAC'
            C = '落地：推广软件 / 注册表 / 服务 / 驱动 / 启动项 / 快捷方式 / hosts / 收藏夹'
            D = '浏览器：首次运行配置 / 会话 / 策略 / 通知 / 扩展 / 缓存'
            E = '残留：旧系统 / PE 目录 / 临时文件'
        }
        Patterns    = [ordered]@{
            DomainRx     = $script:IOC.DomainRx
            BrowserUrlRx = $script:IOC.BrowserUrlRx
            ProcRx       = $script:IOC.ProcRx
        }
        PromoDirs   = $script:IOC.PromoDirNames
        RegRoots    = $script:IOC.RegRoots
        UsbMarks    = $script:IOC.UsbMarks
        ToolNames   = $script:IOC.ToolNames
        WhiteList   = $script:IOC.WhiteList
        KnownChannels = @('2345explorer','360se','360sd','EdgeSetup','2345PCSafe','WPS','iqiyi','kuwo')
    }
    $ij = Join-Path $script:OutDir 'ioc_db.json'
    $iocOut | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ij -Encoding UTF8
    Write-Info 'ioc_db.json 已导出（可自行增补特征）'

    # actions.json
    $aj = Join-Path $script:OutDir 'actions.json'
    $actOut = [ordered]@{
        Timestamp  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Mode       = $(if ($script:IsWrite) { 'write' } else { 'readonly' })
        BackupDir  = $script:BackupDir
        Quarantine = $script:Quarantine
        Actions    = $script:Actions
        Rollback   = '把 Quarantine_* 下的文件按原路径移回即可；Backup_* 下有 .reg / .xml / .lnk / hosts 备份，双击 .reg 导入、Import-ScheduledTask 导入 XML 可恢复'
    }
    $actOut | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $aj -Encoding UTF8

    # report.html
    $h = New-Object System.Collections.Generic.List[string]
    $h.Add('<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">')
    $h.Add('<meta name="viewport" content="width=device-width,initial-scale=1">')
    $h.Add('<title>大白菜装机残留排查报告</title>')
    $h.Add('<style>')
    $h.Add(':root{--bg:#0f1216;--card:#171c22;--line:#2a323c;--tx:#e6edf3;--dim:#9aa7b4;--ok:#3fb950;--warn:#d29922;--bad:#f85149;--acc:#58a6ff}')
    $h.Add('*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:14px/1.7 -apple-system,"Segoe UI","Microsoft YaHei",sans-serif}')
    $h.Add('.wrap{max-width:1120px;margin:0 auto;padding:32px 20px 80px}')
    $h.Add('h1{font-size:26px;margin:0 0 6px}h2{font-size:18px;margin:34px 0 12px;padding-left:10px;border-left:4px solid var(--acc)}')
    $h.Add('h3{font-size:15px;margin:20px 0 8px;color:var(--acc)}')
    $h.Add('.sub{color:var(--dim);font-size:13px}')
    $h.Add('.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px 18px;margin:12px 0}')
    $h.Add('.card.ok{border-left:4px solid var(--ok)}.card.warn{border-left:4px solid var(--warn)}.card.bad{border-left:4px solid var(--bad)}')
    $h.Add('.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin:14px 0}')
    $h.Add('.kpi{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px;text-align:center}')
    $h.Add('.kpi b{display:block;font-size:24px;line-height:1.2}.kpi span{color:var(--dim);font-size:12px}')
    $h.Add('table{width:100%;border-collapse:collapse;margin:10px 0;font-size:13px}')
    $h.Add('th,td{border-bottom:1px solid var(--line);padding:8px 10px;text-align:left;vertical-align:top}')
    $h.Add('th{color:var(--dim);font-weight:600;background:#12171d}')
    $h.Add('code{background:#11161c;border:1px solid var(--line);border-radius:4px;padding:1px 5px;font:12px/1.5 Consolas,monospace;word-break:break-all}')
    $h.Add('.tag{display:inline-block;font-size:11px;padding:1px 7px;border-radius:20px;border:1px solid var(--line)}')
    $h.Add('.t-safe{color:var(--bad);border-color:#5c2a28}.t-rev{color:var(--warn);border-color:#5a4520}.t-pro{color:var(--dim)}')
    $h.Add('ul,ol{padding-left:22px}li{margin:5px 0}')
    $h.Add('.foot{margin-top:40px;color:var(--dim);font-size:12px;border-top:1px solid var(--line);padding-top:14px}')
    $h.Add('@media(max-width:640px){.wrap{padding:20px 14px}table{font-size:12px}}')
    $h.Add('</style></head><body><div class="wrap">')

    $h.Add('<h1>大白菜装机残留排查报告</h1>')
    $h.Add('<div class="sub">' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ｜ 主机 ' + (Esc $env:COMPUTERNAME) + ' ｜ 模式 ' + $(if ($script:IsWrite) { '写模式（逐项确认）' } else { '纯只读' }) + ' ｜ 系统安装于 ' + $(if ($osInstall) { $osInstall.ToString('yyyy-MM-dd') } else { '未知' }) + '</div>')

    $cls = if ($v.Level -eq '高') { 'bad' } elseif ($v.Level -eq '中') { 'warn' } else { 'ok' }
    $h.Add('<div class="card ' + $cls + '"><strong>综合判断：置信度 ' + $v.Level + '</strong><br>' + (Esc $v.Text) + '</div>')

    $h.Add('<div class="grid">')
    $h.Add('<div class="kpi"><b style="color:var(--bad)">' + $v.Safe + '</b><span>可处理（强特征）</span></div>')
    $h.Add('<div class="kpi"><b style="color:var(--warn)">' + $v.Review + '</b><span>需人工确认</span></div>')
    $h.Add('<div class="kpi"><b style="color:var(--dim)">' + $v.Protect + '</b><span>保护项（不碰）</span></div>')
    $h.Add('<div class="kpi"><b>' + $script:Findings.Count + '</b><span>发现项合计</span></div>')
    $h.Add('</div>')

    # 分组表格
    $groups = @(
        @{ L = 'Safe';    T = '一、可处理项（命中强特征）'; C = 't-safe' },
        @{ L = 'Review';  T = '二、需要你确认的项';       C = 't-rev'  },
        @{ L = 'Protect'; T = '三、工具不会碰的项';       C = 't-pro'  }
    )
    foreach ($g in $groups) {
        $items = @($script:Findings | Where-Object Level -eq $g.L)
        $h.Add('<h2>' + $g.T + '（' + $items.Count + '）</h2>')
        if ($items.Count -eq 0) { $h.Add('<div class="card">无</div>'); continue }
        $h.Add('<table><tr><th style="width:70px">阶段</th><th style="width:110px">类别</th><th>对象</th><th style="width:32%">说明</th><th style="width:22%">建议</th></tr>')
        foreach ($it in $items) {
            $h.Add('<tr>')
            $h.Add('<td>' + (Esc $it.Stage) + '</td>')
            $h.Add('<td>' + (Esc $it.Category) + '</td>')
            $h.Add('<td><strong>' + (Esc $it.Name) + '</strong>' + $(if ($it.Path) { '<br><code>' + (Esc $it.Path) + '</code>' } else { '' }) + '</td>')
            $h.Add('<td>' + (Esc $it.Detail) + '</td>')
            $h.Add('<td>' + (Esc $it.Action) + '</td>')
            $h.Add('</tr>')
        }
        $h.Add('</table>')
    }

    # 执行记录
    if ($script:Actions.Count -gt 0) {
        $h.Add('<h2>四、本次实际执行的动作</h2>')
        $h.Add('<table><tr><th style="width:180px">动作</th><th>对象</th><th style="width:120px">结果</th><th style="width:80px">时间</th></tr>')
        foreach ($a in $script:Actions) {
            $h.Add('<tr><td>' + (Esc $a.Step) + '</td><td><code>' + (Esc $a.Target) + '</code></td><td>' + (Esc $a.Result) + '</td><td>' + (Esc $a.Time) + '</td></tr>')
        }
        $h.Add('</table>')
        $h.Add('<div class="card ok"><strong>回滚方式：</strong>把 <code>' + (Esc $script:Quarantine) + '</code> 下的文件按原路径移回；' +
            '<code>' + (Esc $script:BackupDir) + '</code> 下有 <code>.reg</code>（双击导入）、<code>.xml</code>（Import-ScheduledTask）、<code>.lnk</code>、<code>hosts.dbc_bak</code> 备份。</div>')
    }

    # 机理
    $h.Add('<h2>五、这套东西是怎么进来的</h2>')
    $h.Add('<table><tr><th style="width:120px">阶段</th><th>具体行为</th><th style="width:28%">落地痕迹</th></tr>')
    $h.Add('<tr><td>制作 U 盘</td><td>默认勾选「赞助商主页 / 绿色软件」，推广配置写进 PE 镜像</td><td>制作工具个性设置、<code>HKLM\SOFTWARE\DaBaiCai</code></td></tr>')
    $h.Add('<tr><td>PE 启动</td><td><code>X:\windows\Packages\System32.7z</code>、<code>PF.7z</code> 解压出部署程序 <code>NUML0CK.EXE</code></td><td>PE 内 System32、U 盘 <code>\PE\DBC8x64.ISO</code></td></tr>')
    $h.Add('<tr><td>释放镜像</td><td>在 <code>C:\Windows\&lt;随机名&gt;\</code> 放随机名启动器 + 十余个加密 <code>.img/.ext</code> 安装包</td><td>随机名目录、数百 MB 分包</td></tr>')
    $h.Add('<tr><td>无人值守</td><td>写 <code>Panther\unattend.xml</code>：启用 Administrator、关 UAC、首次登录自动拉起启动器</td><td><code>RunSynchronousCommand</code>、<code>ConsentPromptBehaviorAdmin=0</code></td></tr>')
    $h.Add('<tr><td>首次进桌面</td><td>静默装 360 全家桶 / 2345 / 腾讯视频 / 爱奇艺 / 老黄历 / WPS，改主页与收藏夹，启动器自删</td><td>安装日期与会话/配置里的推广域名</td></tr>')
    $h.Add('<tr><td>持续复发</td><td>计划任务、WMI 订阅、组策略键、安全软件「主页锁定」、浏览器会话恢复</td><td>本报告 B / C / D 层</td></tr>')
    $h.Add('</table>')
    $h.Add('<div class="card warn"><strong>关键结论：</strong>用微软原版纯净 ISO 也挡不住——植入发生在 PE 阶段、系统首次启动之前。' +
        '所以「装完再删」只能治标，<strong>去源头重做启动盘 / 换微PE、优启通 + 官方 ISO</strong>才治本。</div>')

    # 手工清单
    $h.Add('<h2>六、工具不做、但你应该做的</h2>')
    $h.Add('<ol>')
    $h.Add('<li><strong>恢复 UAC</strong>：<code>EnableLUA=1</code>、<code>ConsentPromptBehaviorAdmin=5</code>，改前导出注册表键。</li>')
    $h.Add('<li><strong>改回默认应用</strong>：<code>.html</code> 与 <code>http/https</code> 若指向 360seURL，走「设置 → 应用 → 默认应用」改回，别手改注册表（UserChoice 有哈希校验）。</li>')
    $h.Add('<li><strong>卸软件走正规卸载</strong>：设置 → 应用 → 按安装日期排序，卸完用 Geek Uninstaller / Revo 扫残留。</li>')
    $h.Add('<li><strong>清旧系统</strong>：设置 → 系统 → 存储 → 临时文件 → 删除以前版本的 Windows。不要手删 Windows.old。</li>')
    $h.Add('<li><strong>浏览器内再收一遍</strong>：<code>edge://settings/startHomeNTP</code> 选「打开新标签页」；<code>edge://settings/content/all</code> 搜推广域名删站点数据。</li>')
    $h.Add('<li><strong>治本</strong>：大白菜制作器 → 个性设置 → 支持我们 → 取消全部推广 → 保存设置 → <em>重新制作</em>；或直接换微PE / 优启通。</li>')
    $h.Add('</ol>')

    # 边界
    $h.Add('<h2>七、工具边界</h2>')
    $h.Add('<div class="card">')
    $h.Add('<p><strong>只做可逆动作</strong>：改名、移动、注释、禁用、导出备份。移入隔离区不等于释放空间，确认无误后手动清空隔离目录才省空间。</p>')
    $h.Add('<p><strong>绝不自动处理</strong>：<code>unattend.xml</code>、<code>C:\Windows\&lt;随机名&gt;</code>、系统服务与驱动、UAC、组策略键、hosts 之外的系统文件、<code>Windows.old</code>、用户账户、代理设置。' +
        '这些要么在系统目录、要么可能是你自己的开发/调试环境配置。</p>')
    $h.Add('<p><strong>白名单保护</strong>：PlatformIO、Arduino、Python、VS Code、CH340/CP210x/FTDI 驱动等开发工具不会被判为推广软件。</p>')
    $h.Add('<p><strong>已知不完美</strong>：随机名启发式可能漏判新版变体；浏览器 <code>Secure Preferences</code> 受 MAC 保护，工具不碰；' +
        '会话文件在浏览器运行时会被独占，必须先完全退出浏览器再修。</p>')
    $h.Add('</div>')

    # 来源
    $h.Add('<h2>八、情报来源与可信度</h2>')
    $h.Add('<table><tr><th>来源</th><th>内容</th><th style="width:90px">可信度</th></tr>')
    $h.Add('<tr><td>大白菜官网帮助页 help_107</td><td>官方取消赞助商流程、机器码换解锁码</td><td>高（官方）</td></tr>')
    $h.Add('<tr><td>火绒安全 病毒分析报告 834 / 794</td><td>互泰旗下 PE 植入、删除安全软件、NUML0CK 为 AutoIt 编译</td><td>高（厂商研究）</td></tr>')
    $h.Add('<tr><td>SecPulse「这大白菜有毒」</td><td>进程内存中的推广清单、备案主体</td><td>中高（逆向）</td></tr>')
    $h.Add('<tr><td>社区逆向「某白菜 PE 行为分析」</td><td>随机名启动器、11 个加密 img、unattend.xml 字段</td><td>中高（有实验复现）</td></tr>')
    $h.Add('<tr><td>wityx / CSDN 解包实测</td><td><code>System32.7z</code> ≈ 5087KB、删除后推广消失</td><td>中</td></tr>')
    $h.Add('<tr><td>2345 装机联盟官方计费页</td><td>浏览器 3.2–6.6 元/台、导航按访问计费 → 动机闭环</td><td>高（官方）</td></tr>')
    $h.Add('<tr><td>微软官方支持文档</td><td>删除以前版本的 Windows 的正确路径</td><td>高（官方）</td></tr>')
    $h.Add('</table>')
    $h.Add('<div class="card warn"><strong>已知不实信息：</strong>CSDN 上部分「大白菜去广告」问答为 AI 生成内容农场（页面带 AI 选题/分发推广），' +
        '其中 <code>check.adbaidu.cn</code>、<code>DabaiCaiService.exe</code>、<code>adblock=1 noads=1</code> 等均查无佐证，<code>reg delete /f</code> 照做会误伤系统。本工具未采信。</div>')

    $h.Add('<div class="foot">DBC Sweeper ｜ 报告生成于 ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') +
        ' ｜ 数据文件：<code>findings.json</code>、<code>ioc_db.json</code>、<code>actions.json</code>' +
        ' ｜ 本报告只反映扫描时刻的状态</div>')
    $h.Add('</div></body></html>')

    $rp = Join-Path $script:OutDir 'report.html'
    [System.IO.File]::WriteAllText($rp, ($h -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    Write-Ok ('report.html  ' + [math]::Round((Get-Item -LiteralPath $rp).Length / 1KB, 1) + ' KB')
    Write-Info ('输出目录：' + $script:OutDir)
}

# ============================================================
# 6. 主流程
# ============================================================
Write-Host ''
Write-Host '  大白菜装机残留 专项排查与可逆清理工具  DBC Sweeper' -ForegroundColor White
Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray

Invoke-Env
Invoke-StageA
Invoke-StageB
Invoke-StageC
Invoke-StageD
Invoke-StageE

if ($script:IsWrite) {
    if ($Fix)        { Invoke-Fix }
    if ($Quarantine) { Invoke-QuarantineTargets }
    if ($PurgeReg)   { Invoke-PurgeReg }
}

Write-Report

$elapsed = [math]::Round(((Get-Date) - $script:StartAt).TotalSeconds, 1)
Write-Host ''
Write-Host ('  完成，用时 ' + $elapsed + ' 秒') -ForegroundColor Green
$v = Get-Verdict
Write-Host ('  结论：置信度 ' + $v.Level + ' ｜ 可处理 ' + $v.Safe + ' ｜ 待确认 ' + $v.Review + ' ｜ 保护 ' + $v.Protect) -ForegroundColor Cyan
if (-not $script:IsWrite) {
    Write-Host '  本次为纯只读，未做任何改动。要清理请运行 RUN_2_Fix.cmd（管理员）。' -ForegroundColor Gray
}
Write-Host ''
exit 0
