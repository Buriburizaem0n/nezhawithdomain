#!/bin/bash

# 开启报错立即停止
set -e

# 设置根目录变量
ROOT_DIR=$(pwd)
ADMIN_DIR="$ROOT_DIR/admin-frontend-domain"
USER_DIR="$ROOT_DIR/nezha-dash-v1"
BACKEND_DIR="$ROOT_DIR/nezha_domains"

ADMIN_DIST_TARGET="$BACKEND_DIR/cmd/dashboard/admin-dist"
USER_DIST_TARGET="$BACKEND_DIR/cmd/dashboard/user-dist"

echo "======================================"
echo "🚀 开始构建流程"
echo "======================================"

echo "[1/5] 📦 正在更新 Git Submodules..."
# 仅初始化尚未 init 的 submodule，不 checkout 到 detached HEAD
git submodule update --init
# 在每个 submodule 中切换到追踪分支并 pull 最新代码
git submodule foreach '
  BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed "s@^refs/remotes/origin/@@")
  if [ -z "$BRANCH" ]; then
    BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk "{print \$NF}")
  fi
  if [ -n "$BRANCH" ]; then
    git checkout "$BRANCH" && git pull origin "$BRANCH" || echo "Warning: could not pull $BRANCH in $name"
  else
    echo "Warning: could not determine default branch for $name, skipping pull"
  fi
'
echo "✅ Submodules 更新完毕！"

echo "--------------------------------------"
echo "[2/5] 🛠 正在编译管理员前端 (admin-frontend-domain)..."
cd "$ADMIN_DIR"
if [ ! -f "package.json" ]; then
    echo "❌ 错误: 未找到 $ADMIN_DIR/package.json，请检查目前所在目录是否包含正确的管理员前端仓库。"
    exit 1
fi
npm install
npm run build-ignore-error
echo "✅ 管理员前端编译完毕！"

echo "--------------------------------------"
echo "[3/5] 🛠 正在编译用户前端 (nezha-dash-v1)..."
cd "$USER_DIR"
if [ ! -f "package.json" ]; then
    echo "❌ 错误: 未找到 $USER_DIR/package.json，请检查目前所在目录是否包含正确的用户前端仓库。"
    exit 1
fi
npm install
npm run build
echo "✅ 用户前端编译完毕！"

echo "--------------------------------------"
echo "[4/5] 📂 正在清理、拷贝前端构建产物到后端..."
# 清理旧数据并拷贝
if [ -d "$ADMIN_DIR/dist" ]; then
    echo "清理并转移管理员前端产物到 $ADMIN_DIST_TARGET..."
    rm -rf "$ADMIN_DIST_TARGET"
    mkdir -p "$ADMIN_DIST_TARGET"
    cp -r "$ADMIN_DIR/dist"/* "$ADMIN_DIST_TARGET"/
else
    echo "❌ 错误: 管理员前端打包产物目录 $ADMIN_DIR/dist 不存在"
    exit 1
fi

if [ -d "$USER_DIR/dist" ]; then
    echo "清理并转移用户前端产物到 $USER_DIST_TARGET..."
    rm -rf "$USER_DIST_TARGET"
    mkdir -p "$USER_DIST_TARGET"
    cp -r "$USER_DIR/dist"/* "$USER_DIST_TARGET"/
else
    echo "❌ 错误: 用户前端打包产物目录 $USER_DIR/dist 不存在"
    exit 1
fi
echo "✅ 前端产物拷贝完毕！"

echo "--------------------------------------"
echo "[5/5] 🏗 正在编译后端服务 (nezha_domains)..."
cd "$BACKEND_DIR"

echo "正在生成 Swagger 接口文档..."
go install github.com/swaggo/swag/cmd/swag@latest
$(go env GOPATH)/bin/swag init --pd -d . -g ./cmd/dashboard/main.go -o ./cmd/dashboard/docs --parseGoList=false

# 修正构建路径：用户给的命令是在根目录编 '.' 但实际 main.go 存在于 cmd/dashboard
echo "正在执行 Go 构建..."
go build -o ../nezha-server ./cmd/dashboard
echo "✅ 后端编译完毕！当前目录下生成了 nezha-server 可执行文件。"

echo "======================================"
echo "🎉 全流程构建完成！"
echo "======================================"
