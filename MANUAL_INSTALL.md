# Squirrel AI - 手动安装指南

## 快速安装

请在**你自己的终端**中执行以下命令:

### 步骤 1: 停止现有的 Squirrel

```bash
killall Squirrel
```

### 步骤 2: 删除旧版本(如果存在)

```bash
sudo rm -rf "/Library/Input Methods/Squirrel.app"
```

### 步骤 3: 安装新版本

```bash
sudo ditto ~/Desktop/Squirrel.app "/Library/Input Methods/Squirrel.app"
```

### 步骤 4: 启动 Squirrel

```bash
open "/Library/Input Methods/Squirrel.app"
```

## 验证安装

检查是否安装成功:

```bash
ls -la "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
```

应该看到一个可执行文件。

## 使用 AI 配置界面

1. **切换到 Squirrel 输入法**
   - 点击菜单栏的输入法图标
   - 选择 Squirrel/鼠须管

2. **打开 AI 配置**
   - 再次点击输入法图标
   - 选择 **"AI Config..."** 菜单项

3. **填写配置**
   - API Base URL: `https://api.openai.com/v1/chat/completions`
   - API Key: 你的 OpenAI API 密钥
   - Model Name: `gpt-4o-mini` (或其他模型)

4. **保存并部署**
   - 点击"保存"按钮
   - 点击输入法图标 → "重新部署" (或按 `Ctrl+Option+\``)

## 测试 AI 功能

### Tab 键 - 智能联想

1. 输入拼音: `nihao`
2. 按 **Tab** 键
3. 看到 AI 生成的建议句子

### Command 键 - 知识问答

1. 输入拼音: `meixijinnianjisui`
2. 按 **Command** 键查看相关问题
3. 选择问题后再按 **Command** 键查看答案

## 故障排查

### 如果配置界面没有出现

检查菜单项:
```bash
# 重新加载输入法
killall Squirrel
open "/Library/Input Methods/Squirrel.app"
```

### 如果 AI 功能不工作

1. 检查配置文件:
```bash
cat ~/Library/Rime/ai_pinyin.custom.yaml
```

2. 查看 AI 调试日志:
```bash
tail -f ~/Library/Rime/ai_debug.log
```

3. 重新部署:
```bash
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload
```

## 一键安装脚本(可选)

如果你想使用脚本安装,在你的终端中运行:

```bash
cd /Users/abruzz1/code/squirrel
./install_squirrel.sh
```

这个脚本会提示你输入密码并自动完成所有步骤。

## 下一步

安装完成后,你就可以享受 AI 增强的输入法体验了!

- ✨ 智能联想句子补全
- 🤖 基于上下文的问答
- 🎯 个性化建议

祝使用愉快! 🎉
