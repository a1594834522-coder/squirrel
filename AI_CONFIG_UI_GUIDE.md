# Squirrel AI 配置界面使用指南

## 新功能说明

现在 Squirrel 输入法已经内置了 AI 配置的图形界面,无需手动编辑 YAML 文件!

### 主要特性

1. **图形化配置界面**
   - API Base URL 输入框
   - API Key 安全输入框(隐藏输入内容)
   - 模型名称输入框
   - 实时状态反馈

2. **智能配置管理**
   - 自动读取现有配置
   - 一键保存配置
   - 自动生成标准 YAML 格式

3. **便捷访问**
   - 从输入法托盘菜单直接打开
   - 无需记住配置文件路径

## 安装步骤

### 方法 1: 使用安装脚本(推荐)

```bash
cd /Users/abruzz1/code/squirrel
./install_squirrel.sh
```

安装脚本会自动:
- 停止现有的 Squirrel 进程
- 安装新版本到系统
- 提示是否启动 Squirrel

### 方法 2: 手动安装

```bash
# 1. 停止现有进程
killall Squirrel

# 2. 复制应用到系统目录(需要管理员权限)
sudo cp -r ~/Desktop/Squirrel.app "/Library/Input Methods/"

# 3. 启动 Squirrel
open "/Library/Input Methods/Squirrel.app"
```

## 使用 AI 配置界面

### 步骤 1: 打开配置界面

1. 切换到 Squirrel 输入法
2. 点击菜单栏的输入法图标(鼠须管图标)
3. 在下拉菜单中选择 **"AI Config..."**

### 步骤 2: 填写配置信息

配置窗口包含三个字段:

**API Base URL**
- 默认值: `https://api.openai.com/v1/chat/completions`
- 如果使用其他兼容 OpenAI API 的服务,修改为对应的 URL

**API Key**
- 输入你的 API 密钥
- 输入内容会被隐藏保护
- 例如: `sk-...`

**模型名称**
- 默认值: `gpt-4o-mini`
- 可以修改为其他模型,如: `gpt-4`, `gpt-3.5-turbo` 等

### 步骤 3: 保存配置

1. 填写完所有字段后,点击 **"保存"** 按钮
2. 如果成功,会显示 "配置已保存,请重新部署 Squirrel"
3. 窗口会在 1.5 秒后自动关闭

### 步骤 4: 重新部署

1. 再次点击输入法图标
2. 选择 **"重新部署"** (或按 Ctrl+Option+`)
3. 等待部署完成提示

## 配置文件位置

配置会自动保存到:
```
~/Library/Rime/ai_pinyin.custom.yaml
```

你也可以直接编辑这个文件,配置界面会自动读取其中的值。

## AI 功能使用

配置完成后,可以使用两个 AI 功能:

### Tab 键 - 智能联想
1. 输入拼音(如 `nihao`)
2. 按 **Tab** 键
3. 选择 AI 生成的联想句子

### Command 键 - 知识问答
1. 输入拼音(如 `meixijinnianjisui`)
2. 按 **Command** 键 → 看到 3 个相关问题
3. 用方向键选择问题
4. 再按 **Command** 键 → 看到答案
5. 按回车输出答案

## 故障排查

### 配置界面无法打开

检查是否正确安装了新版本:
```bash
ls -la "/Library/Input Methods/Squirrel.app"
```

### 配置保存后不生效

1. 确保点击了 "重新部署"
2. 查看配置文件是否正确生成:
   ```bash
   cat ~/Library/Rime/ai_pinyin.custom.yaml
   ```

### AI 功能无法使用

1. 检查 API Key 是否正确
2. 检查网络连接
3. 查看调试日志:
   ```bash
   tail -f ~/Library/Rime/ai_debug.log
   ```

## 技术实现

### 代码位置

- **配置窗口**: `sources/SquirrelApplicationDelegate.swift` (openAIConfig 方法)
- **菜单项**: `sources/SquirrelInputController.swift` (menu 方法)
- **AI 逻辑**: `~/Library/Rime/rime.lua`

### 配置格式

生成的配置文件格式:
```yaml
patch:
  ai_completion/enabled: true
  ai_completion/trigger_key: "Tab"
  ai_completion/base_url: "你的URL"
  ai_completion/api_key: "你的密钥"
  ai_completion/model_name: "你的模型"
  ai_completion/context_window_minutes: 10
  ai_completion/max_candidates: 3
  key_binder/bindings:
    - { when: composing, accept: Tab, send: Tab }
    - { when: composing, accept: Shift+Tab, send: Shift+Tab }
```

## 下一步

- 体验 AI 智能联想功能
- 尝试知识问答功能
- 根据需要调整模型参数
- 如有问题,查看调试日志

享受智能输入的乐趣! 🎉
