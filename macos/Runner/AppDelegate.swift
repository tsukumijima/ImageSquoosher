import Cocoa
import FinderSync
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private enum Configuration {
    static let appGroupIdentifier = "Q857TCRGS2.net.tsukumijima.image-squoosher"
    static let finderSelectionHost = "finder-selection"
    static let finderSelectionScheme = "imagesquoosher"
    static let finderSyncChannelName = "net.tsukumijima.image-squoosher/finder_sync"
    static let selectedImageURLsKey = "finderSelectedImageURLs"
  }

  // 起動直後の URL イベントも Flutter の初期化後に通知できるよう、一時的に保持する
  private var pendingSelectedImageURLs: [String] = []
  private var finderSyncChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      NSLog("Flutter view controller is unavailable.")
      return
    }

    // Finder 拡張の有効状態と選択 URL を、Dart 側が同じ MethodChannel から取得できるようにする
    let finderSyncChannel = FlutterMethodChannel(
      name: Configuration.finderSyncChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    finderSyncChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleFinderSyncMethodCall(call, result: result)
    }
    self.finderSyncChannel = finderSyncChannel

    sendPendingSelectedImageURLs()
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    super.application(application, open: urls)

    // カスタム URL 以外の起動要求は Flutter プラグインへ委ね、Finder 拡張用の URL だけを処理する
    guard urls.contains(where: isFinderSelectionURL) else {
      return
    }

    let queryPaths = urls
      .filter(isFinderSelectionURL)
      .flatMap { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?
          .filter { $0.name == "path" }
          .compactMap(\.value) ?? []
      }
    pendingSelectedImageURLs = queryPaths.isEmpty ? selectedImageURLs() : queryPaths
    sendPendingSelectedImageURLs()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Finder Sync の状態確認と選択 URL の受け取りを処理する。
  private func handleFinderSyncMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isFinderSyncExtensionEnabled":
      result(FIFinderSyncController.isExtensionEnabled)
    case "showFinderSyncExtensionManagement":
      FIFinderSyncController.showExtensionManagementInterface()
      result(nil)
    case "getFinderSelectedImageURLs":
      let selectedImageURLs = selectedImageURLs()
      // Finder からの起動時だけ前回の選択を引き渡すため、取得済みの値は共有領域から取り除く
      UserDefaults(suiteName: Configuration.appGroupIdentifier)?.removeObject(
        forKey: Configuration.selectedImageURLsKey
      )
      pendingSelectedImageURLs = []
      result(selectedImageURLs)
    case "copySourceFileDatesToOutputFile":
      copySourceFileDatesToOutputFile(call, result: result)
    case "centerOnPointerScreen":
      guard let window = mainFlutterWindow as? MainFlutterWindow else {
        result(FlutterError(code: "WINDOW_UNAVAILABLE", message: "Main window is unavailable.", details: nil))
        return
      }
      window.centerOnPointerScreen()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Finder 拡張が使うカスタム URL だけを受け付ける。
  private func isFinderSelectionURL(_ url: URL) -> Bool {
    return url.scheme == Configuration.finderSelectionScheme &&
      url.host == Configuration.finderSelectionHost
  }

  /// App Group から最後に選択された画像 URL を読み出す。
  private func selectedImageURLs() -> [String] {
    return UserDefaults(suiteName: Configuration.appGroupIdentifier)?
      .stringArray(forKey: Configuration.selectedImageURLsKey) ?? []
  }

  /// 元ファイルの作成日時と更新日時を出力ファイルへ複製する。
  private func copySourceFileDatesToOutputFile(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let sourcePath = arguments["sourcePath"] as? String,
          let outputPath = arguments["outputPath"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing sourcePath or outputPath.", details: nil))
      return
    }

    let sourceURL = URL(fileURLWithPath: sourcePath)
    var outputURL = URL(fileURLWithPath: outputPath)

    do {
      // URLResourceValues を使い、作成日時と更新日時だけを出力ファイルへ反映する
      let sourceResourceValues = try sourceURL.resourceValues(forKeys: [
        .creationDateKey,
        .contentModificationDateKey,
      ])
      var outputResourceValues = URLResourceValues()
      outputResourceValues.creationDate = sourceResourceValues.creationDate
      outputResourceValues.contentModificationDate = sourceResourceValues.contentModificationDate
      try outputURL.setResourceValues(outputResourceValues)
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "COPY_FILE_DATES_FAILED",
          message: "Failed to copy source file dates.",
          details: error.localizedDescription
        )
      )
    }
  }

  /// Flutter の MethodChannel が準備済みの場合に、Finder からの選択 URL を通知する。
  private func sendPendingSelectedImageURLs() {
    guard let finderSyncChannel,
          pendingSelectedImageURLs.isEmpty == false else {
      return
    }

    let selectedImageURLs = pendingSelectedImageURLs
    pendingSelectedImageURLs = []
    finderSyncChannel.invokeMethod(
      "finderSelectedImageURLs",
      arguments: selectedImageURLs
    )
  }
}
