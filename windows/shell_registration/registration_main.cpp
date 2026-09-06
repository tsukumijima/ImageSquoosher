#include "registration_logic.h"

#include <windows.h>

#include <sddl.h>
#include <shellapi.h>
#include <shlwapi.h>

#include <array>
#include <cerrno>
#include <cwchar>
#include <filesystem>
#include <limits>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Management.Deployment.h>
#include <winrt/Windows.Storage.h>
#include <winrt/base.h>

namespace {
using image_squoosher::shell_registration::ClassifyRegistrations;
using image_squoosher::shell_registration::IsValidEventPrefix;
using image_squoosher::shell_registration::RegistrationRecord;
using image_squoosher::shell_registration::kStatusDifferentPathOrBroken;
using image_squoosher::shell_registration::kStatusNotRegistered;
using image_squoosher::shell_registration::kStatusQueryError;
using image_squoosher::shell_registration::kStatusRegisteredHere;
using winrt::Windows::ApplicationModel::Package;
using winrt::Windows::Foundation::Uri;
using winrt::Windows::Management::Deployment::DeploymentOptions;
using winrt::Windows::Management::Deployment::PackageManager;
using winrt::Windows::Management::Deployment::RemovalOptions;

constexpr const wchar_t* kPackageName = L"ImageSquoosher.ShellExtension";
constexpr const wchar_t* kPackagePublisher = L"CN=tsukumijima";
constexpr const wchar_t* kDeveloperModeRegistryPath =
    L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock";
constexpr const wchar_t* kDeveloperModeRegistryValue =
    L"AllowDevelopmentWithoutDevLicense";
constexpr const wchar_t* kOperationMutexName =
    L"Global\\ImageSquoosher.ShellRegistration."
    L"{899D9BF0-62F9-49AC-B592-01EEE3C8CF27}.Operation";
constexpr DWORD kOperationTimeoutMilliseconds = 5 * 60 * 1000;
constexpr DWORD kRestoreTimeoutMilliseconds = 60 * 1000;
constexpr DWORD kElevatedChildTimeoutMilliseconds = 10 * 60 * 1000;
constexpr DWORD kOperationMutexAccess = SYNCHRONIZE | MUTEX_MODIFY_STATE;

/// Win32 ハンドルの所有権をスコープへ閉じ込める
class UniqueHandle final {
 public:
  UniqueHandle() = default;
  explicit UniqueHandle(HANDLE handle) : handle_(handle) {}
  ~UniqueHandle() {
    if (handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE) {
      CloseHandle(handle_);
    }
  }

  UniqueHandle(const UniqueHandle&) = delete;
  UniqueHandle& operator=(const UniqueHandle&) = delete;

  UniqueHandle(UniqueHandle&& other) noexcept : handle_(other.release()) {}
  UniqueHandle& operator=(UniqueHandle&& other) noexcept {
    if (this != &other) {
      UniqueHandle old_handle(handle_);
      handle_ = other.release();
    }
    return *this;
  }

  HANDLE get() const { return handle_; }
  explicit operator bool() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }
  HANDLE release() {
    const HANDLE handle = handle_;
    handle_ = nullptr;
    return handle;
  }

 private:
  HANDLE handle_ = nullptr;
};

/// レジストリキーの所有権をスコープへ閉じ込める
class UniqueRegistryKey final {
 public:
  UniqueRegistryKey() = default;
  explicit UniqueRegistryKey(HKEY key) : key_(key) {}
  ~UniqueRegistryKey() {
    if (key_ != nullptr) {
      RegCloseKey(key_);
    }
  }

  UniqueRegistryKey(const UniqueRegistryKey&) = delete;
  UniqueRegistryKey& operator=(const UniqueRegistryKey&) = delete;

  HKEY get() const { return key_; }

 private:
  HKEY key_ = nullptr;
};

/// LocalAlloc 系 API が返すメモリの所有権をスコープへ閉じ込める
class UniqueLocalMemory final {
 public:
  UniqueLocalMemory() = default;
  explicit UniqueLocalMemory(void* memory) : memory_(memory) {}
  ~UniqueLocalMemory() {
    if (memory_ != nullptr) {
      LocalFree(memory_);
    }
  }

