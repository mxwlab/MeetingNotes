# MeetingNotes 菜单栏一键安装验收报告

日期：2026-08-12  
分支：`feat/installable-packaging`

## 结论

菜单栏 App 已接入 Release zip 的一键安装、升级、重装与卸载路径。自动化门禁与本机真实长会议处理均通过；可以进入合并/发布准备，但本报告不授权合并 `main` 或发布 Release。

## 已通过

- bootstrap 从 7 步扩展为 8 步，第 7 步安装菜单栏 App，第 8 步启用 AirDrop。
- `provision_menubar.sh` 创建独立 `venv-ui`、安装 UI 依赖、用 py2app 构建独立 `MeetingNotes.app`、注册登录自启。
- 菜单栏 LaunchAgent 使用实际安装目录，不含开发机硬编码路径；首次标签释放延迟可重试，二次安装幂等。
- Release zip 白名单包含 UI 源码、UI 依赖、构建脚本与菜单栏 LaunchAgent 模板；zip 可复现、SHA 校验通过、macOS `ditto` 解压后可执行权限保留。
- 中文和空格路径下的 zip→解压→程序安顿→8 步 bootstrap 编排通过。
- 旧安装升级保留 DeepSeek Key、Obsidian 路径、inbox/output/done，并新增菜单栏。
- 普通卸载移除处理服务、菜单栏自启、AirDrop Folder Action 和桌面入口，保留用户数据、配置及运行时。
- `--remove-runtime` 额外删除 `venv-ui/build/dist` 等可重建内容，仍保留用户数据和配置。
- AirDrop Folder Action 已从 Standard Additions shell 命令迁移到 Foundation/NSTask，AppleScript 编译通过；`0059` 音频进入 inbox，`0083` 浏览器下载保留。
- 当前正式服务安装器改动后短录音烟测通过；此前同日下午 71 分 41 秒长会议 E2E 在 7 分 50 秒内完成，菜单栏状态 0→99%→生成→空闲，三产物与 Obsidian 正常。
- Python 测试 30 个通过；全部 shell 测试通过。

## 测试边界

- `/private/tmp` 隔离安装使用独立 HOME/中文空格安装目录；为避免抢占当前真实服务，launchd/Folder Action 的全局注册边界在 orchestration 测试中模拟。
- 菜单栏 py2app 构建在独立测试中真实执行，并覆盖中文空格路径、plist 内容、首次 bootstrap 重试和幂等重跑。
- 约 3 GB Qwen 模型与 Python/ffmpeg 冷下载路径由既有专项测试与本机缓存验证覆盖，本轮没有从公网重复下载全部大件。

## 发布前仍需

- 补齐新手教程中标记的真实截图：下载/解压、右键打开、Key 弹窗、8 步安装、桌面入口与菜单栏状态。
- 在第二台干净 Apple Silicon Mac 上做无缓存冷下载，验证 pip/PyPI、Qwen 模型和 Gatekeeper 首次体验。
- 明确版本号与 Release notes；随后再决定是否合并 `main` 和发布新 prerelease。

## 非阻塞说明

- 沙箱运行 `test_watch_downloads_wait_stable.sh` 时打印 `nice(5) failed: operation not permitted`，两种文件稳定场景仍 PASS；这是测试环境不允许调整优先级，不影响产品逻辑。
