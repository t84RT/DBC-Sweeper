# 人工清理手册（分场景，可照做）

> 原则：**先断源、再卸载、后断根、最后验证**。顺序错了会白干。
> 每一步都写了"为什么"，因为知道原因才知道哪步能跳。

---

## 通用铁律（6 条）

1. **先断网再动手**。多数推广软件有云端复活：检测到本体被删就从服务器重下。拔网线 / 关 WiFi / 开飞行模式。
2. **先关进程再删文件**。文件被占用时删除会失败，且进程会在你删完后 5 秒内重建。
3. **浏览器相关必须先完全退出**（`edge://quit` 或任务管理器确认进程数 0），否则退出时会把标签写回会话文件。
4. **不要手删 `Windows.old`**，走「设置 → 系统 → 存储 → 临时文件 → 删除以前版本的 Windows」。
5. **不要信"一键注册表清理"**。注册表误删的代价是重装系统。
6. **每次只做一类动作，做完重启再看效果**。否则分不清哪步起效，下次不知道该先动哪里。

---

## 场景 S0｜还没装系统（成本最低，收益最大）

### S0-a 用大白菜但想去掉捆绑

1. 打开大白菜制作器 → 左侧「个性设置」→ 右下角「支持我们」。
2. 把「赞助商主页」「绿色软件」等**全部取消勾选**。
3. 弹窗要求密码/解锁码：
   - 老版本：输入 `winbaicai.com`（UEFI 版为 `bigbaicai.com`）。
   - v6.0_2002 之后：点「我要狠心取消」→ 复制弹窗里的**机器码** → 关注公众号发送机器码 → 填入返回的**解锁码**。
     （机器码每次重开窗口都会变，必须与当前弹窗完全一致，区分大小写。）
4. **必须点「保存设置」**，弹「保存成功」才算生效。只取消不保存＝没做。
5. **重新制作一次 U 盘**。已经做好的盘不会自动变干净。

> 注意：这只去掉"装机时自动装软件"，PE 里那些删安全软件、改浏览器设置的模块
> 是否一并消失，厂商没有承诺。想彻底干净，走 S0-b。

### S0-b 换掉工具（推荐）

| 方案 | 说明 |
|---|---|
| 微PE + 官方 ISO + Rufus | 最干净。微PE 本身无推广（但要认准官网，搜索引擎前几条常是仿冒） |
| 优启通（EasyU） | IT 天空出品，带万能驱动，实测无推广软件 |
| 微软官方媒体创建工具 | 只装 Win10/11 当前版本，最简单，但无 PE 工具 |

ISO 校验：下载后对 SHA256，与微软/MSDN 公布值比对。`Get-FileHash .\xxx.iso -Algorithm SHA256`。

### S0-c 已经在用大白菜的盘，想就地净化（进阶）

需要：`FbinstTool`（看 UD 区）、`UltraISO`、`WimTool`、`Dism++`。

