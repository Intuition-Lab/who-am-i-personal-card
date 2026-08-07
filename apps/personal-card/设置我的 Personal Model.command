#!/bin/zsh
set -u
umask 077

CARD_DIR="${0:A:h}"
PERSOME_HOME="${PERSOME_INSTALL_HOME:-$HOME/.persome}"
PERSOME_BIN="$PERSOME_HOME/venv/bin/persome"

find_product_installer() {
  local candidate
  for candidate in \
    "$CARD_DIR/../../install.sh" \
    "$CARD_DIR/../install.sh" \
    "$CARD_DIR/install.sh"; do
    if [[ -f "$candidate" && ! -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Personal Model 内测版目前需要 macOS 13 或更新版本。"
  echo
  read "?按回车关闭…"
  exit 1
fi

if [[ ! -x "$PERSOME_BIN" ]]; then
  PRODUCT_INSTALLER="$(find_product_installer || true)"
  if [[ -z "$PRODUCT_INSTALLER" ]]; then
    echo "安装包里没有找到经过校验的 Personal Model 安装器。"
    echo "请重新下载完整产品，不要单独复制 Card 文件夹。"
    echo
    read "?按回车关闭…"
    exit 1
  fi
  echo "接下来会安装固定版本的 Personal Model Runtime。"
  echo "数据只保存在这台 Mac；macOS 权限需要由你亲自确认。"
  echo
  /bin/bash "$PRODUCT_INSTALLER" --interactive || {
    echo
    echo "安装尚未完成。你可以稍后重新运行这个向导。"
    read "?按回车关闭…"
    exit 1
  }
fi

if [[ ! -x "$PERSOME_BIN" ]]; then
  echo "Personal Model Runtime 没有完成安装。"
  read "?按回车关闭…"
  exit 1
fi

echo
echo "正在验证本机权限与 Personal Model Runtime…"
PERSOME_ROOT="$PERSOME_HOME" "$PERSOME_BIN" onboard --tier tiny || {
  echo
  echo "权限或初始化尚未完成。修正后可以重新运行这个向导。"
  read "?按回车关闭…"
  exit 1
}

PERSOME_ROOT="$PERSOME_HOME" "$PERSOME_BIN" model open --onboarding || true

echo
echo "Personal Model 已准备好。请回到 Who Am I，点击“重新检测”。"
read "?按回车关闭…"
