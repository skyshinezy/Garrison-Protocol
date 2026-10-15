#!/usr/bin/env bash
# start.sh — 只重启：进入工作目录后直接启动服务端，不做任何拉取 / 安装 / 生成。
# 依赖（node_modules）与前端 vendor 必须已随包上传就绪；本脚本绝不触碰它们。
cd "$(dirname "$0")"

# 端口：兼容不同面板注入的环境变量
if [ -n "$SERVER_PORT" ]; then
  export PORT="$SERVER_PORT"
elif [ -z "$PORT" ]; then
  export PORT=3000
fi

# 容器内绑定所有 IPv4 网卡，便于面板端口映射
export HOST="${HOST:-0.0.0.0}"

echo "[start.sh] 直接启动服务端：PORT=$PORT HOST=$HOST"
# exec 让 node 直接成为主进程，接收面板停止信号以优雅退出
exec node server/index.js