  UniqueLocalMemory(const UniqueLocalMemory&) = delete;
  UniqueLocalMemory& operator=(const UniqueLocalMemory&) = delete;

 private:
  void* memory_ = nullptr;
};

/// 同じ端末上の登録変更を直列化する
class OperationLock final {
 public:
  OperationLock() {
    // Developer Mode は端末全体の値なので、別ユーザーの通常プロセスとも同じミューテックスで直列化する
    PSECURITY_DESCRIPTOR security_descriptor = nullptr;
    constexpr const wchar_t* kMutexSecurity =
        L"D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x00100001;;;WD)";
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            kMutexSecurity, SDDL_REVISION_1, &security_descriptor, nullptr)) {
      winrt::throw_hresult(HRESULT_FROM_WIN32(GetLastError()));
    }
    SECURITY_ATTRIBUTES security_attributes{
        sizeof(SECURITY_ATTRIBUTES), security_descriptor, FALSE};
    // 既存オブジェクトを開く場合も DACL が許可した同期権限だけを要求する
    const HANDLE mutex = CreateMutexExW(&security_attributes,
                                        kOperationMutexName, 0,
                                        kOperationMutexAccess);
    const DWORD create_error = mutex == nullptr ? GetLastError() : ERROR_SUCCESS;
    LocalFree(security_descriptor);
    handle_ = UniqueHandle(mutex);
    if (!handle_) {
      winrt::throw_hresult(HRESULT_FROM_WIN32(create_error));
    }
    const DWORD wait_result =
        WaitForSingleObject(handle_.get(), kOperationTimeoutMilliseconds);
    if (wait_result != WAIT_OBJECT_0 && wait_result != WAIT_ABANDONED) {
      const DWORD error = wait_result == WAIT_FAILED ? GetLastError()
                                                      : ERROR_TIMEOUT;
      winrt::throw_hresult(HRESULT_FROM_WIN32(error));
    }
    is_acquired_ = true;
  }

  ~OperationLock() {
    if (is_acquired_) {
      ReleaseMutex(handle_.get());
    }
  }

  OperationLock(const OperationLock&) = delete;
  OperationLock& operator=(const OperationLock&) = delete;

 private:
  UniqueHandle handle_;
  bool is_acquired_ = false;
};

struct RegistrationQuery {
  std::vector<RegistrationRecord> records;
};

struct RegistryValueSnapshot {
  bool has_value = false;
  DWORD type = REG_NONE;
  std::vector<BYTE> data;
};

/// 現在の実行ファイルを長いパスと日本語を保持して取得する
/// @returns 実行ファイルの絶対パス
std::filesystem::path ExecutablePath() {
  std::wstring path(32768, L'\0');
  const DWORD length =
      GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0) {
    winrt::throw_hresult(HRESULT_FROM_WIN32(GetLastError()));
  }
  if (length >= path.size()) {
    winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER));
  }
  path.resize(length);
  return std::filesystem::path(path);
}

/// 登録に必要な配布ファイルが同じフォルダへ揃っていることを確認する
/// @param folder loose package のルートフォルダ
void VerifyRequiredFiles(const std::filesystem::path& folder) {
  constexpr const wchar_t* kRequiredFiles[] = {
      L"AppxManifest.xml", L"ImageSquoosher.exe", L"ImageSquoosherShell.dll",
      L"app_icon_1024.png"};
  for (const auto* file_name : kRequiredFiles) {
    const std::filesystem::path path = folder / file_name;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND));
    }
  }
}

/// PackageManager が返す登録を、状態判定と解除に必要な情報へ変換する
/// @param package_manager 現在ユーザーを照会する PackageManager
/// @returns 同名・同発行者の全登録
RegistrationQuery QueryRegistrations(const PackageManager& package_manager) {
  RegistrationQuery query;
  const auto packages = package_manager.FindPackagesForUser(
      L"", kPackageName, kPackagePublisher);
  for (const Package& package : packages) {
    RegistrationRecord record;
    record.full_name = package.Id().FullName().c_str();
    record.is_healthy = package.Status().VerifyIsOK();
    try {
      record.installed_path = package.InstalledLocation().Path().c_str();
      VerifyRequiredFiles(record.installed_path);
    } catch (const winrt::hresult_error&) {
      // ID を列挙できても配置先へ到達できない登録は、解除して作り直せる破損状態として残す
      record.is_healthy = false;
    }
    query.records.push_back(std::move(record));
  }
  return query;
}

