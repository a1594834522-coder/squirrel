# Squirrel AI 拼音（基于 Rime 的 macOS 输入法）

> 本项目 **基于开源输入法框架 [Rime](https://rime.im/)** 及其 macOS 前端 **Squirrel** 改进而来，并保持与上游项目相同的开源许可。  
> 我们不是 Rime 官方项目，只是在其基础上增加了 AI 拼音方案和相关工具链。

---

## 特性概览

- **Rime 原生能力**
  - 继承 Squirrel 的全部基础特性：多方案支持、可定制词库、简繁/全半角/符号切换等。
  - 保持「拼音 → 汉字」的稳定性为首要目标，AI 功能失效时仍可正常输入。

- **AI 拼音方案（`ai_pinyin`）**
  - 专门为 AI 增强设计的方案，在 `schema_list` 中以 `ai_pinyin` 出现。
  - 通过 Lua 脚本（`rime.lua`）与远程大模型交互，实现句子级联想与问答。
  - AI 功能 **不会接管基础提交逻辑**，只“提供候选”，不破坏原有上屏链路。

- **Tab 联想（句子补全）**
  - 在有拼音预编辑、出现候选时按下 `Tab`：
    - 由当前拼音和最近上下文生成多条自然的句子续写候选；
    - 候选以普通候选形式出现在候选框中，选择后直接上屏。
  - 设计目标：帮你把“正在打的这句话”优雅补完，而不是乱开新话题。

- **双 Command 问答（带 Web Search 工具）**
  - 第一次 `Command`（短时间内连续按两次 `⌘`）：
    - 从当前拼音 + 候选中，生成 1～3 条更自然的提问句（例如把「杭州天气」改写成「杭州今天天气怎么样？」）。
  - 第二次 `Command`：
    - 在刚才生成的问题中选择一条（根据光标/分段），调用带 web_search 的大模型进行问答；
    - 答案以候选形式出现，选中后整体上屏。
  - 对支持 tools 的后端（如 Memorylake / x.ai / 一些兼容 OpenAI tools 的网关）自动携带 `web_search` 工具调用参数。

- **手动分词辅助（`[` 分隔符）**
  - 拼音中可用 `[` 手动标记语义分段，例如：
    - `zhoujielun[de[xinge[shism` → 「周杰伦 / 的 / 新歌 / 是什么」
  - 第一段 Command 会根据 **最后一段** 拼音和整体上下文生成问题，减少歧义：
    - 例如重点理解 `shism` 是「是什么」，而不是前面几段。

- **Memorylake 模板与多模型支持**
  - 前端 AI 配置中内置「Memorylake 模板」：
    - 固定 `base_url = http://117.50.226.120:3002/v1/responses`
    - 提供可选模型下拉列表，而非手动输入：
      - `xai/grok-4-fast-non-reasoning`
      - `xai/grok-4`
      - `gpt-4o`
      - `gpt-4o-mini`
      - `qwen-max`
      - `qwen-flash`
    - `web_search` 工具通过勾选启用，而不是手写 JSON。
  - 不使用 Memorylake 时，也支持标准 OpenAI 兼容接口（自定义 Base URL + 模型名）。

- **隐私与安全**
  - AI 功能完全可选；未配置 API Key 或网络不可用时，只用本地词库。
  - API Key、模型配置等保存在当前用户的配置目录（例如 Rime 用户目录），**不会打包进 `.pkg` 安装包**。
  - 安装/升级 Squirrel 时，你之前在 AI 配置界面填写的 API Key 仍然保留 —— 因为它们属于用户本地配置，而不是应用自身文件。

---

## 安装与启用

### 使用安装包

1. 从构建产物中取得 `package/Squirrel.pkg`。
2. 双击安装，按提示完成。
3. 打开 macOS 系统设置：
   - 「键盘」→「文本输入」→「输入源」中添加并启用「鼠须管（Squirrel）」。
4. 在菜单栏输入法图标中选择 Squirrel，并执行一次「重新部署」。

### 启用 AI 拼音方案

1. 在 Squirrel 菜单中打开「输入方案」选单，勾选 `AI 拼音`。
2. 重新部署后，从方案菜单中切换到 `AI 拼音`。
3. 此时普通拼音输入保持不变，只是额外多了 Tab/Command 的 AI 能力。

---

## 配置 AI 功能

### 打开 AI 配置界面

1. 在菜单栏中点击 Squirrel 图标。
2. 选择「偏好设置…」或类似入口。
3. 切换到「AI 配置」面板。

> 实际菜单文字可能略有不同，以当前版本界面为准。

### 选择 Provider 与模板

- **使用 Memorylake：**
  - Provider 选择为 Memorylake（或你在 UI 中看到的对应名称）。
  - Base URL 自动填为 `http://117.50.226.120:3002/v1/responses`，无需手动修改。
  - 模型下拉框可选择：
    - `xai/grok-4-fast-non-reasoning`
    - `xai/grok-4`
    - `gpt-4o`
    - `gpt-4o-mini`
    - `qwen-max`
    - `qwen-flash`
  - 可勾选是否启用 `web_search` 工具（只在问答模式/第二次 Command 时使用）。

- **使用其他兼容 OpenAI 的服务：**
  - 填写对应的 `Base URL`（如 `https://api.openai.com/v1`）。
  - 填写 `API Key`。
  - 在模型下拉中选择内置选项或输入自定义模型名。

### 测试连接

- 在 AI 配置界面点击「测试连接」按钮：
  - 若配置正确，会收到简单的成功提示；
  - 若提示 App Transport Security（ATS）错误，需要确认：
    - 使用的是 `https`，或在本地建立了合规的 HTTP 例外；
    - 对自建 HTTP 服务（如 Memorylake）应通过应用配置显式允许。

---

## 使用说明

### 基础输入（不使用 AI）

- 像普通 Rime/Squirrel 一样输入拼音并选字即可。
- AI 出问题（网络 / Key / 服务异常）时，基础输入不受影响。

### Tab：句子联想补全

- 输入一段拼音，让候选框出现；
- 按 `Tab`：
  - 输入法会把当前拼音、最近一小段上下文和已有候选发送给大模型；
  - 收到 1～3 条「更自然的完整短句」候选（约 8～25 个字）；
  - 候选展示在候选框中，和普通候选一样用数字键/回车上屏。

### 双 Command：提问 + 答案

- **第一次 Command（Command-1）**
  - 输入一个问题相关的拼音，例如：
    - `hangzhoutianqi`、`zhoujielun[de[xinge[shism` 等；
  - 按两次 `Command`（`⌘`）：
    - AI 从拼音和候选推断你的真实问题；
    - 生成 1～3 条更自然的问句（例如「杭州今天的天气怎么样？」）；
    - 这些问句出现在候选框中，你可以选择其一。

- **第二次 Command（Command-2）**
  - 在 10 秒内再次按两次 `Command`：
    - 使用刚才选中的问题，调用带 `web_search` 工具的大模型；
    - 生成一条相对详细、带实时信息的回答；
    - 回答作为候选展示，你可以像普通候选一样选择上屏。

> 若未启用 web_search 或所选后端不支持 tools，则以纯语言模型回答，提示词会尽量避免“假装实时”。

### 手动分词与下划线内容

- 在拼音中使用 `[` 明确语义分段，例如：
  - `masike[de[zuixintuiwen`
  - `openai[de[zuixinmox`
- 候选中的下划线区域代表当前正在编辑的 segment：
  - Tab/Command 的 AI 推断会更重视 **当前分段的含义**；
  - 例如 `zuixintuiwen` 代表「最新推文」，模型会在问题中用「最新推文」。

---

## 从源码构建

> 以下命令在项目根目录执行；根据你的 Xcode 环境和依赖准备情况，首次构建可能较慢。

### 依赖准备

```bash
make deps
```

- 编译 `librime` / `OpenCC` / `plum` 等依赖，并把生成的二进制和 YAML 拷贝到项目需要的位置。

### 推荐的「最安全」打包流程

```bash
rm -rf build package/Squirrel.pkg
bash package/add_data_files
make release
make package
sudo make install-release
```

- `add_data_files`：根据 `data/` 与 `data/plum/` 更新 Xcode 工程引用，只注入真实文件，避免写入目录名或参数。
- `make release`：构建 Release 版 `Squirrel.app`。
- `make package`：生成 `package/Squirrel.pkg` 安装包。
- `sudo make install-release`：安装到 `/Library/Input Methods` 并执行 `scripts/postinstall`（复制共享资源并预先运行 `rime_deployer --build`）。

> 开发调试时可用 `make debug` 构建调试版。

---

## 开发者指南（AI 相关）

### 关键文件

- `data/rime.lua`  
  - 所有 AI 逻辑（Tab 联想、Command 问答、HTTP 调用等）集中于此。
  - 修改后务必同步到 `data/plum/rime.lua`：
    ```bash
    cp data/rime.lua data/plum/rime.lua
    ```

- `data/ai_pinyin.schema.yaml` / `data/plum/ai_pinyin.schema.yaml`  
  - `ai_pinyin` 方案定义（processors/translators/filters 管线）。
  - 修改后同步并运行：
    ```bash
    cp data/ai_pinyin.schema.yaml data/plum/ai_pinyin.schema.yaml
    bash package/add_data_files
    ```

- 前端 AI 配置：
  - `sources/SquirrelApplicationDelegate.swift`  
    - AI 配置窗口逻辑、Memorylake 模板、模型下拉列表与 tools 勾选等。

### data 与 data/plum 的关系

- 把 `data/` 当作「模板源」，`data/plum/` 是 Xcode 实际引用的文件。
- 推荐工作流：
  1. 在 `data/` 下修改 `rime.lua`、`ai_pinyin.schema.yaml` 等；
  2. 同步到 `data/plum/`；
  3. 运行 `bash package/add_data_files`，再执行 `make debug` / `make release`。

---

## 调试与故障排查

- **核心日志目录：**

  ```text
  /private/var/folders/.../T/rime.squirrel/
  ```

  其中包含：
  - `rime.squirrel.INFO`
  - `rime.squirrel.WARNING`
  - `rime.squirrel.ERROR`

- 典型问题：
  - **候选框完全消失 / 拼音无法上屏**：  
    - 多半是 schema / Lua 把基础提交链路破坏了，优先回滚到上游基线的 `rime.lua` 和 `ai_pinyin.schema.yaml` 再重试。
  - **`invalid metadata.`、某个 dict 无法编译**：  
    - 检查 `data/` 下的词库 YAML 是否被改坏，或 `scripts/sync_rime_ice_dicts.sh` 是否完整复制了必要资源。
  - **AI 无响应但本地能打字**：  
    - 查看 `~/Library/Rime/ai_debug.log`（如果启用）和 curl 输出；
    - 核对 AI 配置中的 Base URL / API Key / 模型名 / tools 参数是否与你的后端兼容。

> 更详细的开发注意事项、事故教训与不能踩的坑，请参考本仓库的 `AGENTS.md`。

---

## 许可证与致谢

- 本项目基于开源输入法框架 **Rime** 及其 macOS 前端 **Squirrel** 改进而来：
  - 上游仓库示例：<https://github.com/rime/squirrel>
- 本仓库遵循与上游相同的开源许可证，具体内容请参见项目中的 `LICENSE.txt`。
- 特别感谢 Rime 社区的长期维护与生态建设，本项目所有 AI 相关功能都是在其稳定的输入法架构之上实现的。
