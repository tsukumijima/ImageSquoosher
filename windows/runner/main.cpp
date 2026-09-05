#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\ImageSquoosher.SingleInstance";
constexpr wchar_t kWindowTitle[] = L"ImageSquoosher";

}  // namespace

/// 単一起動を確認し、Flutter ウィンドウのメッセージループを実行する。
/// @param instance 現在のプロセスのインスタンス (処理には使用しない)
/// @param prev 以前のインスタンス (Win32 では使用しない)
/// @param command_line OS が渡すコマンドライン (引数は別途取得する)
/// @param show_command 表示方法の指定 (ウィンドウ側で表示を制御する)
/// @returns 正常終了または既存起動への引き継ぎで EXIT_SUCCESS、初期化失敗で EXIT_FAILURE
int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // flutter run のコンソールを引き継ぎ、デバッガーからの起動時は新しく作成する
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 同じユーザーセッションではウィンドウを1つに保ち、別セッションの起動は独立させる
  const HANDLE single_instance_mutex =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (single_instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }
  const DWORD create_mutex_error = GetLastError();
  if (create_mutex_error == ERROR_ALREADY_EXISTS) {
    const HWND existing_window = FindWindowW(nullptr, kWindowTitle);
    if (existing_window != nullptr) {
      // 最小化済みの既存ウィンドウも復元して前面へ戻す
      ShowWindow(existing_window, SW_RESTORE);
      SetForegroundWindow(existing_window);
    }
    CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Flutter とプラグインで使う COM を初期化する
  const HRESULT com_initialization_result =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(com_initialization_result)) {
    CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(620, 680);
  if (!window.Create(L"ImageSquoosher", origin, size)) {
    ::CoUninitialize();
    CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
