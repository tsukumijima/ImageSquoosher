#include "shell_integration.h"

#include <shellapi.h>
#include <shlobj.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cwchar>
#include <filesystem>

namespace shell_integration {
namespace {
constexpr const wchar_t* kExtensions[] = {L".jpg", L".jpeg", L".png", L".webp"};

/// 現在の実行ファイルの絶対パスを取得する。
/// @returns 取得したパス (取得失敗時は空)
std::wstring ExecutablePath() {
  std::wstring path(32768, L'\0');
  const DWORD length =
      GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0 || length == path.size()) {
    return {};
  }
  path.resize(length);
  return path;
}

/// 拡張子別のアプリ専用レジストリキーを組み立てる。
/// @param extension 登録対象の拡張子
/// @returns HKCU 配下のキーの相対パス
std::wstring KeyPath(const wchar_t* extension) {
  return std::wstring(L"Software\\Classes\\SystemFileAssociations\\") +
         extension + L"\\shell\\ImageSquoosher";
}

/// 空白や日本語を保持する起動コマンドを組み立てる。
/// @returns 引用符付きの実行ファイルと選択パスのプレースホルダー
std::wstring Command() {
  const auto executable = ExecutablePath();
  return executable.empty() ? std::wstring()
                            : L"\"" + executable + L"\" \"%1\"";
}

/// 対応する実在ファイルを、重複を除いて選択一覧へ追加する。
/// @param paths 追加先の選択一覧
/// @param path 検査するファイルパス
void AddPath(std::vector<std::wstring>& paths, const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    return;
  }
  const auto dot = path.find_last_of(L'.');
  if (dot == std::wstring::npos) {
    return;
  }
  for (const auto* extension : kExtensions) {
    if (_wcsicmp(path.c_str() + dot, extension) == 0) {
      if (std::none_of(paths.begin(), paths.end(), [&](const auto& existing) {
            return _wcsicmp(existing.c_str(), path.c_str()) == 0;
          })) {
        paths.push_back(path);
      }
      return;
    }
  }
}

/// 終端 NUL を含む文字列をレジストリへ書き込む。
/// @param key 書き込み先のキー
/// @param name 値の名前 (既定値では nullptr)
/// @param value 書き込む文字列
/// @returns レジストリ API の結果
LSTATUS WriteValue(HKEY key, const wchar_t* name, const std::wstring& value) {
  return RegSetValueExW(
      key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
}
}  // namespace

std::string ToUtf8(const std::wstring& value) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string result(size, '\0');
  if (size > 0) {
    WideCharToMultiByte(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), result.data(), size,
                        nullptr, nullptr);
  }
  return result;
}

std::vector<std::wstring> ReadSelectedPaths() {
  int count = 0;
  auto arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  std::vector<std::wstring> paths;
  if (arguments != nullptr) {
    for (int index = 1; index < count; ++index) {
      AddPath(paths, arguments[index]);
    }
    LocalFree(arguments);
  }
  return paths;
}

std::vector<std::wstring> DecodeSelection(const COPYDATASTRUCT& data) {
  std::vector<std::wstring> paths;
  if (data.dwData != kSelectionMessage || data.lpData == nullptr ||
      data.cbData < sizeof(wchar_t) || data.cbData % sizeof(wchar_t) != 0 ||
      data.cbData > 1024 * 1024) {
    return paths;
  }
  const auto* characters = static_cast<const wchar_t*>(data.lpData);
  const size_t length = data.cbData / sizeof(wchar_t);
  if (characters[length - 1] != L'\0') {
    return paths;
  }
  size_t offset = 0;
  while (offset < length) {
    const size_t item_length = wcsnlen_s(characters + offset, length - offset);
    if (item_length == 0) {
      // 空要素で途切れたペイロードは全体を不正として扱う
      return {};
    }
    AddPath(paths, std::wstring(characters + offset, item_length));
    offset += item_length + 1;
  }
  return paths;
}

bool ForwardSelection(HWND window, const std::vector<std::wstring>& paths) {
  if (paths.empty()) {
    return true;
  }
  std::wstring payload;
  for (const auto& path : paths) {
    payload.append(path);
    payload.push_back(L'\0');
  }
  COPYDATASTRUCT data{kSelectionMessage,
                      static_cast<DWORD>(payload.size() * sizeof(wchar_t)),
                      payload.data()};
  DWORD_PTR result = 0;
  return SendMessageTimeoutW(
             window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data),
             SMTO_ABORTIFHUNG | SMTO_BLOCK, 5000, &result) != 0 &&
         result != 0;
}

bool IsEnabled() {
  const auto command = Command();
  if (command.empty()) {
    return false;
  }
  for (const auto* extension : kExtensions) {
    const auto key = KeyPath(extension) + L"\\command";
    wchar_t value[32768];
    DWORD bytes = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, key.c_str(), nullptr, RRF_RT_REG_SZ,
                     nullptr, value, &bytes) != ERROR_SUCCESS ||
        command != value) {
      return false;
    }
  }
  return true;
}

