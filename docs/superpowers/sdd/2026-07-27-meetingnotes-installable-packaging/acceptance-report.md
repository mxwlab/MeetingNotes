# MeetingNotes 可安装打包：阶段一验收报告

日期：2026-07-27  
分支：`feat/installable-packaging`  
状态：代码与自动化验收通过；真实测试账号验收待执行

## 已验证

- 当前仓库 `./install.sh --dry-run`：通过，未写入安装状态。
- 当前仓库 `./uninstall.sh --dry-run`：通过，未移除任何服务或数据。
- 本地回归：配置解析、路径解耦、launchd 生成、FluidAudio 预编译/源码回退、模型置备、单文件入库、卸载保留规则、Python 路径测试全部通过。
- Folder Action：在临时 HOME 编译成功；受控 smoke test 中 quarantine `0059` 音频进入临时 inbox，`0083` 音频保持原位。
- FluidAudio native 模型预热：在允许访问用户 Library 缓存的环境中通过。
- 隔离 clone：`git clone` 后 `./install.sh --dry-run` 和除本地 venv 依赖外的 shell 测试通过。`venv/`、`models/`、`tools/` 被 `.gitignore` 排除，需在目标 Mac 安装阶段重建，不能把当前机器的大件状态误算进 clone。

## 验收矩阵

| 标准 | 结果 | 证据 / 未决项 |
|---|---|---|
| #1 录音进入 inbox → output 纪要 | 待现场 | 需干净 Apple Silicon clone 完成真实安装，配置可用 DeepSeek Key 后拖入一段测试录音 |
| #2 AirDrop → Downloads → inbox → 纪要 | 待独立账号 | 需真实 AirDrop、Downloads 权限和自动化授权；当前主账号不执行 |
| #3 未配 Obsidian仍可工作；配置后额外同步 | 自动化通过 | `OBSIDIAN_DIR=''` 与指定目录路径均已覆盖；需在 #1 现场链路复核产物 |
| #4 uninstall 后服务/Folder Action移除、数据保留 | 自动化通过 | 临时 HOME 两种卸载模式均通过；真实账号卸载待 #1/#2 后执行 |

## 阶段边界

阶段一尚未“全绿”，因此停止在这里，不执行当前用户账号的迁移。下一步需要在独立 macOS 测试账号完成 #1/#2，再记录真实产物路径、授权结果和卸载结果。只有这些验收通过且用户明确同意，才进入阶段二迁移：停用旧快捷指令、切换 `config.local.sh`、重挂服务与 Folder Action。

