# Git Worktree 开发工作流

## 目的
避免在主分支上直接开发导致的冲突，每个功能/修复都在独立的 worktree 中开发。

## 标准流程

### 1. 创建新的 worktree
```bash
# 从 main 分支创建新的 feature worktree
git worktree add .worktrees/feat-<功能名> -b feat/<功能名>

# 从 main 分支创建新的 fix worktree
git worktree add .worktrees/fix-<问题名> -b fix/<问题名>
```

### 2. 在 worktree 中开发
```bash
# 进入 worktree 目录
cd .worktrees/feat-<功能名>

# 正常开发、提交
git add .
git commit -m "feat: 描述"
```

### 3. 完成后合并到 main
```bash
# 回到主仓库
cd /Users/horse/work/stick

# 合并分支
git merge feat/<功能名>

# 推送到远程
git push origin main
```

### 4. 清理 worktree
```bash
# 移除 worktree
git worktree remove .worktrees/feat-<功能名>

# 删除分支（可选）
git branch -d feat/<功能名>
```

## 当前 worktree 管理

### 查看所有 worktree
```bash
git worktree list
```

### 清理已锁定的 worktree
```bash
# 强制移除（谨慎使用）
git worktree remove -f -f <path>
```

### 清理已合并的分支对应的 worktree
```bash
# 1. 检查分支是否已合并
git branch --merged main

# 2. 移除 worktree
git worktree remove <path>

# 3. 删除本地分支
git branch -d <branch-name>

# 4. 删除远程分支（如果有）
git push origin --delete <branch-name>
```

## 目录约定

- **主仓库**: `/Users/horse/work/stick`
- **worktree 目录**: `/Users/horse/work/stick/.worktrees/` (不在 .claude 目录下)
- **分支命名**:
  - 新功能: `feat/<功能名>`
  - 修复: `fix/<问题名>`
  - 重构: `refactor/<模块名>`

## 注意事项

1. **不要在主仓库的 main 分支上直接开发**
2. **每个 worktree 应该对应一个独立的功能或修复**
3. **定期清理已完成的 worktree**
4. **如果 worktree 被锁定，检查是否有进程正在使用**
5. **worktree 之间不共享未提交的更改**

## Claude Agent 使用的 worktree

Claude Code 会自动在 `.claude/worktrees/` 目录下创建 worktree。
这些 worktree 通常以 `agent-<id>` 命名。

**清理建议**:
- 如果 agent 任务已完成，可以安全删除对应的 worktree
- 如果 agent 还在运行，不要删除
- 定期运行清理脚本（见下文）

## 自动清理脚本

创建 `.scripts/cleanup-worktrees.sh`:

```bash
#!/bin/bash
# 清理已合并到 main 的 worktree

cd /Users/horse/work/stick

# 获取已合并到 main 的分支
merged_branches=$(git branch --merged main | grep -E "^(feat|fix|refactor)/" | sed 's/^[ *]*//')

for branch in $merged_branches; do
    echo "处理已合并的分支: $branch"
    
    # 查找对应的 worktree
    worktree_path=$(git worktree list --porcelain | grep -B1 "branch refs/heads/$branch" | head -1 | cut -d' ' -f2)
    
    if [ -n "$worktree_path" ] && [ "$worktree_path" != "/Users/horse/work/stick" ]; then
        echo "  移除 worktree: $worktree_path"
        git worktree remove "$worktree_path"
    fi
    
    # 删除本地分支
    echo "  删除本地分支: $branch"
    git branch -d "$branch" 2>/dev/null || echo "  分支未完全合并，跳过删除"
    
    echo ""
done

echo "清理完成"
```

## 当前状态

最后一次更新: 2026-07-01

- 主分支: main (领先 origin/main 20 commits)
- 现有 worktree:
  - 主仓库: `/Users/horse/work/stick` (main)
  - 进行中的功能: `feat/sleep-awake-segments`
- 已清理: 6 个已合并的 worktree-agent 分支和对应的 worktree

## 快速开始

### 示例：创建一个新的功能 worktree

```bash
# 1. 确保在主仓库目录
cd /Users/horse/work/stick

# 2. 拉取最新代码
git pull origin main

# 3. 创建 worktree
git worktree add .worktrees/feat-我的功能 -b feat/我的功能

# 4. 进入 worktree 开始开发
cd .worktrees/feat-我的功能

# 5. 打开 Xcode 进行开发
open /Users/horse/work/stick/ios/Stick.xcodeproj
```

### 示例：完成功能并合并

```bash
# 1. 在 worktree 中提交代码
cd /Users/horse/work/stick/.worktrees/feat-我的功能
git add .
git commit -m "feat: 实现我的功能"

# 2. 推送到远程
git push origin feat/我的功能

# 3. 回到主仓库合并
cd /Users/horse/work/stick
git merge feat/我的功能

# 4. 推送到远程 main
git push origin main

# 5. 清理 worktree
git worktree remove .worktrees/feat-我的功能
git branch -d feat/我的功能
```

## 清理完成

- ✅ 已清理 6 个已合并的 worktree-agent worktree
- ✅ 已删除对应的本地分支
- ✅ 创建了 `.worktrees/` 目录（已在 `.gitignore` 中）
- ✅ 建立了标准的 worktree 开发流程
