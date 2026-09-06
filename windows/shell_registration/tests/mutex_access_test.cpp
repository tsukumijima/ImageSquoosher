#include <windows.h>

#include <sddl.h>

#include <iostream>
#include <iterator>
#include <string>

namespace {
constexpr DWORD kMutexAccess = SYNCHRONIZE | MUTEX_MODIFY_STATE;

/// 子プロセスのコマンドラインでも空白を保持できるよう引数を引用する
/// @param argument 引用する引数
/// @returns CreateProcessW() へ渡せる引用済み引数
std::wstring QuoteArgument(const std::wstring& argument) {
  std::wstring quoted = L"\"";
  size_t backslash_count = 0;
  for (const wchar_t character : argument) {
    if (character == L'\\') {
      ++backslash_count;
      continue;
    }
    if (character == L'\"') {
      quoted.append(backslash_count * 2 + 1, L'\\');
      quoted.push_back(character);
      backslash_count = 0;
      continue;
    }
    quoted.append(backslash_count, L'\\');
    backslash_count = 0;
    quoted.push_back(character);
  }
  quoted.append(backslash_count * 2, L'\\');
  quoted.push_back(L'\"');
  return quoted;
}

/// DACL が許可する最小権限と、各ミューテックス API の要求権限を子プロセスで比較する
/// @param mutex_name 親プロセスが作ったミューテックス名
/// @returns 権限境界が想定どおりの場合は0、それ以外は非0
int RunChild(const wchar_t* mutex_name) {
  // CreateMutexW() は既存オブジェクトへ MUTEX_ALL_ACCESS を要求するため、この DACL では拒否される
  HANDLE broad_access_mutex = CreateMutexW(nullptr, FALSE, mutex_name);
  if (broad_access_mutex != nullptr) {
    CloseHandle(broad_access_mutex);
    std::cerr << "CreateMutexW unexpectedly opened the restricted mutex.\n";
    return 2;
  }
  if (GetLastError() != ERROR_ACCESS_DENIED) {
    std::cerr << "CreateMutexW failed with an unexpected error.\n";
    return 3;
  }

  // CreateMutexExW() は待機と解放に必要な権限だけを要求でき、同じ DACL の既存オブジェクトを開ける
  HANDLE precise_access_mutex =
      CreateMutexExW(nullptr, mutex_name, 0, kMutexAccess);
  if (precise_access_mutex == nullptr) {
    std::cerr << "CreateMutexExW could not open the restricted mutex.\n";
    return 4;
  }
  CloseHandle(precise_access_mutex);
  return 0;
}
}  // namespace

/// 同じ権限の親子2プロセスで、制限付きミューテックスを開く API の差を検証する
/// @param argument_count コマンドライン引数の個数
/// @param arguments コマンドライン引数
/// @returns 全検証に成功した場合は0、それ以外は非0
int wmain(int argument_count, wchar_t** arguments) {
  if (argument_count == 3 && wcscmp(arguments[1], L"--child") == 0) {
    return RunChild(arguments[2]);
  }
  if (argument_count != 1) {
    std::cerr << "Unexpected arguments.\n";
    return 1;
  }

  const std::wstring mutex_name =
      L"Global\\ImageSquoosher.ShellRegistration.MutexTest." +
      std::to_wstring(GetCurrentProcessId()) + L"." +
      std::to_wstring(GetTickCount64());
  PSECURITY_DESCRIPTOR security_descriptor = nullptr;
  // 管理者や所有者にも最小権限だけを許可し、実行時の昇格状態に左右されず API の要求権限差を検証する
  constexpr const wchar_t* kMutexSecurity =
      L"D:(D;;0x000F0000;;;WD)(A;;0x00100001;;;WD)";
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          kMutexSecurity, SDDL_REVISION_1, &security_descriptor, nullptr)) {
    std::cerr << "The mutex security descriptor could not be created.\n";
    return 1;
  }
  SECURITY_ATTRIBUTES security_attributes{
      sizeof(SECURITY_ATTRIBUTES), security_descriptor, FALSE};
  HANDLE mutex = CreateMutexExW(&security_attributes, mutex_name.c_str(), 0,
                                kMutexAccess);
  const DWORD create_error = mutex == nullptr ? GetLastError() : ERROR_SUCCESS;
  LocalFree(security_descriptor);
  if (mutex == nullptr) {
    std::cerr << "The restricted mutex could not be created. error: "
              << create_error << ".\n";
    return 1;
  }

  wchar_t executable_path[32768]{};
  const DWORD executable_path_length = GetModuleFileNameW(
      nullptr, executable_path, static_cast<DWORD>(std::size(executable_path)));
  if (executable_path_length == 0 ||
      executable_path_length >= std::size(executable_path)) {
    CloseHandle(mutex);
    std::cerr << "The test executable path could not be resolved.\n";
    return 1;
  }
  std::wstring command_line = QuoteArgument(executable_path) + L" --child " +
                              QuoteArgument(mutex_name);
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  if (!CreateProcessW(executable_path, command_line.data(), nullptr, nullptr,
                      FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup_info,
                      &process_info)) {
    CloseHandle(mutex);
    std::cerr << "The normal child process could not be started.\n";
    return 1;
  }
  CloseHandle(process_info.hThread);

  const DWORD wait_result = WaitForSingleObject(process_info.hProcess, 5000);
  DWORD child_exit_code = 1;
  const BOOL has_exit_code =
      GetExitCodeProcess(process_info.hProcess, &child_exit_code);
  CloseHandle(process_info.hProcess);
  CloseHandle(mutex);
  if (wait_result != WAIT_OBJECT_0 || !has_exit_code || child_exit_code != 0) {
    std::cerr << "The child process did not verify the mutex access boundary. "
              << "wait: " << wait_result << ", exit: " << child_exit_code
              << ".\n";
    return 1;
  }
  return 0;
}
