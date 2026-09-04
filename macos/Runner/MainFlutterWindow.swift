import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // 通常のドラッグによるサイズ変更を維持し、ウィンドウ操作は手動リサイズへ集約する
    standardWindowButton(.zoomButton)?.isHidden = true
    collectionBehavior.remove(.fullScreenPrimary)
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

  override func zoom(_ sender: Any?) {
    // 手動リサイズの寸法を保ち、緑のズーム操作後も現在の枠を維持する
  }

  override func toggleFullScreen(_ sender: Any?) {
    // 通常ウィンドウとして扱い、メニュー操作後も現在の表示形態を保つ
  }
}
