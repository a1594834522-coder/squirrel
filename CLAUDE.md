# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Squirrel (鼠鬚管) is a macOS input method client for the Rime input method engine. It's a Swift-based application that implements the Input Method Kit (IMK) framework to provide Chinese character input on macOS.

**Key Technologies:**
- Swift 5.x (pure Swift implementation, no Objective-C)
- macOS Input Method Kit (IMK) framework
- librime C API (via bridging header)
- NSTextLayoutManager for modern text layout
- Core Animation for custom UI rendering

## Build Commands

### Prerequisites
- Xcode 14.0+ (from App Store)
- cmake (`brew install cmake` or `port install cmake`)

### Initial Setup
```bash
# Clone with submodules
git clone --recursive https://github.com/rime/squirrel.git

# Or update existing clone
git submodule update --init --recursive

# Optional: Install Rime plugins
bash librime/install-plugins.sh rime/librime-lua
```

### Common Build Commands

```bash
# Full release build (recommended)
make release

# Debug build
make debug

# Build dependencies only
make deps

# Quick install to system (requires sudo)
make install

# Create distributable package
make package

# Clean build artifacts
make clean

# Clean all dependencies
make clean-deps

# Clean package artifacts
make clean-package
```

### Build with Options

```bash
# Universal binary (ARM64 + x86_64)
make ARCHS='arm64 x86_64' BUILD_UNIVERSAL=1

# ARM64 only
make ARCHS='arm64'

# With code signing (requires Developer ID)
make DEV_ID="Your Developer Name"

# With specific Boost installation
make BOOST_ROOT=/path/to/boost
```

### Quick Development Cycle

```bash
# Use pre-built librime (faster for development)
bash ./action-install.sh

# Then build Squirrel
make release

# Install locally for testing
make install
```

## Architecture Overview

### Source Code Organization

```
sources/
├── Main.swift                          # App entry point, CLI handling
├── SquirrelApplicationDelegate.swift   # App lifecycle, Rime initialization
├── SquirrelInputController.swift       # IMK event handling, text input
├── SquirrelConfig.swift               # Configuration file parsing
├── SquirrelTheme.swift                # Theme system (colors, fonts)
├── SquirrelPanel.swift                # Candidate window UI
├── SquirrelView.swift                 # Text rendering engine
├── MacOSKeyCodes.swift                # Key code translation
├── InputSource.swift                  # Input source registration
├── BridgingFunctions.swift            # C/Swift interop utilities
└── Squirrel-Bridging-Header.h         # C API imports
```

### Key Components and Responsibilities

**SquirrelInputController** (595 lines)
- Implements IMKInputController protocol
- Handles all keyboard events from macOS
- Manages Rime session per application client
- Translates macOS key codes to Rime key codes
- Updates UI based on Rime engine state
- Entry point: `handle(_ event: NSEvent, client sender: Any!) -> Bool`

**SquirrelApplicationDelegate** (327 lines)
- Application lifecycle management
- Rime engine setup and initialization
- Configuration loading
- Distributed notification handling (reload, sync)
- User notification management
- Key methods: `setupRime()`, `startRime()`, `loadSettings()`

**SquirrelPanel + SquirrelView** (500+ lines combined)
- Custom candidate window rendering
- NSTextLayoutManager-based text layout
- CAShapeLayer for borders and backgrounds
- Light/dark mode theme support
- Mouse interaction (click, hover, scroll)

**SquirrelConfig** (150 lines)
- Wraps Rime C config API
- Type-safe property accessors with caching
- Hierarchical config lookup (schema → base)
- Color parsing (0xAARRGGBB format)

**MacOSKeyCodes** (200+ lines)
- Translates macOS key codes to Rime key codes
- Handles special keys (F1-F20, modifiers, etc.)
- Maps character keys to X11 keysym values

### Input Event Processing Flow

```
macOS NSEvent (keyDown)
    ↓
SquirrelInputController.handle()
    ↓
Translate key code (macOS → Rime)
    ↓
rimeAPI.process_key(session, keycode, modifiers)
    ↓
Rime Engine (librime.dylib) processes input
    ↓
Get context (composition + candidates)
    ↓
Update UI:
  - Inline preedit (NSTextView marked text)
  - Candidate panel (SquirrelPanel)
    ↓
Commit text when ready
    ↓
macOS inserts text into application
```