/// 配置先パスを WinRT の Uri へ安全に変換する
/// @param path URI 化する絶対ファイルパス
/// @returns RegisterPackageAsync() へ渡せる file URI
Uri FileURI(const std::filesystem::path& path) {
  std::wstring uri(32768, L'\0');
  DWORD uri_length = static_cast<DWORD>(uri.size());
  const HRESULT result =
      UrlCreateFromPathW(path.c_str(), uri.data(), &uri_length, 0);
  if (FAILED(result)) {
    winrt::throw_hresult(result);
  }
  uri.resize(uri_length);
  return Uri(uri);
}

/// 展開操作が非同期処理内で返した詳細 HRESULT も成功条件へ含める
/// @param result PackageManager の展開結果
void VerifyDeploymentResult(
    const winrt::Windows::Management::Deployment::DeploymentResult& result) {
  const HRESULT extended_error = result.ExtendedErrorCode();
  if (FAILED(extended_error)) {
    winrt::throw_hresult(extended_error);
  }
}

/// 同名・同発行者の登録だけを、アプリデータを保持して解除する
/// @param package_manager 現在ユーザーの登録を変更する PackageManager
/// @param registrations 解除対象の照会結果
void RemoveRegistrations(const PackageManager& package_manager,
                         const RegistrationQuery& registrations) {
  for (const auto& registration : registrations.records) {
    // シェル登録以外の利用者データへ影響を広げないよう、パッケージ側のデータ領域も保持する
    const auto operation = package_manager.RemovePackageAsync(
        registration.full_name, RemovalOptions::PreserveApplicationData);
    VerifyDeploymentResult(operation.get());
  }
}

/// 現在フォルダの loose manifest を現在ユーザーへ登録する
/// @param package_manager 現在ユーザーの登録を変更する PackageManager
/// @param folder マニフェストを含む配布フォルダ
void RegisterCurrentFolder(const PackageManager& package_manager,
                           const std::filesystem::path& folder) {
  const auto operation = package_manager.RegisterPackageAsync(
      FileURI(folder / L"AppxManifest.xml"),
      winrt::single_threaded_vector<Uri>(),
      DeploymentOptions::DevelopmentMode);
  VerifyDeploymentResult(operation.get());

  // WinRT の完了だけでなく、Explorer が参照する登録パスと配布ファイルの実状態まで確認する
  const int status =
      ClassifyRegistrations(QueryRegistrations(package_manager).records,
                            folder.wstring());
  if (status != kStatusRegisteredHere) {
    winrt::throw_hresult(E_FAIL);
  }
}

/// 登録準備が完了した後で、移動前の登録を現在フォルダの登録へ置き換える
/// @param package_manager 現在ユーザーの登録を変更する PackageManager
/// @param folder マニフェストを含む配布フォルダ
void RepairRegistration(const PackageManager& package_manager,
                        const std::filesystem::path& folder) {
  const RegistrationQuery registrations = QueryRegistrations(package_manager);
  const int status =
      ClassifyRegistrations(registrations.records, folder.wstring());
  if (status == kStatusRegisteredHere) {
    return;
  }
  if (!registrations.records.empty()) {
    RemoveRegistrations(package_manager, registrations);
  }
  RegisterCurrentFolder(package_manager, folder);
}

/// Developer Mode が既に有効な場合だけ、昇格を省略できると判定する
/// @returns HKLM の値が REG_DWORD 1 の場合は true
bool IsDeveloperModeEnabled() {
  DWORD value = 0;
  DWORD value_size = sizeof(value);
  const LSTATUS status = RegGetValueW(
      HKEY_LOCAL_MACHINE, kDeveloperModeRegistryPath,
      kDeveloperModeRegistryValue, RRF_RT_REG_DWORD, nullptr, &value,
      &value_size);
  return status == ERROR_SUCCESS && value_size == sizeof(value) && value == 1;
}

