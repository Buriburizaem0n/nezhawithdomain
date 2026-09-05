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

echo "[1/5] 📦 正在检查/更新 Git Submodules..."
git submodule update --init 2>/dev/null || true
git submodule foreach '
  BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "")
  if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
    DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk "{print \$NF}")
    if [ -n "$DEFAULT_BRANCH" ]; then
      git checkout "$DEFAULT_BRANCH" 2>/dev/null || true
    fi
  fi
'
echo "✅ Submodules 检查完毕！"


echo "--------------------------------------"
echo "[2/5] 🛠 正在编译管理员前端 (admin-frontend-domain)..."
cd "$ADMIN_DIR"
if [ ! -f "package.json" ]; then
    echo "❌ 错误: 未找到 $ADMIN_DIR/package.json，请检查目前所在目录是否包含正确的管理员前端仓库。"
    exit 1
fi
if command -v pnpm &> /dev/null; then
    pnpm install
    pnpm run build
elif command -v npm &> /dev/null; then
    npm install
    npm run build
elif command -v docker &> /dev/null; then
    echo "Using docker to build admin-frontend-domain..."
    docker run --rm -v "$ROOT_DIR":/workspace -w /workspace/admin-frontend-domain node:22-alpine sh -c "corepack enable && pnpm install --frozen-lockfile && pnpm run build"
    docker run --rm -v "$ROOT_DIR":/workspace node:22-alpine chown -R $(id -u):$(id -g) /workspace/admin-frontend-domain/dist
else
    echo "❌ 错误: 未找到 pnpm, npm 或 docker"
    exit 1
fi
echo "✅ 管理员前端编译完毕！"


echo "--------------------------------------"
echo "[3/5] 🛠 正在编译用户前端 (nezha-dash-v1)..."
cd "$USER_DIR"
if [ ! -f "package.json" ]; then
    echo "❌ 错误: 未找到 $USER_DIR/package.json，请检查目前所在目录是否包含正确的用户前端仓库。"
    exit 1
fi
if command -v pnpm &> /dev/null; then
    pnpm install
    pnpm run build
elif command -v npm &> /dev/null; then
    npm install --legacy-peer-deps
    npm run build
elif command -v docker &> /dev/null; then
    echo "Using docker to build nezha-dash-v1..."
    docker run --rm -v "$ROOT_DIR":/workspace -w /workspace/nezha-dash-v1 node:22-alpine sh -c "corepack enable && pnpm install --frozen-lockfile && pnpm run build"
    docker run --rm -v "$ROOT_DIR":/workspace node:22-alpine chown -R $(id -u):$(id -g) /workspace/nezha-dash-v1/dist
else
    echo "❌ 错误: 未找到 pnpm, npm 或 docker"
    exit 1
fi
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
touch "$ADMIN_DIST_TARGET/.gitkeep"
touch "$USER_DIST_TARGET/.gitkeep"
echo "✅ 前端产物拷贝完毕！"

echo "--------------------------------------"
echo "[5/5] 🏗 正在编译后端服务 (nezha_domains)..."
cd "$BACKEND_DIR"

export PATH="$PATH:/usr/local/go/bin:$(go env GOPATH 2>/dev/null || echo /home/buri/go)/bin"

echo "正在生成 Swagger 接口文档..."
go install github.com/swaggo/swag/cmd/swag@v1.16.6 2>/dev/null || go install github.com/swaggo/swag/cmd/swag@latest
$(go env GOPATH)/bin/swag init --pd -d . -g ./cmd/dashboard/main.go -o ./cmd/dashboard/docs --parseGoList=false

# 修正构建路径：用户给的命令是在根目录编 '.' 但实际 main.go 存在于 cmd/dashboard
echo "正在执行 Go 构建..."
go build -o ../nezha-server ./cmd/dashboard
echo "✅ 后端编译完毕！当前目录下生成了 nezha-server 可执行文件。"

echo "======================================"
echo "🎉 全流程构建完成！"
echo "======================================"
