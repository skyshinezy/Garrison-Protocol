#!/usr/bin/env bash
# start(2).sh — 启动前自动解压官方战斗特效素材，再拉起服务端。
#
# 约定：本脚本位于仓库的 cs/ 子目录，项目根目录为其父目录（server/index.js、public/ 所在处）。
# 若你的部署把脚本直接放在项目根，请把下面第一行改成 cd "$(dirname "$0")"。
#
# 官方特效素材（Hypergryph 版权）不进仓库，需手动上传压缩包到项目根目录：
#   本机打包（在仓库根目录执行）：
#     zip -r local-fx-bundle.zip public/assets/local/fx data/local-fx.json
#   上传 local-fx-bundle.zip 到服务器项目根目录即可。
# 压缩包内部结构须为：
#   public/assets/local/fx/...   （特效文件，约 1.2 万个）
#   data/local-fx.json           （清单）
# 解压即落到正确位置；public/assets/local/fx 已有内容则跳过（幂等，重复启动不重复解压）。
# 若未上传压缩包，服务端照常启动，仅回退到程序化特效。
set -euo pipefail
cd "$(dirname "$0")/.."

# 端口：兼容不同面板注入的环境变量
if [ -n "$SERVER_PORT" ]; then
  export PORT="$SERVER_PORT"
elif [ -z "$PORT" ]; then
  export PORT=3000
fi

# 容器内绑定所有 IPv4 网卡，便于面板端口映射
export HOST="${HOST:-0.0.0.0}"

FX_ZIP="${FX_ZIP:-local-fx-bundle.zip}"
FX_DIR="public/assets/local/fx"
MANIFEST="data/local-fx.json"

if [ -f "$FX_ZIP" ]; then
  # fx 目录不存在或为空时才解压（幂等）
  if [ ! -d "$FX_DIR" ] || [ -z "$(ls -A "$FX_DIR" 2>/dev/null)" ]; then
    echo "[start(2).sh] 解压官方特效素材：$FX_ZIP → $FX_DIR / $MANIFEST"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o -q "$FX_ZIP" || echo "[start(2).sh] 警告：解压失败，特效将不可用（回退程序化特效）"
    elif command -v bsdtar >/dev/null 2>&1; then
      bsdtar -xf "$FX_ZIP" || echo "[start(2).sh] 警告：解压失败，特效将不可用（回退程序化特效）"
    else
      echo "[start(2).sh] 未找到 unzip / bsdtar，跳过解压（请手动解压 $FX_ZIP）"
    fi
    # 解压后简单校验
    if [ -f "$MANIFEST" ] && [ -d "$FX_DIR" ] && [ -n "$(ls -A "$FX_DIR" 2>/dev/null)" ]; then
      echo "[start(2).sh] 特效素材就绪：$(ls -A "$FX_DIR" 2>/dev/null | wc -l) 个文件"
    else
      echo "[start(2).sh] 警告：解压后未检测到特效素材，将回退程序化特效"
    fi
  else
    echo "[start(2).sh] $FX_DIR 已有素材，跳过解压"
  fi
else
  echo "[start(2).sh] 未找到 $FX_ZIP（未上传特效素材）：将使用程序化特效"
fi

echo "[start(2).sh] 启动服务端：PORT=$PORT HOST=$HOST"
# exec 让 node 直接成为主进程，接收面板停止信号以优雅退出
exec node server/index.js
