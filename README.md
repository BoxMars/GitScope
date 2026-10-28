# GitScope

一个用 SwiftUI 写的 macOS 原生 Git 客户端，面向「同时维护很多本地仓库」的场景：多仓库标签页、提交历史与分支图、逐文件 diff、暂存与提交、分支/标签/远程操作、stash、worktree、blame、reflog、冲突处理、交互式 rebase。

对标 Fork 的核心功能，本地运行，不依赖任何账号或云服务。

![GitScope](docs/screenshot.png)

## 构建与运行

依赖：macOS 14+、Xcode（提供 macOS SDK 与 Swift 工具链）。

```bash
# Debug 构建，产物在 build/GitScope.app
./scripts/build.sh

# Release 构建
./scripts/build.sh release

# 运行
open build/GitScope.app
```

首次启动后点击左下角 `Add` 或欢迎页的 `Open Repository`，选择仓库目录即可；也支持把文件夹直接拖进窗口。

命令行也可以直接定位到某个提交（调试/脚本用）：

```bash
./build/GitScope.app/Contents/MacOS/GitScope --open /path/to/repo --select <commit-hash>
```

## 功能

**多仓库**
- 仓库列表 + 多标签页，标签上显示当前分支和未提交改动
- 最近仓库持久化，重启后恢复标签与上次查看的提交
- 拖拽添加、右键在 Finder/Terminal 中打开

**历史与 diff**
- 分支图（泳道、合并曲线、merge 空心节点、ref 徽章）
- 提交列表过滤：按消息、作者、邮箱、hash 搜索
- 按分支/远程分支过滤历史
- 提交详情：作者、时间、hash、正文、改动文件列表
- diff 视图：统一 / 并排两种布局、语法高亮、行号
- 图片 diff（修改前后并排）
- 文件历史、blame、reflog
- stash 内容查看

**工作区**
- Staged / Unstaged 分组，整文件与单 hunk 的 stage/unstage
- 丢弃改动
- 提交编辑器（Amend、Stage all）
- 冲突文件识别与 Ours/Theirs/Mark resolved
- Merge/Rebase/Cherry-pick/Revert 进行中的 Continue / Abort 提示

**操作**
- fetch / pull / push（自动处理首次 push 的 upstream）
- 分支：checkout、新建、重命名、删除；远程分支 checkout 为本地分支
- 标签：新建（含附注）、删除
- stash：push / apply / pop / drop
- worktree：查看、新建、移除
- merge、rebase、cherry-pick、revert、reset（soft/mixed/hard）
- 交互式 rebase：调整顺序、squash、drop
- patch：复制 / 另存为
- submodule 状态查看与一键更新

## 快捷键

| 快捷键 | 动作 |
| --- | --- |
| ⌘O | 添加仓库 |
| ⇧⌘O | 克隆仓库 |
| ⌘R | 刷新 |
| ⇧⌘F / ⇧⌘P / ⇧⌘K | Fetch / Pull / Push |
| ⇧⌘S | Stash 当前改动 |
| ⌥⌘S | 显示/隐藏侧边栏 |
| ⌥⌘D | 切换统一/并排 diff |
| ⌘↵ | 提交（焦点在提交框时） |

## 代码结构

```
Sources/
  App.swift                  应用入口、菜单命令、截图辅助
  Model/
    AppModel.swift           全局状态：仓库、标签页、偏好持久化
    RepoSession.swift        单个仓库的状态与所有 git 操作
    Models.swift             Commit / Branch / Tag / FileChange / Diff 等
  Git/
    GitCLI.swift             进程封装（异步、可取消）
    GitRepo.swift            高层 git 命令与输出解析
    DiffParser.swift         unified diff → 结构化 hunk / 并排行
    GraphLayout.swift        提交图泳道布局
  UI/
    ContainerView.swift      主界面、标签栏、仓库工具栏
    SidebarView.swift        仓库/分支/远程/标签/stash/worktree 侧边栏
    HistoryView.swift        提交列表 + 分支图绘制
    DetailView.swift         提交详情
    ChangesView.swift        工作区改动、冲突、提交编辑器
    DiffView.swift           统一/并排 diff 渲染
    InspectorSheets.swift    blame / 文件历史 / reflog / submodule / stash
    RebaseSheet.swift        交互式 rebase
    WorktreeSheet.swift      新建 worktree
    Syntax.swift             轻量语法高亮
    Theme.swift              配色、字体与通用组件
```

## 实现说明

- 所有 git 操作通过子进程调用系统 `git`（优先 Homebrew 版本），没有链接 libgit2。
- 进程读取用独立队列并发读取 stdout/stderr，避免管道阻塞；任务取消会终止子进程。
- 提交图在客户端计算泳道：父提交不在已加载窗口内时泳道自动结束，避免长历史下泳道无限扩张。
- 大量 ref（例如 1500+ tag）只渲染前 30 条，完整列表放在可搜索的弹窗里。

## 已知限制

- 交互式 rebase 的 squash 使用 git 默认合并信息，未提供逐条改写的编辑器。
- merge 冲突只提供 ours/theirs/标记解决，没有三方合并编辑器；可用「Open in editor」交给外部工具。
- 不支持 Git LFS 的拉取/推送 UI、GPG 签名展示、git-flow、子模块递归 diff。
- 大仓库默认加载 2000 条提交，可点「Load more」继续。
