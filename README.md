# Antimatter Dimensions — White Screen Recovery

为 Steam Windows 版《反物质维度》增加 **F5 页面重载快捷键**，并记录渲染进程异常，帮助在白屏后尝试恢复游戏。

**v1.0.0 · 预览版**。已实测普通页面重载；真实白屏后的恢复能力仍待更多验证。此项目尚未定位或修复白屏根因，不能保证所有白屏都能恢复。

## 下载

前往 [Releases](https://github.com/LDlornd/AD-WhiteScreen-Recovery/releases)，下载 `AD-WhiteScreen-Recovery-v1.0.0.zip`。解压整个压缩包后使用；没有必要安装 Node.js 或 Python。

## 已验证环境

| 项目 | 版本或范围 |
| --- | --- |
| 平台 | Steam Windows 版 |
| 游戏版本 | 11.5，Steam Build ID 16370635 |
| Electron | 10.4.7 |
| 汉化 | Smirk1921/AD-Zh-CN-Patch 0.3.2 |
| 长按辅助 | Smirk1921/AD-HoldKeys-Mod 1.3.0 |

安装器要求游戏内部版本为 11.5，并校验预期的 `main.js` 结构。其他 Mod 组合、macOS 和其他游戏版本尚未验证。

## 安装与使用

1. 在游戏中保存进度，并导出一份存档备份。
2. **完全退出游戏**。安装后需重新打开一次，新的主进程代码才能加载。
3. 解压下载的安装包，运行 `Install-Recovery.cmd`。如果提示没有游戏目录的写入权限，以管理员身份运行该文件。
4. 从 Steam 正常启动游戏。
5. 游戏窗口在前台时，按 **F5**，或备用快捷键 **Ctrl+Alt+R**。

默认游戏目录为 `C:\Program Files (x86)\Steam\steamapps\common\Antimatter Dimensions`。安装在其他位置时，在补丁目录打开 PowerShell，指定实际路径：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Recovery.ps1 -Action Install -GameRoot "D:\SteamLibrary\steamapps\common\Antimatter Dimensions"
```

快捷键首先尝试重新加载页面；若 8 秒后仍未完成加载，会尝试重建游戏的渲染进程一次。窗口和游戏主进程保留。窗口已被 Electron 判定为无响应时，会直接尝试重建渲染进程。

### 使用边界

- 重载会读取最近保存的进度，**未保存的进度可能丢失**。
- 主进程卡死、驱动故障或系统资源耗尽时，快捷键也可能无效。
- 快捷键仅在游戏窗口有焦点时注册。某个快捷键被其他软件占用时，可尝试另一个。
- 汉化和长按辅助会随页面重新加载。如果已启用恢复长按，辅助可能按原设置恢复运行。
- 不会在白屏发生时自动重载；由玩家按快捷键触发。

## 检查与卸载

- `Check-Recovery.cmd`：只读检查安装状态和归档哈希。
- 完全退出游戏后运行 `Uninstall-Recovery.cmd`：校验哈希，恢复安装前的整个游戏归档。
- 自定义游戏目录同样可通过 `Manage-Recovery.ps1 -Action Check` 或 `-Action Uninstall` 的 `-GameRoot` 参数指定。

安装前原件保存在：

```text
%LOCALAPPDATA%\AntimatterDimensionsWhiteScreenRecovery\original-app.asar
```

卸载会恢复安装前已有的汉化和长按辅助。如果之后更新了游戏或其他 Mod，卸载器会拒绝覆盖不匹配的文件。**更新游戏或其他 Mod 前，请先卸载本补丁**。同一 Windows 用户的默认状态目录只管理一份游戏安装。

## 诊断记录

```text
%APPDATA%\Antimatter Dimensions\white-screen-recovery\recovery.log
```

日志包含恢复动作、页面加载、窗口无响应、渲染进程退出原因及 Electron 提供的进程内存统计；不记录存档正文，不联网。日志达到约 1 MB 后停止追加。

反馈问题时，请说明游戏版本、Mod 组合、触发场景，以及 F5 是否有效。分享诊断日志前请自行检查内容。

## 修改范围

安装器只在 `resources/app.asar` 中：

- 给 `main.js` 增加一处恢复模块挂钩。
- 添加 `ad-white-screen-recovery.js`。

发布包不包含游戏本体、汉化词库、长按辅助源码、存档或本机备份。安装器先备份原件，再通过临时文件替换归档；卸载只接受与本补丁安装结果哈希一致的归档。

## 验证与开发

```sh
npm test
```

无需安装 npm 依赖。测试覆盖快捷键焦点管理、重复按键限制、正常重载、超时回退、无响应恢复、日志和退出清理。

还可对安装前后的两个归档运行字节级对照：

```sh
node tests/recovery.test.cjs original-app.asar patched-app.asar
```

安装器在游戏副本上完成了安装、检查、卸载和哈希还原验证；实机已验证 F5 可在原窗口重新加载游戏。详情见 [validation.txt](validation.txt)。

## 致谢与许可

- 游戏：[IvarK/AntimatterDimensionsSourceCode](https://github.com/IvarK/AntimatterDimensionsSourceCode)
- 汉化：[Smirk1921/AD-Zh-CN-Patch](https://github.com/Smirk1921/AD-Zh-CN-Patch)
- 长按辅助：[Smirk1921/AD-HoldKeys-Mod](https://github.com/Smirk1921/AD-HoldKeys-Mod)
- 恢复方案使用 Electron 的 [webContents 重载及渲染进程恢复 API](https://www.electronjs.org/docs/latest/api/web-contents#contentsforcefullycrashrenderer)。

这是独立的非官方社区补丁，与游戏及上述 Mod 的作者没有官方隶属关系。代码在 AI 助手协作下编写。本仓库新增代码按 [MIT License](LICENSE) 发布，各上游项目保留其原有许可。

## English

An unofficial recovery add-on for Antimatter Dimensions on Steam Windows 11.5. Press **F5** while the game window is focused to reload its page without closing the window. A stalled reload can fall back to recreating the renderer after 8 seconds.

This is a preview release. Normal reload was verified on a real installation with the Chinese patch 0.3.2 and HoldKeys 1.3.0; recovery from an actual white-screen incident remains unverified. It does not fix the underlying cause. Reloading restores the latest saved progress and may lose unsaved progress.
