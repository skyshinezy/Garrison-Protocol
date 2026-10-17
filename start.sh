#!/bin/bash
# start.sh — 从 GitHub 同步最新代码并启动服务端（容器每次重启都会拉取最新提交）
# 仓库：https://github.com/skyshinezy/Garrison-Protocol  （分支 main）
set -uo pipefail

NODE_VERSION="${NODE_VERSION:-22.14.0}"
REPO="https://github.com/skyshinezy/Garrison-Protocol.git"
DIR="Stronghold-Protocol"

# 优先用 mise 固定 Node 版本；没有 mise 时退回系统 node
if command -v mise >/dev/null 2>&1; then
  RUN_NODE="mise exec node@${NODE_VERSION} --"
else
  RUN_NODE=""
fi

log() { echo "[start] $*"; }

cd /home/container || { echo "[start] ✘ /home/container 不存在"; exit 1; }

# 清掉可能残留的旧进程（面板重启时常见），确保是“重启”
pkill -9 node 2>/dev/null || true
sleep 1

# 首次克隆，之后每次拉取最新（仅快进）。
# 拉取前先丢弃本仓库所有“已跟踪文件”的本地改动（git checkout -- .），
# 这样即使之前手动改过前端源码等文件，也不会再被 “本地修改将被合并覆盖” 卡住。
# 说明：git checkout -- . 只影响已被 git 跟踪的文件，不会动 public/assets、public/vendor、
# node_modules 等被 .gitignore 忽略的目录；data/assets.json 稍后由脚本重新登记。
if [ ! -d "$DIR/.git" ]; then
  if [ ! -e "$DIR" ]; then
    log "克隆仓库 $REPO → $DIR"
    git clone "$REPO" "$DIR" || { echo "[start] ✘ 克隆失败（容器需能访问 github.com）"; exit 1; }
  else
    # 目录已存在但不是 git 仓库：保留原样，直接启动（兼容老的手动部署）
    log "目录 $DIR 已存在但非 git 仓库，跳过同步，直接启动"
  fi
else
  ( cd "$DIR" && git checkout -- . 2>/dev/null; git pull --ff-only ) || log "⚠ git pull 失败，继续使用已有代码"
fi

cd "/home/container/$DIR" || { echo "[start] ✘ 代码目录不存在：$DIR"; exit 1; }

# 皮肤：仓库出于体积考虑未包含 public/assets 下的皮肤骨骼与头像（被 .gitignore 忽略），
# 且 tools/fetch-assets.mjs 的下载计划不含干员皮肤，所以这里专门从 jsdelivr 拉取缺失的皮肤文件，
# 并把磁盘实况重新登记进 data/assets.json（有骨骼才登记 spine；头像本地有则本地、否则回退远程）。
# 尽力而为：CDN 不可达时会自动跳过，游戏仍可正常启动，下次重启自动续传。
log "同步皮肤资源（骨骼+头像，尽力而为）…"
$RUN_NODE node tools/fetch-skin-spines.mjs || log "⚠ 皮肤下载未完成（CDN 不可达？游戏仍可运行，稍后重启续传）"
$RUN_NODE node tools/inject-skins-assets.mjs || log "⚠ 皮肤登记失败（不影响启动）"

# 首次部署或缺失依赖/资源时，用 setup 补齐（node_modules / public/vendor / public/assets）。
# 幂等：已就绪则几乎 instant；缺美术音频时会下载约 550MB（可断点续传）。
if [ ! -d node_modules ] || [ ! -d public/vendor ] || [ ! -d public/assets/audio ]; then
  log "补齐依赖与资源（node tools/setup.mjs）…"
  $RUN_NODE node tools/setup.mjs || log "⚠ setup 未完全成功：棋盘/场景已随仓库自带，其余资源可能缺失"
fi

export PORT="${PORT:-14650}"
log "启动服务端，端口 ${PORT}…"
# exec 让 node 直接成为主进程，接收面板停止信号以优雅退出
exec $RUN_NODE node server/index.js
