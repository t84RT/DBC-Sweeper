# IOC 特征库

> 用途：人工核对时逐条比对；也可直接改 `DBC_Sweeper.ps1` 里的 `$script:IOC`，或改输出目录下的 `ioc_db.json`。
> 标记：**强** = 命中基本可判定；**中** = 需结合上下文；**弱** = 仅作参考线索。

---

## A｜源头

| 类型 | 值 | 强度 |
|---|---|---|
| 注册表 | `HKLM\SOFTWARE\DaBaiCai`（含 `Version`/`FileName`/`UniqueCode`/`Soft`） | 强 |
| 注册表 | `HKLM\SOFTWARE\WOW6432Node\DaBaiCai` | 强 |
| 渠道号键名 | `2345explorer`、`360se`、`360safe`、`EdgeSetup`、`Chrome`、`DriveTheLife`、`Taobao`、`chaojituzi` | 强 |
| 安装目录 | `%ProgramFiles%\DaBaiCai`、`%ProgramFiles(x86)%\DaBaiCai`、`%LOCALAPPDATA%\DaBaiCai` | 中 |
| 硬盘目录 | `D:\大白菜PE`、`D:\DBC`、`D:\PETools` | 中 |
| 品牌词 | `DaBaiCai`、`大白菜`、`winbaicai`、`dabaicai` | 中 |
| U 盘文件 | `\DBC8x64.ISO`、`\DBC8x64.WIM`、`\DBC32.ISO`、`\PE\`、`\PETools\`、`\DBCMenu`、`grldr`、`fb.cfg` | 强（配合 U 盘） |
| PE 内部 | `X:\windows\Packages\System32.7z`（≈5087 KB）、`X:\windows\Packages\PF.7z` | 强（PE 内） |
| UD 区 | `\IUQD\IMGS\Important.IMG`（同类样本） | 中 |

## B｜部署期

| 类型 | 值 | 强度 |
|---|---|---|
| 文件 | `C:\Windows\Panther\unattend.xml`（注意文件名常为 `unattend.xml`） | 中（OEM 也用） |
| 内容标记 | `RunSynchronousCommand`、`FirstLogonCommands` | 中 |
| 内容标记 | `ConsentPromptBehaviorAdmin` / `EnableLUA` | 中 |
| 内容标记 | `net user Administrator /active:yes`、`Administrator ploc` | 强 |
| 目录 | `C:\Windows\<8–16 位首字母大写字母串>\` | 中 |
| 载荷 | 同目录下 `.img`、`.img1`…`.img9`、`.ext`、`SUPPORT.IMG*` | 强 |
| 程序 | `NUML0CK.EXE`（AutoIt 编译，混淆） | 强 |
| 程序 | `C:\Uexqgrydo\Wmdnbc.exe`（公开样本路径） | 强（若存在） |
| 注册表 | `HKLM\...\Policies\System\ConsentPromptBehaviorAdmin = 0` | 中（可能是自己关的） |
| 注册表 | `EnableLUA = 0` | 中 |

## C｜落地

### 目录（**强**，用显式名，不要用 `*360*` / `*2345*` 泛匹配）

```
%ProgramFiles%\360            %ProgramFiles(x86)%\360
%ProgramData%\360sd           %LOCALAPPDATA%\360Chrome
%ProgramFiles%\2345Soft\2345PCSafe
%ProgramFiles(x86)%\2345Soft\2345PCSafe
%ProgramData%\2345Soft        %LOCALAPPDATA%\2345
%APPDATA%\2345Soft            %LOCALAPPDATA%\2345Soft
%ProgramFiles%\Tencent\QQPCMgr
%ProgramFiles%\kuwo           %ProgramFiles%\iqiyi
```

### 注册表

| 键 | 强度 |
|---|---|
| `HKCU\Software\2345.com` | 强 |
| `HKCU\Software\2345`、`HKLM\SOFTWARE\2345`、`HKLM\SOFTWARE\WOW6432Node\2345` | 强 |
| `HKLM\SOFTWARE\360Safe`、`HKLM\SOFTWARE\WOW6432Node\360`、`HKLM\SOFTWARE\360` | 强 |

### 服务 / 驱动

| 名称 | 说明 |
|---|---|
| `2345PCSafe` | 2345 安全卫士服务 |
| `360Safe` / `360AntiHacker.sys` | 360 自保护驱动 |
| `2345BdPcSafe.sys` | 2345 驱动 |
| `TAOKernel.sys`、`TAOAccelerator.sys`、`TSDefenseB.sys`、`TAOFltMgr.sys` | 腾讯电脑管家驱动 |
| `bd001.sys` | 百度卫士驱动 |
| `kisknl.sys` | 金山毒霸驱动 |

> 驱动级残留**不要直接删 `.sys`**。先在设备管理器「显示隐藏的设备」里卸载对应设备，
> 再处理服务项，最后才谈文件。

### 进程 / 文件名

```
2345Update.exe  2345Svc.exe  2345Explorer.exe  2345PCSafe.exe
360Safe.exe     360se.exe    360sd.exe         360Chrome.exe
QQPCMgr.exe     kuwo.exe     iqiyi.exe
Ludashi.exe     DriverGenius.exe  DrvInst.exe   kuaizip.exe
NUML0CK.exe
```

### 文件关联 / 收藏夹

| 项 | 值 | 说明 |
|---|---|---|
| `.html` UserChoice | `360seURL` | 走「默认应用」改，别手改注册表（有哈希） |
| `http/https` UserChoice | `360seHTML` / `360seURL` | 同上 |
| 收藏夹 | 含 `dabaicai` / `winbaicai` / `2345` / `hao123` 的 `.url` | PE 预置收藏夹，**强** |

## D｜浏览器

| 类型 | 值 | 强度 |
|---|---|---|
| 文件 | `<EdgeInstall>\initial_preferences`（官方安装不带） | 强 |
| 文件 | `<ChromeInstall>\initial_preferences` / `master_preferences` | 中（Chrome 可能自带模板） |
| JSON | `homepage` 指向推广域名 | 强 |
| JSON | `session.restore_on_startup = 4` + `session.startup_urls` 非空 | 强 |
| JSON | `profile.content_settings.exceptions.notifications` 里有推广站点且 `setting=1` | 强 |
| JSON | `extensions.settings` 里 `manifest.homepage_url` 含推广域名 | 中 |
| 文件 | `User Data\<Profile>\Sessions\Tabs_*` / `Session_*` 含推广 URL | 强 |
| 目录 | `User Data\<Profile>\Code Cache\js\*` 含推广域名 | 中（可能只是访问记录） |
| 注册表 | `Policies\Microsoft\Edge\HomepageLocation`、`RestoreOnStartup`、`RestoreOnStartupURLs` | 强（导致灰化） |
| 注册表 | 同上，`Google\Chrome` 路径 | 强 |

**不要动**：`Secure Preferences`（含 `startup_urls_edge_enclave` 之类 MAC 保护字段）。
手改会导致校验失败，浏览器会重置整个配置或报"配置损坏"。

### 推广域名

```
2345.com        2354mt.com      hao123.com      hao.360.cn
999.com         2345.cn         wangpai.2345.cn
dabaicai.com    dabaicai.cn     winbaicai.com
laomaotao.net   laomaotao.com   diannaodian.com
by.<4–8位字母数字>.com/.cn/.net     ← 变体跳转域名，例如 by.2354mt.com
```

`?4108`、`?41308`、`?kwoxiang` 这类 query 是**渠道号**，不是用户参数。

## E｜残留

| 位置 | 说明 | 处理 |
|---|---|---|
| `C:\Windows.old`、`$Windows.~BT`、`$Windows.~WS` | 旧系统残留，常 10–30 GB | 设置 → 存储 → 临时文件 → 删除以前版本的 Windows |
| `C:\Drivers`、`D:\万能驱动` | PE 带的驱动包 | 确认后移到移动硬盘 |
| `<随机名目录>` | 数百 MB 加密分包 | 隔离，确认后清空 |
| `D:\Win11_*.iso` | 装机源镜像，常 5–8 GB | 确认不需要回滚后删 |

---

## 白名单（不判为推广，最多 Review）

```
Microsoft  Windows  WindowsApps  WinSxS  System32  SysWOW64
Python  PlatformIO  Arduino  Code(VS Code)  Git  nodejs  Java
CH340  CP210x  FTDI  Silicon Labs  Espressif
Realtek  Intel  NVIDIA  AMD
```

理由：这些是开发/嵌入式环境的常见组件，误删代价远大于收益。
本机实测中被正确保护的有：PlatformIO、Arduino、CH340 驱动、Python、VS Code。

---

## 误报来源（真实踩过的）

| 现象 | 原因 | 修法 |
|---|---|---|
| `WXWork`、`AweSun`、`Everything` 被判"随机名启动器" | PowerShell `-match` **默认不区分大小写**，`[A-Z][a-z]{5,15}` 退化成"任意字母" | 用 `-cmatch`，并限定 `C:\Windows\` 前缀 |
| `DiagTrack`、`BrowserCore`、`servicing` 被判可疑目录 | 随机名启发式过宽 | 加可读词白名单 + 要求目录内含 payload |
| `desktop.ini` 被列为启动项 | 启动文件夹里的隐藏系统文件 | 显式跳过 |
| Visual C++ 运行库刷屏 | 安装日期窗口过滤太宽 | 按发布者/名称过滤大厂与运行库 |
| `.NET NGEN` 任务被视为 IOC | 把通用 GUID 当特征 | 不收录该 GUID |
