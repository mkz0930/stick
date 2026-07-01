#!/bin/bash
# 清理已合并到 main 的 worktree 和分支

cd /Users/horse/work/stick

echo "=== 开始清理已合并的 worktree ==="
echo ""

# 已合并的分支列表
merged_branches=(
    "worktree-agent-a2683caf5d6019939"
    "worktree-agent-a43343a9f438e0bbe"
    "worktree-agent-a5e7975110a576a50"
    "worktree-agent-a67c9877ec2472606"
    "worktree-agent-a7123e7958b05641f"
    "worktree-agent-ad173e3adc1672544"
)

for branch in "${merged_branches[@]}"; do
    echo "处理分支: $branch"
    
    # 查找对应的 worktree 路径
    worktree_path=$(git worktree list --porcelain | grep -A1 "branch refs/heads/$branch" | grep "^worktree" | cut -d' ' -f2)
    
    if [ -n "$worktree_path" ]; then
        echo "  -> 移除 worktree: $worktree_path"
        git worktree remove "$worktree_path"
        echo "  -> worktree 已移除"
    else
        echo "  -> 未找到对应的 worktree"
    fi
    
    # 删除本地分支
    echo "  -> 删除本地分支: $branch"
    git branch -d "$branch" 2>/dev/null
    
    # 删除远程分支（如果存在）
    remote_branch=$(git branch -r | grep "$branch")
    if [ -n "$remote_branch" ]; then
        echo "  -> 删除远程分支: origin/$branch"
        git push origin --delete "$branch" 2>/dev/null || echo "  -> 远程分支不存在或已删除"
    fi
    
    echo ""
done

echo "=== 清理完成 ==="
echo ""
echo "当前 worktree 列表:"
git worktree list
echo ""
echo "剩余分支列表:"
git branch | grep worktree-agent
