# MeetingNotes 可安装打包：阶段一验收报告

日期：2026-07-27  
分支：`feat/installable-packaging`  
状态：主账号阶段二迁移完成，#1–#4 已实测通过；剩全新 Mac 的 Folder Action 冷启动缺口待修

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
| #1 录音进入 inbox → output 纪要 | ✅ 主账号实测通过 | 2026-07-27 迁移后:`录音测试.m4a`(10s)经 config.local.sh + 新服务 `com.meetingnotes.533aaa8b` 触发,转录/分离/DeepSeek 总结/output/Obsidian 全链路 22:54 完成;launchd 触发经锁竞争佐证 |
| #2 AirDrop → Downloads → inbox → 纪要 | ✅ 主账号实测通过(模拟传输) | Folder Action 已挂载;投放带 `com.apple.quarantine=0059` 音频至 Downloads,零手动:9s 自动搬入 inbox、24s 自动出纪要。`0083`(浏览器下载)门控忽略已验。仅「物理 AirDrop 传输那一下」未做,其等价于投放 0059 文件 |
| #3 未配 Obsidian仍可工作；配置后额外同步 | ✅ 通过 | 自动化覆盖 `OBSIDIAN_DIR=''` 跳过分支;主账号 config.local.sh 显式指向 `会议纪要`,#1/#2 实测产出笔记 |
| #4 uninstall 后服务/Folder Action移除、数据保留 | 自动化通过 | 临时 HOME 两种卸载模式均通过;主账号真实卸载未执行(当前处于已迁移使用状态) |

## 阶段二迁移结果(2026-07-27,主账号)

用户在主账号选择「先验证再迁移」。已完成并实测:

- `config.local.sh`(600):从 `.zshrc` 迁移可用 DeepSeek key,显式 `OBSIDIAN_DIR="$HOME/Documents/Obsidian Vault/会议纪要"`(避免留空=关闭同步)。
- launchd 平滑替换:卸载旧 `com.moxiuwen.meetingnotes`(plist 备份为 `.pre-phase2.bak`),加载新路径哈希 `com.meetingnotes.533aaa8b`;两者同脚本,功能等价。
- AirDrop Folder Action:`MeetingNotes-533aaa8b.scpt` 已挂到 Downloads。
- #1/#2 全自动链路实测通过,测试副产物已从 vault/output/done 清理。

### 发现并已加固:Folder Action 冷启动瞬态失败

首次挂载 `attach_folder_action.sh` 报 `-1728 Can't get folder action "Downloads"`(当时 `folder actions enabled=false`)。**定性(诚实修正)**:随后用 `killall System Events` 还原到真正冷状态(`enabled=false, count=0`)后,原始脚本反而能成功——即**无法确定性复现**。判断为 System Events / Folder Actions 守护进程在本会话**首次被脚本触碰时的冷初始化瞬态竞态**,一旦"热"过一次即不再出现。

**已修复(防御性加固)**:`scripts/attach_folder_action.sh` 在正式挂载前用**独立 osascript 进程**先 `set folder actions enabled to true`(提交子系统状态),并对挂载**失败重试一次**,给守护进程留启动时间。验证:从冷状态(`enabled=false, count=0`)运行修复后脚本一次成功;`tests/test_attach_folder_action.sh` 回归 PASS;修复后再跑全自动 AirDrop-sim E2E 仍 24s 出纪要。此改动降低干净 clone `install.sh` 8/8 步在全新 Mac 上偶发失败的风险。

## 阶段边界

主账号 #1–#4 已实测通过,阶段二迁移完成并处于日常使用态。Folder Action 冷启动瞬态已加固。剩余(可选):真实第二设备物理 AirDrop 复测(链路逻辑已等价验证);干净 clone 全新 Mac 的一键安装现场复跑。旧 `com.moxiuwen.meetingnotes.plist.pre-phase2.bak` 与回滚步骤保留在案。

