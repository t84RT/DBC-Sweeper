# 工具参考：DBC_Sweeper.ps1

> 单文件 PowerShell 5.1+ 脚本，UTF-8 BOM，约 96 KB。
> 设计前提：**默认只读；写操作三重闸；所有改动可回滚。**

---

## 1. 文件清单

| 文件 | 作用 |
|---|---|
| `scripts/DBC_Sweeper.ps1` | 主脚本 |
| `scripts/RUN_1_Scan.cmd` | 双击 = 只读排查（零改动） |
| `scripts/RUN_2_Fix.cmd` | 右键管理员 = 可逆修复，逐项 YES |
| `scripts/RUN_3_Quarantine.cmd` | 右键管理员 = 隔离推广目录/载荷，单批 ≤10 |
| `scripts/RUN_4_PurgeReg.cmd` | 右键管理员 = 删推广注册表键（先导出 .reg） |

`.cmd` 启动器已内置 `-ExecutionPolicy Bypass`（本机 `ExecutionPolicy=Restricted` 时必需），
`RUN_2/3/4` 会自动请求管理员权限（`Start-Process -Verb RunAs`）。

## 2. 参数

| 参数 | 说明 |
|---|---|
| （无） | 等同于 `-Scan`，纯只读 |
| `-Fix` | 可逆修复。需 `-IAcknowledge` + 管理员 + 交互控制台 |
| `-Quarantine` | 把推广软件目录、随机名载荷目录、`unattend.xml` 移入隔离区 |
| `-PurgeReg` | 删除明确推广注册表键，逐个导出 `.reg` 备份 |
| `-IAcknowledge` | 写操作显式确认。缺它 → `exit 1` |
| `-Measure` | 统计相关目录体积（慢一些，但能看清 450 MB 那种大头） |
| `-SkipBrowser` | 跳过 D 层（只想看系统层时用） |
| `-OutDir <路径>` | 报告输出目录，默认 `<脚本目录>\DBC_Sweeper_Report` |
| `-MaxBatch <n>` | `-Quarantine` 单批上限，默认 10 |

## 3. 安全闸（实测过，不是摆设）

```
写模式 = $Fix -or $Quarantine -or $PurgeReg

闸 1  缺 -IAcknowledge            → exit 1（打印如何正确调用）
闸 2  非交互 / -NonInteractive    → exit 1（防无人值守误操作）
闸 3  非管理员                     → exit 1（提示右键管理员运行）
闸 4  每个具体动作单独 Read-Host，必须输入大写 YES
```

> 历史坑（已修）：PS 5.1 下 `$ErrorActionPreference='SilentlyContinue'` **会把 `throw` 一起吞掉**，
> 脚本继续往下跑，安全闸形同虚设。本脚本改用 `exit 1` 硬退出，并显式设
> `$ErrorActionPreference='Continue'`，靠各 cmdlet 自己的 `-ErrorAction SilentlyContinue` 抑制噪声。

## 4. 五层检查项

| 层 | 检查内容 |
|---|---|
| **0 环境** | 系统版本/安装日期、UAC（`EnableLUA`、`ConsentPromptBehaviorAdmin`）、管理员令牌、磁盘余量、是否 PE 环境 |
| **A 源头** | 制作工具目录、卸载项、`HKLM\SOFTWARE\DaBaiCai` + `Soft` 渠道号、U 盘载荷（UD/EFI 特征文件）、硬盘上的装机 ISO、`D:\大白菜PE` |
| **B 部署期** | `Panther\unattend.xml` 字段打分、`C:\Windows\<随机名>` + `.img/.ext` 分包、系统盘根随机名目录、`NUML0CK`、伪装计划任务 |
| **C 落地** | 装机窗口内新装软件（按发布者过滤大厂）、推广目录、推广注册表键、服务/驱动、Run/RunOnce、启动文件夹、快捷方式尾巴、hosts、代理（只报告）、收藏夹、文件关联、WMI 订阅 |
| **D 浏览器** | `initial_preferences`、`Preferences.session`、`Sessions\*`、`Code Cache\js`、`Policies`、通知权限、扩展、默认搜索 |
| **E 残留** | `Windows.old` / `$Windows.~BT`、`Windows\Temp`、驱动包、回收站 |

## 5. 结果分级

| 级别 | 含义 | 工具行为 |
|---|---|---|
| **Safe** | 命中强特征，可判定为推广/劫持 | 写模式下可处理（改名/移动/注释/禁用） |
| **Review** | 需人工判断（可能是你自己装的） | 只报告 |
| **Protect** | 工具绝不处理 | 只报告（系统组件、代理、文件关联、临时目录） |

**综合置信度**：Safe ≥ 4 → 高；Safe 1–3 → 中；Safe 0 → 低。

## 6. 输出