1. `FbinstTool` 打开 U 盘 → 导出 `\PE\DBC8x64.ISO` 到硬盘。
2. `UltraISO` 打开该 ISO → 提取其中的 `DBC8x64.WIM`。
3. `WimTool` / `Dism++` 解开 WIM → 定位 `Windows\Packages\`。
4. 删除 `System32.7z`（≈5087 KB）与 `PF.7z`。
   - 依据：社区实测删掉 `System32.7z` 后，PE 里不再出现 `NUML0CK.exe`，装完系统无推广。
5. 重新打包 WIM → 替换回 ISO → 用 FbinstTool 写回 UD 区。
6. **Win2003PE、Win8PE、Win10PE 等多个镜像都要处理**，只改一个不彻底。

> 风险：改坏 WIM 会导致 U 盘无法启动。改前把原 ISO 备份到硬盘。

---

## 场景 S1｜刚装完系统，还没装自己的东西（最佳时机）

这是唯一能"接近彻底"清理的窗口。**顺序不能变**。

### 第 1 步｜断网 + 备份

- 拔网线 / 关 WiFi。
- C 盘空间够就建还原点；空间紧张（< 5 GB）就别建，改为把要留的文件拷到移动硬盘。
- 导出已装软件清单备用：
  ```powershell
  Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*,
                   HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
    Sort-Object InstallDate | Export-Csv "$env:USERPROFILE\Desktop\installed.csv" -NoTypeInformation -Encoding UTF8
  ```

### 第 2 步｜卸载（按安装日期排序）

设置 → 应用 → 安装的应用 → 按「安装日期」排序 → 装机当天那一批批量卸载。

卸载时注意：
- 「保留用户数据 / 保留主页设置 / 推荐安装其他软件」**全部取消**。
- 出现「修复」「升级」按钮说明你点错了，那是挽留界面。
- 卸载完**不要**点"立即重启"之外的任何"优化"。

卸不干净的用 **Geek Uninstaller**（5 MB 单文件、免安装）：右键 → 强制删除 → 自动扫残留目录和注册表。

### 第 3 步｜断根（最容易漏，漏了必复发）

| 位置 | 操作 | 说明 |
|---|---|---|
| `任务管理器 → 启动应用` | 禁用陌生项，看「发布者」列 | 空白/乱码的重点看 |
| `taskschd.msc` | 找动作指向 `AppData`、`Temp`、随机名 exe 的任务 | **先禁用，观察两天再删** |
| `services.msc` | 按「可执行文件路径」排序，找指向不存在目录的 | 停了服务也要看驱动 |
| **Autoruns**（微软 Sysinternals） | 一处看全 Logon/Services/Drivers/Scheduled Tasks/WMI | 未签名项会标色；WMI 页签是重点 |
| `regedit` → `Run`/`RunOnce` | 删前右键导出备份 | `HKCU`、`HKLM`、`WOW6432Node` 三处都要看 |
| 启动文件夹 | `shell:startup` + `shell:common startup` | 空的才正常 |

### 第 4 步｜拆掉部署期载荷

1. 找到 `C:\Windows\<随机名>\`（本机实例：`C:\Windows\Vmaprlfxn\`，内含 10 个 `SUPPORT.IMG*`，450 MB）。
2. 找到 `C:\Windows\Panther\unattend.xml`，看写入时间是否 ≈ 系统安装时间。
3. **在 PE 环境下**（不是已进桌面）把这两项一起删/改名。原因：进桌面后删，`specialize` 阶段可能已经重建过一次。
4. 如果已经是"用了很久"的系统，这两项留着危害有限（启动器早已自删），但 450 MB 值得回收。
   **不建议**在已装好大量软件的系统上删 `unattend.xml`——某些 OEM 机器靠它维护配置。

### 第 5 步｜修浏览器（见 S3）

### 第 6 步｜恢复被改的系统设置

```powershell
# 1) 恢复 UAC（改前先导出备份！）
reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "%USERPROFILE%\Desktop\uac_backup.reg" /y
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name ConsentPromptBehaviorAdmin -Value 5
# 重启生效
```

- `.html` / `http` / `https` 关联：走「设置 → 应用 → 默认应用」，**不要**手改 `UserChoice`（带哈希校验，会被重置）。

### 第 7 步｜验证（见 S6）

---

## 场景 S2｜已经用了很久（保守清理）

不要按 S1 全套做——你机器上有大量自己的软件，激进清理风险高。

**只做这四件**：

1. **卸载明确的推广软件**（设置 → 应用，按名称筛 360/2345/腾讯视频/爱奇艺/酷狗/老黄历/鲁大师/驱动人生/快压）。
2. **修浏览器**（S3 全套）。
3. **清残留目录**（本工具 `RUN_3_Quarantine.cmd`，逐项 YES，移入隔离区而非删除）。
4. **全盘扫描**：火绒全盘 + Windows 安全中心「Microsoft Defender 脱机扫描」。

**不做**：删 `unattend.xml`、改 UAC、动服务/驱动、清注册表大扫除。
理由：这些在长期使用的系统上收益低、风险高。

---

## 场景 S3｜只有浏览器每天弹广告（定点修）

这是最高频的场景，也是"看起来最像中毒、实际最好修"的场景。

### 3.1 先判断是哪一层

| 现象 | 层 | 位置 |
|---|---|---|
| 浏览器设置里"启动时"是灰的、改不了 | ① 策略层 | `Policies\Microsoft\Edge` |
| "启动时"能改，但改完重启又变回推广页 | ② 配置层 | `initial_preferences` |
| 启动设置正常，但每天第一次打开会多出一个标签 | ③ 会话层 | `Sessions\Tabs_*` |
| 弹的是右下角通知条 | ④ 通知层 | `content_settings.exceptions.notifications` |
| 弹的是独立窗口、有标题栏和按钮 | ⑤ 进程层 | 有常驻程序，查启动项/计划任务 |

### 3.2 操作顺序

**第 0 步｜彻底退出浏览器**

```
edge://quit        （Edge）
chrome://quit      （Chrome）
```

然后任务管理器确认 `msedge.exe` / `chrome.exe` 进程数为 **0**。
浏览器的"启动增强 / 后台常驻"会让它假装关掉了。

**第 1 步｜查策略层**

```powershell
foreach ($k in @(
  'HKLM:\SOFTWARE\Policies\Microsoft\Edge','HKCU:\SOFTWARE\Policies\Microsoft\Edge',
  'HKLM:\SOFTWARE\Policies\Google\Chrome','HKCU:\SOFTWARE\Policies\Google\Chrome')) {
  if (Test-Path $k) { $i=Get-Item $k; foreach($n in $i.GetValueNames()){ "$k :: $n = $($i.GetValue($n))" } }
}
```

看到 `HomepageLocation` / `RestoreOnStartup` / `RestoreOnStartupURLs` 指向推广域名 → 删掉这些值
（先导出备份）。删除后浏览器设置项会从灰变可点。

**第 2 步｜查配置层**

```powershell
# Edge 首次运行配置（官方安装不带这个文件）
Get-Item 'C:\Program Files (x86)\Microsoft\Edge\Application\initial_preferences' |
  Select-Object FullName, Length, CreationTime, LastWriteTime
