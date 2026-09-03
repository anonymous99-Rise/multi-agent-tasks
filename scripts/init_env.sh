#!/bin/bash
# init_env.sh - Multi-Agent Tasks 环境初始化
# v1.0.0 - 自动检测框架、操作系统，设定正确路径，不存在则自动 clone
#
# 用法: source scripts/init_env.sh [framework]
#   framework: openclaw | hermes (可选，默认自动检测)

set -euo pipefail

# =============================================
# 框架检测
# =============================================
detect_framework() {
  if [ -n "${1:-}" ]; then
    FRAMEWORK="$1"
  elif command -v openclaw &>/dev/null; then
    FRAMEWORK="openclaw"
  elif command -v hermes &>/dev/null; then
    FRAMEWORK="hermes"
  else
    echo "❌ Error: Cannot detect framework. Please specify: openclaw | hermes"
    return 1
  fi
}

# =============================================
# 操作系统检测
# =============================================
detect_os() {
  case "$(uname -s)" in
    Linux*)     OS="linux" ;;
    Darwin*)    OS="macos" ;;
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    *)          OS="linux" ;;
  esac
}

# =============================================
# 路径解析
# =============================================
resolve_path() {
  local base_path=""

  case "$FRAMEWORK" in
    openclaw)
      case "$OS" in
        linux|macos)
          base_path="$HOME/.openclaw/workspace/multi-agent-tasks"
          ;;
        windows)
          base_path="$(cygpath -u "$USERPROFILE" 2>/dev/null || echo "$HOME")/.openclaw/workspace/multi-agent-tasks"
          ;;
      esac
      ;;
    hermes)
      case "$OS" in
        linux|macos)
          base_path="$HOME/.hermes/skills/multi-agent-tasks"
          ;;
        windows)
          base_path="$(cygpath -u "$USERPROFILE" 2>/dev/null || echo "$HOME")/.hermes/skills/multi-agent-tasks"
          ;;
      esac
      ;;
  esac

  echo "$base_path"
}

# =============================================
# 自动 Clone（如果不存在）
# =============================================
auto_clone() {
  local target_path="$1"
  local repo_url="${REPO_URL:-https://github.com/adminlove520/multi-agent-tasks.git}"

  if [ -d "$target_path" ]; then
    echo "✅ Path exists: $target_path"
    return 0
  fi

  echo "📦 Path not found, cloning..."
  echo "   Target: $target_path"
  echo "   Repo:   $repo_url"

  local parent_dir="$(dirname "$target_path")"
  mkdir -p "$parent_dir"

  if command -v git &>/dev/null; then
    git clone "$repo_url" "$target_path"
    echo "✅ Cloned successfully"
    return 0
  else
    echo "❌ Error: git not found. Please install git or create path manually."
    return 1
  fi
}

# =============================================
# Git Pull（如果存在但需要更新）
# =============================================
git_pull_if_needed() {
  local target_path="$1"

  if [ ! -d "$target_path/.git" ]; then
    return 0
  fi

  cd "$target_path"
  
  # 检查是否有未提交的更改
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "⚠️  Warning: $target_path has uncommitted changes, skipping pull"
    return 0
  fi

  echo "📥 Pulling latest changes..."
  git pull origin main 2>/dev/null && echo "✅ Updated" || echo "⚠️  Pull failed (may be detached HEAD)"
}

# =============================================
# 主逻辑
# =============================================
main() {
  local framework_arg="${1:-}"
  
  detect_framework "$framework_arg"
  detect_os

  echo "🔍 Detected:"
  echo "   Framework: $FRAMEWORK"
  echo "   OS: $OS"
  echo "   Home: $HOME"

  local target_path
  target_path=$(resolve_path)

  echo ""
  echo "📁 Target path: $target_path"

  # 自动 Clone（如果不存在）
  if ! auto_clone "$target_path"; then
    return 1
  fi

  # 更新到最新（如果存在）
  git_pull_if_needed "$target_path"

  # 导出环境变量
  export MAT_ROOT="$target_path"
  export MAT_FRAMEWORK="$FRAMEWORK"
  export MAT_OS="$OS"

  echo ""
  echo "✅ Environment initialized"
  echo "   MAT_ROOT=$MAT_ROOT"
  echo "   MAT_FRAMEWORK=$MAT_FRAMEWORK"
  echo ""
  echo "💡 Run with: cd \$MAT_ROOT && bash scripts/inbox_processor.sh"
}

# 如果被 source 则只定义函数，否则直接运行
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # 被 source
  main "$@"
else
  # 直接运行
  main "$@"
fi