```
DBC_Sweeper_Report\
├─ report.html            自包含 HTML 报告（深色，可直接给用户看）
├─ findings.json          机器可读，便于二次处理 / 前后对比
├─ ioc_db.json            本次使用的特征库（可自行增补）
├─ actions.json           写模式下每步动作 + 回滚说明
├─ Backup_<时间戳>\        .reg / .xml / .lnk / hosts.dbc_bak / Preferences.bak
└─ Quarantine_<时间戳>\    被移走的目录与文件（Promo / Payload / Sessions / CodeCache / Favorites / Panther）
```

### report.html 章节

1. 综合判断（置信度 + 一句话结论）
2. KPI（Safe / Review / Protect / 合计）
3. 三张分级表（阶段 / 类别 / 对象与路径 / 说明 / 建议）
4. 本次实际执行的动作 + 回滚方式
5. 植入链路表（六阶段 → 落地痕迹）
6. 工具不做但你应该做的（6 条）
7. 工具边界（做/不做/不完美）
8. 情报来源与可信度 + 已知不实信息

### findings.json 结构

```json
{
  "Stage": "B 部署期",
  "Level": "Safe",
  "Category": "随机名载荷目录",
  "Name": "Vmaprlfxn（含加密分包）",
  "Detail": "命中 10 个 .img/.ext 分包，合计 450.3 MB；exe 0 个",
  "Path": "C:\\Windows\\Vmaprlfxn",
  "Action": "系统目录，工具不代删；确认后建议在 PE 下处理",
  "SizeMB": ""
}
```

前后对比：把两次的 `findings.json` 按 `Path` 做 diff，即可量化"清掉了什么"。

## 7. 写模式具体做什么

| 动作 | 目标 | 可逆方式 |
|---|---|---|
| 改名 | `initial_preferences` → `.dbc_bak` | 改回原名 |
| 重写（改名失败时） | 只清 `homepage` / `homepage_is_newtabpage` / `session.restore_on_startup` / `session.startup_urls` | `Backup_*\*_Preferences.bak` 覆盖回去 |
| 移动 | `Sessions\Tabs_*`、`Code Cache\js\*`、收藏夹 `.url` | 从 `Quarantine_*` 移回 |
| 删除注册表值 | Run/RunOnce 里的推广项 | `Backup_*\Run_*.reg` 双击导入 |
| 禁用任务 | 命中推广特征的计划任务 | `Enable-ScheduledTask` 或导入 `Backup_*\Task_*.xml` |
| 改快捷方式 | 清掉「目标」参数里被追加的网址 | `Backup_*\*.lnk` 覆盖回去 |
| 注释 hosts | 加 `# [DBC-Sweeper] ` 前缀 | `hosts.dbc_bak` 覆盖回去 |
| 改通知权限 | 推广站点 `setting` 改为 2（阻止） | `Backup_*\*_Preferences.bak` |
| 移动目录 | 推广软件目录 / 随机名载荷 / `unattend.xml` | 从 `Quarantine_*` 移回 |

## 8. 工具**不做**什么（刻意的）

- 不删任何文件：一律 `Move-Item` 到隔离区。**隔离不等于释放空间**，要你确认后手动清空。
- 不碰 `Secure Preferences`（MAC 保护，手改会校验失败）。
- 不碰组策略键（可能有其他合法策略）、UAC、服务、驱动、`Windows.old`、用户账户、代理。
- 不碰 `C:\Windows\<随机名>` 和 `unattend.xml`（系统目录 + 可能是 OEM 配置）——只报告，`-Quarantine` 才动，且要逐项 YES。
- 不自动卸载软件（卸载向导有挽留陷阱，交人工）。
- 不联网。

## 9. 常见失败与处理

| 报错 | 原因 | 处理 |
|---|---|---|
| `[已拒绝] 写操作需要管理员权限` | 非提升会话 | 右键 `.cmd` → 以管理员身份运行 |
| `[已拒绝] 检测到非交互会话` | 从自动化/管道调用 | 必须人工在控制台跑（设计如此） |
| 改名 `initial_preferences` 失败 | `BUILTIN\Users` 只有读权限 | 脚本会自动降级为"重写字段"；或提权后再跑 |
| 隔离目录失败：文件被占用 | 进程还在跑 | 任务管理器结束进程，或重启后重试 |
| 会话文件被跳过 | 浏览器仍在运行 | `edge://quit` 后确认进程数 0 |
| 输出中文乱码 | 控制台代码页 | `.cmd` 已 `chcp 65001`；直接跑 ps1 时先 `chcp 65001` |

## 10. 性能

本机实测（Win11、200 GB C 盘、约 110 个已装程序）：**9–14 秒**（不加 `-Measure`）。
加 `-Measure` 会遍历目录大小，视目录规模可能到 1–3 分钟。