Get-Content 'C:\Program Files (x86)\Microsoft\Edge\Application\initial_preferences' -Raw
```

命中 `homepage` / `restore_on_startup` / `startup_urls` 指向推广域名 → **改名为 `.dbc_bak`**（需管理员）。

> 只改文件内容不够彻底：某些变体会在 Edge 更新时重新生成。改名 + 观察两天最稳。

也检查 `Preferences`：

```powershell
$p = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"
(Get-Content $p -Raw | ConvertFrom-Json).session | ConvertTo-Json -Depth 5
```

**第 3 步｜查会话层（关键，多数教程漏掉）**

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

`Hits > 0` 的文件**移走**（不是删，移到备份目录），Edge 下次启动会重建干净会话。

**第 4 步｜查通知层**

`edge://settings/content/notifications` → 删掉所有不认识的「允许」。
或脚本定位：

```powershell
$p = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"
$j = Get-Content $p -Raw | ConvertFrom-Json
$j.profile.content_settings.exceptions.notifications.PSObject.Properties |
  ForEach-Object { "$($_.Name)  setting=$($_.Value.setting)" }
# setting=1 允许, 2 阻止
```

**第 5 步｜查扩展**

`edge://extensions` → 按「最近添加」排序 → 名字含"导航/加速/主页/搜索/快搜/省心"的一律**移除**（不是停用）。

**第 6 步｜清站点数据**

`edge://settings/content/all` → 搜 `2345.com`、`2354mt` → 删除。

**第 7 步｜验证**

