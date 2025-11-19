# Repository Guidelines

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