# Repository Guidelines
用中文回答我的问题
## Project Structure & Module Organization
`sources/` hosts the Swift app logic, with UI assets under `Assets.xcassets` and shared resources in `resources/`. Vendor engines and data live in `librime/`, `plum/`, and their generated outputs (`lib/`, `bin/`, `data/`). Packaging logic, Sparkle bits, and installer scripts are contained in `package/`, while helper automation sits inside `scripts/` and `action-*.sh`. Keep experimental output inside `build/` only.

## Build, Test, and Development Commands
- `make deps`: compile librime/OpenCC/plum and copy their binaries and YAML into place.
- `make debug` / `make release`: invoke `xcodebuild` for the Squirrel scheme; results land in `build/Build/Products/<Config>/Squirrel.app`.
- `make package`: assemble assets via `package/add_data_files` and emit `package/Squirrel.pkg` (set `DEV_ID="Developer ID Application:…"` to sign).
- `make install-release`: push the release app into `/Library/Input Methods` and re-run `scripts/postinstall`.
- `make clean` or `make clean-deps`: remove DerivedData or fully reset vendor outputs when switching environments.

## Coding Style & Naming Conventions
Swift files use two-space indentation, explicit access control, and descriptive camelCase members/PascalCase types. SwiftLint rules are enforced, so favor local fixes and keep `// swiftlint:disable:next …` scoped to a single statement. Keep ObjC bridging helpers in `BridgingFunctions.swift` prefixed with `Rime`, store localized strings as UTF-8, and mirror existing file names when adding YAML schemas in `data/`.

## Testing Guidelines
No XCTest target exists, so rely on manual validation. After `make debug`, enable the built `Squirrel.app`, type through a candidate cycle, toggle inline preedit, and switch between Tahoe/native themes. Any script or deployment change must be followed by `make install-release` on a clean account plus a check that `bin/rime_deployer` and `bin/rime_dict_manager` are executable. Attach repro steps, screenshots, or relevant `Console.app` snippets to PRs.

## Commit & Pull Request Guidelines
Use short imperative commit summaries similar to `feat(ui): adopt system appearance` or `[Fix] Tahoe panel offset`, and append `(#1234)` when closing an issue. Limit each commit to one logical change and refresh `CHANGELOG.md` when the UX shifts. PRs should list motivation, validation commands (`make release`, manual QA), and screenshots for UI or data changes. Call out whenever vendor data (`data/plum/*`, `data/opencc/*`) or Sparkle submodules were regenerated.

## Release & Configuration Tips
Configure `ARCHS` or `MACOSX_DEPLOYMENT_TARGET` when targeting additional Macs, and export credentials via `DEV_ID` for signing/notarization. Before tagging, run `make package archive` so installers, Sparkle appcasts, and `package/appcast.xml` match the intended CDN URLs.

• 核心坑点
：Xcode 工程并不是直接引用 data/rime.lua、lua/ai_completion.lua，而是引用它们在 data/plum/ 下面的副本（参见 Squirrel.xcodeproj/project.pbxproj 中 path = data/plum/rime.lua / data/plum/ai_completion.lua 的条目）
  - package/add_data_files: 早期用 ls … | xargs basename，在文件多时触发 sysconf(_SC_ARG_MAX) 报错，还会把
    目录名（build, opencc, data/plum/build: 等）写进工程导致 Xcode 复制阶段找不到 “opencc:”/“build:” 这些
    伪文件。解决：改用 cd dir && find . -maxdepth 1 -type f，只注入真实文件；若未来新增目录，保持这一策略
    即可避免重复错误。
  - Xcode “Copy Shared Support Files” 里残留 build:、opencc: 等无效条目时，xcodebuild 会在打包阶段抱怨
    Copy … build: /path/data/plum/build:、Copy … opencc: 失败并中止。更新工程前务必清理这些旧引用，确保新
    增文件的 UUID 不与历史冲突；如果自动脚本修改了 project.pbxproj，要自查是否插入了目录名或重复 ID。
  - 共享资源缺失：ai_pinyin.schema.yaml、ai_pinyin.custom.yaml.example、symbols_v.yaml、rime_ice.dict.yaml
    等如果不放进 SharedSupport 或 postinstall，不管用户本地如何手动调试，新安装都会缺候选（英文/无候选）且
    Tab/Command 失效。后续新增 Lua/词库，必须同步放入 data/plum 并在 postinstall 里复制到 ~/Library/Rime。
  - postinstall 只复制 Lua 脚本而未运行 rime_deployer 时，安装后 ~/Library/Rime/build 为空，导致输入法开机
    后要用户自行部署才有候选。当前脚本已经在安装阶段用 rime_deployer --build 预热；以后若脚本调整，别忘了
    保留这一步。
  - .pkg 时间戳/体积不更新：即使 make package 成功，若旧包未删，可能误以为未生成。现在打包前先删除旧
    package/Squirrel.pkg，并关注日志末尾 pkgbuild: Wrote package to Squirrel.pkg；同时可 stat 或 md5 校
    验。今后建议在流程中加入 rm -f package/Squirrel.pkg。

  后续开发建议

  1. 每次修改 data/ 下资源后先跑 bash package/add_data_files，看是否出现 “adding …” 输出并确认
     project.pbxproj 没写入目录名。
  2. 跑 make release 前清理 package/Squirrel.pkg，保持日志和产物一一对应。
  3. 如需新增 AI 配置/脚本，记得同步 data/plum + scripts/postinstall，并验证 ~/Library/Rime 初次安装即具备
     全部文件。
  4. 复杂改动后，可在测试账号删除 ~/Library/Rime，重新安装 .pkg 验证 Tab/Command 与候选是否正常。

