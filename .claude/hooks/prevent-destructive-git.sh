#!/usr/bin/env bash
input=$(cat)
command=$(echo "$input" | grep -oP '"command"\s*:\s*"\K[^"]*' | head -1)

# Block git push --force and variants (-f, --force-with-lease, --force-if-includes)
if echo "$command" | grep -qiP 'git\s+push\s+.*(-f|--force)\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"Force push is blocked. Use regular git push instead. If you need to force push, ask the user to do it manually."}}
EOF
  exit 0
fi

# Block git reset --hard
if echo "$command" | grep -qiP 'git\s+reset\s+.*--hard\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"git reset --hard is blocked because it discards uncommitted changes. Use git stash or git checkout -- <file> instead."}}
EOF
  exit 0
fi

# Block git clean -f (force delete untracked files)
if echo "$command" | grep -qiP 'git\s+clean\s+.*-[a-zA-Z]*f'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"git clean -f is blocked because it permanently deletes untracked files. Ask the user to run it manually if needed."}}
EOF
  exit 0
fi

# Block git checkout with --force/-f on branches (not file restores)
if echo "$command" | grep -qiP 'git\s+checkout\s+(-f|--force)\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"git checkout --force is blocked because it discards local changes. Use git stash first, then checkout."}}
EOF
  exit 0
fi

# Block git branch -D (force delete)
if echo "$command" | grep -qiP 'git\s+branch\s+.*-D\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"git branch -D (force delete) is blocked. Use git branch -d for safe deletion, or ask the user to force-delete manually."}}
EOF
  exit 0
fi

# Block git rebase on shared/remote branches (rebase with upstream refs)
if echo "$command" | grep -qiP 'git\s+rebase\s+.*(origin|upstream)\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"Rebasing against remote branches is blocked to prevent history rewrites. Ask the user before rebasing."}}
EOF
  exit 0
fi

# Block amending commits (could rewrite published history)
if echo "$command" | grep -qiP 'git\s+commit\s+.*--amend\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"git commit --amend is blocked because it rewrites commit history. Create a new commit instead, or ask the user to amend manually."}}
EOF
  exit 0
fi

exit 0