/// GUID を含む推測困難な名前で、昇格した子プロセスと共有するイベントを作る
/// @returns 固定名前空間と GUID からなるイベント接頭辞
std::wstring CreateEventPrefix() {
  GUID guid{};
  winrt::check_hresult(CoCreateGuid(&guid));
  wchar_t guid_text[39]{};
  if (StringFromGUID2(guid, guid_text, static_cast<int>(std::size(guid_text))) !=
      39) {
    winrt::throw_hresult(E_FAIL);
  }
  return std::wstring(L"Local\\ImageSquoosher.ShellRegistration.") +
         guid_text;
}

/// 昇格した別資格情報のプロセスからも同期だけを許可するイベントを作る
/// @param name GUID を含む完全なイベント名
/// @param security_attributes 読み取り専用のセキュリティ属性
/// @returns 作成した手動リセットイベント
UniqueHandle CreateCoordinationEvent(const std::wstring& name,
                                     SECURITY_ATTRIBUTES* security_attributes) {
  UniqueHandle event(
      CreateEventW(security_attributes, TRUE, FALSE, name.c_str()));
  if (!event) {
    winrt::throw_hresult(HRESULT_FROM_WIN32(GetLastError()));
  }
  return event;
}

/// 子プロセスの終了を待ち、元の Developer Mode 値へ戻せたことを確認する
/// @param process ShellExecuteExW() が返した子プロセス
/// @param timeout_milliseconds 復元完了を待つ上限
/// @returns 子プロセスが返した復元結果
HRESULT WaitForChildResult(HANDLE process, DWORD timeout_milliseconds) {
  const DWORD wait_result = WaitForSingleObject(process, timeout_milliseconds);
  if (wait_result == WAIT_TIMEOUT) {
    return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
  }
  if (wait_result == WAIT_FAILED) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  DWORD exit_code = 0;
  if (!GetExitCodeProcess(process, &exit_code)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  return static_cast<HRESULT>(exit_code);
}

/// 一時的な Developer Mode の有効化中に現在ユーザーの登録だけを実行する
/// @param package_manager 現在ユーザーの登録を変更する PackageManager
/// @param folder マニフェストを含む配布フォルダ
void RegisterWithTemporaryDeveloperMode(const PackageManager& package_manager,
                                        const std::filesystem::path& folder) {
  const std::wstring event_prefix = CreateEventPrefix();

  PSECURITY_DESCRIPTOR security_descriptor = nullptr;
  constexpr const wchar_t* kEventSecurity =
      L"D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x00100002;;;WD)";
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          kEventSecurity, SDDL_REVISION_1, &security_descriptor, nullptr)) {
    winrt::throw_hresult(HRESULT_FROM_WIN32(GetLastError()));
  }
  UniqueLocalMemory owned_security_descriptor(security_descriptor);
  SECURITY_ATTRIBUTES security_attributes{
      sizeof(SECURITY_ATTRIBUTES), security_descriptor, FALSE};
  UniqueHandle ready_event = CreateCoordinationEvent(
      event_prefix + L".Ready", &security_attributes);
  UniqueHandle done_event = CreateCoordinationEvent(
      event_prefix + L".Done", &security_attributes);

  // runas の子はレジストリだけを担当し、PackageManager は通常ユーザーのこのプロセスに留める
  const std::filesystem::path executable_path = ExecutablePath();
  const std::wstring parameters =
      L"--developer-mode \"" + event_prefix + L"\" " +
      std::to_wstring(GetCurrentProcessId());
  SHELLEXECUTEINFOW execute_info{};
  execute_info.cbSize = sizeof(execute_info);
  execute_info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
  execute_info.lpVerb = L"runas";
  execute_info.lpFile = executable_path.c_str();
  execute_info.lpParameters = parameters.c_str();
  execute_info.nShow = SW_HIDE;
  if (!ShellExecuteExW(&execute_info)) {
    winrt::throw_hresult(HRESULT_FROM_WIN32(GetLastError()));
  }
  UniqueHandle child_process(execute_info.hProcess);

  const std::array<HANDLE, 2> ready_or_child{
      ready_event.get(), child_process.get()};
  const DWORD ready_result = WaitForMultipleObjects(
      static_cast<DWORD>(ready_or_child.size()), ready_or_child.data(), FALSE,
      kOperationTimeoutMilliseconds);
  if (ready_result != WAIT_OBJECT_0) {
    const DWORD wait_error = ready_result == WAIT_OBJECT_0 + 1
                                 ? ERROR_PROCESS_ABORTED
                             : ready_result == WAIT_FAILED ? GetLastError()
                                                           : ERROR_TIMEOUT;
    SetEvent(done_event.get());
    const HRESULT child_result =
        WaitForChildResult(child_process.get(), kRestoreTimeoutMilliseconds);
    if (FAILED(child_result)) {
      winrt::throw_hresult(child_result);
    }
    winrt::throw_hresult(HRESULT_FROM_WIN32(wait_error));
  }

  HRESULT registration_result = S_OK;
  try {
    RepairRegistration(package_manager, folder);
  } catch (const winrt::hresult_error& error) {
    registration_result = error.code();
  } catch (const std::bad_alloc&) {
    registration_result = E_OUTOFMEMORY;
  } catch (...) {
    registration_result = E_FAIL;
  }

  // 子を終了させて HKLM の元値へ戻した結果を、登録処理の成否より先に確定する
  if (!SetEvent(done_event.get())) {
    winrt::throw_hresult(HRESULT_FROM_WIN32(GetLastError()));
  }
  const HRESULT child_result =
      WaitForChildResult(child_process.get(), kRestoreTimeoutMilliseconds);
  if (FAILED(child_result)) {
    winrt::throw_hresult(child_result);
  }
  if (FAILED(registration_result)) {
    winrt::throw_hresult(registration_result);
  }
}