## AI 功能开发指南

1）修改优先级  
- 业务逻辑（API、提示词、tools 等）优先改：
  - `data/rime.lua`
  - 由前端生成的 `ai_pinyin.custom.yaml`  
- `data/ai_pinyin.schema.yaml` 能不动就别动；必须修改时只做小 patch，避免整体复制雾凇配置重拼 engine。  

2）Schema 与 Lua 一一对齐  
- 修改 `data/ai_pinyin.schema.yaml` 后，务必执行：
  - `cp data/ai_pinyin.schema.yaml data/plum/ai_pinyin.schema.yaml`
  - `bash package/add_data_files`
  - `make debug`（或 `make release`）  
- 然后检查 `~/Library/Rime/build/ai_pinyin.schema.yaml` 的 `engine` 段是否包含：
  - `lua_processor@ai_history_processor`（或带 `*`）
  - `lua_processor@ai_completion_processor`
  - `lua_translator@ai_completion_translator`
  - `lua_filter@ai_history_filter`  
- 再确认 `schema_list` 中有 `ai_pinyin`，并且当前确实切到了该方案。  

3）data 与 data/plum 的职责  
- 把 `data/` 视为「模板源」，`data/plum` 才是 Xcode 工程实际引用的真源。  
- 推荐工作流：
  - 在 `data/` 下修改 `rime.lua`、`ai_pinyin.schema.yaml` 等；
  - 修改完执行：
    - `cp data/rime.lua data/plum/rime.lua`
    - `cp data/ai_pinyin.schema.yaml data/plum/ai_pinyin.schema.yaml`
  - 再运行 `bash package/add_data_files` 更新工程引用。  
- 避免只改 `data/plum` 忘记同步 `data`，防止出现双源不一致。  

4）打包与安装的标准流程  
- 出可交付安装包时，尽量遵循：
  - `rm -rf build package/Squirrel.pkg`
  - `bash package/add_data_files`
  - `make release`
  - `make package`
  - `sudo make install-release`  
- 安装后在干净账号做一次「从零体验」验证：
  - 删除该账号的 `~/Library/Rime`；
  - 安装刚生成的 `.pkg`；
  - 登录后启用「AI 拼音」方案；
  - 检查：
    1. 打字有候选框（基础词库正常）；  
    2. 默认输出简体（opencc + 简繁开关正常）；  
    3. Tab 能触发 AI 补全；  
    4. 连按两次 Command 能触发问答模式。  

5）谨慎修改工程文件与安装脚本  
- `Squirrel.xcodeproj/project.pbxproj`：  
  - 只让 `package/add_data_files` 注入真实文件引用；  
  - 定期确认没有伪条目：
    - `rg "build:" Squirrel.xcodeproj/project.pbxproj`
    - `rg "opencc:" Squirrel.xcodeproj/project.pbxproj`  
- `scripts/postinstall` 与 `scripts/sync_rime_ice_dicts.sh`：  
  - 只做「复制必要资源 + 调用 \`rime_deployer --build\`」这两件事情；  
  - 更复杂的逻辑尽量放在用户级工具脚本中，避免直接堆到安装阶段。  

6）调试策略：优先看部署结果  
- 每次调整 AI 相关配置后，建议显式跑一遍：
  ```bash
  /Library/Input\ Methods/Squirrel.app/Contents/MacOS/rime_deployer \
      --build ~/Library/Rime \
      /Library/Input\ Methods/Squirrel.app/Contents/SharedSupport \
      ~/Library/Rime/build
  ```  
- 然后检查：
  - `~/Library/Rime/build/ai_pinyin.schema.yaml`  
  - `~/Library/Rime/default.custom.yaml` 与 `~/Library/Rime/build/default.yaml`  
  - 以及（若启用日志）`~/Library/Rime/ai_debug.log` 是否有期望的记录。  
- 通过这些结果可以尽早发现 schema 是否被自动 patch，Lua 处理器是否挂上，而不是等到按键无反应才回头排查。  
