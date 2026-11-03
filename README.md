# Claude Desktop 运行时汉化

适用于 Windows 版 Claude Desktop 的第三方中文界面脚本。双击入口，将当前窗口中的界面文案替换为中文；关闭或完整刷新页面后，需要重新运行。

**当前版本：v0.4.0。非 Anthropic 官方项目。**

## 下载与使用

1. 在本仓库右侧的 **Releases** 中下载 `Claude-runtime-zh-v0.4.0.zip`，完整解压到有写入权限的普通文件夹。
2. 打开 Claude Desktop。首次使用需由本人启用 Claude 的 **Developer Mode**；开发者工具若显示粘贴安全提示，请本人阅读并处理。
3. 双击 **一键启动汉化.cmd**。执行期间暂停键鼠及剪贴板操作，避免焦点或复制内容被改变。
4. 等待出现 `SUCCESS`，确认 Claude 界面变为中文。需要恢复时，双击 **一键恢复英文.cmd**。

主界面通常需要约 10–25 秒；同时处理推理配置窗口可能需要约 20–50 秒，具体取决于机器与窗口状态。按 **Esc** 可中止。

整个解压文件夹可以移动或改名；保留内部文件结构，移动后重新创建已有快捷方式。启动器会在该文件夹的上一级创建 `logs/claude-zh-owned-drafts`，只记录请求编号和载荷哈希，因此上一级目录也需要可写。

## 支持范围

- 支持 Windows 桌面版的当前主界面，以及已经打开的第三方推理配置窗口。配置窗口后来才打开时，再运行同一个入口。
- 本地开发验证环境为 Windows、Windows PowerShell 5.1 和 Claude Desktop **4.4212.0.0**；其他版本尚未逐一验证。macOS、Linux 不在启动器支持范围内。
- 不修改 Claude 的 EXE 或 ASAR 文件，不安装开机任务或常驻服务。不修改密钥、网关、模型和代理配置。
- 页面脚本不主动发送网络请求；Claude 本身的联网行为不受此说明影响。
- 尽量跳过输入框、代码、常见会话正文、文件预览，以及已识别的自定义项目名、模型名和动态路径。页面结构变化后，这些保护需要重新验证。
- 原生 Windows/Electron 菜单可能仍是英文；未收录文案、新版页面结构可能漏译。

## 常见问题

**重启后又变成英文？**

这是运行时汉化。每次 Claude 重启或页面完整刷新后，重新双击入口即可。

**只弹出开发者工具，界面没有变中文？**

查看黑色启动窗口中的 `STOPPED:` 信息。运行时暂停键鼠和复制操作；若提示无法聚焦，点击目标 Claude 窗口后重试。控制台中的黄色警告本身不代表汉化失败。

**提示存在未知的未完成命令？**

本人检查控制台，处理该命令后再运行。启动器不会清空无法识别的草稿；旧汉化草稿仅在其全文哈希与本机记录匹配时才会被替换。移动目录后，旧记录不会自动迁移，遇到旧草稿时也可能需要本人处理。

**出现粘贴安全提示？**

请先检查本项目代码，并由本人决定如何处理提示。脚本不会代替你关闭或绕过这项保护。

**恢复英文后还有部分中文？**

先尝试重新运行恢复入口；完整刷新或重启 Claude 会移除本项目的运行时脚本。

**剪贴板里出现一大段代码？**

启动器需要暂用剪贴板，结束后可能留下汉化代码。不会自动覆盖你后来复制的内容。

手动备用入口为 `copy-script.cmd` 与 `restore.cmd`；配置专用旧入口放在 `兼容入口`，日常使用统一入口即可。

## 开发与验证

运行启动器不需要额外安装 Python 或 Node.js；以下工具只用于开发测试。

```powershell
node --check claude-zh.js
node test-safety.cjs
python -m unittest test_dictionary.py
powershell.exe -NoProfile -MTA -ExecutionPolicy Bypass -File test-unified-launcher.ps1
powershell.exe -NoProfile -MTA -ExecutionPolicy Bypass -File test-launcher-reliability.ps1
```

Windows 安装 Edge 后，可运行独立 DOM 测试：

```powershell
python verify.py
python verify.py --page configuration-preview.html --report configuration-verification.json
python verify.py --page confirmation-preview.html --report confirmation-verification.json
python verify.py --page optimization-preview.html --report optimization-verification.json
```

这些测试使用独立本地测试页，不会对真实 Claude 窗口执行授权、删除或发送消息。真实窗口兼容性仍需另行验证。

词库重建入口：

```powershell
python build_dictionary.py --source "path/to/claude-desktop-zh-cn-main.zip" --resources "path/to/Claude/app/resources"
```

构建时只读输入资源，写入本项目目录。生成的来源报告可能含本机绝对路径，公开提交前请先移除本机路径。

## 来源与许可

翻译数据参考 [javaht/claude-desktop-zh-cn](https://github.com/javaht/claude-desktop-zh-cn)，与对应版本的英文资源匹配生成。来源文件哈希见 `dictionary-provenance.json`，保留上游 MIT 许可于 `UPSTREAM-LICENSE.txt`。

本项目采用 [MIT License](LICENSE)。仓库不包含 Claude 安装文件。Claude 及相关商标属于其各自所有者。

反馈问题时请提供 Claude 版本、脚本版本和 `STOPPED:` 报错；截图前遮住账号、密钥、聊天正文等私人信息。