/// Developer Mode 値の有無・型・バイト列を一時変更前に保存する
/// @param key 読み書き可能な AppModelUnlock キー
/// @returns 復元に必要な値の完全なスナップショット
RegistryValueSnapshot ReadDeveloperModeValue(HKEY key) {
  RegistryValueSnapshot snapshot;
  DWORD data_size = 0;
  LSTATUS status = RegQueryValueExW(key, kDeveloperModeRegistryValue, nullptr,
                                    &snapshot.type, nullptr, &data_size);
  if (status == ERROR_FILE_NOT_FOUND) {
    return snapshot;
  }
  if (status != ERROR_SUCCESS) {
    winrt::throw_hresult(HRESULT_FROM_WIN32(status));
  }

  snapshot.has_value = true;
  snapshot.data.resize(data_size);
  if (data_size > 0) {
    status = RegQueryValueExW(key, kDeveloperModeRegistryValue, nullptr,
                              &snapshot.type, snapshot.data.data(), &data_size);
    if (status != ERROR_SUCCESS) {
      winrt::throw_hresult(HRESULT_FROM_WIN32(status));
    }
    snapshot.data.resize(data_size);
  }
  return snapshot;
}

/// 一時変更前に保存した Developer Mode 値を正確に復元する
/// @param key 読み書き可能な AppModelUnlock キー
/// @param snapshot 値の有無・型・バイト列を保持したスナップショット
HRESULT RestoreDeveloperModeValue(HKEY key,
                                  const RegistryValueSnapshot& snapshot) {
  LSTATUS status = ERROR_SUCCESS;
  if (snapshot.has_value) {
    const BYTE* data = snapshot.data.empty() ? nullptr : snapshot.data.data();
    status = RegSetValueExW(key, kDeveloperModeRegistryValue, 0, snapshot.type,
                            data, static_cast<DWORD>(snapshot.data.size()));
  } else {
    status = RegDeleteValueW(key, kDeveloperModeRegistryValue);
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;
    }
  }
  return status == ERROR_SUCCESS ? S_OK : HRESULT_FROM_WIN32(status);
}