LSTATUS SetEnabled(bool is_enabled, const std::wstring& label) {
  const auto command = Command();
  if (command.empty()) {
    return ERROR_BAD_PATHNAME;
  }
  for (const auto* extension : kExtensions) {
    const auto path = KeyPath(extension);
    // ユーザーが選んだ登録状態を、対応する拡張子へ順に反映する
    if (!is_enabled) {
      const LSTATUS status = RegDeleteTreeW(HKEY_CURRENT_USER, path.c_str());
      if (status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND) {
        return status;
      }
      continue;
    }
    HKEY key = nullptr;
    LSTATUS status =
        RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0,
                        KEY_WRITE, nullptr, &key, nullptr);
    if (status != ERROR_SUCCESS) {
      return status;
    }
    status = WriteValue(key, nullptr, label);
    if (status == ERROR_SUCCESS) {
      status = WriteValue(key, L"Icon", L"\"" + ExecutablePath() + L"\",0");
    }
    if (status == ERROR_SUCCESS) {
      status = WriteValue(key, L"MultiSelectModel", L"Player");
    }
    RegCloseKey(key);
    if (status != ERROR_SUCCESS) {
      return status;
    }
    status = RegCreateKeyExW(HKEY_CURRENT_USER, (path + L"\\command").c_str(),
                             0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr);
    if (status != ERROR_SUCCESS) {
      return status;
    }
    status = WriteValue(key, nullptr, command);
    RegCloseKey(key);
    if (status != ERROR_SUCCESS) {
      return status;
    }
  }
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return ERROR_SUCCESS;
}

bool UsesModernMenu() {
  // アプリ互換モードのバージョン補正を受けず、実際の OS ビルドで経路を選ぶ
  using GetVersion = LONG(WINAPI*)(OSVERSIONINFOW*);
  const auto get_version = reinterpret_cast<GetVersion>(
      GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  OSVERSIONINFOW version{};
  version.dwOSVersionInfoSize = sizeof(version);
  return get_version != nullptr && get_version(&version) == 0 &&
         version.dwBuildNumber >= 22000;
}

DWORD GetStatus(std::string& state) {
  if (!UsesModernMenu()) {
    state = IsEnabled() ? "enabled" : "disabled";
    return ERROR_SUCCESS;
  }
  // Package Manager の照会を小さなヘルパーへ任せ、設定ファイルの記録と区別する
  const auto helper = std::filesystem::path(ExecutablePath()).parent_path() /
                      L"ImageSquoosherShellRegistration.exe";
  auto command = L"\"" + helper.wstring() + L"\" --status";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    return GetLastError();
  }
  CloseHandle(process.hThread);
  const DWORD wait_result = WaitForSingleObject(process.hProcess, 5000);
  DWORD exit_code = ERROR_TIMEOUT;
  if (wait_result == WAIT_OBJECT_0) {
    if (!GetExitCodeProcess(process.hProcess, &exit_code)) {
      exit_code = GetLastError();
    }
  }
  CloseHandle(process.hProcess);
  if (exit_code > 2) {
    return exit_code;
  }
  state = exit_code == 0 ? "enabled" : exit_code == 2 ? "repair" : "disabled";
  return ERROR_SUCCESS;
}

DWORD StartUpdate(bool is_enabled, const std::wstring& label, HANDLE& process) {
  process = nullptr;
  if (!UsesModernMenu()) {
    return SetEnabled(is_enabled, label);
  }
  // UAC と登録の待機はヘルパーが引き受け、通常のアプリは描画と入力を続ける
  const auto helper = std::filesystem::path(ExecutablePath()).parent_path() /
                      L"ImageSquoosherShellRegistration.exe";
  auto command = L"\"" + helper.wstring() +
                 (is_enabled ? L"\" --register" : L"\" --unregister");
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION information{};
  if (!CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, nullptr, &startup,
                      &information)) {
    return GetLastError();
  }
  CloseHandle(information.hThread);
  process = information.hProcess;
  return ERROR_SUCCESS;
}

DWORD CompleteUpdate() {
  // 新メニューの登録が確定した後で、同じアプリの旧メニュー項目を整理する
  const auto legacy_status = SetEnabled(false, L"");
  if (legacy_status != ERROR_SUCCESS) {
    return legacy_status;
  }
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return ERROR_SUCCESS;
}

std::vector<uint8_t> GetUACShieldIcon() {
  using Microsoft::WRL::ComPtr;
  SHSTOCKICONINFO icon{};
  icon.cbSize = sizeof(icon);
  if (FAILED(SHGetStockIconInfo(SIID_SHIELD, SHGSI_ICON | SHGSI_SMALLICON,
                                &icon))) {
    return {};
  }
  // OS のアイコンから透過 PNG を作り、Flutter 側でも同じ盾を表示する
  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICBitmap> bitmap;
  HRESULT result = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                     CLSCTX_INPROC_SERVER,
                                     IID_PPV_ARGS(&factory));
  if (SUCCEEDED(result)) {
    result = factory->CreateBitmapFromHICON(icon.hIcon, &bitmap);
  }
  DestroyIcon(icon.hIcon);
  if (FAILED(result)) {
    return {};
  }
  ComPtr<IStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  UINT width = 0;
  UINT height = 0;
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) ||
      FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) ||
      FAILED(encoder->CreateNewFrame(&frame, nullptr)) ||
      FAILED(frame->Initialize(nullptr)) ||
      FAILED(bitmap->GetSize(&width, &height)) ||
      FAILED(frame->SetSize(width, height)) ||
      FAILED(frame->SetPixelFormat(&format)) ||
      FAILED(frame->WriteSource(bitmap.Get(), nullptr)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return {};
  }
  STATSTG statistics{};
  if (FAILED(stream->Stat(&statistics, STATFLAG_NONAME)) ||
      statistics.cbSize.QuadPart > 1024 * 1024) {
    return {};
  }
  std::vector<uint8_t> bytes(static_cast<size_t>(statistics.cbSize.QuadPart));
  LARGE_INTEGER offset{};
  ULONG read = 0;
  if (FAILED(stream->Seek(offset, STREAM_SEEK_SET, nullptr)) ||
      FAILED(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read)) ||
      read != bytes.size()) {
    return {};
  }
  return bytes;
}
}  // namespace shell_integration
