#!/usr/bin/env bash
# start (1).sh — 直接启动（无任何拉取/安装步骤，无论第几次启动都直接拉起服务端）
cd "$(dirname "$0")"

# 端口：兼容不同面板注入的环境变量
if [ -n "$SERVER_PORT" ]; then
  export PORT="$SERVER_PORT"
elif [ -z "$PORT" ]; then
  export PORT=3000
fi

# 容器内绑定所有 IPv4 网卡，便于面板端口映射
export HOST="${HOST:-0.0.0.0}"

echo "[start (1).sh] 直接启动服务端：PORT=$PORT HOST=$HOST"
# exec 让 node 直接成为主进程，接收面板停止信号以优雅退出
exec node server/index.js
