# GitScope 设计说明

## 目标

给同时维护多个本地仓库的开发者一个 macOS 原生工具：一眼看到所有仓库的状态，快速翻历史、看 diff，并且能完成日常的暂存/提交/分支/同步操作，不必在多个 Fork 窗口或终端之间切换。

失败的判定：

- 打开仓库需要等很久，或大仓库（2000+ 提交、上千 ref）卡顿
- diff 看不清、不能单 hunk 暂存，导致还是得回终端
- 只能看不能改，任何提交都要切回别的工具

## 非目标

- 不做 GitHub/GitLab 的 PR、issue、CI 面板
- 不做账号体系、云同步、团队协作
- 不做自带合并编辑器（交给外部编辑器）
- 不追求和 Fork 100% 像素一致

## 可选项与选择

**A. Electron + TypeScript**：跨端复用、diff 组件成熟，但体积大、启动慢，与 macOS 交互要跨语言桥接。

**B. 本地 Web 应用**：最快出东西，但每次要开浏览器，不是一个「App」。

**C. 原生 SwiftUI**（选定）：真正的 macOS 应用，滚动/选中/菜单顺手，Xcode 与 Swift 6 环境已具备；代价是 diff、语法高亮、分支图都要自己写。

选择 C，并把「自己写」的成本前置：先做只读浏览，再做写操作。

## 架构

```
AppModel ── RepoSession × N ── GitRepo ── GitCLI ── /opt/homebrew/bin/git
   │             │
   │             ├── GraphLayout（泳道布局）
   │             └── DiffParser（unified → hunk / 并排）
   └── SwiftUI 视图树（侧边栏 / 历史 / 详情 / diff）
```

- **AppModel**：仓库集合、标签页、当前仓库、偏好（diff 布局、侧边栏）持久化到 UserDefaults；同时保存每个仓库上次选中的提交，重启后恢复。
- **RepoSession**：一个仓库的全部可变状态与操作。刷新时并发拉取 info/branches/tags/stashes/worktrees/status/remotes/log，任一失败给出可读错误。
- **GitCLI**：`Process` 封装，stdout/stderr 并行读取避免死锁，`withTaskCancellationHandler` 支持取消。
- **GitRepo**：命令构造 + 文本解析。log 用 `\x1f`/`\x1e` 分隔，refs 用 `%D`，status 用 `--porcelain=v2 -z`，二进制安全。
- **GraphLayout**：按 `--date-order` 顺序维护活跃泳道；父提交不在当前窗口内时直接结束泳道，防止长历史泳道爆炸；渲染层把泳道数钳制到 8 列。
- **DiffParser**：解析多文件 patch 为 `FileDiff → DiffHunk → DiffLine`，并生成并排视图的行配对（删除/新增按块配对）。

## 关键决策

1. **shell 调 git，而不是 libgit2**：行为与用户终端一致，无需打包二进制；代价是解析成本，但所有输出格式都稳定。
2. **只读优先**：第一版不碰写操作，先把历史/diff 的正确性做扎实；写操作按「暂存 → 提交 → 分支/同步 → 重写历史」分层加入。
3. **hunk 级暂存用 patch**：从 diff 中取单个 hunk，拼成 `diff --git/---/+++` 头，`git apply --cached` 暂存、`--reverse` 取消暂存；已单独验证。
4. **侧边栏大列表收敛**：tag/remote 上千时只渲染 30 条，其余进可搜索弹窗；已加载超过 30 条的区块默认折叠。
5. **图片 diff 单独渲染**：二进制文件不解码文本，按扩展名识别图片，用 `git show <rev>:<path>` 取两侧字节并排显示。
6. **状态机提示**：通过 `.git/MERGE_HEAD`、`rebase-merge/` 等文件判断进行中的操作，展示 Continue/Abort，避免用户卡在半完成状态。

## 交给实现者的空间

- 分支图的曲线控制点、颜色顺序可调
- 提交列表行高、图标、徽章样式可调
- 冲突解决可以接三方合并工具
- 交互式 rebase 可以扩展 reword/edit