### Rime Engine Integration

The application integrates with librime through a C API bridging layer:

```swift
// Global API access
let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee

// Session management (per client app)
session = rimeAPI.create_session()
rimeAPI.process_key(session, keycode, modifiers)
rimeAPI.get_context(session, &context)
rimeAPI.destroy_session(session)

// Configuration
rimeAPI.config_open("squirrel", &config)
rimeAPI.schema_open(schemaID, &config)

// Deployment
rimeAPI.deploy()
rimeAPI.sync_user_data()
```

### Configuration System

Configuration is loaded hierarchically:

1. **Base config**: `data/squirrel.yaml` (bundled with app)
2. **Schema config**: `schema_name.schema.yaml` (per input method)
3. **User customization**: `~/.local/share/rime/squirrel.custom.yaml`
4. **App-specific options**: `app_options/com.app.bundle.id/` in config

Key configuration sections:
- `style/`: UI appearance (colors, fonts, geometry)
- `style/preset_color_schemes/`: Theme definitions
- `app_options/`: Per-application overrides
- `chord_duration`: Chord typing timing (default 0.1s)

### Theme System

Squirrel supports dual themes (light/dark) that switch automatically based on system appearance:

```swift
// Loading themes
panel.load(config: config, forDarkMode: false)  // Light theme
panel.load(config: config, forDarkMode: true)   // Dark theme

// Runtime selection
var currentTheme: SquirrelTheme {
  (isDark && darkTheme.available) ? darkTheme : lightTheme
}
```

Theme properties include colors, fonts, geometry (corner radius, borders, spacing), and layout flags (linear/stacked, horizontal/vertical).

## Development Patterns

### Working with C Structs

All Rime C structs require proper initialization:

```swift
// Use rimeStructInit() for structs with data_size field
var context = RimeContext_stdbool.rimeStructInit()
var status = RimeStatus_stdbool.rimeStructInit()
var commit = RimeCommit.rimeStructInit()

// Always free after use
rimeAPI.free_context(&context)
rimeAPI.free_commit(&commit)
rimeAPI.free_status(&status)
```

### String Handling with C API

```swift
// Swift → C (careful memory management)
var traits = RimeTraits.rimeStructInit()
traits.setCString(path, to: \.shared_data_dir)  // Properly allocates

// C → Swift
let text = String(cString: commit.text)
```

### Adding New Key Mappings

Edit `MacOSKeyCodes.swift`:

```swift
// For special keys, add to additionalCodeMappings
private static let additionalCodeMappings: [UInt16: UInt32] = [
  kVK_F1: XK_F1,
  // Add new mapping here
]

// For character keys, add to keycodeMappings
private static let keycodeMappings: [CChar: UInt32] = [
  0x20: XK_space,
  // Add new mapping here
]
```

### Modifying UI Rendering

**SquirrelView.swift** contains the core rendering logic:
- `textView`: NSTextView for text layout
- `textLayoutManager`: Modern text layout system (macOS 12+)
- `shape`: CAShapeLayer for borders/backgrounds
- `draw(_:)`: Main rendering method

**SquirrelPanel.swift** manages the window:
- Positioning relative to text cursor
- Mouse event handling
- Window level and appearance
- Visual effect view for blur/transparency

### Configuration Changes

For UI configuration:
1. Edit `data/squirrel.yaml` for bundled defaults
2. Or users can override in `~/.local/share/rime/squirrel.custom.yaml`
3. App applies changes after "重新部署" (Redeploy) from menu

Changes require redeployment:
```swift
// Trigger via distributed notification
DistributedNotificationCenter.default()
  .postNotificationName(.init("SquirrelReloadNotification"), object: nil)

// Or via command line
./Squirrel.app/Contents/MacOS/Squirrel --reload
```

## Testing Locally

### Installation Paths

- System installation: `/Library/Input Methods/Squirrel.app`
- User data: `~/.local/share/rime/`
- Temporary logs: `/tmp/rime.squirrel/`

### Testing Workflow

1. Build: `make release` or `make debug`
2. Install: `make install` (may need `sudo`)
3. Logout and login (or kill existing Squirrel process)
4. Select Squirrel from Input Sources in System Preferences
5. Test in any text application

### Debugging

