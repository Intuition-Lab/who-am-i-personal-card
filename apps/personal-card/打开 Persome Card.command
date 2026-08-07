#!/bin/zsh
set -u
umask 077

CARD_DIR="${0:A:h}"
CARD_URL="http://127.0.0.1:8772/"
CARD_LOG_DIR="$HOME/Library/Logs/Who Am I"
CARD_LOG="$CARD_LOG_DIR/card-server.log"
MANAGED_NODE="$CARD_DIR/runtime/node/bin/node"
MANAGED_NPM="$CARD_DIR/runtime/node/bin/npm"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$CARD_DIR/product-version" 2>/dev/null || true)"

mkdir -p "$CARD_LOG_DIR"
chmod 700 "$CARD_LOG_DIR"
touch "$CARD_LOG"
chmod 600 "$CARD_LOG"

if [[ -x "$MANAGED_NODE" && -x "$MANAGED_NPM" ]]; then
  NODE_BIN="$MANAGED_NODE"
  NPM_BIN="$MANAGED_NPM"
  export PATH="$CARD_DIR/runtime/node/bin:/usr/bin:/bin:/usr/sbin:/sbin"
else
  NODE_BIN="$(command -v node || true)"
  NPM_BIN="$(command -v npm || true)"
fi

is_expected_card() {
  local status
  status="$(/usr/bin/curl -fsS "$CARD_URL/api/setup/status" 2>/dev/null || true)"
  [[ -n "$EXPECTED_VERSION" ]] \
    && [[ "$status" == *'"devMode":false'* ]] \
    && [[ "$status" == *"\"productVersion\":\"$EXPECTED_VERSION\""* ]]
}

if ! is_expected_card; then
  if /usr/bin/curl -fsS "$CARD_URL" >/dev/null 2>&1; then
    osascript -e 'display alert "Who Am I 无法启动" message "本机端口 8772 正被另一个版本或其他应用占用。请先关闭旧版 Who Am I，再重新打开。"' >/dev/null
    exit 1
  fi
  cd "$CARD_DIR" || exit 1
  if [[ -z "$NODE_BIN" || -z "$NPM_BIN" ]] || ! "$NODE_BIN" --version >/dev/null 2>&1; then
    osascript -e 'display alert "Personal Card 安装不完整" message "没有找到产品自带的运行环境，请重新运行产品 install.sh。"' >/dev/null
    exit 1
  fi
  if [[ ! -d "$CARD_DIR/node_modules/ajv" ]]; then
    "$NPM_BIN" ci --omit=dev --ignore-scripts >>"$CARD_LOG" 2>&1 || {
      osascript -e 'display alert "Personal Card 安装失败" message "请检查网络后重新打开，或在项目目录运行 npm ci。"' >/dev/null
      exit 1
    }
  fi
  /usr/bin/nohup /usr/bin/env WHOAMI_DEV_MODE=0 NODE_ENV=production "$NODE_BIN" "$CARD_DIR/persome-card-server.mjs" >>"$CARD_LOG" 2>&1 &
  for _ in {1..20}; do
    is_expected_card && break
    sleep 0.2
  done
fi

if ! is_expected_card; then
  osascript -e 'display alert "Who Am I 启动失败" message "Personal Card 没有在预期时间内启动。诊断日志保存在 ~/Library/Logs/Who Am I/card-server.log。"' >/dev/null
  exit 1
fi

open "$CARD_URL"
