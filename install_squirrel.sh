#!/bin/bash

# Squirrel AI 版本安装脚本

echo "========================================"
echo "  Squirrel AI 安装工具"
echo "========================================"
echo ""

# 检查应用是否存在
APP_SOURCE="$HOME/Desktop/Squirrel.app"
if [ ! -d "$APP_SOURCE" ]; then
    echo "错误：在桌面找不到 Squirrel.app"
    echo "请先运行构建命令生成应用"
    exit 1
fi

echo "发现应用：$APP_SOURCE"
echo ""

# 杀掉现有的 Squirrel 进程
echo "停止现有的 Squirrel 进程..."
killall Squirrel 2>/dev/null || echo "  (没有运行中的 Squirrel 进程)"

# 安装应用
echo ""
echo "安装 Squirrel.app 到 /Library/Input Methods/..."
echo "(需要管理员权限)"

# 先删除旧版本(如果存在)
if [ -d "/Library/Input Methods/Squirrel.app" ]; then
    echo "删除旧版本..."
    sudo rm -rf "/Library/Input Methods/Squirrel.app"
fi

# 使用 ditto 命令复制,可以正确处理符号链接
sudo ditto "$APP_SOURCE" "/Library/Input Methods/Squirrel.app"

if [ $? -eq 0 ]; then
    echo "✓ 安装成功！"
    echo ""
    echo "现在你可以:"
    echo "  1. 打开系统偏好设置 > 键盘 > 输入法"
    echo "  2. 添加 Squirrel 输入法"
    echo "  3. 切换到 Squirrel 输入法"
    echo "  4. 点击输入法图标 > AI Config... 配置 AI 功能"
    echo ""
    echo "是否现在启动 Squirrel? (y/n)"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        open "/Library/Input Methods/Squirrel.app"
        echo "✓ Squirrel 已启动"
    fi
else
    echo "✗ 安装失败"
    exit 1
fi
