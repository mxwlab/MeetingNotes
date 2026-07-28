# MeetingNotes Mac 双击安装（A1.5）设计

日期：2026-07-28
分支：`feat/installable-packaging`（后续实现另开分支）
状态：设计已确认，进入实现计划

## 背景与目标

**北极星**：让别人更方便地用上 MeetingNotes。

讨论中确认了两条硬约束，把方案挤到唯一可行角落：

1. **不接受托管服务**——录音不能经制作者的服务器（保留「本地优先、录音只在用户本机、仅文字发给 LLM」的隐私模型）。
2. 想覆盖 Windows，但现引擎（MLX Whisper + FluidAudio）**仅 Apple Silicon**，Windows 本地无法运行。

「不托管 + Windows」只能靠**跨平台本地引擎重写**同时满足，属几周量级重投入。用户在此阶段（自用 + 3–5 朋友内测，暂不商业化）**选择放弃 Windows（方案 A）**，把 **Mac 本地安装做到极致傻瓜**；Windows 留作以后独立阶段。

「网页插件 / wechat-cc 插件」在上述约束下均不成立（都需制作者托管处理或仍需本地引擎），故不采用。

## 方案：A1.5 — 小 zip + 双击 `.command`，首次自动置备

一个非技术 Mac 用户的目标体验：

1. 下载一个小 zip（`MeetingNotes-mac.zip`，数 MB 级——因 B2 下重物均首次下载，包内基本只有启动器与脚本）。**不用 git、不用终端。**
2. 解压，双击 `开始使用.command`。
3. 因未签名，**首次需右键→打开**确认一次（下载页配图说明，唯一的「技术味」操作）。
4. 终端窗口出现，显示**友好中文进度**；技术噪音重定向到日志。
5. 弹**原生对话框**填 DeepSeek key（唯一需要人的一步）：自动打开官网、当场验证 key 有效。
6. 自动下载运行环境与 3GB 语音模型（一次性，约 5–10 分钟）。
7. 完成对话框提示：把录音拖到桌面「MeetingNotes 录音」图标，或 AirDrop 到本机。
8. 日常：拖录音 / AirDrop → 自动出纪要，之后无需再碰设置。

与现状对比：从「装 Homebrew + Xcode + git clone + 敲命令 + 等编译」压缩为「解压 → 双击 → 右键打开一次 → 填 key → 等一次下载」。**隐私模型不变**（录音仅本地处理，只有文字发 LLM）。

### 已确认的设计决定

| 主题 | 决定 |
|---|---|
| 分发形式 | 小 zip（重物首次下载，B2），非 git clone |
| 安装位置 | 首次**安顿到 `~/MeetingNotes`**（防误删）；桌面放替身「MeetingNotes 录音」 |
| 面向朋友的文件夹名 | 中文「录音 / 纪要」 |
| Python | **首次自动下载独立 Python（python-build-standalone）+ 装依赖**，绕开可重定位难题 |
| ffmpeg | 首次下载**静态 ffmpeg（arm64）**，替代 Homebrew；许可证补入 `NOTICE` |
| FluidAudio | 用 **GitHub Release 上的预编译二进制**（已编译、仅依赖系统库、可移植）；老系统跑不起时回退源码编译 |
| 模型 | 首次下载，沿用镜像→官方源自动回退 |
| 填 key | **原生对话框** + 自动开官网 + 当场验证；不在终端里敲 |
| 进度感知 | 终端只显示友好中文进度，噪音进日志；终端窗口会出现（接受）；右键打开一次（接受） |
| 签名 | **内测不签名**；`.app` + 公证（$99/年）留作 A2 后续 |
| LLM 服务商 | **默认 DeepSeek**（国内朋友摩擦最小）；换服务商（base_url/model/key）作**隐藏高级选项**，不摆在朋友面前 |
| 自动更新 | 不做；改代码后重发 Release，朋友重新下载 |

## 架构与组件

复用现有本地引擎与脚本，仅新增「双击启动 + 首次置备编排 + 环境自带化」外壳。

