<p align="center">
  <img src="docs/icon.png" width="112" alt="GitScope icon">
</p>

<h1 align="center">GitScope</h1>

<p align="center">macOS 原生 Git 客户端，为「同时维护多个本地仓库」而做。</p>
<p align="center">SwiftUI · 单窗口 · 本地运行 · 无账号 · 无第三方依赖</p>


## 特性

### 多仓库
- 贴边侧边栏，一个窗口管理所有仓库；仓库行显示当前分支和未提交改动
- 分屏视图（`⌘\`）：左右并排两个仓库，各自选择仓库与分支，独立浏览提交和 diff
- 拖拽文件夹添加仓库；右键在 Finder / Terminal 中打开；重启恢复仓库和上次选中提交

### 历史
- 提交图：泳道、合并曲线、merge 空心节点、ref 徽标，右上角 `?` 查看图例
- 过滤：按消息 / 作者 / 邮箱 / hash 搜索；按本地或远程分支过滤
- 提交详情：作者、时间、hash、正文、改动文件列表，或整个文件树
- 文件历史、blame、reflog
- 距底部 30 条时自动续载，首屏 2000 条提交

### Diff
- 统一 / 并排两种布局（`⌥⌘D` 或 diff 头部切换）
- 语法高亮、行号；长行自动换行，不再省略
- 图片 diff（修改前后并排）
- 忽略空白（`±w`）
- 整文件或单 hunk 的 stage / unstage / discard
- patch 复制或另存为

### 工作区
- Staged / Unstaged 分组，整文件与单 hunk 操作
- 提交编辑器：Amend、Stage all、`⌘↵` 提交
- 冲突文件：Ours / Theirs / Mark resolved；merge、rebase、cherry-pick、revert 进行中的 Continue / Abort 提示
- stash 内容查看

### 仓库操作
- fetch / pull / push（首次 push 自动设置 upstream）
- 分支：checkout、新建、重命名、删除；远程分支 checkout 为本地分支
- 标签：新建（含附注）、删除
- stash：push / apply / pop / drop
- worktree：查看、新建、移除
- merge、rebase、cherry-pick、revert、reset（soft / mixed / hard）
- 交互式 rebase：调整顺序、squash、drop
- submodule 状态查看与一键更新

### 外观
- 隐藏标题栏，交通灯并入玻璃侧边栏；侧边栏空白处可直接拖动窗口
- 蓝色胶囊选中仓库，提交列表选中整行浅蓝背景
- 跟随系统 / 浅色 / 深色三档
- 原生菜单栏与右键菜单

## 构建与运行

依赖：macOS 14+、Xcode（macOS SDK 与 Swift 工具链）。

```bash
# Debug 构建，产物在 build/GitScope.app
./scripts/build.sh

# Release 构建
./scripts/build.sh release

# 运行
open build/GitScope.app
```

首次启动点左下角 `Add` 或欢迎页的 `Add repository…`，也可以直接把文件夹拖进窗口。

## 命令行

```bash
# 打开指定仓库并定位到某个提交
GitScope --open /path/to/repo --select <commit-hash>

# 指定 diff 布局
GitScope --open /path/to/repo --side-by-side
```

## 快捷键

| 快捷键 | 动作 |
| --- | --- |
| `⌘O` | 添加仓库 |
| `⇧⌘O` | 克隆仓库 |
| `⌘R` | 刷新 |
| `⇧⌘F` / `⇧⌘P` / `⇧⌘K` | Fetch / Pull / Push |
| `⇧⌘S` | Stash 当前改动 |
| `⌥⌘S` | 显示/隐藏侧边栏 |
| `⌥⌘D` | 切换统一 / 并排 diff |
| `⌘\` | 打开 / 关闭分屏视图 |
| `⌘↵` | 提交（焦点在提交框时） |

## 代码结构

```
Sources/
  App.swift                  应用入口、菜单命令、命令行参数
  Model/
    AppModel.swift           全局状态：仓库、分屏、偏好持久化
    RepoSession.swift        单个仓库的状态与所有 git 操作
    Models.swift             Commit / Branch / Tag / FileChange / Diff 等
  Git/
    GitCLI.swift             进程封装（异步、可取消）
    GitRepo.swift            高层 git 命令与输出解析
    DiffParser.swift         unified diff → 结构化 hunk / 并排行
    GraphLayout.swift        提交图泳道布局
  UI/
    ContainerView.swift      主界面、分屏、仓库头
    SidebarView.swift        仓库 / 分支 / 远程 / 标签 / stash / worktree 侧边栏
    HistoryView.swift        提交列表 + 分支图绘制
    DetailView.swift         提交详情
    ChangesView.swift        工作区改动、冲突、提交编辑器
    DiffView.swift           统一 / 并排 diff 渲染
    InspectorSheets.swift    blame / 文件历史 / reflog / submodule / stash
    RebaseSheet.swift        交互式 rebase
    WorktreeSheet.swift      新建 worktree
    Syntax.swift             轻量语法高亮
    Theme.swift              配色、字体与通用组件
scripts/
  build.sh                   构建 .app
  make-icon.swift            生成 AppIcon.icns 与 docs/icon.png
```

## 实现说明

- 所有 git 操作通过子进程调用系统 `git`，不链接 libgit2。
- 进程读取使用独立队列并发读 stdout/stderr，避免管道阻塞；任务取消会终止子进程。
- 提交图在客户端计算泳道；父提交不在已加载窗口内时泳道结束，避免长历史泳道无限扩张。
- 泳道按列表宽度等比缩放；分屏模式下只显示单个分支的线性列表，避免多泳道挤在窄栏里。
- 大 ref 集合（例如 1500+ tag）只渲染前 30 条，完整列表放在可搜索的弹窗里。

## 已知限制

- 交互式 rebase 的 squash 使用 git 默认合并信息，未提供逐条改写的编辑器。
- merge 冲突只提供 ours / theirs / 标记解决，没有三方合并编辑器；可以交给外部工具。
- 不支持 LFS 拉取/推送 UI、GPG 签名展示、git-flow、子模块递归 diff。
