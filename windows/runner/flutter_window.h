#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

/// Flutter のビューとファイル操作チャネルを保持するウィンドウ。
class FlutterWindow : public Win32Window {
 public:
  /// 表示する Flutter プロジェクトを保持する。
  /// @param project ウィンドウ内で実行する Dart プロジェクト
  /// @param selected_paths Explorer から渡された初期選択
  explicit FlutterWindow(const flutter::DartProject& project,
                         const std::vector<std::wstring>& selected_paths = {});
  /// Flutter のビューとチャネルを含むメンバーを破棄する。
  virtual ~FlutterWindow();

 protected:
  /// Flutter のエンジン、ビュー、ファイル操作チャネルを初期化する。
  /// @returns ウィンドウと Flutter を初期化できた場合は true
  bool OnCreate() override;
  /// ファイル操作チャネルと Flutter のビューを解放する。
  void OnDestroy() override;
  /// Flutter と OS のウィンドウメッセージを処理する。
  /// @param window メッセージの対象ウィンドウ
  /// @param message Win32 メッセージ識別子
  /// @param wparam メッセージ固有の追加情報
  /// @param lparam メッセージ固有の追加情報
  /// @returns Flutter または基底ウィンドウによる処理結果
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Explorer の連続起動をまとめ、Dart が受信可能になってから通知する
  std::vector<std::wstring> pending_selection_;
  bool is_selection_listener_ready_ = false;

  // 登録ヘルパーの終了をタイマーで待ち、UAC 表示中もウィンドウを描画する
  HANDLE shell_registration_process_ = nullptr;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
      shell_registration_result_;

  // ウィンドウ内で実行するプロジェクト
  flutter::DartProject project_;

  // ウィンドウが保持する Flutter のエンジンとビュー
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 元画像の日時複製と検証済み出力の置換を実行する MethodChannel
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      file_operations_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