重启 → 第一次开浏览器 → 确认没有多出标签。**连续观察两天**（会话层问题可能隔天才复现）。

---

## 场景 S4｜清了又回来（断根）

如果 S3 做完第二天又复发，说明有东西在写回。按此顺序查：

1. **安全软件的"主页锁定"**：360/2345/腾讯管家都有「浏览器保护 / 主页锁定」。
   它锁定的主页是它自己认为"安全"的那个。关掉它，或把锁定地址改成你要的。
2. **计划任务**：`taskschd.msc`，动作列里带 `http` 或指向 `AppData` 的，禁用。
3. **WMI 永久订阅**：Autoruns → WMI 页签。`CommandLineEventConsumer` 有内容就是有问题。
4. **浏览器快捷方式尾巴**：桌面 + 任务栏 + 开始菜单三处的 `.lnk`，属性 → 目标，末尾多出的网址删掉。
5. **hosts**：`C:\Windows\System32\drivers\etc\hosts`，只留 `127.0.0.1 localhost`。
6. **多用户**：`C:\Users\` 下是否有第二个账户带着同样的劫持配置（`netplwiz` 查看）。

---

## 场景 S5｜清理后仍不稳（回滚）

所有工具动作都可回滚：

| 改了什么 | 怎么恢复 |
|---|---|
| `initial_preferences` 改名为 `.dbc_bak` | 把 `.dbc_bak` 改回原名 |
| 会话 / 缓存文件 | 从 `Quarantine_*\Sessions`、`Quarantine_*\CodeCache` 移回原目录 |
| 启动项值 | 双击 `Backup_*\Run_*.reg` 导入 |
| 计划任务被禁用 | `Enable-ScheduledTask -TaskName X -TaskPath Y`，或用 `Backup_*\Task_*.xml` 重注册 |
| hosts | 用 `Backup_*\hosts.dbc_bak` 覆盖回去 |
| 推广目录 | 从 `Quarantine_*\Promo\` 移回原路径 |

---

## 场景 S6｜验证是否清干净（五查）

1. **查来源**：`HKLM\SOFTWARE\DaBaiCai` 还在不在（在＝这台机器确实是大白菜装的，属正常留证）。
2. **查载荷**：`C:\Windows\` 下还有没有 8–16 位随机字母目录，里面有 `.img/.ext`？
3. **查落地**：`C:\Program Files`、`Program Files (x86)`、`ProgramData`、`%LOCALAPPDATA%`、`%APPDATA%`
   还有没有 `360`、`2345Soft` 目录？
4. **查复活**：`taskschd.msc` 是否还有指向 AppData/Temp/随机名 exe 的任务；Autoruns WMI 页签是否干净。
5. **查浏览器**：连续两天，每天第一次开浏览器，看是否多出标签 / 首页是否被改。

五查全过 ≈ 干净。再跑一次 `RUN_1_Scan.cmd`，`Safe` 应为 0（`Review` 里剩下的多为访问痕迹）。

---

## 附：常用命令速查

```powershell
# 按安装日期看软件（含日期）
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*,
                 HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Where-Object DisplayName |
  Select-Object DisplayName, Publisher, InstallDate |
  Sort-Object InstallDate -Descending | Format-Table -AutoSize

# 看浏览器进程数（修之前必须为 0）
(Get-Process msedge,chrome -ErrorAction SilentlyContinue | Group-Object Name |
  Select-Object Name,Count) | Format-Table

# 看系统安装时间
(Get-CimInstance Win32_OperatingSystem).InstallDate

# 扫某个目录里含 2345 的小文件（快速定位缓存/配置残留）
$lat=[Text.Encoding]::GetEncoding(28591)
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data" -Recurse -File -EA 0 |
  Where-Object Length -lt 8MB | ForEach-Object {
    $s=$lat.GetString([IO.File]::ReadAllBytes($_.FullName))
    if ($s -match '2345\.com|2354mt') { $_.FullName }
  }
```
