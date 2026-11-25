#!/usr/bin/env bash
set -euo pipefail
REPO_RAW_BASE="${AGY_ZH_REPO_RAW:-https://raw.githubusercontent.com/Macmu/antigravity-zh-launcher/main}"
LANG_CODE="zh-CN"
UPDATE_ENGINE=false
CREATE_SHORTCUT=true
DRY_RUN=false
usage() {
  cat <<'EOF'
Antigravity 多语言独立启动器（默认：zh-CN / Antigravity 中文）
用法: bash install.sh [--lang <code>] [--update-engine] [--no-shortcut] [--dry-run]
语言: zh-CN zh-TW ja ko es fr de ru pt-BR
--update-engine  刷新简体中文上游词库；其他语言随安装包更新
--no-shortcut    仅安装命令行与 Prompt 插件
--dry-run        显示安装计划，不写入用户目录或运行应用
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) [[ $# -ge 2 ]] || { echo '[错误] --lang 缺少语言代码' >&2; exit 1; }; LANG_CODE="$2"; shift 2 ;;
    --lang=*) LANG_CODE="${1#*=}"; shift ;;
    --update-engine) UPDATE_ENGINE=true; shift ;;
    --no-shortcut) CREATE_SHORTCUT=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[错误] 未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done
case "$LANG_CODE" in zh-CN|zh-TW|ja|ko|es|fr|de|ru|pt-BR) ;; *) echo "[错误] 不支持的语言: $LANG_CODE" >&2; usage >&2; exit 1 ;; esac
for cmd in python3 curl; do
  command -v "$cmd" >/dev/null || { echo "[错误] 缺少工具: $cmd" >&2; exit 1; }
done
TMP_DIR=""
STAGE=""
cleanup() {
  if [[ -n "$STAGE" ]]; then rm -rf "$STAGE"; fi
  if [[ -n "$TMP_DIR" ]]; then rm -rf "$TMP_DIR"; fi
}
trap cleanup EXIT
trap 'echo "[错误] 安装失败（行 $LINENO）。请检查上方错误后重试。" >&2' ERR
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -f "$SCRIPT_DIR/locales/index.json" ]]; then
  SOURCE_ROOT="$SCRIPT_DIR"
else
  TMP_DIR="$(mktemp -d)"
  SOURCE_ROOT="$TMP_DIR"
  fetch() {
    mkdir -p "$(dirname "$SOURCE_ROOT/$1")"
    curl -fsSL --retry 2 --connect-timeout 15 "$REPO_RAW_BASE/$1" -o "$SOURCE_ROOT/$1"
  }
  fetch locales/index.json
  for code in zh-CN zh-TW ja ko es fr de ru pt-BR; do fetch "locales/$code.json"; done
  for file in bin/agy-zh lib/locale.py lib/overlay.js lib/zh-overlay.py; do fetch "$file"; done
fi
META="$(python3 "$SOURCE_ROOT/lib/locale.py" metadata "$LANG_CODE")"
IFS=$'\t' read -r APP_NAME COMMAND_NAME PLUGIN_NAME BUNDLE_ID <<< "$META"
LOCAL_BIN="$HOME/.local/bin"
ASSETS="$LOCAL_BIN/agy-i18n"
CONFIG_DIR="${GEMINI_CONFIG_DIR:-$HOME/.gemini/config}"
PLUGIN_DEST="$CONFIG_DIR/plugins/$PLUGIN_NAME"
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] $LANG_CODE → $APP_NAME; CLI: $LOCAL_BIN/$COMMAND_NAME; plugin: $PLUGIN_DEST; shortcut: $CREATE_SHORTCUT"
  exit 0
fi
[[ "$(uname -s)" == Darwin ]] || { echo '[错误] 仅支持 macOS；Windows 请使用 install.ps1。' >&2; exit 1; }
if [[ -n "$TMP_DIR" ]]; then
  fetch "plugins/$PLUGIN_NAME/plugin.json"
  fetch "plugins/$PLUGIN_NAME/rules/AGENTS.md"
  fetch plugins/antigravity-zh-prompt/assets/logo.svg
fi
# Build first in a temporary data directory, before replacing a working install.
STAGE="$(mktemp -d)"
# Keep the legacy cache and custom URL behavior for zh-CN.
DATA_DIR="${AGY_ZH_DATA_DIR:-$LOCAL_BIN}"
if [[ -f "$DATA_DIR/antigravity-hans-overlay.base.js" && "$UPDATE_ENGINE" == false ]]; then
  cp "$DATA_DIR/antigravity-hans-overlay.base.js" "$STAGE/antigravity-hans-overlay.base.js"
fi
BUILD_ARGS=(--lang "$LANG_CODE" build-overlay)
if [[ "$UPDATE_ENGINE" == true ]]; then BUILD_ARGS+=(--force); fi
if ! AGY_ZH_DATA_DIR="$STAGE" bash "$SOURCE_ROOT/bin/agy-zh" "${BUILD_ARGS[@]}"; then
  rm -rf "$STAGE"
  exit 1
fi
mkdir -p "$ASSETS/lib" "$ASSETS/locales" "$ASSETS/installed" "$DATA_DIR" "$PLUGIN_DEST/assets" "$PLUGIN_DEST/rules"
cp "$SOURCE_ROOT"/lib/{locale.py,overlay.js,zh-overlay.py} "$ASSETS/lib/"
cp "$SOURCE_ROOT"/locales/*.json "$ASSETS/locales/"
cp "$SOURCE_ROOT/bin/agy-zh" "$LOCAL_BIN/agy-zh"
chmod 755 "$LOCAL_BIN/agy-zh"
if [[ "$COMMAND_NAME" != agy-zh ]]; then
  cat > "$LOCAL_BIN/$COMMAND_NAME" <<EOF
#!/usr/bin/env bash
exec "\$(cd -P "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)/agy-zh" --lang '$LANG_CODE' "\$@"
EOF
  chmod 755 "$LOCAL_BIN/$COMMAND_NAME"
fi
cp "$STAGE"/*.js "$DATA_DIR/"
rm -rf "$STAGE"
cp "$SOURCE_ROOT/plugins/$PLUGIN_NAME/plugin.json" "$PLUGIN_DEST/"
cp "$SOURCE_ROOT/plugins/$PLUGIN_NAME/rules/AGENTS.md" "$PLUGIN_DEST/rules/"
cp "$SOURCE_ROOT/plugins/antigravity-zh-prompt/assets/logo.svg" "$PLUGIN_DEST/assets/"
"$LOCAL_BIN/agy-zh" --lang "$LANG_CODE" prompt off >/dev/null
touch "$ASSETS/installed/$LANG_CODE"
if [[ "$LANG_CODE" == zh-CN ]]; then rm -f "$LOCAL_BIN/antigravity-hans"; fi
if [[ "$CREATE_SHORTCUT" == true ]]; then "$LOCAL_BIN/agy-zh" --lang "$LANG_CODE" shortcut; fi
echo "[成功] $APP_NAME ($LANG_CODE) 已安装。启动: $COMMAND_NAME start；状态: $COMMAND_NAME status"
echo '[信息] Prompt 插件默认关闭。原版 Antigravity 应用文件保持不变。'
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then echo "[提示] 请将 $LOCAL_BIN 加入 PATH，或使用命令的完整路径。"; fi
