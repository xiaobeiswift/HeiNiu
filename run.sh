#!/usr/bin/env bash
# 黑妞短剧 · 命令行编译并启动（无需打开 Xcode GUI）
#
# 用法：
#   ./run.sh              # Debug 编译并启动
#   ./run.sh --release    # Release 编译并启动
#   ./run.sh --no-build   # 只启动最近一次产物（不重新编译）
#   ./run.sh --build-only # 只编译不启动
#   ./run.sh --quiet      # 编译时少打日志
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SCHEME="HeiNiu"
CONFIGURATION="Debug"
DO_BUILD=1
DO_OPEN=1
QUIET=0
LOG_FILE="/tmp/heiniu-build.log"

for arg in "$@"; do
  case "$arg" in
    --release|-r) CONFIGURATION="Release" ;;
    --no-build)   DO_BUILD=0 ;;
    --build-only) DO_OPEN=0 ;;
    --quiet|-q)   QUIET=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $arg（见 ./run.sh --help）" >&2
      exit 2
      ;;
  esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "找不到 xcodebuild。请先安装 Xcode 或 Command Line Tools。" >&2
  exit 1
fi

resolve_app_path() {
  local settings products name
  settings="$(
    xcodebuild \
      -project "$ROOT/HeiNiu.xcodeproj" \
      -scheme "$SCHEME" \
      -destination 'platform=macOS' \
      -configuration "$CONFIGURATION" \
      -showBuildSettings 2>/dev/null
  )"
  products="$(printf '%s\n' "$settings" | awk -F' = ' '/^[ ]*BUILT_PRODUCTS_DIR = /{print $2; exit}')"
  name="$(printf '%s\n' "$settings" | awk -F' = ' '/^[ ]*FULL_PRODUCT_NAME = /{print $2; exit}')"
  if [[ -z "${products:-}" || -z "${name:-}" ]]; then
    echo "无法解析构建产物路径（scheme=$SCHEME configuration=$CONFIGURATION）" >&2
    exit 1
  fi
  echo "${products}/${name}"
}

if [[ "$DO_BUILD" -eq 1 ]]; then
  echo "→ 编译 ${SCHEME} (${CONFIGURATION})…"
  set +e
  if [[ "$QUIET" -eq 1 ]]; then
    xcodebuild \
      -project "$ROOT/HeiNiu.xcodeproj" \
      -scheme "$SCHEME" \
      -destination 'platform=macOS' \
      -configuration "$CONFIGURATION" \
      build >"$LOG_FILE" 2>&1
    status=$?
    if command -v rg >/dev/null 2>&1; then
      rg "error:|\\*\\* BUILD " "$LOG_FILE" || true
    else
      grep -E "error:|\*\* BUILD " "$LOG_FILE" || true
    fi
  else
    xcodebuild \
      -project "$ROOT/HeiNiu.xcodeproj" \
      -scheme "$SCHEME" \
      -destination 'platform=macOS' \
      -configuration "$CONFIGURATION" \
      build 2>&1 | tee "$LOG_FILE"
    status=${PIPESTATUS[0]}
  fi
  set -e

  if [[ $status -ne 0 ]]; then
    echo "编译失败（exit=$status）。完整日志：$LOG_FILE" >&2
    exit "$status"
  fi
  if ! grep -q "BUILD SUCCEEDED" "$LOG_FILE"; then
    echo "未看到 BUILD SUCCEEDED，完整日志：$LOG_FILE" >&2
    exit 1
  fi
  echo "→ 编译完成"
fi

APP_PATH="$(resolve_app_path)"
if [[ ! -d "$APP_PATH" ]]; then
  echo "找不到 App：$APP_PATH" >&2
  echo "请先成功编译（去掉 --no-build）" >&2
  exit 1
fi

if [[ "$DO_OPEN" -eq 1 ]]; then
  pkill -x HeiNiu 2>/dev/null || true
  sleep 0.3
  echo "→ 启动 $APP_PATH"
  # -n：即使已有实例也新开；避免卡在已挂掉的旧进程
  open -n "$APP_PATH"
  sleep 1
  if pgrep -x HeiNiu >/dev/null 2>&1; then
    echo "→ 已启动（pid: $(pgrep -x HeiNiu | tr '\n' ' '))"
    # 尽量前置（可能因辅助功能权限失败，忽略即可）
    osascript -e 'tell application "HeiNiu" to activate' 2>/dev/null || true
  else
    echo "进程未起来，尝试直接执行二进制…" >&2
    BIN="$APP_PATH/Contents/MacOS/HeiNiu"
    if [[ -x "$BIN" ]]; then
      "$BIN" > /tmp/heiniu-run.out 2> /tmp/heiniu-run.err &
      sleep 1
      if pgrep -x HeiNiu >/dev/null 2>&1; then
        echo "→ 二进制启动成功"
      else
        echo "启动失败。stderr：" >&2
        cat /tmp/heiniu-run.err >&2 || true
        exit 1
      fi
    else
      echo "找不到可执行文件：$BIN" >&2
      exit 1
    fi
  fi
else
  echo "→ 产物：$APP_PATH"
fi
