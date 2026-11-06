# FAQ 与排障

## 判断类

**Q：我怎么知道自己这台是不是大白菜装的？**
看四处，命中两条即可：`HKLM\SOFTWARE\DaBaiCai` 存在；`C:\Windows\Panther\unattend.xml` 写入时间≈装机时间且含 `RunSynchronous`；`C:\Windows\` 下有随机字母目录装 `.img/.ext`；装机当天集中出现 360/2345 系软件。跑 `RUN_1_Scan.cmd` 会自动给结论。

**Q：用的是微软原版 ISO，为什么还有推广？**
因为脏的是 PE 不是 ISO。ISO 被 PE 里的装机工具释放到 C 盘，推广是在这之后由 PE 侧注入的。

**Q：`HKLM\SOFTWARE\DaBaiCai` 删掉是不是就好了？**
不是。它只是渠道记账，删了不影响任何已装的软件，反而丢了溯源证据。建议保留。

**Q：报告里 Safe 是 0，但我还是被弹广告？**
先分清弹的是什么：右下角通知条 → 浏览器站点通知权限；独立窗口 → 有常驻进程，查启动项/计划任务/Autoruns WMI；浏览器内新标签 → 会话层。这三类都不一定命中"推广软件"特征。

**Q：`Review` 里那些是我自己装的软件，要处理吗？**
不用。Review 只是"装机时间窗口内出现的、发布者不是大厂的软件"，供你核对。确认是自己装的就忽略。

## 操作类

**Q：为什么必须先完全退出浏览器？**
浏览器有后台常驻（启动增强 / `--win-session-start`）。它退出时会把当前标签写回 `Sessions\Tabs_*`，你刚清理的文件会被覆盖回去。`edge://quit` 后要在任务管理器确认 `msedge.exe` 数量为 0。

**Q：改了"启动时"设置，第二天又变回推广页？**
三层劫持：策略层（`Policies\...\Edge`）> 配置层（`initial_preferences`）> 会话层（`Sessions\Tabs_*`）。只改界面设置动的是第 2 层的用户可见部分，前两层还在。

**Q：`edge://settings` 里"启动时"是灰的，点不了？**
策略层被写了 `RestoreOnStartup` / `HomepageLocation`。删掉 `Policies\Microsoft\Edge` 下对应的值（先导出备份），重启浏览器。

**Q：为什么工具不帮我删 `C:\Windows\Vmaprlfxn`？**
在系统目录、且可能是 OEM 部署配置的残留。工具只报告；要动请用 `RUN_3_Quarantine.cmd`（移入隔离区），或进 PE 手动处理。

**Q：`-Quarantine` 之后 C 盘没变大？**
隔离是 `Move-Item`，文件还在同一块盘上。要你确认无误后**手动清空** `Quarantine_*` 目录才释放空间。

**Q：能直接删 `Windows.old` 吗？**
不要手删。走「设置 → 系统 → 存储 → 临时文件 → 删除以前版本的 Windows」。手删常留下权限死结，且无法回滚旧系统。

**Q：UAC 被关了，怎么恢复？**
`EnableLUA=1`、`ConsentPromptBehaviorAdmin=5`，改前导出 `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`。改完重启。

**Q：`.html` 关联变成 `360seURL`，改注册表改不动？**
`UserChoice` 带哈希校验，手改会被系统重置。走「设置 → 应用 → 默认应用」。

**Q：我清完想反悔，怎么恢复？**
见 `04-tool-reference.md` 第 7 节，或 `03-manual-guide.md` 场景 S5。所有东西都在 `Backup_*` / `Quarantine_*` 里。

## 工具类

**Q：为什么写模式说"需要管理员"？我明明是管理员账户？**
UAC 会过滤管理员令牌（`FilterAdministratorToken`）。右键 `.cmd` → 以管理员身份运行，或确认 `ConsentPromptBehaviorAdmin` 允许静默提权。

**Q：能从计划任务/自动化里调 `-Fix` 吗？**
不能，设计如此。非交互会话直接 `exit 1`。清理必须人工逐项确认。

**Q：脚本执行报"无法加载文件，因为在此系统上禁止运行脚本"？**
`ExecutionPolicy` 是 `Restricted`。用 `.cmd` 启动器（已带 `-ExecutionPolicy Bypass`），或手动加该参数。

**Q：输出中文乱码？**
`.cmd` 已 `chcp 65001`。直接跑 `.ps1` 时先执行 `chcp 65001`，或用 Windows Terminal。

**Q：报告里的路径太长，表格挤在一起？**
`report.html` 用 `word-break:break-all`，浏览器窗口拉宽即可；手机上看会自动折行。

## 效果类

**Q：清完还要做什么？**
1) 重开浏览器确认没多出标签；2) 连续观察两天；3) 重跑 `RUN_1_Scan.cmd`，`Safe` 应为 0；4) 治本——重做纯净启动盘或换微PE。

**Q：会不会下次装系统又中？**
用同一支 U 盘就会。除非按 S0 取消赞助商后**重新制作**，或换工具。

**Q：装完系统后多久内清理最有效？**
越早越好。刚装完、还没装自己软件的窗口期是唯一能"接近彻底"的时机。用了半年再清，只能保守处理。

**Q：清理会不会影响我的开发环境（PlatformIO / Arduino / CH340）？**
工具白名单保护这些。写模式只动浏览器配置、推广启动项、推广计划任务、被追加网址的快捷方式、hosts 里的推广行、推广目录——都不涉及开发工具。
