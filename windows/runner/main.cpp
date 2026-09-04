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

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
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

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
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