/// 昇格した子として Developer Mode を一時有効化し、親の登録完了後に元へ戻す
/// @param event_prefix 親が作った ready・done イベントの共通名
/// @param parent_process_id 通常権限で登録する親プロセスの ID
/// @returns 値の復元まで成功した場合は S_OK
HRESULT RunDeveloperModeChild(const std::wstring& event_prefix,
                              DWORD parent_process_id) {
  if (!IsValidEventPrefix(event_prefix) || parent_process_id == 0 ||
      parent_process_id == GetCurrentProcessId()) {
    return E_INVALIDARG;
  }

  UniqueHandle process_token;
  HANDLE raw_process_token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw_process_token)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  process_token = UniqueHandle(raw_process_token);
  TOKEN_ELEVATION elevation{};
  DWORD returned_size = 0;
  if (!GetTokenInformation(process_token.get(), TokenElevation, &elevation,
                           sizeof(elevation), &returned_size)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  if (elevation.TokenIsElevated == 0) {
    return HRESULT_FROM_WIN32(ERROR_ELEVATION_REQUIRED);
  }

  // 親・イベントの実在を確認してから HKLM を変更し、単独起動で値が残る経路を閉じる
  UniqueHandle ready_event(OpenEventW(EVENT_MODIFY_STATE, FALSE,
                                      (event_prefix + L".Ready").c_str()));
  if (!ready_event) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  UniqueHandle done_event(OpenEventW(SYNCHRONIZE, FALSE,
                                     (event_prefix + L".Done").c_str()));
  if (!done_event) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  UniqueHandle parent_process(
      OpenProcess(SYNCHRONIZE, FALSE, parent_process_id));
  if (!parent_process) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  HKEY raw_key = nullptr;
  DWORD disposition = 0;
  const LSTATUS open_status = RegCreateKeyExW(
      HKEY_LOCAL_MACHINE, kDeveloperModeRegistryPath, 0, nullptr,
      REG_OPTION_NON_VOLATILE, KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr,
      &raw_key, &disposition);
  if (open_status != ERROR_SUCCESS) {
    return HRESULT_FROM_WIN32(open_status);
  }
  UniqueRegistryKey key(raw_key);

  RegistryValueSnapshot snapshot;
  try {
    snapshot = ReadDeveloperModeValue(key.get());
  } catch (const winrt::hresult_error& error) {
    return error.code();
  }
  const DWORD enabled_value = 1;
  const LSTATUS set_status = RegSetValueExW(
      key.get(), kDeveloperModeRegistryValue, 0, REG_DWORD,
      reinterpret_cast<const BYTE*>(&enabled_value), sizeof(enabled_value));
  if (set_status != ERROR_SUCCESS) {
    return HRESULT_FROM_WIN32(set_status);
  }

  HRESULT operation_result = S_OK;
  if (!SetEvent(ready_event.get())) {
    operation_result = HRESULT_FROM_WIN32(GetLastError());
  } else {
    const std::array<HANDLE, 2> done_or_parent{done_event.get(),
                                               parent_process.get()};
    const DWORD wait_result = WaitForMultipleObjects(
        static_cast<DWORD>(done_or_parent.size()), done_or_parent.data(), FALSE,
        kElevatedChildTimeoutMilliseconds);
    if (wait_result == WAIT_FAILED) {
      operation_result = HRESULT_FROM_WIN32(GetLastError());
    } else if (wait_result == WAIT_TIMEOUT) {
      operation_result = HRESULT_FROM_WIN32(ERROR_TIMEOUT);
    } else if (wait_result != WAIT_OBJECT_0 &&
               wait_result != WAIT_OBJECT_0 + 1) {
      operation_result = E_FAIL;
    }
  }

  const HRESULT restore_result = RestoreDeveloperModeValue(key.get(), snapshot);
  return FAILED(restore_result) ? restore_result : operation_result;
}

/// status コマンドの固定終了コードへ実際のパッケージ状態を写像する
/// @param folder ヘルパー自身の配布フォルダ
/// @returns 0: 現在パス、1: 未登録、2: 別パスまたは破損、3: 照会失敗
int ExecuteStatus(const std::filesystem::path& folder) {
  try {
    PackageManager package_manager;
    return ClassifyRegistrations(QueryRegistrations(package_manager).records,
                                 folder.wstring());
  } catch (...) {
    return kStatusQueryError;
  }
}

