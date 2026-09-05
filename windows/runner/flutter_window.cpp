#include "flutter_window.h"

#include <windows.h>

#include <cstdint>
#include <algorithm>
#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "shell_integration.h"

namespace {
constexpr UINT_PTR kSelectionTimer = 0x4953;
constexpr UINT kSelectionDelayMs = 250;

constexpr char kFileOperationsChannelName[] =
    "net.tsukumijima.image-squoosher/finder_sync";

/// 日本語や空白を含むパスを Win32 API 用の UTF-16 に変換する。
/// @param utf8 変換する UTF-8 文字列
/// @returns UTF-16 文字列 (空の入力や変換失敗では空文字列)
std::wstring Utf8ToWide(const std::string& utf8) {
  // 空の入力は空文字列として返す
  if (utf8.empty()) {
    return std::wstring();
  }

  // UTF-16 の必要文字数を求めてから出力領域を確保する
  const int size = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8.c_str(),
      static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }

  std::wstring wide(size, L'\0');
  const int converted = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8.c_str(),
      static_cast<int>(utf8.size()), wide.data(), size);
  return converted == size ? wide : std::wstring();
}

/// 読み取り用と書き込み用のハンドルを分けて作成日時と更新日時を複製する。
/// @param source_path 元画像の UTF-16 パス
/// @param output_path 日時を反映する出力ファイルの UTF-16 パス
/// @param error_code 失敗時に Win32 エラーコードを書き込む有効なポインター
/// @returns 両方の日時を反映できた場合は true
bool CopyFileDates(const std::wstring& source_path,
                   const std::wstring& output_path,
                   DWORD* error_code) {
  // 元画像は属性の読み取り権限だけで開く
  const HANDLE source_handle = CreateFileW(
      source_path.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (source_handle == INVALID_HANDLE_VALUE) {
    *error_code = GetLastError();
    return false;
  }

  // 作成日時と更新日時を取得し、元画像のハンドルを解放する
  FILETIME creation_time;
  FILETIME modified_time;
  const BOOL read_succeeded =
      GetFileTime(source_handle, &creation_time, nullptr, &modified_time);
  if (!read_succeeded) {
    *error_code = GetLastError();
    CloseHandle(source_handle);
    return false;
  }
  CloseHandle(source_handle);

  // 出力は属性の書き込み権限で開き、取得した日時を反映する
  const HANDLE output_handle = CreateFileW(
      output_path.c_str(), FILE_WRITE_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (output_handle == INVALID_HANDLE_VALUE) {
    *error_code = GetLastError();
    return false;
  }

  const BOOL write_succeeded =
      SetFileTime(output_handle, &creation_time, nullptr, &modified_time);
  if (!write_succeeded) {
    *error_code = GetLastError();
  }
  CloseHandle(output_handle);
  return write_succeeded != FALSE;
}

/// 同じディレクトリの検証済み一時出力を単一の Win32 操作で確定する。
/// @param staged_output_path 検証済み一時 JPEG の UTF-16 パス
/// @param output_path 置き換える出力先の UTF-16 パス
/// @param error_code 失敗時に Win32 エラーコードを書き込む有効なポインター
/// @returns 一時出力を出力先へ移動できた場合は true
bool ReplaceStagedOutputAtomically(const std::wstring& staged_output_path,
                                   const std::wstring& output_path,
                                   DWORD* error_code) {
  const BOOL move_succeeded = MoveFileExW(
      staged_output_path.c_str(), output_path.c_str(),
      MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
  if (move_succeeded == FALSE) {
    *error_code = GetLastError();
    return false;
  }
  return true;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             const std::vector<std::wstring>& selected_paths)
    : pending_selection_(selected_paths), project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  // 初期化中の後続起動も、このウィンドウへ選択を送れる状態にする
  if (!SetPropW(GetHandle(), shell_integration::kWindowProperty, reinterpret_cast<HANDLE>(1))) {
    return false;
  }

  RECT frame = GetClientArea();

  // 起動時の描画領域をウィンドウ寸法に合わせ、一度の生成で初期表示を準備する
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // エンジンとビューの両方が初期化できた場合にプラグインを登録する
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // macOS と同じチャネル名を使い、Dart 側は OS ごとのファイル操作だけを呼び分ける
  file_operations_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          kFileOperationsChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  file_operations_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getFinderSelectedImageURLs") {
          is_selection_listener_ready_ = true;
          // 起動中に届いた複数ファイルも最初の通知へまとめる
          if (!pending_selection_.empty()) {
            SetTimer(GetHandle(), kSelectionTimer, kSelectionDelayMs, nullptr);
          }
          result->Success(flutter::EncodableValue(flutter::EncodableList{}));
          return;
        }
        if (call.method_name() == "isWindowsShellIntegrationEnabled") {
          result->Success(
              flutter::EncodableValue(shell_integration::IsEnabled()));
          return;
        }
        if (call.method_name() == "setWindowsShellIntegrationEnabled") {
          const auto* arguments =
              call.arguments() == nullptr
                  ? nullptr
                  : std::get_if<flutter::EncodableMap>(call.arguments());
          const bool* is_enabled = nullptr;
          const std::string* label = nullptr;
          if (arguments != nullptr) {
            const auto entry =
                arguments->find(flutter::EncodableValue("enabled"));
            if (entry != arguments->end()) {
              is_enabled = std::get_if<bool>(&entry->second);
            }
            const auto label_entry =
                arguments->find(flutter::EncodableValue("label"));
            if (label_entry != arguments->end()) {
              label = std::get_if<std::string>(&label_entry->second);
            }
          }
          if (is_enabled == nullptr) {
            result->Error("INVALID_ARGS", "Missing enabled flag.");
            return;
          }
          const auto menu_label =
              label == nullptr ? std::wstring() : Utf8ToWide(*label);
          if (*is_enabled && menu_label.empty()) {
            result->Error("INVALID_ARGS", "Missing menu label.");
            return;
          }
          const LSTATUS status =
              shell_integration::SetEnabled(*is_enabled, menu_label);
          if (status != ERROR_SUCCESS) {
            result->Error(
                "SHELL_INTEGRATION_FAILED",
                "Could not update Explorer integration.",
                flutter::EncodableValue(static_cast<int64_t>(status)));
          } else {
            result->Success();
          }
          return;
        }
        if (call.method_name() == "centerOnPointerScreen") {
          if (CenterOnPointerScreen()) {
            result->Success();
          } else {
            result->Error("WINDOW_POSITION_FAILED",
                          "Could not center the window on the pointer screen.");
          }
          return;
        }
        const bool is_copy_file_dates_call =
            call.method_name() == "copySourceFileDatesToOutputFile";
        const bool is_replace_staged_output_call =
            call.method_name() == "replaceStagedOutputAtomically";
        if (!is_copy_file_dates_call && !is_replace_staged_output_call) {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("INVALID_ARGS", "Missing arguments.");
          return;
        }

        // メソッドごとの入力パスと共通の出力パスを取得する
        const auto source_iterator = arguments->find(flutter::EncodableValue(
            is_copy_file_dates_call ? "sourcePath" : "stagedOutputPath"));
        const auto output_iterator =
            arguments->find(flutter::EncodableValue("outputPath"));
        if (source_iterator == arguments->end() ||
            output_iterator == arguments->end()) {
          result->Error(
              "INVALID_ARGS", "Missing sourcePath/stagedOutputPath or outputPath.");
          return;
        }

        const auto* source_value =
            std::get_if<std::string>(&source_iterator->second);
        const auto* output_value =
            std::get_if<std::string>(&output_iterator->second);
        if (source_value == nullptr || output_value == nullptr) {
          result->Error("INVALID_ARGS", "Invalid path argument types.");
          return;
        }

        // UTF-8 として有効なパスだけを Win32 のファイル操作へ渡す
        const std::wstring source_path = Utf8ToWide(*source_value);
        const std::wstring output_path = Utf8ToWide(*output_value);
        if (source_path.empty() || output_path.empty()) {
          result->Error("INVALID_ARGS", "Invalid UTF-8 file path.");
          return;
        }

        // OS の失敗コードを Flutter へ返し、変換側で元画像を保持できるようにする
        DWORD error_code = ERROR_SUCCESS;
        if (is_copy_file_dates_call &&
            !CopyFileDates(source_path, output_path, &error_code)) {
          result->Error(
              "COPY_FILE_DATES_FAILED", "Failed to copy source file dates.",
              flutter::EncodableValue(static_cast<int64_t>(error_code)));
          return;
        }

        if (is_replace_staged_output_call &&
            !ReplaceStagedOutputAtomically(source_path, output_path,
                                           &error_code)) {
          result->Error(
              "REPLACE_STAGED_OUTPUT_FAILED",
              "Failed to atomically replace staged JPEG output.",
              flutter::EncodableValue(static_cast<int64_t>(error_code)));
          return;
        }

        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // 最初の描画がコールバック登録前に終わっていても、次の描画でウィンドウを表示する
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (GetHandle() != nullptr) {
    KillTimer(GetHandle(), kSelectionTimer);
    RemovePropW(GetHandle(), shell_integration::kWindowProperty);
  }
  // チャネルを先に閉じてからエンジンとビューを解放する
  file_operations_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Explorer がファイルごとに起動したプロセスからの選択を受け取る
  if (message == WM_COPYDATA && lparam != 0) {
    const auto& data = *reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (data.dwData != shell_integration::kSelectionMessage) {
      return FALSE;
    }
    const auto paths = shell_integration::DecodeSelection(data);
    for (const auto& path : paths) {
      if (std::none_of(pending_selection_.begin(), pending_selection_.end(),
                       [&](const auto& existing) {
                         return _wcsicmp(existing.c_str(), path.c_str()) == 0;
                       })) {
        pending_selection_.push_back(path);
      }
    }
    if (is_selection_listener_ready_ && !pending_selection_.empty()) {
      SetTimer(hwnd, kSelectionTimer, kSelectionDelayMs, nullptr);
    }
    return TRUE;
  }
  // 最後の受信から一定時間空いた時点で、選択一覧を1回の通知にまとめる
  if (message == WM_TIMER && wparam == kSelectionTimer) {
    KillTimer(hwnd, kSelectionTimer);
    if (is_selection_listener_ready_ && file_operations_channel_ &&
        !pending_selection_.empty()) {
      flutter::EncodableList paths;
      for (const auto& path : pending_selection_) {
        paths.emplace_back(shell_integration::ToUtf8(path));
      }
      pending_selection_.clear();
      file_operations_channel_->InvokeMethod(
          "finderSelectedImageURLs",
          std::make_unique<flutter::EncodableValue>(paths));
    }
    return 0;
  }
  // プラグインを含む Flutter 側へ先にウィンドウメッセージを渡す
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
