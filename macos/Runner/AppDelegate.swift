import Cocoa
import FinderSync
import FlutterMacOS

@main
/// アプリの起動と Finder の選択受信、ファイル日時の複製を処理する。
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

  /// Flutter の起動後に Finder 連携チャネルを登録する。
  /// - Parameter notification: アプリの起動完了通知
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

  /// 起動 URL から Finder の選択を受け取り、Flutter へ渡す。
  /// - Parameter application: URL を受け取ったアプリ
  /// - Parameter urls: OS から渡された起動 URL の一覧
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
    let storedPaths = takeSelectedImageURLs()
    let receivedPaths = queryPaths.isEmpty ? storedPaths : queryPaths
    // 続けて届いた URL が消費済みの共有領域を参照しても、未送信の選択を保持する
    guard receivedPaths.isEmpty == false else {
      return
    }
    pendingSelectedImageURLs = receivedPaths
    sendPendingSelectedImageURLs()
  }

  /// 最後のウィンドウを閉じたときにアプリも終了する。
  /// - Parameter sender: 終了条件を問い合わせたアプリ
  /// - Returns: ウィンドウを閉じた後に終了するための true
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  /// ウィンドウ状態の安全な復元に対応する。
  /// - Parameter app: 復元への対応を問い合わせたアプリ
  /// - Returns: 安全な復元を有効にする true
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Finder Sync の状態確認と選択 URL の受け取りを処理する。
  /// - Parameter call: Dart からのメソッド名と引数
  /// - Parameter result: 成功値または FlutterError を返すコールバック
  private func handleFinderSyncMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isFinderSyncExtensionEnabled":
      result(FIFinderSyncController.isExtensionEnabled)
    case "showFinderSyncExtensionManagement":
      FIFinderSyncController.showExtensionManagementInterface()
      result(nil)
    case "getFinderSelectedImageURLs":
      // 共有領域は URL イベントで消費し、初期取得では本体が受信済みの選択だけを渡す
      let selectedImageURLs = pendingSelectedImageURLs
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
  /// - Parameter url: 起動時に渡された URL
  /// - Returns: スキームとホストが Finder 選択用の値に一致するかどうか
  private func isFinderSelectionURL(_ url: URL) -> Bool {
    return url.scheme == Configuration.finderSelectionScheme &&
      url.host == Configuration.finderSelectionHost
  }

  /// App Group の選択を消費し、通常起動時には空の一覧から開始できるようにする。
  /// - Returns: 共有領域から取り出したパスの一覧 (未保存なら空の一覧)
  private func takeSelectedImageURLs() -> [String] {
    let defaults = UserDefaults(suiteName: Configuration.appGroupIdentifier)
    let selectedImageURLs = defaults?.stringArray(forKey: Configuration.selectedImageURLsKey) ?? []
    // URL イベントを受け取った時点で、選択を本体のメモリへ移す
    defaults?.removeObject(forKey: Configuration.selectedImageURLsKey)
    return selectedImageURLs
  }

  /// 元ファイルの作成日時と更新日時を出力ファイルへ複製する。
  /// - Parameter call: sourcePath と outputPath を含むリクエスト
  /// - Parameter result: 成功時は nil、失敗時は FlutterError を返すコールバック
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
