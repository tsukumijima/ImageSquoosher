#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

/// 高 DPI のウィンドウを管理し、派生クラスへ描画と入力処理を委ねる。
class Win32Window {
 public:
  /// ウィンドウの初期位置を表す座標。
  struct Point {
    unsigned int x;
    unsigned int y;
    /// 初期位置の座標を保持する。
    /// @param x 水平方向の座標
    /// @param y 垂直方向の座標
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  /// ウィンドウの初期寸法。
  struct Size {
    unsigned int width;
    unsigned int height;
    /// 初期寸法を保持する。
    /// @param width 横幅
    /// @param height 高さ
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  /// 生存ウィンドウ数を増やして共有クラスの使用を開始する。
  Win32Window();
  /// 生存ウィンドウ数を減らし、保持するリソースを解放する。
  virtual ~Win32Window();

  /// 指定位置のモニターの DPI に合わせて非表示のウィンドウを作成する。
  /// @param title タイトルバーに表示する文字列
  /// @param origin DPI 倍率を適用する前の初期位置
  /// @param size DPI 倍率を適用する前の初期寸法
  /// @returns ウィンドウ生成と OnCreate() が成功した場合は true
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  /// ウィンドウを通常表示する。
  /// @returns 呼び出し前にウィンドウが表示されていた場合は true
  bool Show();

  /// ポインターがある画面の作業領域中央へウィンドウを移動する。
  /// @returns 画面情報を取得して移動できた場合は true
  bool CenterOnPointerScreen();

  /// 派生クラスの終了処理を呼び、ウィンドウの OS リソースを解放する。
  void Destroy();

  /// 子ウィンドウを表示領域いっぱいに配置してフォーカスする。
  /// @param content 配置する子ウィンドウのハンドル
  void SetChildContent(HWND content);

  /// アイコンやウィンドウ属性の操作に使うハンドルを取得する。
  /// @returns 本体ウィンドウのハンドル (破棄後は nullptr)
  HWND GetHandle();

  /// ウィンドウを閉じたときにアプリも終了するかを設定する。
  /// @param quit_on_close 終了メッセージを送信する場合は true
  void SetQuitOnClose(bool quit_on_close);

  /// タイトルバーと枠を除く表示領域を取得する。
  /// @returns クライアント座標で表した表示領域
  RECT GetClientArea();

 protected:
  /// サイズ変更、DPI、フォーカスなどのウィンドウメッセージを処理する。
  /// @param window 対象ウィンドウのハンドル
  /// @param message Win32 メッセージ識別子
  /// @param wparam メッセージ固有の追加情報
  /// @param lparam メッセージ固有の追加情報
  /// @returns メッセージの処理結果 (未処理の場合は OS の既定処理の結果)
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  /// Create() から呼ばれ、派生クラスの初期化を行う。
  /// @returns 初期化成功時は true (基底実装は常に true)
  virtual bool OnCreate();

  /// Destroy() から呼ばれ、派生クラスのリソースを解放する。
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  /// OS のウィンドウ生成通知でインスタンスを関連付け、以後の処理を委譲する。
  /// @param window 対象ウィンドウのハンドル
  /// @param message Win32 メッセージ識別子
  /// @param wparam メッセージ固有の追加情報
  /// @param lparam メッセージ固有の追加情報 (生成時は CREATESTRUCT のポインター)
  /// @returns MessageHandler() または OS の既定処理の結果
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  /// ウィンドウに関連付けたインスタンスを取得する。
  /// @param window 検索対象のウィンドウハンドル
  /// @returns 登録済みインスタンスのポインター (未登録なら nullptr)
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  /// システムのアプリ配色設定をウィンドウ枠に反映する。
  /// @param window 配色を反映するウィンドウハンドル
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // 本体ウィンドウのハンドル
  HWND window_handle_ = nullptr;

  // 内部に配置する子ウィンドウのハンドル
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
