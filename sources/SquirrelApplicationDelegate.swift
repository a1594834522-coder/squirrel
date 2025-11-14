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

  func openAIConfig() {
    // 如果窗口已经存在，直接显示
    if let window = aiConfigWindow {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    // 创建配置窗口
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 280),
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
    var currentBaseURL = "https://api.openai.com/v1/chat/completions"
    var currentAPIKey = ""
    var currentModel = "gpt-4o-mini"

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

    // 创建标签和输入框
    let yStart: CGFloat = 220
    let labelWidth: CGFloat = 120
    let fieldWidth: CGFloat = 340
    let rowHeight: CGFloat = 60

    // Base URL
    let baseURLLabel = NSTextField(labelWithString: "API Base URL:")
    baseURLLabel.frame = NSRect(x: 20, y: yStart, width: labelWidth, height: 20)
    baseURLLabel.alignment = .right
    contentView.addSubview(baseURLLabel)

    let baseURLField = NSTextField(string: currentBaseURL)
    baseURLField.frame = NSRect(x: 150, y: yStart - 5, width: fieldWidth, height: 24)
    baseURLField.placeholderString = "https://api.openai.com/v1/chat/completions"
    contentView.addSubview(baseURLField)

    // API Key
    let apiKeyLabel = NSTextField(labelWithString: "API Key:")
    apiKeyLabel.frame = NSRect(x: 20, y: yStart - rowHeight, width: labelWidth, height: 20)
    apiKeyLabel.alignment = .right
    contentView.addSubview(apiKeyLabel)

    let apiKeyField = NSSecureTextField(string: currentAPIKey)
    apiKeyField.frame = NSRect(x: 150, y: yStart - rowHeight - 5, width: fieldWidth, height: 24)
    apiKeyField.placeholderString = "sk-..."
    contentView.addSubview(apiKeyField)

    // Model Name
    let modelLabel = NSTextField(labelWithString: "模型名称:")
    modelLabel.frame = NSRect(x: 20, y: yStart - rowHeight * 2, width: labelWidth, height: 20)
    modelLabel.alignment = .right
    contentView.addSubview(modelLabel)

    let modelField = NSTextField(string: currentModel)
    modelField.frame = NSRect(x: 150, y: yStart - rowHeight * 2 - 5, width: fieldWidth, height: 24)
    modelField.placeholderString = "gpt-4o-mini"
    contentView.addSubview(modelField)

    // 状态标签
    let statusLabel = NSTextField(labelWithString: "")
    statusLabel.frame = NSRect(x: 20, y: 50, width: 460, height: 20)
    statusLabel.alignment = .center
    statusLabel.textColor = .systemGreen
    contentView.addSubview(statusLabel)

    // 保存按钮
    let saveButton = NSButton(title: "保存", target: nil, action: nil)
    saveButton.frame = NSRect(x: 300, y: 15, width: 80, height: 32)
    saveButton.bezelStyle = .rounded
    saveButton.keyEquivalent = "\r"
    contentView.addSubview(saveButton)

    // 取消按钮
    let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    cancelButton.frame = NSRect(x: 390, y: 15, width: 80, height: 32)
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1b}"
    contentView.addSubview(cancelButton)

    // 保存按钮处理
    saveButton.target = self
    saveButton.action = #selector(saveAIConfig(_:))
    saveButton.tag = 0

    // 存储字段引用
    aiConfigFields = [
      "baseURL": baseURLField,
      "apiKey": apiKeyField,
      "model": modelField,
      "status": statusLabel
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

  @objc private func saveAIConfig(_ sender: NSButton) {
    guard let fields = aiConfigFields,
          let baseURLField = fields["baseURL"] as? NSTextField,
          let apiKeyField = fields["apiKey"] as? NSSecureTextField,
          let modelField = fields["model"] as? NSTextField,
          let statusLabel = fields["status"] as? NSTextField else {
      return
    }

    let baseURL = baseURLField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    let apiKey = apiKeyField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    let model = modelField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

    // 验证输入
    if baseURL.isEmpty || apiKey.isEmpty || model.isEmpty {
      statusLabel.stringValue = "请填写所有字段"
      statusLabel.textColor = NSColor.systemRed
      return
    }

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
      ai_completion/base_url: "\(baseURL)"
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

    do {
      try configContent.write(to: configPath, atomically: true, encoding: String.Encoding.utf8)
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
