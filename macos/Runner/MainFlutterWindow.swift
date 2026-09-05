import Cocoa
import FlutterMacOS

/// Flutter の表示と手動リサイズに対応するメインウィンドウ。
class MainFlutterWindow: NSWindow {
  /// Nib の枠寸法を引き継いで Flutter とプラグインを初期化する。
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // 通常のドラッグによるサイズ変更を維持し、ウィンドウ操作は手動リサイズへ集約する
    collectionBehavior.remove(.fullScreenPrimary)
  }

  /// ウィンドウを前面へ出し、ズームボタンを非表示にする。
  /// - Parameter sender: ウィンドウを表示する操作の送信元
  override func makeKeyAndOrderFront(_ sender: Any?) {
    super.makeKeyAndOrderFront(sender)

    // プラグインによるタイトルバー初期化後も、表示のたびに手動リサイズ専用のボタン配置へ戻す
    standardWindowButton(.zoomButton)?.isHidden = true
  }

  /// マウスポインターがある画面の中央へウィンドウを移動する。
  func centerOnPointerScreen() {
    let pointerLocation = NSEvent.mouseLocation
    let targetScreen = NSScreen.screens.first { $0.frame.contains(pointerLocation) } ?? NSScreen.main
    if let visibleFrame = targetScreen?.visibleFrame {
      let centeredOrigin = NSPoint(
        x: visibleFrame.midX - frame.width / 2,
        y: visibleFrame.midY - frame.height / 2
      )
      setFrameOrigin(centeredOrigin)
    }
  }

  /// ズーム操作を受けても手動で指定されたウィンドウ寸法を保つ。
  /// - Parameter sender: ズーム操作の送信元
  override func zoom(_ sender: Any?) {
    // 手動リサイズの寸法を保ち、緑のズーム操作後も現在の枠を維持する
  }

  /// フルスクリーン操作を受けても通常ウィンドウの表示を保つ。
  /// - Parameter sender: フルスクリーン操作の送信元
  override func toggleFullScreen(_ sender: Any?) {
    // 通常ウィンドウとして扱い、メニュー操作後も現在の表示形態を保つ
  }
}
