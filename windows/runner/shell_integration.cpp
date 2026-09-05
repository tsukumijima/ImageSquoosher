#include "shell_integration.h"

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <cwchar>

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
}  // namespace shell_integration