**新增**：
- `开始使用.command` — 极薄启动器（可双击）。设定友好输出模式，调用 `bootstrap_mac.sh`。
- `scripts/bootstrap_mac.sh` — 首次置备编排器，**幂等**：安顿到 `~/MeetingNotes` → 取 Python → 取 ffmpeg → 复用 provision 脚本置备 FluidAudio/模型 → 弹框填并验证 key → 生成 launchd + Folder Action → 建桌面替身 → 完成提示。噪音入 `logs/`，终端只出友好进度。
- `scripts/fetch_python.sh` — 下载并就位固定版本独立 Python，装 `requirements.txt`（arm64 wheel，无需编译）。
- `scripts/fetch_ffmpeg.sh` — 下载并就位静态 ffmpeg 至 `~/MeetingNotes/bin/`。
- key 录入助手 — `osascript display dialog`（可内联在 bootstrap）。
- `build_release.sh` — 组装 `MeetingNotes-mac.zip`（启动器 + 脚本 + 资源），供 GitHub Release 发布。

**复用（基本不动）**：`scripts/provision_fluidaudio.sh`（走预编译 URL 路径）、`scripts/provision_models.sh`、`scripts/gen_launchd.sh`、`scripts/attach_folder_action.sh`、`watch_inbox.sh`、`watch_downloads.sh`、`process.py`。

**关键接线**：
- 所有脚本通过 `MEETINGNOTES_PYTHON` 指向自带 Python；ffmpeg 路径加入 watch 脚本 PATH（现已前置 `/opt/homebrew/bin`，追加 `~/MeetingNotes/bin`）。
- `FLUIDAUDIO_PREBUILT_URL` 默认指向你的 Release 资产。
- 换服务商：`config.local.sh` 可选 `LLM_BASE_URL` / `LLM_MODEL`；`process.py` 读环境变量，缺省用 DeepSeek 当前值（需小改：把写死的 `base_url`/`LLM_MODEL` 改为可被环境覆盖）。

## 数据流

录音（拖入 `录音`/inbox 或 AirDrop→Downloads→自动搬入）→ 本机 ffmpeg 转码 → 本机 Whisper 转录 + FluidAudio 分离 → 文字发 LLM（默认 DeepSeek）整理 → 纪要写入 `纪要`/output（可选同步 Obsidian）。**录音始终不出本机。**

## 制作方产出与维护

一次性：上传预编译 FluidAudio 至 Release；定好静态 ffmpeg 来源并补 `NOTICE`；写 `build_release.sh`。
日常：改代码 → 重跑 `build_release.sh` → 发新 Release；朋友重新下载更新。
新增维护面：预编译 FluidAudio（升级/改补丁时重编）、Python/ffmpeg 固定下载地址、发 Release 工序。均不重。

## 边界与风险

**特意不做（YAGNI）**：`.app`/签名公证、Windows、自动更新、托管、终端外图形界面。

**已知风险**：
- 首次需联网 + 约 5–10 分钟（Python 依赖 + 3GB 模型）。网络差可能失败——脚本可续传 + 镜像回退，重跑即可。
- 老 macOS 上预编译 FluidAudio 可能跑不起，回退源码编译（需 Xcode，极少数人受影响）；下载页标注最低系统版本。
- 首次装 torch 等大依赖（arm64 有现成 wheel，不编译）——即现 `install.sh` 已做、已验证。
- 未签名：一次右键→打开；终端窗口出现；DeepSeek key 仍需填（不托管的必然）。

## 验收标准

1. 在一台**未装 Homebrew / Xcode CLT** 的 Apple Silicon Mac 上，仅「解压 → 右键打开 `.command` → 弹框填 key」即完成安装，无需终端输入、无需手装任何前置。
2. 首次置备全程终端只见友好中文进度，无技术噪音瀑布；噪音可在 `logs/` 查到。
3. key 填错时当场弹框提示重填，不进入后续流程。
4. 安装后：桌面「MeetingNotes 录音」替身可用；拖入录音与 AirDrop 均自动出纪要；`~/MeetingNotes` 为固定位置。
5. 高级用户在 `config.local.sh` 设 `LLM_BASE_URL`/`LLM_MODEL` 后可切换到其他 OpenAI 兼容服务商。
6. 再次双击 `.command` 幂等，不重复安装。

## 待办（进入实现计划再细化）

- `process.py` 让 `base_url`/`model` 可被环境变量覆盖（保持 DeepSeek 默认）。
- 选定 python-build-standalone 与静态 ffmpeg 的具体固定版本 URL。
- `bootstrap_mac.sh` 的友好输出与噪音重定向约定。
- 桌面替身与 `~/MeetingNotes` 安顿的幂等实现。
