#include "flutter_window.h"

#include <windows.h>

#include <cstdint>
#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kFileOperationsChannelName[] =
    "net.tsukumijima.image-squoosher/finder_sync";

// 日本語や空白を含むパスも Win32 API へ欠損なく渡せるよう UTF-16 に変換する
std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }

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

// 元画像へ書き込み権限を要求せず、読み取り用と書き込み用のハンドルを分けて日時を複製する
bool CopyFileDates(const std::wstring& source_path,
                   const std::wstring& output_path,
                   DWORD* error_code) {
  const HANDLE source_handle = CreateFileW(
      source_path.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (source_handle == INVALID_HANDLE_VALUE) {
    *error_code = GetLastError();
    return false;
  }

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

// 同じディレクトリに作った一時出力を移動し、既存 JPEG の置換も単一の Win32 操作へ収める
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

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
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

        const std::wstring source_path = Utf8ToWide(*source_value);
        const std::wstring output_path = Utf8ToWide(*output_value);
        if (source_path.empty() || output_path.empty()) {
          result->Error("INVALID_ARGS", "Invalid UTF-8 file path.");
          return;
        }

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

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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
  // Give Flutter, including plugins, an opportunity to handle window messages.
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
