#include <windows.h>
#include <shellapi.h>

#include <cstdint>
#include <string>

/// DLL から渡された全引数をプロセスごとのバイナリログへ保存する
/// @returns ログを保存できた場合は0、それ以外は1
int wmain() {
  // Flutter の相対 data パスが安定するよう、DLL が実行ファイルのディレクトリを指定したことを検証する
  wchar_t executable_path[32768]{};
  const DWORD executable_length = GetModuleFileNameW(
      nullptr, executable_path, static_cast<DWORD>(_countof(executable_path)));
  wchar_t current_directory[32768]{};
  const DWORD current_directory_length = GetCurrentDirectoryW(
      static_cast<DWORD>(_countof(current_directory)), current_directory);
  if (executable_length == 0 ||
      executable_length >= _countof(executable_path) ||
      current_directory_length == 0 ||
      current_directory_length >= _countof(current_directory)) {
    return 1;
  }
  std::wstring expected_directory(executable_path, executable_length);
  const size_t separator = expected_directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return 1;
  }
  expected_directory.resize(separator);
  if (_wcsicmp(expected_directory.c_str(), current_directory) != 0) {
    return 1;
  }

  // 親テストごとに用意した場所へ、並行起動しても衝突しないプロセス別ログを保存する
  wchar_t log_directory[32768]{};
  const DWORD directory_length = GetEnvironmentVariableW(
      L"IMAGE_SQUOOSHER_SHELL_TEST_LOG", log_directory,
      static_cast<DWORD>(_countof(log_directory)));
  if (directory_length == 0 || directory_length >= _countof(log_directory)) {
    return 1;
  }

  int argument_count = 0;
  LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments == nullptr) {
    return 1;
  }

  // ファイルを排他的に開き、親テストは閉じた後の完成ログだけを読む
  const std::wstring log_path =
      std::wstring(log_directory) + L"\\" +
      std::to_wstring(GetCurrentProcessId()) + L".bin";
  HANDLE log_file = CreateFileW(log_path.c_str(), GENERIC_WRITE, 0, nullptr,
                                CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (log_file == INVALID_HANDLE_VALUE) {
    LocalFree(arguments);
    return 1;
  }

  bool is_success = true;
  const uint32_t path_count =
      argument_count > 1 ? static_cast<uint32_t>(argument_count - 1) : 0;
  DWORD written = 0;
  // UTF-16 パスを長さ付きで保存し、空白や日本語を文字列変換なしで検証できる形式にする
  is_success = WriteFile(log_file, &path_count, sizeof(path_count), &written,
                         nullptr) != FALSE &&
               written == sizeof(path_count);
  for (int index = 1; is_success && index < argument_count; ++index) {
    const uint32_t path_length =
        static_cast<uint32_t>(wcslen(arguments[index]));
    is_success = WriteFile(log_file, &path_length, sizeof(path_length), &written,
                           nullptr) != FALSE &&
                 written == sizeof(path_length);
    if (is_success && path_length > 0) {
      const DWORD path_bytes = path_length * sizeof(wchar_t);
      is_success = WriteFile(log_file, arguments[index], path_bytes, &written,
                             nullptr) != FALSE &&
                   written == path_bytes;
    }
  }

  CloseHandle(log_file);
  LocalFree(arguments);
  return is_success ? 0 : 1;
}
