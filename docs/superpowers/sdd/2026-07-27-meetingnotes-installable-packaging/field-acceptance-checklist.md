# MeetingNotes 阶段一现场验收 Checklist

面向：在**独立 macOS 测试账号**（Apple Silicon）上执行 #1/#2 真实链路验收。
自动化验收（#3/#4）已在临时 HOME 通过，这里只补真机部分。
执行完把每步结果回填「结果」列，交回后我更新 `acceptance-report.md` 与共享记忆。

## 前提（三件外部条件）

- [ ] 一个独立 macOS 测试账号（不是当前主账号，避免污染现有快捷指令/服务）
- [ ] 一个真实 DeepSeek API Key（https://platform.deepseek.com）
- [ ] 一台能对本机 AirDrop 的第二设备（iPhone / 另一台 Mac）
- [ ] 已装 Homebrew + Xcode Command Line Tools（`xcode-select --install`）

## 0. 干净 clone

```sh
git clone <repo-url> ~/MeetingNotes-test
cd ~/MeetingNotes-test
git checkout feat/installable-packaging
```

- [ ] clone 成功、分支正确
- 结果：

## 1. Dry run 预检（不写状态）

```sh
./install.sh --dry-run
```

- [ ] 输出「环境预检通过：macOS arm64，Python 3.x」
- [ ] 列出 2/8–8/8 步骤且提示「未写入任何安装状态」
- 结果：

## 2. 真实安装

```sh
cp config.example.sh config.local.sh
# 编辑 config.local.sh：填入 DEEPSEEK_API_KEY；OBSIDIAN_DIR 见下方 #3 分支
./install.sh
```

- [ ] 8 步全部完成，无 `安装失败：`
- [ ] `config.local.sh` 权限为 600（`ls -l config.local.sh` → `-rw-------`）
- [ ] launchd 服务已加载（`launchctl list | grep meetingnotes` 有输出）
- 结果：

## 3. 验收 #1 — 录音入库 → 生成纪要

先按无 Obsidian 分支测（覆盖验收标准 #3 前半）：`OBSIDIAN_DIR` 留空。

```sh
cp <一段真实测试录音>.m4a inbox/
# 等待 watch_inbox 服务处理（观察日志）
tail -f logs/*.log
```

- [ ] `output/` 下生成对应纪要（记录真实产物路径）
- [ ] 纪要含说话人分离（A/B/C 标签）与正文
- 产物路径：
- 结果：

再测 Obsidian 分支（覆盖 #3 后半）：在 `config.local.sh` 设 `OBSIDIAN_DIR=<vault 内目录>`，重挂服务后再入库一段。

- [ ] Obsidian 目录额外落一份纪要
- 结果：

## 4. 验收 #2 — AirDrop → Downloads → inbox → 纪要

```sh
# 从第二设备 AirDrop 一段 .m4a 到本测试账号
# 观察 watch_downloads 服务是否把它搬进 inbox 并触发处理
tail -f logs/*.log
```

- [ ] AirDrop 文件落入 `~/Downloads`
- [ ] 自动搬入 `inbox/` 并生成纪要
- [ ] 记录所需授权（Downloads 访问 / 自动化授权弹窗结果）
- 授权结果：
- 结果：

## 5. 验收 #4 — 卸载后服务移除、数据保留

```sh
./uninstall.sh --dry-run     # 先看将移除什么
./uninstall.sh               # 默认保留 venv/models/tools 与 inbox/output/done/config
```

- [ ] launchd 服务已卸载（`launchctl list | grep meetingnotes` 无输出）
- [ ] Folder Action 已解除
- [ ] `inbox/ output/ done/` 内录音与纪要**仍在**
- [ ] `config.local.sh` 仍在
- 结果：

## 通过后

四项全绿且用户明确同意后，才进入**阶段二迁移**（当前主账号）：停用旧快捷指令、切换 `config.local.sh`、重挂服务与 Folder Action。在此之前停止。