/// register コマンドを現在ユーザーのパッケージ登録へ適用する
/// @param folder ヘルパー自身の配布フォルダ
void ExecuteRegister(const std::filesystem::path& folder) {
  OperationLock operation_lock;
  VerifyRequiredFiles(folder);
  PackageManager package_manager;
  const RegistrationQuery registrations = QueryRegistrations(package_manager);
  const int status =
      ClassifyRegistrations(registrations.records, folder.wstring());
  if (status == kStatusRegisteredHere) {
    return;
  }
  // UAC が拒否された場合も既存登録を維持できるよう、登録解除は Developer Mode の準備後に行う
  if (IsDeveloperModeEnabled()) {
    RepairRegistration(package_manager, folder);
  } else {
    RegisterWithTemporaryDeveloperMode(package_manager, folder);
  }
}

/// unregister コマンドを現在ユーザーの一致する登録だけへ適用する
void ExecuteUnregister() {
  OperationLock operation_lock;
  PackageManager package_manager;
  const RegistrationQuery registrations = QueryRegistrations(package_manager);
  if (registrations.records.empty()) {
    return;
  }
  RemoveRegistrations(package_manager, registrations);
  if (!QueryRegistrations(package_manager).records.empty()) {
    winrt::throw_hresult(E_FAIL);
  }
}

/// 数値以外を受け入れず、親プロセス ID を DWORD へ変換する
/// @param text コマンドライン上の10進数
/// @returns 検証済みのプロセス ID
DWORD ParseProcessID(const wchar_t* text) {
  if (text == nullptr || *text == L'\0') {
    winrt::throw_hresult(E_INVALIDARG);
  }
  wchar_t* end = nullptr;
  errno = 0;
  const unsigned long value = std::wcstoul(text, &end, 10);
  if (errno == ERANGE || end == text || *end != L'\0' || value == 0 ||
      value > std::numeric_limits<DWORD>::max()) {
    winrt::throw_hresult(E_INVALIDARG);
  }
  return static_cast<DWORD>(value);
}
}  // namespace

/// シェル登録を操作する GUI サブシステムのエントリーポイント
/// @returns 成功時は0、失敗時は HRESULT または status の固定終了コード
int WINAPI wWinMain(HINSTANCE instance,
                    HINSTANCE previous_instance,
                    PWSTR command_line,
                    int show_command) {
  UNREFERENCED_PARAMETER(instance);
  UNREFERENCED_PARAMETER(previous_instance);
  UNREFERENCED_PARAMETER(command_line);
  UNREFERENCED_PARAMETER(show_command);

  bool is_status_command = false;
  try {
    int argument_count = 0;
    const auto arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
    if (arguments == nullptr) {
      return static_cast<int>(HRESULT_FROM_WIN32(GetLastError()));
    }
    UniqueLocalMemory owned_arguments(arguments);

    is_status_command =
        argument_count == 2 && wcscmp(arguments[1], L"--status") == 0;
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    const std::filesystem::path folder = ExecutablePath().parent_path();
    if (is_status_command) {
      return ExecuteStatus(folder);
    }
    if (argument_count == 2 && wcscmp(arguments[1], L"--register") == 0) {
      ExecuteRegister(folder);
      return 0;
    }
    if (argument_count == 2 && wcscmp(arguments[1], L"--unregister") == 0) {
      ExecuteUnregister();
      return 0;
    }
    if (argument_count == 4 &&
        wcscmp(arguments[1], L"--developer-mode") == 0) {
      return static_cast<int>(RunDeveloperModeChild(
          arguments[2], ParseProcessID(arguments[3])));
    }
    return static_cast<int>(E_INVALIDARG);
  } catch (const winrt::hresult_error& error) {
    return is_status_command ? kStatusQueryError : error.code().value;
  } catch (const std::bad_alloc&) {
    return is_status_command ? kStatusQueryError
                             : static_cast<int>(E_OUTOFMEMORY);
  } catch (...) {
    return is_status_command ? kStatusQueryError : static_cast<int>(E_FAIL);
  }
}
