//
//  SquirrelApplicationDelegate.swift
//  Squirrel
//
//  Created by Leo Liu on 5/6/24.
//

import UserNotifications
import Sparkle
import AppKit

final class SquirrelApplicationDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
  static let rimeWikiURL = URL(string: "https://github.com/rime/home/wiki")!
  static let updateNotificationIdentifier = "SquirrelUpdateNotification"
  static let notificationIdentifier = "SquirrelNotification"

  let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  var config: SquirrelConfig?
  var panel: SquirrelPanel?
  var enableNotifications = false
  let updateController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  var supportsGentleScheduledUpdateReminders: Bool {
    true
  }

  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    NSApp.setActivationPolicy(.regular)
    if !state.userInitiated {
      NSApp.dockTile.badgeLabel = "1"
      let content = UNMutableNotificationContent()
      content.title = NSLocalizedString("A new update is available", comment: "Update")
      content.body = NSLocalizedString("Version [version] is now available", comment: "Update").replacingOccurrences(of: "[version]", with: update.displayVersionString)
      let request = UNNotificationRequest(identifier: Self.updateNotificationIdentifier, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request)
    }
  }

  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
    NSApp.dockTile.badgeLabel = ""
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.updateNotificationIdentifier])
  }

  func standardUserDriverWillFinishUpdateSession() {
    NSApp.setActivationPolicy(.accessory)
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier == Self.updateNotificationIdentifier && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      updateController.updater.checkForUpdates()
    }

    completionHandler()
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    panel = SquirrelPanel(position: .zero)
    addObservers()
  }

  func applicationWillTerminate(_ notification: Notification) {
    // swiftlint:disable:next notification_center_detachment
    NotificationCenter.default.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
    panel?.hide()
  }

  func deploy() {
    print("Start maintenance...")
    self.shutdownRime()
    self.startRime(fullCheck: true)
    self.loadSettings()
  }

  func syncUserData() {
    print("Sync user data")
    _ = rimeAPI.sync_user_data()
  }

  func openLogFolder() {
    NSWorkspace.shared.open(SquirrelApp.logDir)
  }

  func openRimeFolder() {
    NSWorkspace.shared.open(SquirrelApp.userDir)
  }

  func checkForUpdates() {
    if updateController.updater.canCheckForUpdates {
      print("Checking for updates")
      updateController.updater.checkForUpdates()
    } else {
      print("Cannot check for updates")
    }
  }

  func openWiki() {
    NSWorkspace.shared.open(Self.rimeWikiURL)
  }

  private var aiConfigWindow: NSWindow?
  private var aiConfigFields: [String: Any]?
  private let memorylakeBaseURL = "http://117.50.226.120:3002/v1/responses"
  private let responsesModelOptions = ["xai/grok-4-fast-non-reasoning", "xai/grok-4", "gpt-4o", "gpt-4o-mini"]

  func openAIConfig() {
    ensureEditMenuAvailable()
    // 如果窗口已经存在，直接显示
    if let window = aiConfigWindow {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    // 创建配置窗口
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "AI 模型配置"
    window.center()

    // 创建内容视图
    let contentView = NSView(frame: window.contentView!.bounds)
    contentView.autoresizingMask = [.width, .height]

    // 读取当前配置
    let configPath = SquirrelApp.userDir.appending(component: "ai_pinyin.custom.yaml")
    let defaultOpenAIURL = "https://api.openai.com/v1/chat/completions"
    let geminiModel = "gemini-2.5-flash"
    let geminiURL = geminiEndpoint(for: geminiModel)
    let grokURL = "https://api.x.ai/v1/responses"
    let defaults = UserDefaults.standard
    var currentBaseURL = defaults.string(forKey: "AIBaseURL") ?? defaultOpenAIURL
    var currentAPIKey = defaults.string(forKey: "AIApiKey") ?? ""
    let toolsConfigPath = SquirrelApp.userDir.appending(component: "ai_pinyin.tools.json")
    var currentToolsConfig = defaults.string(forKey: "AIToolsConfig") ?? ""
    let defaultOpenAIModel = "gpt-4o-mini"
    let grokModel = "grok-4-fast"
    var currentModel = defaults.string(forKey: "AIModelName") ?? defaultOpenAIModel
    let toolsEnabledByDefault: Bool = {
      let lower = currentToolsConfig.lowercased()
      return lower.contains("web_search")
    }()

    if FileManager.default.fileExists(atPath: configPath.path) {
      if let content = try? String(contentsOf: configPath) {
        // 解析 YAML 配置
        if let baseURLMatch = content.range(of: #"ai_completion/base_url:\s*"([^"]*)"#, options: .regularExpression) {
          let match = content[baseURLMatch]
          if let urlMatch = match.range(of: "\"([^\"]*)\"", options: .regularExpression) {
            currentBaseURL = String(match[urlMatch]).replacingOccurrences(of: "\"", with: "")
          }
        }
        if let apiKeyMatch = content.range(of: #"ai_completion/api_key:\s*"([^"]*)"#, options: .regularExpression) {
          let match = content[apiKeyMatch]
          if let keyMatch = match.range(of: "\"([^\"]*)\"", options: .regularExpression) {
            currentAPIKey = String(match[keyMatch]).replacingOccurrences(of: "\"", with: "")
          }
        }
        if let modelMatch = content.range(of: #"ai_completion/model_name:\s*"([^"]*)"#, options: .regularExpression) {
          let match = content[modelMatch]
          if let nameMatch = match.range(of: "\"([^\"]*)\"", options: .regularExpression) {
            currentModel = String(match[nameMatch]).replacingOccurrences(of: "\"", with: "")
          }
        }
      }
    }
    if FileManager.default.fileExists(atPath: toolsConfigPath.path) {
      if let toolsContent = try? String(contentsOf: toolsConfigPath) {
        currentToolsConfig = toolsContent
      }
    }
    if isGeminiProvider(baseURL: currentBaseURL, model: currentModel) {
      currentBaseURL = geminiEndpoint(for: currentModel)
    } else if isGrokProvider(baseURL: currentBaseURL, model: currentModel) {
      currentBaseURL = normalizedGrokResponsesURL(from: currentBaseURL)
    } else {
      currentBaseURL = normalizedChatCompletionsURL(from: currentBaseURL)
    }

    let isMemorylakePreset = isMemorylakeProvider(baseURL: currentBaseURL, model: currentModel)
    let isGeminiPreset = isGeminiProvider(baseURL: currentBaseURL, model: currentModel)
    let isGrokPreset = !isGeminiPreset && isGrokProvider(baseURL: currentBaseURL, model: currentModel) && !isMemorylakePreset

    // 创建标签和输入框
    let yStart: CGFloat = 370
    let labelWidth: CGFloat = 120
    let fieldWidth: CGFloat = 230
    let rowHeight: CGFloat = 68

    // Provider Preset
    let providerLabel = NSTextField(labelWithString: "配置预设:")
    providerLabel.frame = NSRect(x: 20, y: yStart, width: labelWidth, height: 20)
    providerLabel.alignment = .right
    contentView.addSubview(providerLabel)

    let providerPopup = NSPopUpButton(frame: NSRect(x: 150, y: yStart - 5, width: fieldWidth + 90, height: 24))
    providerPopup.addItems(withTitles: ["Memorylake 模板", "OpenAI 旧格式", "OpenAI /responses 格式", "Googleapis 格式"])
    if isMemorylakePreset {
      providerPopup.selectItem(at: 0)
    } else if isGrokPreset {
      providerPopup.selectItem(at: 2)
    } else if isGeminiPreset {
      providerPopup.selectItem(at: 3)
    } else {
      providerPopup.selectItem(at: 1)
    }
    providerPopup.target = self
    providerPopup.action = #selector(providerChanged(_:))
    contentView.addSubview(providerPopup)

    // Base URL
    let baseURLLabel = NSTextField(labelWithString: "API Base URL:")
    baseURLLabel.frame = NSRect(x: 20, y: yStart - rowHeight, width: labelWidth, height: 20)
    baseURLLabel.alignment = .right
    contentView.addSubview(baseURLLabel)

    let baseURLField = NSTextField(string: currentBaseURL)
    baseURLField.frame = NSRect(x: 150, y: yStart - rowHeight - 5, width: fieldWidth, height: 24)
    baseURLField.isSelectable = true
    baseURLField.isEditable = true
    if isMemorylakePreset {
      baseURLField.stringValue = memorylakeBaseURL
      baseURLField.placeholderString = memorylakeBaseURL
      baseURLField.isEnabled = false
    } else if isGeminiPreset {
      baseURLField.placeholderString = geminiURL
    } else if isGrokPreset {
      baseURLField.placeholderString = grokURL
    } else {
      baseURLField.placeholderString = defaultOpenAIURL
    }
    contentView.addSubview(baseURLField)

    // API Key
    let apiKeyLabel = NSTextField(labelWithString: "API Key:")
    apiKeyLabel.frame = NSRect(x: 20, y: yStart - rowHeight * 2, width: labelWidth, height: 20)
    apiKeyLabel.alignment = .right
    contentView.addSubview(apiKeyLabel)

    // Use a standard text field so API keys can be copied/pasted like other fields.
    let apiKeyField = NSTextField(string: currentAPIKey)
    apiKeyField.frame = NSRect(x: 150, y: yStart - rowHeight * 2 - 5, width: fieldWidth, height: 24)
    apiKeyField.isSelectable = true
    apiKeyField.isEditable = true
    if isGeminiPreset {
      apiKeyField.placeholderString = "AIza..."
    } else if isGrokPreset {
      apiKeyField.placeholderString = "xai-..."
    } else {
      apiKeyField.placeholderString = "sk-..."
    }
    contentView.addSubview(apiKeyField)

    // Model Name
    let modelLabel = NSTextField(labelWithString: "模型名称:")
    modelLabel.frame = NSRect(x: 20, y: yStart - rowHeight * 3, width: labelWidth, height: 20)
    modelLabel.alignment = .right
    contentView.addSubview(modelLabel)

    let modelField = NSTextField(string: currentModel)
    modelField.frame = NSRect(x: 150, y: yStart - rowHeight * 3 - 5, width: fieldWidth - 20, height: 24)
    modelField.isSelectable = true
    modelField.isEditable = true
    modelField.placeholderString = isGeminiPreset ? geminiModel : (isGrokPreset ? grokModel : defaultOpenAIModel)
    let modelPopup = NSPopUpButton(frame: NSRect(x: 150 + fieldWidth - 10, y: yStart - rowHeight * 3 - 6, width: 130, height: 26))
    modelPopup.addItems(withTitles: responsesModelOptions + ["自定义"])
    modelPopup.target = self
    modelPopup.action = #selector(modelOptionChanged(_:))
    modelPopup.isHidden = !(isMemorylakePreset || isGrokPreset)
    let modelMatchesPresetOption = responsesModelOptions.firstIndex(where: { $0.caseInsensitiveCompare(currentModel) == .orderedSame })
    if let idx = modelMatchesPresetOption {
      modelPopup.selectItem(at: idx)
      modelField.stringValue = responsesModelOptions[idx]
      modelField.isEditable = false
    } else {
      modelPopup.selectItem(withTitle: "自定义")
      modelField.isEditable = !(isMemorylakePreset || isGrokPreset)
    }
    contentView.addSubview(modelField)
    contentView.addSubview(modelPopup)

    // Tools 配置（仅 /responses 模板）
    let toolsLabel = NSTextField(labelWithString: "Tools 配置:")
    toolsLabel.frame = NSRect(x: 20, y: 110, width: labelWidth, height: 20)
    toolsLabel.alignment = .right
    contentView.addSubview(toolsLabel)

    let toolsCheckbox = NSButton(checkboxWithTitle: "启用 Web Search（仅第二次 Command 生效）", target: nil, action: nil)
    toolsCheckbox.frame = NSRect(x: 150, y: 106, width: fieldWidth + 100, height: 24)
    toolsCheckbox.state = toolsEnabledByDefault ? .on : .off
    contentView.addSubview(toolsCheckbox)

    let initialShowTools = isGrokPreset || isMemorylakePreset
    toolsLabel.isHidden = !initialShowTools
    toolsCheckbox.isHidden = !initialShowTools

    // 状态标签
    let statusLabel = NSTextField(labelWithString: "")
    statusLabel.frame = NSRect(x: 20, y: 40, width: 480, height: 20)
    statusLabel.alignment = .center
    statusLabel.textColor = .secondaryLabelColor
    contentView.addSubview(statusLabel)

    // 测试按钮
    let testButton = NSButton(title: "测试连接", target: nil, action: nil)
    testButton.frame = NSRect(x: 20, y: 10, width: 100, height: 32)
    testButton.bezelStyle = .rounded
    contentView.addSubview(testButton)

    // 保存按钮
    let saveButton = NSButton(title: "保存", target: nil, action: nil)
    saveButton.frame = NSRect(x: 300, y: 10, width: 80, height: 32)
    saveButton.bezelStyle = .rounded
    saveButton.keyEquivalent = "\r"
    contentView.addSubview(saveButton)

    // 取消按钮
    let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    cancelButton.frame = NSRect(x: 390, y: 10, width: 80, height: 32)
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1b}"
    contentView.addSubview(cancelButton)

    // 保存按钮处理
    saveButton.target = self
    saveButton.action = #selector(saveAIConfig(_:))
    saveButton.tag = 0

    testButton.target = self
    testButton.action = #selector(testAIConfig(_:))

    // 存储字段引用
    aiConfigFields = [
      "provider": providerPopup,
      "baseURL": baseURLField,
      "apiKey": apiKeyField,
      "model": modelField,
      "modelPopup": modelPopup,
      "toolsLabel": toolsLabel,
      "toolsCheckbox": toolsCheckbox,
      "status": statusLabel,
      "saveButton": saveButton,
      "testButton": testButton
    ] as [String : Any]

    // 取消按钮处理
    cancelButton.target = self
    cancelButton.action = #selector(closeAIConfig(_:))

    window.contentView = contentView
    window.delegate = self
    aiConfigWindow = window

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func ensureEditMenuAvailable() {
    guard NSApp.mainMenu == nil else { return }

    let mainMenu = NSMenu(title: "MainMenu")

    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu(title: "Squirrel")
    appMenuItem.submenu = appMenu
    appMenu.addItem(withTitle: NSLocalizedString("Quit", comment: "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    mainMenu.addItem(appMenuItem)

    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: NSLocalizedString("Edit", comment: "Edit"))
    editMenuItem.submenu = editMenu

    editMenu.addItem(withTitle: NSLocalizedString("Cut", comment: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: NSLocalizedString("Copy", comment: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: NSLocalizedString("Paste", comment: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: NSLocalizedString("Select All", comment: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    mainMenu.addItem(editMenuItem)
    NSApp.mainMenu = mainMenu
  }

  private func normalizedChatCompletionsURL(from rawValue: String) -> String {
    rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func normalizedGrokResponsesURL(from rawValue: String) -> String {
    rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func isMemorylakeProvider(baseURL: String, model: String) -> Bool {
    let lowerBase = baseURL.lowercased()
    let lowerModel = model.lowercased()
    return lowerBase.contains("117.50.226.120:3002") || lowerBase == memorylakeBaseURL.lowercased() || lowerModel.contains("memorylake")
  }

  private func geminiEndpoint(for model: String) -> String {
    let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedModel = trimmedModel.isEmpty ? "gemini-2.5-flash" : trimmedModel
    return "https://generativelanguage.googleapis.com/v1beta/models/\(resolvedModel):generateContent"
  }

  private func ensureGeminiBaseURL(_ baseURL: String, model: String) -> String {
    return geminiEndpoint(for: model)
  }

  private func isGeminiProvider(baseURL: String, model: String) -> Bool {
    let lowerBase = baseURL.lowercased()
    let lowerModel = model.lowercased()
    return lowerBase.contains("generativelanguage.googleapis.com") || lowerModel.contains("gemini")
  }

  private func isGrokProvider(baseURL: String, model: String) -> Bool {
    let lowerBase = baseURL.lowercased()
    let lowerModel = model.lowercased()
    if lowerBase.contains("api.x.ai") || lowerBase.contains("/responses") {
      return true
    }
    return lowerModel.contains("grok")
  }

  @objc private func providerChanged(_ sender: NSPopUpButton) {
    guard let fields = aiConfigFields,
          let baseURLField = fields["baseURL"] as? NSTextField,
          let apiKeyField = fields["apiKey"] as? NSTextField,
          let modelField = fields["model"] as? NSTextField else {
      return
    }

    let toolsLabel = fields["toolsLabel"] as? NSView
    let toolsCheckbox = fields["toolsCheckbox"] as? NSButton
    let modelPopup = fields["modelPopup"] as? NSPopUpButton

    let defaultOpenAIURL = "https://api.openai.com/v1/chat/completions"
    let grokURL = "https://api.x.ai/v1/responses"
    let defaultOpenAIModel = "gpt-4o-mini"
    let geminiModel = "gemini-2.5-flash"
    let grokModel = "grok-4-fast"
    let trimmedModelValue = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedBaseValue = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowerBaseValue = trimmedBaseValue.lowercased()
    let isGeminiBase = lowerBaseValue.contains("generativelanguage.googleapis.com")
    let isLegacyGrokBase = lowerBaseValue.contains("api.x.ai") && lowerBaseValue.contains("/chat/completions")
    let isGrokBase = lowerBaseValue.contains("api.x.ai") || lowerBaseValue.contains("/responses")

    switch sender.indexOfSelectedItem {
    case 0:
      baseURLField.stringValue = memorylakeBaseURL
      baseURLField.placeholderString = memorylakeBaseURL
      baseURLField.isEnabled = false
      apiKeyField.placeholderString = "Bearer ..."
      if trimmedModelValue.isEmpty || !responsesModelOptions.contains(where: { $0.caseInsensitiveCompare(trimmedModelValue) == .orderedSame }) {
        modelField.stringValue = responsesModelOptions.first ?? grokModel
      }
      modelField.placeholderString = responsesModelOptions.first ?? grokModel
      modelPopup?.isHidden = false
      selectModelPopup(using: modelPopup, with: modelField.stringValue)
      syncModelField(with: modelPopup, field: modelField)
    case 2:
      baseURLField.isEnabled = true
      if trimmedBaseValue.isEmpty || trimmedBaseValue == defaultOpenAIURL || isGeminiBase || isLegacyGrokBase {
        baseURLField.stringValue = grokURL
      }
      if modelField.stringValue.isEmpty || modelField.stringValue == defaultOpenAIModel || modelField.stringValue == geminiModel {
        modelField.stringValue = grokModel
      }
      baseURLField.placeholderString = grokURL
      apiKeyField.placeholderString = "xai-..."
      modelField.placeholderString = grokModel
      modelPopup?.isHidden = false
      selectModelPopup(using: modelPopup, with: modelField.stringValue)
      syncModelField(with: modelPopup, field: modelField)
    case 1:
      baseURLField.isEnabled = true
      if trimmedBaseValue.isEmpty || isGeminiBase || isGrokBase {
        baseURLField.stringValue = defaultOpenAIURL
      }
      if modelField.stringValue.isEmpty || modelField.stringValue == geminiModel || modelField.stringValue == grokModel {
        modelField.stringValue = defaultOpenAIModel
      }
      baseURLField.placeholderString = defaultOpenAIURL
      apiKeyField.placeholderString = "sk-..."
      modelField.placeholderString = defaultOpenAIModel
      modelField.isEditable = true
      modelPopup?.isHidden = true
    default:
      baseURLField.isEnabled = true
      let resolvedModel: String
      if trimmedModelValue.isEmpty || trimmedModelValue == defaultOpenAIModel || trimmedModelValue == grokModel {
        resolvedModel = geminiModel
        modelField.stringValue = resolvedModel
      } else {
        resolvedModel = trimmedModelValue
      }
      let suggestedGeminiURL = geminiEndpoint(for: resolvedModel)
      let baseMatchesResolvedModel = trimmedBaseValue.lowercased().contains(resolvedModel.lowercased())
      if trimmedBaseValue.isEmpty ||
          trimmedBaseValue == defaultOpenAIURL ||
          trimmedBaseValue == grokURL ||
           !baseMatchesResolvedModel {
        baseURLField.stringValue = suggestedGeminiURL
      }
      baseURLField.placeholderString = suggestedGeminiURL
      apiKeyField.placeholderString = "AIza..."
      modelField.placeholderString = geminiModel
      modelPopup?.isHidden = true
      modelField.isEditable = true
    }

    let shouldShowTools = sender.indexOfSelectedItem == 2 || sender.indexOfSelectedItem == 0
    toolsLabel?.isHidden = !shouldShowTools
    toolsCheckbox?.isHidden = !shouldShowTools
  }

  @objc private func modelOptionChanged(_ sender: NSPopUpButton) {
    guard let fields = aiConfigFields,
          let modelField = fields["model"] as? NSTextField else {
      return
    }
    syncModelField(with: sender, field: modelField)
  }

  private func selectModelPopup(using popup: NSPopUpButton?, with value: String) {
    guard let popup else { return }
    if let idx = responsesModelOptions.firstIndex(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
      popup.selectItem(at: idx)
    } else {
      popup.selectItem(withTitle: "自定义")
    }
  }

  private func syncModelField(with popup: NSPopUpButton?, field: NSTextField) {
    guard let popup, !popup.isHidden else {
      field.isEditable = true
      field.isSelectable = true
      return
    }
    let title = popup.titleOfSelectedItem ?? ""
    if responsesModelOptions.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
      field.stringValue = title
      field.isEditable = false
    } else {
      field.isEditable = true
    }
  }

  @objc private func saveAIConfig(_ sender: NSButton) {
    guard let fields = aiConfigFields,
          let baseURLField = fields["baseURL"] as? NSTextField,
          let apiKeyField = fields["apiKey"] as? NSTextField,
          let modelField = fields["model"] as? NSTextField,
          let statusLabel = fields["status"] as? NSTextField else {
      return
    }

    let toolsCheckbox = fields["toolsCheckbox"] as? NSButton
    let providerPopup = fields["provider"] as? NSPopUpButton
    let modelPopup = fields["modelPopup"] as? NSPopUpButton

    let baseURL = baseURLField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    let apiKey = apiKeyField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    let model = modelField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    let defaults = UserDefaults.standard

    // 验证输入
    if baseURL.isEmpty || apiKey.isEmpty || model.isEmpty {
      statusLabel.stringValue = "请填写所有字段"
      statusLabel.textColor = NSColor.systemRed
      return
    }

    let isGemini = isGeminiProvider(baseURL: baseURL, model: model)
    let isMemorylake = !isGemini && isMemorylakeProvider(baseURL: baseURL, model: model)
    let isGrok = !isGemini && !isMemorylake && isGrokProvider(baseURL: baseURL, model: model)
    let isResponsesPreset = providerPopup?.indexOfSelectedItem == 2 || providerPopup?.indexOfSelectedItem == 0 || isGrok || isMemorylake
    let normalizedBaseURL: String
    if isMemorylake {
      normalizedBaseURL = memorylakeBaseURL
      baseURLField.stringValue = memorylakeBaseURL
    } else if isGemini {
      normalizedBaseURL = ensureGeminiBaseURL(baseURL, model: model)
    } else if isGrok {
      normalizedBaseURL = normalizedGrokResponsesURL(from: baseURL)
    } else {
      normalizedBaseURL = normalizedChatCompletionsURL(from: baseURL)
    }
    baseURLField.stringValue = normalizedBaseURL

    // 生成配置文件
    let configContent = """
    # ai_pinyin.custom.yaml
    # AI 拼音输入方案自定义配置
    # 通过 AI 配置界面生成

    patch:
      # AI 补全配置
      ai_completion/enabled: true
      ai_completion/trigger_key: "Tab"

      # AI 模型配置
      ai_completion/base_url: "\(normalizedBaseURL)"
      ai_completion/api_key: "\(apiKey)"
      ai_completion/model_name: "\(model)"

      # 上下文配置
      ai_completion/context_window_minutes: 10
      ai_completion/max_candidates: 3

      # 按键绑定配置
      key_binder/bindings:
        - { when: composing, accept: Tab, send: Tab }
        - { when: composing, accept: Shift+Tab, send: Shift+Tab }
    """

    let configPath = SquirrelApp.userDir.appending(component: "ai_pinyin.custom.yaml")
    let toolsPath = SquirrelApp.userDir.appending(component: "ai_pinyin.tools.json")
    let shouldEnableTools = (toolsCheckbox?.state == .on) && isResponsesPreset
    let toolsConfig = shouldEnableTools ? "[{\"type\":\"web_search\"}]" : ""

    do {
      try configContent.write(to: configPath, atomically: true, encoding: String.Encoding.utf8)

      defaults.set(normalizedBaseURL, forKey: "AIBaseURL")
      defaults.set(apiKey, forKey: "AIApiKey")
      defaults.set(model, forKey: "AIModelName")
      if let modelPopup = modelPopup, !modelPopup.isHidden {
        defaults.set(modelPopup.indexOfSelectedItem, forKey: "AIModelPresetIndex")
      }

      if isResponsesPreset && shouldEnableTools {
        try toolsConfig.write(to: toolsPath, atomically: true, encoding: .utf8)
        defaults.set(toolsConfig, forKey: "AIToolsConfig")
      } else {
        if FileManager.default.fileExists(atPath: toolsPath.path) {
          try? FileManager.default.removeItem(at: toolsPath)
        }
        defaults.removeObject(forKey: "AIToolsConfig")
      }

      statusLabel.stringValue = "配置已保存，请重新部署 Squirrel"
      statusLabel.textColor = NSColor.systemGreen

      // 延迟关闭窗口
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        self?.closeAIConfig(sender)
      }
    } catch {
      statusLabel.stringValue = "保存失败: \(error.localizedDescription)"
      statusLabel.textColor = NSColor.systemRed
    }
  }

  @objc private func testAIConfig(_ sender: NSButton) {
    guard let fields = aiConfigFields,
          let baseURLField = fields["baseURL"] as? NSTextField,
          let apiKeyField = fields["apiKey"] as? NSTextField,
          let modelField = fields["model"] as? NSTextField,
          let statusLabel = fields["status"] as? NSTextField,
          let saveButton = fields["saveButton"] as? NSButton,
          let testButton = fields["testButton"] as? NSButton else {
      return
    }

    let toolsCheckbox = fields["toolsCheckbox"] as? NSButton
    let providerPopup = fields["provider"] as? NSPopUpButton
    let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !baseURL.isEmpty, !apiKey.isEmpty, !model.isEmpty else {
      statusLabel.stringValue = "请先填写 Base URL、API Key 和模型"
      statusLabel.textColor = .systemRed
      return
    }

    let isGemini = isGeminiProvider(baseURL: baseURL, model: model)
    let isMemorylake = !isGemini && isMemorylakeProvider(baseURL: baseURL, model: model)
    let isGrok = !isGemini && !isMemorylake && isGrokProvider(baseURL: baseURL, model: model)
    let isResponsesLike = isGrok || isMemorylake || providerPopup?.indexOfSelectedItem == 2 || providerPopup?.indexOfSelectedItem == 0
    let shouldSendTools = isResponsesLike && (toolsCheckbox?.state == .on)
    let normalizedBaseURL: String
    if isMemorylake {
      normalizedBaseURL = memorylakeBaseURL
      baseURLField.stringValue = memorylakeBaseURL
    } else if isGemini {
      normalizedBaseURL = ensureGeminiBaseURL(baseURL, model: model)
    } else if isGrok {
      normalizedBaseURL = normalizedGrokResponsesURL(from: baseURL)
    } else {
      normalizedBaseURL = normalizedChatCompletionsURL(from: baseURL)
    }
    baseURLField.stringValue = normalizedBaseURL

    guard let url = URL(string: normalizedBaseURL) else {
      statusLabel.stringValue = "Base URL 无效"
      statusLabel.textColor = .systemRed
      return
    }

    statusLabel.stringValue = "测试中..."
    statusLabel.textColor = .secondaryLabelColor
    saveButton.isEnabled = false
    testButton.isEnabled = false

    let payload: [String: Any]
    if isGemini {
      payload = [
        "contents": [
          [
            "role": "user",
            "parts": [
              ["text": "ping"]
            ]
          ]
        ],
        "generationConfig": [
          "maxOutputTokens": 64
        ]
      ]
    } else if isResponsesLike {
      var responsesPayload: [String: Any] = [
        "model": model,
        "input": [
          [
            "role": "user",
            "content": "ping"
          ]
        ]
      ]
      if shouldSendTools {
        responsesPayload["tools"] = [
          ["type": "web_search"]
        ]
      }
      payload = responsesPayload
    } else {
      payload = [
        "model": model,
        "messages": [
          ["role": "user", "content": "ping"]
        ],
        "temperature": 0,
        "max_tokens": 32
      ]
    }

    guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
      statusLabel.stringValue = "无法创建测试请求"
      statusLabel.textColor = .systemRed
      saveButton.isEnabled = true
      testButton.isEnabled = true
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if isGemini {
      request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
    } else {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    request.timeoutInterval = 8
    request.httpBody = body

    var sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.timeoutIntervalForRequest = 8
    sessionConfig.timeoutIntervalForResource = 10
    let session = URLSession(configuration: sessionConfig)

    let task = session.dataTask(with: request) { data, response, error in
      DispatchQueue.main.async {
        saveButton.isEnabled = true
        testButton.isEnabled = true

        if let error = error {
          statusLabel.stringValue = "连接失败：\(error.localizedDescription)"
          statusLabel.textColor = .systemRed
          return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
          statusLabel.stringValue = "连接失败：未知响应"
          statusLabel.textColor = .systemRed
          return
        }

        guard httpResponse.statusCode == 200, let data = data else {
          statusLabel.stringValue = "连接失败：HTTP \(httpResponse.statusCode)"
          statusLabel.textColor = .systemRed
          return
        }

        var preview = ""
        var hasChoices = false
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
          if isGemini {
            if let candidates = json["candidates"] as? [[String: Any]] {
              hasChoices = !candidates.isEmpty
              if let first = candidates.first,
                 let contentDict = first["content"] as? [String: Any],
                 let parts = contentDict["parts"] as? [[String: Any]] {
                for part in parts {
                  if let text = part["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                      preview = trimmed
                      break
                    }
                  }
                }
              }
            }
          } else if isResponsesLike {
            if let outputs = json["output_text"] as? [String] {
              hasChoices = !outputs.isEmpty
              if let first = outputs.first {
                preview = first.trimmingCharacters(in: .whitespacesAndNewlines)
              }
            }
            if preview.isEmpty, let outputBlocks = json["output"] as? [[String: Any]] {
              hasChoices = hasChoices || !outputBlocks.isEmpty
              outer: for block in outputBlocks {
                if let contents = block["content"] as? [[String: Any]] {
                  for entry in contents {
                    if let text = entry["text"] as? String {
                      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                      if !trimmed.isEmpty {
                        preview = trimmed
                        break outer
                      }
                    }
                  }
                }
              }
            }
          } else if let choices = json["choices"] as? [[String: Any]] {
            hasChoices = !choices.isEmpty
            if let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
              preview = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
          }
        }

        if preview.isEmpty {
          if hasChoices {
            statusLabel.stringValue = "连接成功：HTTP 200 (响应无文本，尝试提高 max_tokens)"
            statusLabel.textColor = .systemOrange
          } else {
            statusLabel.stringValue = "连接失败：未返回内容"
            statusLabel.textColor = .systemRed
          }
        } else {
          let snippet = preview.count > 30 ? String(preview.prefix(30)) + "…" : preview
          statusLabel.stringValue = "连接成功：\(snippet)"
          statusLabel.textColor = .systemGreen
        }
      }
    }

    task.resume()
  }

  @objc private func closeAIConfig(_ sender: Any) {
    aiConfigWindow?.close()
    aiConfigWindow = nil
    aiConfigFields = nil
  }

  func windowWillClose(_ notification: Notification) {
    if notification.object as? NSWindow === aiConfigWindow {
      aiConfigWindow = nil
      aiConfigFields = nil
    }
  }

  static func showMessage(msgText: String?) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .provisional]) { _, error in
      if let error = error {
        print("User notification authorization error: \(error.localizedDescription)")
      }
    }
    center.getNotificationSettings { settings in
      if (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) && settings.alertSetting == .enabled {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Squirrel", comment: "")
        if let msgText = msgText {
          content.subtitle = msgText
        }
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil)
        center.add(request) { error in
          if let error = error {
            print("User notification request error: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  func setupRime() {
    createDirIfNotExist(path: SquirrelApp.userDir)
    createDirIfNotExist(path: SquirrelApp.logDir)
    // swiftlint:disable identifier_name
    let notification_handler: @convention(c) (UnsafeMutableRawPointer?, RimeSessionId, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = notificationHandler
    let context_object = Unmanaged.passUnretained(self).toOpaque()
    // swiftlint:enable identifier_name
    rimeAPI.set_notification_handler(notification_handler, context_object)

    var squirrelTraits = RimeTraits.rimeStructInit()
    squirrelTraits.setCString(Bundle.main.sharedSupportPath!, to: \.shared_data_dir)
    squirrelTraits.setCString(SquirrelApp.userDir.path(), to: \.user_data_dir)
    squirrelTraits.setCString(SquirrelApp.logDir.path(), to: \.log_dir)
    squirrelTraits.setCString("Squirrel", to: \.distribution_code_name)
    squirrelTraits.setCString("鼠鬚管", to: \.distribution_name)
    squirrelTraits.setCString(Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String, to: \.distribution_version)
    squirrelTraits.setCString("rime.squirrel", to: \.app_name)
    rimeAPI.setup(&squirrelTraits)
  }

  func startRime(fullCheck: Bool) {
    print("Initializing la rime...")
    rimeAPI.initialize(nil)
    // check for configuration updates
    if rimeAPI.start_maintenance(fullCheck) {
      // update squirrel config
      // print("[DEBUG] maintenance suceeds")
      _ = rimeAPI.deploy_config_file("squirrel.yaml", "config_version")
    } else {
      // print("[DEBUG] maintenance fails")
    }
  }

  func loadSettings() {
    config = SquirrelConfig()
    if !config!.openBaseConfig() {
      return
    }

    enableNotifications = config!.getString("show_notifications_when") != "never"
    if let panel = panel, let config = self.config {
      panel.load(config: config, forDarkMode: false)
      panel.load(config: config, forDarkMode: true)
    }
  }

  func loadSettings(for schemaID: String) {
    if schemaID.count == 0 || schemaID.first == "." {
      return
    }
    let schema = SquirrelConfig()
    if let panel = panel, let config = self.config {
      if schema.open(schemaID: schemaID, baseConfig: config) && schema.has(section: "style") {
        panel.load(config: schema, forDarkMode: false)
        panel.load(config: schema, forDarkMode: true)
      } else {
        panel.load(config: config, forDarkMode: false)
        panel.load(config: config, forDarkMode: true)
      }
    }
    schema.close()
  }

  // prevent freezing the system
  func problematicLaunchDetected() -> Bool {
    var detected = false
    let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("squirrel_launch.json", conformingTo: .json)
    // print("[DEBUG] archive: \(logFile)")
    do {
      let archive = try Data(contentsOf: logFile, options: [.uncached])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .millisecondsSince1970
      let previousLaunch = try decoder.decode(Date.self, from: archive)
      if previousLaunch.timeIntervalSinceNow >= -2 {
        detected = true
      }
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {

    } catch {
      print("Error occurred during processing launch time archive: \(error.localizedDescription)")
      return detected
    }
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .millisecondsSince1970
      let record = try encoder.encode(Date.now)
      try record.write(to: logFile)
    } catch {
      print("Error occurred during saving launch time to archive: \(error.localizedDescription)")
    }
    return detected
  }

  // add an awakeFromNib item so that we can set the action method.  Note that
  // any menuItems without an action will be disabled when displayed in the Text
  // Input Menu.
  func addObservers() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: nil, using: workspaceWillPowerOff)

    let notifCenter = DistributedNotificationCenter.default()
    notifCenter.addObserver(forName: .init("SquirrelReloadNotification"), object: nil, queue: nil, using: rimeNeedsReload)
    notifCenter.addObserver(forName: .init("SquirrelSyncNotification"), object: nil, queue: nil, using: rimeNeedsSync)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    print("Squirrel is quitting.")
    rimeAPI.cleanup_all_sessions()
    return .terminateNow
  }

}

private func notificationHandler(contextObject: UnsafeMutableRawPointer?, sessionId: RimeSessionId, messageTypeC: UnsafePointer<CChar>?, messageValueC: UnsafePointer<CChar>?) {
  let delegate: SquirrelApplicationDelegate = Unmanaged<SquirrelApplicationDelegate>.fromOpaque(contextObject!).takeUnretainedValue()

  let messageType = messageTypeC.map { String(cString: $0) }
  let messageValue = messageValueC.map { String(cString: $0) }
  if messageType == "deploy" {
    switch messageValue {
    case "start":
      SquirrelApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_start", comment: ""))
    case "success":
      SquirrelApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_success", comment: ""))
    case "failure":
      SquirrelApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_failure", comment: ""))
    default:
      break
    }
    return
  }
  // off
  if !delegate.enableNotifications {
    return
  }

  if messageType == "schema", let messageValue = messageValue, let schemaName = try? /^[^\/]*\/(.*)$/.firstMatch(in: messageValue)?.output.1 {
    delegate.showStatusMessage(msgTextLong: String(schemaName), msgTextShort: String(schemaName))
    return
  } else if messageType == "option" {
    let state = messageValue?.first != "!"
    let optionName = if state {
      messageValue
    } else {
      String(messageValue![messageValue!.index(after: messageValue!.startIndex)...])
    }
    if let optionName = optionName {
      optionName.withCString { name in
        let stateLabelLong = delegate.rimeAPI.get_state_label_abbreviated(sessionId, name, state, false)
        let stateLabelShort = delegate.rimeAPI.get_state_label_abbreviated(sessionId, name, state, true)
        let longLabel = stateLabelLong.str.map { String(cString: $0) }
        let shortLabel = stateLabelShort.str.map { String(cString: $0) }
        delegate.showStatusMessage(msgTextLong: longLabel, msgTextShort: shortLabel)
      }
    }
  }
}

private extension SquirrelApplicationDelegate {
  func showStatusMessage(msgTextLong: String?, msgTextShort: String?) {
    if !(msgTextLong ?? "").isEmpty || !(msgTextShort ?? "").isEmpty {
      panel?.updateStatus(long: msgTextLong ?? "", short: msgTextShort ?? "")
    }
  }

  func shutdownRime() {
    config?.close()
    rimeAPI.finalize()
  }

  func workspaceWillPowerOff(_: Notification) {
    print("Finalizing before logging out.")
    self.shutdownRime()
  }

  func rimeNeedsReload(_: Notification) {
    print("Reloading rime on demand.")
    self.deploy()
  }

  func rimeNeedsSync(_: Notification) {
    print("Sync rime on demand.")
    self.syncUserData()
  }

  func createDirIfNotExist(path: URL) {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: path.path()) {
      do {
        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
      } catch {
        print("Error creating user data directory: \(path.path())")
      }
    }
  }
}

extension NSApplication {
  var squirrelAppDelegate: SquirrelApplicationDelegate {
    self.delegate as! SquirrelApplicationDelegate
  }
}
