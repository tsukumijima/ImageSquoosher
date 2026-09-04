import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
  private enum Configuration {
    static let appGroupIdentifier = "Q857TCRGS2.net.tsukumijima.image-squoosher"
    static let selectedImageURLsKey = "finderSelectedImageURLs"
    static let applicationURL = "imagesquoosher://finder-selection"
    static let menuItemTitle = "ImageSquoosher で圧縮・リサイズ"
    static let supportedImageExtensions: Set<String> = [
      "jpeg",
      "jpg",
      "png",
      "webp",
    ]
  }

  // Finder 上の選択を本体アプリへ渡すため、両方のターゲットで共有する領域を使う
  private let sharedDefaults = UserDefaults(suiteName: Configuration.appGroupIdentifier)

  override init() {
    super.init()

    // ローカル、iCloud Drive、外付けボリュームを同じメニューで扱えるよう、ルートから監視する
    FIFinderSyncController.default().directoryURLs = Set([URL(fileURLWithPath: "/")])
    NSLog("Finder Sync extension initialized.")
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    // Finder のツールバーやフォルダ背景へ項目を足さず、ファイルの右クリックだけを拡張する
    guard menuKind == .contextualMenuForItems,
          supportedImageURLs(from: FIFinderSyncController.default().selectedItemURLs()).isEmpty == false else {
      return nil
    }

    let menu = NSMenu(title: "")
    let menuItem = NSMenuItem(
      title: Configuration.menuItemTitle,
      action: #selector(openImageSquoosher(_:)),
      keyEquivalent: ""
    )
    // Finder Sync のインスタンスへ直接送ることで、拡張のレスポンダーチェーンに依存せず選択を開く
    menuItem.target = self
    menu.addItem(menuItem)
    return menu
  }

  @IBAction private func openImageSquoosher(_ sender: Any?) {
    let selectedImageURLs = supportedImageURLs(
      from: FIFinderSyncController.default().selectedItemURLs()
    )
    guard selectedImageURLs.isEmpty == false else {
      return
    }

    // 選択 URL を先に共有領域へ保存してから本体を起動し、本体の起動順序に依存しない受け渡しにする
    sharedDefaults?.set(selectedImageURLs.map(\.path), forKey: Configuration.selectedImageURLsKey)
    sharedDefaults?.synchronize()

    guard let applicationURL = applicationURL(for: selectedImageURLs) else {
      NSLog("Failed to create ImageSquoosher launch URL.")
      return
    }

    // Finder の実行結果をすぐ確認できるよう、本体を通常の macOS アクティベーションで開く
    let openConfiguration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open(applicationURL, configuration: openConfiguration) { _, error in
      if let error {
        NSLog("Failed to open ImageSquoosher: %@", error.localizedDescription)
        return
      }

      NSLog("Sent selected image URLs to ImageSquoosher: %ld", selectedImageURLs.count)
    }
  }

  /// App Group を使えない Debug 署名では、選択パスを起動 URL の query へ載せる。
  private func applicationURL(for selectedImageURLs: [URL]) -> URL? {
    #if DEBUG
    guard var components = URLComponents(string: Configuration.applicationURL) else {
      return nil
    }
    components.queryItems = selectedImageURLs.map { URLQueryItem(name: "path", value: $0.path) }
    return components.url
    #else
    return URL(string: Configuration.applicationURL)
    #endif
  }

  /// Finder の選択から画像として処理できる URL だけを取り出す。
  private func supportedImageURLs(from urls: [URL]?) -> [URL] {
    return (urls ?? []).filter { url in
      Configuration.supportedImageExtensions.contains(url.pathExtension.lowercased())
    }
  }
}
