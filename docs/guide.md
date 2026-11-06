# 大白菜装机清理 · 完整使用说明

> 适用：用大白菜（DaBaiCai）U 盘启动盘装完 Windows 后，出现推广软件、弹窗广告、主页被改、浏览器每天自己开推广页、卸载后反复复活等问题。
> 也适用于同门工具：老毛桃、电脑店、晨枫、U深度（机理同构，特征库覆盖主要项）。
> 版本：v1.0 ｜ 2026-11-06 ｜ 工具：`DBC_Sweeper.ps1`（PowerShell 5.1+，单文件，96 KB）

---

## 目录

- [第 0 章 三分钟快速上手](#第-0-章-三分钟快速上手)
- [第 1 章 先搞清楚：这些东西是怎么进来的](#第-1-章-先搞清楚这些东西是怎么进来的)
- [第 2 章 判断：你这台属于哪一种](#第-2-章-判断你这台属于哪一种)
- [第 3 章 工具篇：四个启动器怎么用](#第-3-章-工具篇四个启动器怎么用)
- [第 4 章 手工篇：分场景操作](#第-4-章-手工篇分场景操作)
- [第 5 章 深入：特征库与判定逻辑](#第-5-章-深入特征库与判定逻辑)
- [第 6 章 辟谣：这五条别照做](#第-6-章-辟谣这五条别照做)
- [第 7 章 FAQ（32 条）](#第-7-章-faq32-条)
- [第 8 章 本机实测案例（真实数据）](#第-8-章-本机实测案例真实数据)
- [附录](#附录)

---

## 第 0 章 三分钟快速上手

### 只有三件事

```
① 双击 RUN_1_Scan.cmd      → 10 秒，出报告，零改动
② 看 report.html 的结论    → 高 / 中 / 低
③ 要清就右键 RUN_2_Fix.cmd → 管理员运行，逐项输入 YES
```

**不要**跳过第 ① 步直接清。原因：不同机器的"中招程度"差很多，有人只是浏览器被改，有人整套载荷还在硬盘上。先看清楚再动手。

### 三条铁律

1. **先断网**（拔网线 / 关 WiFi）。多数推广软件有云端复活，删了会重下。
2. **先关浏览器**（`edge://quit`，再确认进程数 0）。浏览器退出时会写回会话文件，不清就白干。
3. **只做可回滚的动作**。工具把所有改动都备份在 `Backup_*` / `Quarantine_*`，删了就没了。

### 如果你只是想"以后不再中招"

直接跳 [S0 场景](#s0还没装系统成本最低收益最大)：取消赞助商 → **必须点保存设置** → **重新制作一次 U 盘**。
已经做好的盘不会自动变干净。

---

## 第 1 章 先搞清楚：这些东西是怎么进来的

### 1.1 一句话

**脏的不是系统镜像，是 PE。** 你用微软原版纯净 ISO，装完照样多出 360、2345、腾讯视频、老黄历——因为推广是在 PE 阶段注入的，发生在系统首次启动之前。

### 1.2 五阶段链路

```
【阶段 A】制作 U 盘
   默认勾选「赞助商主页 / 绿色软件」→ 推广配置和软件包写进 PE 镜像
   顺手把装机来源写进注册表：HKLM\SOFTWARE\DaBaiCai（含渠道号）

【阶段 B】PE 启动
   X:\windows\Packages\System32.7z（约 5 MB）、PF.7z 解压
   → 生成 NUML0CK.EXE（AutoIt 编译 + 混淆）
   → 常驻内存，按关键词删掉 PE 和目标盘里的安全软件

【阶段 C】释放镜像
   在 C:\Windows\<8~16 位随机字母>\ 放随机名启动器
   + 11 个加密安装包（.img / .img1…9 / .ext，本机实测 450 MB）
   + 写 C:\Windows\Panther\unattend.xml

【阶段 D】首次进桌面
   unattend.xml 里的 RunSynchronousCommand 自动拉起启动器
   → 静默装 360 全家桶、2345 系、腾讯视频、爱奇艺、酷我、WPS、电脑管家、老黄历
   → 改浏览器主页 / 收藏夹 / 默认搜索
   → 启动器自删，只剩加密分包躺在那里

【阶段 E】持续复发
   计划任务 / WMI 永久订阅 / 浏览器组策略 / 安全软件主页锁定 / 浏览器会话恢复
```

### 1.3 为什么它要关 UAC

`unattend.xml` 里有一行：

```
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
        /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f
```

因为启动器要静默提权装软件。如果弹 UAC 而用户点了「否」，整条链路就断了。

**所以：`ConsentPromptBehaviorAdmin=0` 或 `EnableLUA=0` 本身就是一条强旁证。**
（也可能是你自己为了方便关的——所以工具只标 Review。）

### 1.4 为什么这件事是"生意"而不是"随机的流氓软件"

2345 装机联盟公开的计费标准（官方页面，可信度最高的一环）：

| 推广项 | 单价 |
|---|---|
| 2345 浏览器（标准版推广包） | 6.0–6.6 元/台 |
| 2345 浏览器（纯净版推广包） | 3.9–4.2 元/台 |
| 加速浏览器（安全版） | 3.2–3.5 元/台 |
| 2345 网址导航 | 按访问用户计费，**终身计费**（50–65 积分/访问用户） |
| WPS Office | 0.3–0.33 元/台 |
| 爱奇艺 | 0.4–0.44 元/台 |
| 酷我 | 0.3–0.33 元/台 |
| 2345 看图王 | 0.22–0.24 元/台 |

装一台机器的软件分成大概 2–10 元，而**导航分成是长期现金流**——这就是为什么"主页必须改掉"，
以及为什么改了还会被改回来。

本机注册表里那组数字就是这套账的凭证：

```
2345explorer=511097    360se=5000783     360safe=5000782
EdgeSetup=1773998236   Chrome=1773998236 DriveTheLife=57459
Taobao=cbdh956         chaojituzi=lm
```

不是版本号，是**渠道 / 计费 ID**。

### 1.5 一个必须接受的现实

同一个 U 盘，装一百台机器，一百台都会中。你今天清干净，明天帮人重装又用这支盘，照样中。

所以本说明把"治标（清理）"和"治本（换源）"分开写。**能重装就治本，不能重装才治标。**

---

## 第 2 章 判断：你这台属于哪一种

### 2.1 五种典型症状 → 对应章节

| 你看到的现象 | 大概率是 | 去做 |
|---|---|---|
| 桌面/开始菜单多出 360、2345、腾讯视频、老黄历 | 推广软件已落地 | [S1](#s1刚装完系统还没装自己的东西最佳时机) 或 [S2](#s2已经用了很久保守清理) |
| 浏览器主页变成 hao123 / 2345 导航，改不回来 | 三层劫持（策略/配置/会话） | [S3](#s3只有浏览器每天弹广告定点修) |
| **每天第一次**开浏览器会自己多出一个 2345 标签 | 会话层劫持（`Sessions\Tabs_*`） | [S3 第 3 步](#32-操作顺序) |
| 卸载了过几天又回来 | 计划任务 / WMI / 主页锁定 | [S4](#s4清了又回来断根) |
| 右下角弹通知条，点开是导航站 | 浏览器站点通知权限 | [S3 第 4 步](#32-操作顺序) |

### 2.2 用"四个硬指标"确认是不是大白菜装的

按证据强度排序，**命中任意两条即可确认**：

| # | 指标 | 怎么查 |
|---|---|---|
| 1 | `HKLM\SOFTWARE\DaBaiCai` 存在，且有 `FileName`（镜像名）与 `Soft`（渠道号） | 工具 A2 段 |
| 2 | `C:\Windows\Panther\unattend.xml` 写入时间 ≈ 系统安装时间，且含 `RunSynchronous` | 工具 B1 段 |
| 3 | `C:\Windows\` 下有 8–16 位随机字母目录，里面是 `.img/.ext` 分包 | 工具 B2 段 |
| 4 | 装机当天集中出现 360/2345 系软件，且与 `Soft` 键渠道号对得上 | 工具 C1/C2 段 |

四条全中 = 证据链完整。只有第 4 条 = 可能只是你自己装的软件。

### 2.3 系统安装时间怎么查

```powershell
(Get-CimInstance Win32_OperatingSystem).InstallDate
```

这个时间点是一切比对的基准。工具的 C1 段就是拿它 ±3 天去筛"装机当天那批软件"。

> 注意：`InstallDate` 在做过"系统还原"或"镜像克隆"后可能不准。此时以 `C:\Windows\Panther\unattend.xml` 的写入时间为准。

---

## 第 3 章 工具篇：四个启动器怎么用

### 3.0 文件清单

```
大白菜清理工具\
├─ RUN_1_Scan.cmd          ← 双击 = 只读排查（零改动）
├─ RUN_2_Fix.cmd           ← 右键管理员 = 可逆修复（逐项 YES）
├─ RUN_3_Quarantine.cmd    ← 右键管理员 = 隔离目录（单批 ≤10）
├─ RUN_4_PurgeReg.cmd      ← 右键管理员 = 删注册表键（先导出 .reg）
├─ DBC_Sweeper.ps1         ← 主脚本（启动器都调它）
├─ DBC_Sweeper_Report\     ← 跑过一次就有的报告目录（见第 3.1 节）
├─ dabaicai-cleaner.zip    ← 可直接安装的 skill 包
└─ 大白菜装机清理-使用说明.md
```

**为什么用 `.cmd` 而不是直接跑 `.ps1`：**
本机 `ExecutionPolicy` 常是 `Restricted`，直接双击 `.ps1` 会被拦。`.cmd` 已内置 `-ExecutionPolicy Bypass`，
而且 `RUN_2/3/4` 会自动弹 UAC 请求管理员权限。

> 启动器本身是纯 ASCII、CRLF 换行，中文全部由 PowerShell 输出——这样在任何区域设置（中文 936 / 英文 437 / UTF-8 65001）下都不会出现乱码或被截断。这是踩过的坑：UTF-8 中文写进 `.cmd`，在 936 代码页下会把换行吃掉，导致命令被拆成 `ho` / `ershell.exe` 这种碎片。

### 3.1 RUN_1_Scan.cmd：只读排查

**做什么**：扫五个层、生成报告。**不删、不改、不禁用、不联网。**

**耗时**：9–14 秒（不加 `-Measure`）。加 `-Measure` 统计目录体积，可能 1–3 分钟。

**输出**（在 `大白菜清理工具\DBC_Sweeper_Report\`）：

| 文件 | 用途 |
|---|---|
| `report.html` | 自包含报告，双击用浏览器打开 |
| `findings.json` | 机器可读，便于做前后对比 |
| `ioc_db.json` | 本次使用的特征库，可自己加 |
| `actions.json` | 写模式才有内容 |

### 3.2 报告怎么读

#### 第一节：综合判断

```
综合判断：置信度 高
多项强特征吻合，系统确实被大白菜 PE 植入了推广/劫持
```

置信度规则：**Safe ≥ 4 → 高**；Safe 1–3 → 中；Safe 0 → 低。

#### 第二节：四个数字

- **可处理（强特征）** = 明确是推广/劫持，写模式可以处理
- **需人工确认** = 可能是你自己装的，工具不动
- **保护项** = 系统组件 / 代理 / 文件关联，工具永远不碰
- **合计**

#### 第三节：三张分级表

每行是：`阶段 | 类别 | 对象（含完整路径） | 说明 | 建议`

**读法**：先看「可处理」那张表，这些是真正要处理的；「需人工确认」快速扫一眼有没有你不认识的；
「保护项」一般可以直接忽略。

#### 后四节

植入链路表（帮助理解为什么）、工具不做但你应该做的（6 条）、工具边界（做什么/不做什么/已知不完美）、
情报来源与可信度（哪条来自官方、哪条来自逆向、哪条是推测）。

### 3.3 RUN_2_Fix.cmd：可逆修复

**前提**：右键 → 以管理员身份运行。

**它做什么**（每项都会先备份，再问你 `YES`）：

| 动作 | 对象 | 可逆方式 |
|---|---|---|
| 改名 | `initial_preferences` → `.dbc_bak` | 改回原名 |
| 重写（改名失败时） | 只清 `homepage` / `restore_on_startup` / `startup_urls` 四个字段，其余不动 | `Backup_*\*_Preferences.bak` 覆盖回去 |
| 移动 | `Sessions\Tabs_*`、`Code Cache\js\*`、收藏夹 `.url` | 从 `Quarantine_*` 移回 |
| 删注册表值 | Run/RunOnce 里的推广项 | `Backup_*\Run_*.reg` 双击导入 |
| 禁用任务 | 命中推广特征的计划任务 | `Enable-ScheduledTask` 或导入 XML |
| 改快捷方式 | 只清「目标」参数里被追加的网址，不动目标程序 | `Backup_*\*.lnk` 覆盖 |
| 注释 hosts | 加 `# [DBC-Sweeper]` 前缀，不删行 | `hosts.dbc_bak` 覆盖 |
| 改通知权限 | 推广站点改为「阻止」（setting=2），不删站点数据 | `Backup_*\*_Preferences.bak` |

**它不做什么**：不卸载软件、不删文件、不碰服务/驱动/UAC/组策略/`Windows.old`。

**浏览器还在运行时**：工具会自动跳过会话与缓存清理，并提示「Edge 还在运行（N 个进程）」。
先 `edge://quit` + 任务管理器确认 0，再跑。

### 3.4 RUN_3_Quarantine.cmd：隔离目录

把三样东西**移入**隔离区（不是删除）：

1. 推广软件目录（`360`、`2345Soft`、`360sd`、`360Chrome` 等，用显式名不泛匹配）
2. `C:\Windows\<随机名>\` 里的加密分包目录
3. `Panther\unattend.xml`（仅当命中特征时）

**单批上限 10 个**，逐项问 `YES`。超过 10 个会提示"再次运行可继续"。

> ⚠️ **隔离 ≠ 释放空间**。`Move-Item` 只是换了个目录。要确认没问题后**手动清空** `Quarantine_*` 才真正腾出空间。

### 3.5 RUN_4_PurgeReg.cmd：删注册表键

只删这七个明确属于推广的根键：

```
HKCU\Software\2345.com          HKCU\Software\2345
HKLM\SOFTWARE\2345              HKLM\SOFTWARE\WOW6432Node\2345
HKLM\SOFTWARE\360Safe           HKLM\SOFTWARE\WOW6432Node\360Safe
HKLM\SOFTWARE\360               HKLM\SOFTWARE\WOW6432Node\360
```

每个键删除前**自动导出 `.reg`**（UTF-16，双击可导入恢复）。

**不会删** `HKLM\SOFTWARE\DaBaiCai`。它是溯源的证据，删了不影响任何软件，只会让你以后查不到来源。

### 3.6 参数全集

| 参数 | 说明 |
|---|---|
| （无） | 纯只读，等同 `-Scan` |
| `-Fix` | 可逆修复 |
| `-Quarantine` | 隔离目录 |
| `-PurgeReg` | 删推广注册表键 |
| `-IAcknowledge` | 写操作必须。缺它 → `exit 1` |
| `-Measure` | 统计目录体积（慢） |
| `-SkipBrowser` | 跳过浏览器层 |
| `-OutDir <路径>` | 指定输出目录 |
| `-MaxBatch <n>` | 隔离单批上限，默认 10 |

手动调用示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DBC_Sweeper.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\DBC_Sweeper.ps1 -Fix -IAcknowledge
powershell -NoProfile -ExecutionPolicy Bypass -File .\DBC_Sweeper.ps1 -Quarantine -IAcknowledge -Measure
```

### 3.7 安全闸与回滚

#### 四道闸

```
闸 1  缺 -IAcknowledge                     → exit 1
闸 2  非交互会话 / -NonInteractive         → exit 1（防无人值守误操作）
闸 3  非管理员                             → exit 1
闸 4  每个具体动作单独 Read-Host，必须大写 YES
```

出于安全考虑，**写模式不能在计划任务、自动化、管道里被批量执行**——这是设计，不是缺陷。

#### 回滚对照表

| 改了什么 | 怎么恢复 |
|---|---|
| `initial_preferences` 改名 | 把 `.dbc_bak` 改回原名 |
| 会话 / 缓存文件 | 从 `Quarantine_*\Sessions`、`Quarantine_*\CodeCache` 移回 |
| 启动项值 | 双击 `Backup_*\Run_*.reg` |
| 计划任务 | `Enable-ScheduledTask -TaskName X -TaskPath Y` |
| hosts | `Backup_*\hosts.dbc_bak` 覆盖 |
| 快捷方式 | `Backup_*\*.lnk` 覆盖 |
| 推广目录 | 从 `Quarantine_*\Promo\` 移回原路径 |
| 注册表键 | 双击 `Backup_*\HKEY_*.reg` |

---

## 第 4 章 手工篇：分场景操作

### S0｜还没装系统（成本最低，收益最大）

#### S0-a 继续用大白菜，但去掉捆绑

1. 打开大白菜制作器 → 左侧「个性设置」→ 右下角「支持我们」
2. **全部取消勾选**（赞助商主页、绿色软件）
3. 弹窗要密码 / 解锁码：
   - 老版本：输入 `winbaicai.com`（UEFI 版为 `bigbaicai.com`）
   - v6.0_2002 之后：点「我要狠心取消」→ 复制弹窗里的**机器码** → 关注公众号发送机器码 → 填入返回的**解锁码**
     （机器码每次重开窗口都会变，必须与当前弹窗完全一致，区分大小写）
4. **必须点「保存设置」**，出现「保存成功」才算生效。只取消不保存 = 没做
5. **重新制作一次 U 盘**

> 这只去掉"装机时自动装软件"。PE 里那些删安全软件、改浏览器设置的模块是否一并消失，
> 厂商没有承诺。想彻底干净走 S0-b。

#### S0-b 换工具（推荐）

| 方案 | 说明 |
|---|---|
| 微PE + 官方 ISO + Rufus | 最干净。但搜索引擎前几条常是仿冒站，认准官网 |
| 优启通（EasyU） | IT 天空出品，带万能驱动，实测无推广 |
| 微软媒体创建工具 | 最简单，但无 PE 维护工具 |

ISO 校验：`Get-FileHash .\xxx.iso -Algorithm SHA256`，与官方公布值比对。

#### S0-c 就地净化 U 盘（进阶，有风险）

需要 `FbinstTool` + `UltraISO` + `WimTool`（或 `Dism++`）：

1. FbinstTool 打开 U 盘 → 导出 `\PE\DBC8x64.ISO`
2. UltraISO 打开 ISO → 提取 `DBC8x64.WIM`
3. WimTool 解开 WIM → 定位 `Windows\Packages\`
4. 删 `System32.7z`（约 5087 KB）与 `PF.7z`
5. 重新打包 WIM → 替换回 ISO → FbinstTool 写回 UD 区
6. **所有 PE 镜像都要处理**（Win2003PE / Win8PE / Win10PE / UEFI 版）

> 改坏 WIM 会导致 U 盘无法启动。改前把原 ISO 备份到硬盘。

---

### S1｜刚装完系统，还没装自己的东西（最佳时机）

这是唯一能"接近彻底"的窗口。**顺序不能变。**

#### 第 1 步｜断网 + 备份

- 拔网线 / 关 WiFi
- C 盘空间够（> 5 GB）就建还原点；不够就别建（还原点会继续吃 C 盘），改为把要留的文件拷到移动硬盘
- 导出已装软件清单：

```powershell
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*,
                 HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
  Sort-Object InstallDate |
  Export-Csv "$env:USERPROFILE\Desktop\installed.csv" -NoTypeInformation -Encoding UTF8
```

#### 第 2 步｜卸载

设置 → 应用 → 安装的应用 → 按「安装日期」排序 → 装机当天那批批量卸载。

卸载时注意：

- 「保留用户数据 / 保留主页设置 / 推荐安装其他软件」**全部取消**
- 出现「修复」「升级」按钮说明你点到挽留界面了，退回去找「卸载」
- 卸不干净用 **Geek Uninstaller**（5 MB 单文件免安装）：右键 → 强制删除 → 自动扫残留

#### 第 3 步｜断根（最容易漏，漏了必复发）

| 位置 | 操作 | 说明 |
|---|---|---|
| 任务管理器 → 启动应用 | 禁用陌生项，看「发布者」列 | 空白/乱码重点看 |
| `taskschd.msc` | 动作指向 `AppData`、`Temp`、随机名 exe 的任务 | **先禁用，观察两天再删** |
| `services.msc` | 按「可执行文件路径」排序，找指向不存在目录的 | 停服务后还要看驱动 |
| **Autoruns** | Logon / Services / Drivers / Scheduled Tasks / WMI 一页看全 | WMI 页签是重点 |
| `regedit` → Run / RunOnce | 删前右键导出 | `HKCU`、`HKLM`、`WOW6432Node` 三处都看 |
| 启动文件夹 | `shell:startup` 与 `shell:common startup` | 空的才正常 |

#### 第 4 步｜拆部署期载荷

1. 找 `C:\Windows\<随机名>\`（本机实例：`C:\Windows\Vmaprlfxn\`，内含 10 个 `SUPPORT.IMG*`，450 MB）
2. 找 `C:\Windows\Panther\unattend.xml`，确认写入时间 ≈ 系统安装时间
3. **在 PE 环境下**把这两项一起处理
4. 如果系统已经用了很久，这两项危害有限（启动器早自删），但几百 MB 值得回收

> 为什么不建议在已装大量软件的系统上删 `unattend.xml`：某些 OEM 机器靠它维护配置。
> 这也是工具默认只报告、要你显式 `-Quarantine` 才动的原因。

#### 第 5 步｜修浏览器

完整流程见 [S3](#s3只有浏览器每天弹广告定点修)。

#### 第 6 步｜恢复被改的系统设置

```powershell
# 恢复 UAC（改前先导出备份）
reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
           "%USERPROFILE%\Desktop\uac_backup.reg" /y
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name ConsentPromptBehaviorAdmin -Value 5
```

`.html` / `http` / `https` 关联走「设置 → 应用 → 默认应用」，**不要**手改 `UserChoice`（带哈希校验）。

#### 第 7 步｜验证

见 [S6](#s6验证是否清干净五查)。

---

### S2｜已经用了很久（保守清理）

不要按 S1 全套做——你机器上有大量自己的软件，激进清理风险高。

**只做这四件**：

1. 卸载明确的推广软件（按名称筛 360 / 2345 / 腾讯视频 / 爱奇艺 / 酷狗 / 老黄历 / 鲁大师 / 驱动人生 / 快压）
2. 修浏览器（S3 全套）
3. 隔离残留目录（`RUN_3_Quarantine.cmd`，逐项 YES）
4. 全盘扫描：火绒全盘 + Windows 安全中心「Microsoft Defender 脱机扫描」

**不做**：删 `unattend.xml`、改 UAC、动服务/驱动、注册表大扫除。
理由：在长期使用的系统上收益低、风险高。

---

### S3｜只有浏览器每天弹广告（定点修）

这是最高频、也最容易修的场景。

#### 3.1 先判断是哪一层

| 现象 | 层 | 位置 |
|---|---|---|
| 设置里「启动时」是灰的，点不了 | ① 策略层 | `Policies\Microsoft\Edge` |
| 能改，但重启又变回推广页 | ② 配置层 | `initial_preferences` |
| 启动设置正常，但每天第一次打开会多出标签 | ③ 会话层 | `Sessions\Tabs_*` |
| 弹的是右下角通知条 | ④ 通知层 | `content_settings.exceptions.notifications` |
| 弹的是独立窗口、有标题栏和按钮 | ⑤ 进程层 | 有常驻程序，查启动项/计划任务 |

#### 3.2 操作顺序

##### 第 0 步｜彻底退出浏览器

```
edge://quit      （Edge）
chrome://quit    （Chrome）
```

任务管理器确认 `msedge.exe` / `chrome.exe` 进程数为 **0**。
浏览器的「启动增强 / 后台常驻」会让它假装关掉了。

##### 第 1 步｜查策略层

```powershell
foreach ($k in @(
  'HKLM:\SOFTWARE\Policies\Microsoft\Edge','HKCU:\SOFTWARE\Policies\Microsoft\Edge',
  'HKLM:\SOFTWARE\Policies\Google\Chrome','HKCU:\SOFTWARE\Policies\Google\Chrome')) {
  if (Test-Path $k) { $i=Get-Item $k; foreach($n in $i.GetValueNames()){ "$k :: $n = $($i.GetValue($n))" } }
}
```

看到 `HomepageLocation` / `RestoreOnStartup` / `RestoreOnStartupURLs` 指向推广域名 →
先导出备份，再删这些值。删完浏览器设置项会从灰变可点。

##### 第 2 步｜查配置层

```powershell
$p = 'C:\Program Files (x86)\Microsoft\Edge\Application\initial_preferences'
Get-Item $p | Select-Object FullName, Length, CreationTime, LastWriteTime
Get-Content $p -Raw
```

关键判据：**Edge 官方安装不带这个文件**。如果它有内容且 `LastWriteTime` ≈ 装机时间 → 就是它。

命中后改名为 `.dbc_bak`（需管理员）。工具会自动做，改名失败时降级为"只清 4 个字段"。

也检查 `Preferences`：

```powershell
$p = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"
(Get-Content $p -Raw | ConvertFrom-Json).session | ConvertTo-Json -Depth 5
```

##### 第 3 步｜查会话层（关键，多数教程漏掉）

```powershell
$s = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Sessions"
$lat = [System.Text.Encoding]::GetEncoding(28591)
Get-ChildItem $s -File | ForEach-Object {
  $t = $lat.GetString([System.IO.File]::ReadAllBytes($_.FullName))
  [pscustomobject]@{
    File = $_.Name
    Hits = ([regex]::Matches($t,'(?i)2345\.com|2354mt|hao123')).Count
    Time = $_.LastWriteTime
  }
} | Format-Table -AutoSize
```

`Hits > 0` 的文件**移走**（不是删），Edge 下次启动会重建干净会话。

> 这是"每天第一次打开才弹"的真正原因：Edge 冷启动恢复上次会话，把推广标签原样带回。
> 时间戳会精确对应"你今天第一次开浏览器"的时刻。

##### 第 4 步｜查通知层

`edge://settings/content/notifications` → 删掉所有不认识的「允许」。

或脚本定位：

```powershell
$p = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"
$j = Get-Content $p -Raw | ConvertFrom-Json
$j.profile.content_settings.exceptions.notifications.PSObject.Properties |
  ForEach-Object { "$($_.Name)  setting=$($_.Value.setting)" }
# setting=1 允许，setting=2 阻止
```

##### 第 5 步｜查扩展

`edge://extensions` → 按「最近添加」排序 → 名字含"导航 / 加速 / 主页 / 搜索 / 快搜 / 省心"的
一律**移除**（不是停用——停用后它仍能后台写注册表）。

##### 第 6 步｜清站点数据

`edge://settings/content/all` → 搜 `2345.com`、`2354mt` → 删除。

##### 第 7 步｜验证

重启 → 第一次开浏览器 → 确认没多出标签。**连续观察两天**（会话层问题可能隔天才复现）。

---

### S4｜清了又回来（断根）

按此顺序查：

1. **安全软件的"主页锁定"**：360 / 2345 / 腾讯管家都有「浏览器保护 / 主页锁定」。
   它锁定的主页是它自己认为"安全"的那个。你改了，它秒改回去。关掉它，或把锁定地址改成你要的。
2. **计划任务**：`taskschd.msc`，动作列带 `http` 或指向 `AppData` 的，禁用。
3. **WMI 永久订阅**：Autoruns → WMI 页签。`CommandLineEventConsumer` 有内容就是有问题。
4. **快捷方式尾巴**：桌面 + 任务栏 + 开始菜单三处 `.lnk`，属性 → 目标，末尾多出的网址删掉。
5. **hosts**：`C:\Windows\System32\drivers\etc\hosts`，只留 `127.0.0.1 localhost`。
6. **多用户**：`C:\Users\` 下是否有第二个账户带着同样的劫持配置（`netplwiz` 查看）。

---

### S5｜回滚

见 [3.7 回滚对照表](#37-安全闸与回滚)。

---

### S6｜验证是否清干净（五查）

1. **查来源**：`HKLM\SOFTWARE\DaBaiCai` 还在不在（在 = 这台确实是大白菜装的，属正常留证）
2. **查载荷**：`C:\Windows\` 下还有没有随机字母目录装 `.img/.ext`
3. **查落地**：`Program Files`、`Program Files (x86)`、`ProgramData`、`%LOCALAPPDATA%`、`%APPDATA%`
   还有没有 `360`、`2345Soft`
4. **查复活**：`taskschd.msc` 是否还有可疑任务；Autoruns WMI 页签是否干净
5. **查浏览器**：连续两天，每天第一次开浏览器，看是否多出标签

五查全过 ≈ 干净。再跑 `RUN_1_Scan.cmd`，`Safe` 应为 0
（`Review` 里剩下的多为站点访问痕迹、装机留证、`.html` 关联）。

---

## 第 5 章 深入：特征库与判定逻辑

### 5.1 五层扫描

| 层 | 检查内容 |
|---|---|
| **0 环境** | 系统版本 / 安装日期、UAC 两项、管理员令牌、磁盘余量、是否 PE 环境 |
| **A 源头** | 制作工具目录、卸载项、`HKLM\SOFTWARE\DaBaiCai` + 渠道号、U 盘载荷、硬盘上的装机 ISO、`D:\大白菜PE` |
| **B 部署期** | `unattend.xml` 字段打分、随机名目录 + `.img/.ext`、系统盘根随机名目录、`NUML0CK`、伪装计划任务 |
| **C 落地** | 装机窗口内新装软件、推广目录、注册表键、服务/驱动、Run/RunOnce、启动文件夹、快捷方式尾巴、hosts、代理（只读）、收藏夹、文件关联、WMI |
| **D 浏览器** | `initial_preferences`、`Preferences.session`、`Sessions\*`、`Code Cache\js`、`Policies`、通知权限、扩展、默认搜索 |
| **E 残留** | `Windows.old` / `$Windows.~BT`、`Windows\Temp`、驱动包、回收站 |

### 5.2 分级原则

| 级别 | 判定标准 | 工具行为 |
|---|---|---|
| **Safe** | 命中强特征（显式目录名 / 明确域名 / 无人值守字段组合） | 写模式可处理 |
| **Review** | 需上下文（可能是你自己装的、可能是 OEM 配置） | 只报告 |
| **Protect** | 系统组件、代理、文件关联、临时目录 | 永远不碰 |

### 5.3 白名单（保护你的开发环境）

```
Microsoft  Windows  WindowsApps  WinSxS  System32  SysWOW64
Python  PlatformIO  Arduino  Code(VS Code)  Git  nodejs  Java
CH340  CP210x  FTDI  Silicon Labs  Espressif
Realtek  Intel  NVIDIA  AMD
```

这些不会被判成推广软件。本机实测中被正确保护的有 PlatformIO、Arduino、CH340 驱动、Python、VS Code。

### 5.4 已知误报来源（都修过）

| 现象 | 原因 | 修法 |
|---|---|---|
| `WXWork`、`AweSun`、`Everything` 被判"随机名启动器" | PowerShell `-match` **默认不区分大小写**，`[A-Z][a-z]{5,15}` 退化成"任意字母" | 用 `-cmatch` + 限定 `C:\Windows\` 前缀 |
| `DiagTrack`、`BrowserCore`、`servicing` 被判可疑 | 随机名启发式过宽 | 加可读词白名单 + 要求目录含 payload |
| `desktop.ini` 被列为启动项 | 启动文件夹里的隐藏系统文件 | 显式跳过 |
| Visual C++ 运行库刷屏 | 安装日期窗口过滤太宽 | 按发布者 / 名称过滤大厂与运行库 |
| `.NET NGEN` 任务被视为 IOC | 把通用 GUID 当特征 | 不收录该 GUID |

---

## 第 6 章 辟谣：这五条别照做

### ✗ 1. CSDN「问」上那些大白菜去广告回答

特征：页面底部有「GEO 优化 / AI 选题 / 数据监测 / 一键分发」推广位；回答结构工整但空泛；
给出的键值、域名、进程名在别处查不到；动辄 `reg delete /f` + `del /f`。

危害：`reg delete /f` 会删掉真实存在的系统键。**本工具未采信其中任何一条。**

### ✗ 2. "删掉 `System32.7z` 就一劳永逸"

部分对：

- 对**还没装的系统**有效——删掉后 PE 里不再生成 `NUML0CK.exe`
- 对**已经装好的系统**无效——软件已经装了，删 U 盘里的文件不会卸载它们
- 而且要处理**所有** PE 镜像，只改一个不彻底

### ✗ 3. "把 `.NET Framework NGEN` 任务删掉"

逆向记录里出现过它的 TaskCache GUID（`{9903F86D-…}`），但那就是**系统自带的 NGEN 维护任务**。
当 IOC 会大面积误报，删了可能影响 .NET 程序启动。**不要动。**

### ✗ 4. "用 XX 一键清理大师深度清理注册表"

注册表误删的代价是重装系统，收益是"可能"少几个残留键。
正确做法：只删你**能指出它属于哪个软件**的键，删前导出 `.reg`。

### ✗ 5. "装个 360 就能防住"

被推广装的 360 本身就是推广目标之一，而且它会**默认锁定浏览器首页**——
这正是"改了设置又变回去"的常见原因之一。

### 一条自检口诀

看到一个"大白菜 IOC"时问三句：

1. 能在两个独立来源里找到吗？（只有一处且带推广位 → 大概率编的）
2. 它是"行为描述"还是"具体路径/键值"？（后者才能在自己机器上验证）
3. 它建议的动作可逆吗？（让你 `reg delete /f`、`del /f`、全盘 `takeown` 的，先怀疑）

---

## 第 7 章 FAQ（32 条）

### 判断类

**1. 我怎么知道这台是不是大白菜装的？**
看 2.2 的四个硬指标，命中两条即可。跑 `RUN_1_Scan.cmd` 会自动给结论。

**2. 用的是微软原版 ISO，为什么还有推广？**
脏的是 PE 不是 ISO。ISO 被 PE 里的装机工具释放到 C 盘，推广是在这之后注入的。

**3. 删掉 `HKLM\SOFTWARE\DaBaiCai` 是不是就好了？**
不是。它只是渠道记账，删了不影响已装软件，反而丢了溯源证据。建议保留。

**4. 报告里 Safe 是 0，但我还是被弹广告？**
先分清弹的是什么：通知条 → 站点通知权限；独立窗口 → 有常驻进程；浏览器内新标签 → 会话层。
这三类不一定命中"推广软件"特征。

**5. `Review` 里那些是我自己装的软件，要处理吗？**
不用。Review 只是"装机窗口内出现的、发布者不是大厂的软件"，供你核对。

**6. 为什么工具说"置信度高"，但我没看到明显广告？**
强特征指"植入链路完整"（无人值守文件 + 载荷目录 + 渠道号 + 推广目录），
不等于"现在还在弹广告"——启动器早已自删，剩下的是残留。

**7. 系统安装日期不准怎么办？**
以 `C:\Windows\Panther\unattend.xml` 的写入时间为准。做过系统还原或镜像克隆时 `InstallDate` 会失真。

### 操作类

**8. 为什么必须先完全退出浏览器？**
浏览器有后台常驻（启动增强 / `--win-session-start`）。退出时会把当前标签写回 `Sessions\Tabs_*`，
你刚清理的文件会被覆盖回去。`edge://quit` 后确认进程数 0。

**9. 改了"启动时"设置，第二天又变回推广页？**
三层劫持：策略层 > 配置层 > 会话层。只改界面动的是第 2 层的用户可见部分，前两层还在。

**10. "启动时"是灰的，点不了？**
策略层被写了 `RestoreOnStartup` / `HomepageLocation`。删掉 `Policies\Microsoft\Edge` 下对应值
（先导出备份），重启浏览器。

**11. 为什么工具不帮我删 `C:\Windows\Vmaprlfxn`？**
在系统目录，且可能是 OEM 配置残留。工具只报告；要动用 `RUN_3_Quarantine.cmd` 移入隔离区，
或进 PE 处理。

**12. `-Quarantine` 之后 C 盘没变大？**
隔离是移动，文件还在同一块盘。要确认无误后**手动清空** `Quarantine_*` 才释放空间。

**13. 能直接删 `Windows.old` 吗？**
不要手删。走「设置 → 系统 → 存储 → 临时文件 → 删除以前版本的 Windows」。
手删常留下权限死结，且无法回滚旧系统。

**14. UAC 被关了怎么恢复？**
`EnableLUA=1`、`ConsentPromptBehaviorAdmin=5`，改前导出注册表键，改完重启。

**15. `.html` 关联变成 `360seURL`，改注册表改不动？**
`UserChoice` 带哈希校验，手改会被重置。走「设置 → 应用 → 默认应用」。

**16. 卸载 360 时它弹"保留主页设置"怎么办？**
**不要勾选保留**。那个"保留"就是保住劫持。

**17. 360 卸不掉，提示被保护？**
进安全模式（`msconfig` → 引导 → 安全引导 → 网络）再卸，或先用它的自带"完全卸载"。

**18. 系统代理被改成 `127.0.0.1:7897`，是病毒吗？**
大概率是你自己的代理工具。工具只报告不改。看 `ProxyOverride` 是否排除了所有内网段——那是典型的人工配置。

**19. 想反悔怎么恢复？**
见 3.7 回滚对照表。所有东西都在 `Backup_*` / `Quarantine_*`。

**20. 桌面图标全没了 / 桌面文件不见了？**
只可能是误删或被"优化"工具动过。本工具不碰桌面文件（只清快捷方式参数里的网址）。
先从回收站找，再从 `C:\Users\<你>\Desktop` 与 `C:\Users\Public\Desktop` 核对。

### 工具类

**21. 提示"需要管理员"，我明明是管理员账户？**
UAC 会过滤管理员令牌（`FilterAdministratorToken`）。右键 `.cmd` → 以管理员身份运行。

**22. 能从计划任务/自动化里调 `-Fix` 吗？**
不能，设计如此。非交互会话直接 `exit 1`。清理必须人工逐项确认。

**23. 报"无法加载文件，因为在此系统上禁止运行脚本"？**
`ExecutionPolicy` 是 `Restricted`。用 `.cmd` 启动器（已带 Bypass），或手动加该参数。

**24. 输出中文乱码？**
`.cmd` 已 `chcp 65001`。直接跑 `.ps1` 时先 `chcp 65001`，或用 Windows Terminal。

**25. 扫描时某个目录报"拒绝访问"？**
正常，被系统保护。脚本已用 `-ErrorAction SilentlyContinue` 跳过，不影响结论。

**26. 报告表格挤在一起？**
`report.html` 用了 `word-break:break-all`，窗口拉宽即可；手机上看会自动折行。

**27. 需要装什么依赖吗？**
不需要。PowerShell 5.1（Win8.1 及以上自带）+ 管理员权限即可。不联网、不装任何东西。

**28. 会不会误删我的开发环境？**
白名单保护 PlatformIO / Arduino / Python / VS Code / CH340 等。写模式只动浏览器配置、
推广启动项、推广计划任务、被追加网址的快捷方式、hosts 推广行、推广目录。

### 效果类

**29. 清完还要做什么？**
1) 重开浏览器确认没多出标签；2) 连续观察两天；3) 重跑扫描，`Safe` 应为 0；4) 治本——重做纯净启动盘。

**30. 会不会下次装系统又中？**
用同一支 U 盘就会。除非按 S0 取消赞助商后**重新制作**，或换工具。

**31. 装完多久内清理最有效？**
越早越好。刚装完、还没装自己软件的窗口期是唯一能"接近彻底"的时机。

**32. 清完还是觉得卡？**
广告残留只是原因之一。看启动项数量、磁盘剩余（< 10% 会明显卡）、内存占用。
不要用"一键优化"——它会关掉你需要的服务。

---

## 第 8 章 本机实测案例（真实数据）

> 这台机器是 2026-11-03 用大白菜装的 Win11 专业版。以下全部为实测，非示意。

### 8.1 扫描结果

```
主机：Win11 专业版 ｜ 系统安装：2026-11-03 10:21 ｜ 耗时 9.3 秒
结论：置信度 高 ｜ Safe 6 ｜ Review 13 ｜ Protect 2
```

### 8.2 六项 Safe（强特征）

| 阶段 | 对象 | 证据 |
|---|---|---|
| B 部署期 | `C:\Windows\Panther\unattend.xml` | 2583 字节，写入 2026-11-03 10:21；命中 `RunSynchronousCommand`×8、`FirstLogonCommands`×2、`ConsentPromptBehaviorAdmin`×2、`net user Administrator`×2、ploc 账户、随机名启动器路径 |
| B 部署期 | `C:\Windows\Vmaprlfxn\` | 10 个 `SUPPORT.IMG*` 分包，合计 **450.3 MB**，无 exe |
| C 落地 | `C:\ProgramData\360sd` | 360 杀毒数据目录 |
| C 落地 | `%LOCALAPPDATA%\360Chrome` | 360 浏览器数据目录 |
| C 落地 | 收藏夹 `大白菜官网.URL` | **PE 预置收藏夹**，直接证据 |
| D 浏览器 | Edge `Code Cache\js` 2 个文件 | 含 2345 推广脚本缓存 |

### 8.3 装机记录（最有说服力的一条）

```
HKLM\SOFTWARE\DaBaiCai
  Version    = 6.0.2604.3
  FileName   = Win11_25H2_Pro_Chinese_Simplified_x64_v2.iso
  UniqueCode = E703E6BAEF05F27B46C7B47498350D47
  Soft\      DriveTheLife=57459   Taobao=cbdh956   chaojituzi=lm
             2345explorer=511097  360se=5000783   EdgeSetup=1773998236
             360safe=5000782      Chrome=1773998236
```

### 8.4 十三项 Review（供人工确认）

`UAC 提权不弹窗`、`装机记录键`、`D:\Win11_25H2_Pro_...iso（7897 MB）`、
`火绒安全软件`、`CC Switch`、`AutoShop`、`DTools Pro`、`EBpro`、`ima`、`TRAE CN`、
`代理 127.0.0.1:7897`、`.html → 360seURL`、`Chrome 的 initial_preferences`。

> 这台的 Review 质量是"零误报"：每一项都确实值得人看一眼。
> 其中 6 项是用户自己装的工业软件/开发工具，2 项是系统设置，5 项是溯源与残留。

### 8.5 一个额外发现

`.html` 关联被改成了 `360seURL`。这个只能走「设置 → 应用 → 默认应用」改，
手改注册表会被 `UserChoice` 的哈希校验重置——工具因此只标 Review，不动它。

---

## 附录

### A. 命令速查

```powershell
# 系统安装时间
(Get-CimInstance Win32_OperatingSystem).InstallDate

# 按安装日期看软件
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*,
                 HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Where-Object DisplayName |
  Select-Object DisplayName, Publisher, InstallDate |
  Sort-Object InstallDate -Descending | Format-Table -AutoSize

# 浏览器进程数（修之前必须为 0）
Get-Process msedge,chrome -ErrorAction SilentlyContinue |
  Group-Object Name | Select-Object Name,Count

# 查大白菜装机记录
Get-ItemProperty 'HKLM:\SOFTWARE\DaBaiCai' | Format-List
Get-ItemProperty 'HKLM:\SOFTWARE\DaBaiCai\Soft' | Format-List

# 扫某目录里含 2345 的小文件
$lat=[Text.Encoding]::GetEncoding(28591)
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data" -Recurse -File -EA 0 |
  Where-Object Length -lt 8MB | ForEach-Object {
    $s=$lat.GetString([IO.File]::ReadAllBytes($_.FullName))
    if ($s -match '2345\.com|2354mt') { $_.FullName }
  }

# 恢复 UAC
reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "$env:USERPROFILE\Desktop\uac.reg" /y
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name ConsentPromptBehaviorAdmin -Value 5
```

### B. 常用系统入口

| 目的 | 命令 |
|---|---|
| 卸载列表 | `appwiz.cpl` |
| Internet 选项 | `inetcpl.cpl` |
| 任务计划 | `taskschd.msc` |
| 服务 | `services.msc` |
| 启动文件夹 | `shell:startup` / `shell:common startup` |
| 用户账户 | `netplwiz` |
| 存储/临时文件 | `ms-settings:storagesense` |
| 默认应用 | `ms-settings:defaultapps` |
| Edge 启动设置 | `edge://settings/startHomeNTP` |
| Edge 站点数据 | `edge://settings/content/all` |
| Edge 通知 | `edge://settings/content/notifications` |
| Chrome 对应页 | `chrome://settings/onStartup` 等 |

### C. 情报来源与可信度

| 级别 | 来源 | 提供了什么 |
|---|---|---|
| A 官方 | 大白菜官网 `help_107` | 取消赞助商 9 步、机器码/解锁码 |
| A 官方 | 2345 装机联盟计费页 | 浏览器 3.2–6.6 元/台、导航终身计费 → 动机闭环 |
| A 官方 | 微软支持文档 | 删除"以前版本的 Windows"正确路径 |
| B 厂商研究 | 火绒安全报告 834 / 794 | 互泰旗下 PE 植入、删安全软件、`NUML0CK` 为 AutoIt 编译 |
| C 逆向 | SecPulse《这大白菜有毒》 | 进程内存推广清单、备案主体 |
| C 逆向 | 社区《某白菜 PE 行为分析》 | 随机名启动器、11 个加密 img、`unattend.xml` 字段 |
| C 实测 | wityx / CSDN 解包实测 | `System32.7z` ≈ 5087 KB，删后推广消失 |
| C 实测 | 本机实证（2026-11） | 见第 8 章 |
| D 推测 | 同篇逆向 | `explorer.exe` 被替换、包藏在 `pagefile.sys` —— **未经证实，不写入特征库** |

### D. 边界与免责

- 本工具与文档用于**清理自己机器上不需要的软件与设置**，不涉及绕过授权、破解或攻击他人系统。
- 修改自己 U 盘里的 PE 镜像、重做启动盘，属于对自己财产的处置。
- 所有写操作都可回滚，但**回滚需要你保留 `Backup_*` / `Quarantine_*` 目录**。清理前请勿删它们。
- 工具不联网、不上传任何数据。
- 特征库随版本变化，`ioc_db.json` 可自行增补。新版变体可能漏判——这也是为什么每次清理后建议**连续观察两天**。

---

*文档版本 v1.0 ｜ 生成于 2026-11-06 ｜ 配套工具 DBC_Sweeper.ps1*