View logs:
```bash
# Application logs (print statements)
log stream --predicate 'process == "Squirrel"' --level debug

# Rime engine logs
tail -f /tmp/rime.squirrel/rime.log
tail -f /tmp/rime.squirrel/squirrel.log
```

Check session state:
```bash
# List active sessions
ps aux | grep Squirrel

# Check input source registration
/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Support/lsregister -dump | grep -i squirrel
```

### Common Issues

**Input method not appearing:**
- Run `make install` with proper permissions
- Logout/login required after first install
- Check `System Preferences > Keyboard > Input Sources`

**Changes not taking effect:**
- Click "重新部署" (Redeploy) in Squirrel menu
- Or run: `./Squirrel.app/Contents/MacOS/Squirrel --reload`

**Crash on launch:**
- Check for problematic launch detection in logs
- Clean build artifacts: `make clean && make clean-deps`
- Verify librime.dylib is present in app bundle

## Important Files

### Configuration
- `data/squirrel.yaml` - Base UI configuration (bundled)
- `resources/Info.plist` - Bundle configuration, input source definitions
- `~/.local/share/rime/squirrel.custom.yaml` - User overrides (created by user)

### Build System
- `Makefile` - Top-level build orchestration
- `Squirrel.xcodeproj/` - Xcode project (Swift compilation)
- `package/make_package` - Package creation script
- `scripts/postinstall` - Installation script

### Dependencies
- `librime/` - Rime engine (git submodule)
- `plum/` - Schema/data manager (git submodule)
- `Sparkle/` - Auto-update framework (git submodule)

## Key Constraints

1. **macOS Version**: Requires macOS 13.0+ (deployment target)
2. **Xcode Version**: Requires Xcode 14.0+ for building
3. **Architecture**: Supports arm64 and x86_64 (Universal binary)
4. **Framework**: Depends on InputMethodKit (macOS framework)
5. **Text Layout**: Uses NSTextLayoutManager (macOS 12+ API)

## Common Development Tasks

### Adding a New Color Theme

1. Edit `data/squirrel.yaml`
2. Add new entry under `style/preset_color_schemes/`:
```yaml
preset_color_schemes:
  my_theme:
    name: 我的主题
    text_color: 0x424242
    back_color: 0xFFFFFF
    candidate_text_color: 0x000000
    hilited_candidate_text_color: 0xFFFFFF
    hilited_candidate_back_color: 0x4A90D9
```
3. Set as default: `style/color_scheme: my_theme`
4. Rebuild and redeploy

### Adding App-Specific Behavior

Edit `data/squirrel.yaml`:
```yaml
app_options:
  com.myapp.bundle.id:
    inline: false              # Show panel instead of inline
    inline_candidate: false    # Don't show candidates inline
    vim_mode: true            # Auto-switch to ASCII on Esc
    ascii_mode: true          # Start in ASCII mode
```

### Modifying Candidate Window Appearance

1. **Layout**: Edit `SquirrelPanel.swift` for positioning/sizing
2. **Rendering**: Edit `SquirrelView.swift` for drawing logic
3. **Theme**: Edit `SquirrelTheme.swift` for styling properties
4. **Config**: Users can override via `squirrel.yaml` without code changes

### Working with Input Sources

```bash
# Register Squirrel as input method
./Squirrel.app/Contents/MacOS/Squirrel --register-input-source

# Enable Simplified Chinese mode
./Squirrel.app/Contents/MacOS/Squirrel --enable-input-source Hans

# Enable Traditional Chinese mode
./Squirrel.app/Contents/MacOS/Squirrel --enable-input-source Hant

# Select as current input method
./Squirrel.app/Contents/MacOS/Squirrel --select-input-source Hans
```

## Code Style Notes

- Pure Swift codebase (no Objective-C except bridging header)
- Use `rimeAPI` global for Rime function calls
- Always free C structs after use (`free_context`, `free_commit`, etc.)
- Use `String(cString:)` for C string conversion
- Prefer `let` over `var` where possible
- Use computed properties for derived values
- Follow Swift naming conventions (camelCase for functions/variables)

## External Resources

- Rime Documentation: https://rime.im/docs/
- Rime GitHub: https://github.com/rime/home
- Input Method Kit: https://developer.apple.com/documentation/inputmethodkit
- librime API: https://github.com/rime/librime/blob/master/src/rime_api.h




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

