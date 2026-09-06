#include "shell_extension.h"

#include <shlobj.h>
#include <shlwapi.h>
#include <windows.h>
#include <wrl.h>
#include <wrl/module.h>

#include <algorithm>
#include <memory>
#include <new>
#include <string>
#include <vector>

namespace {

using Microsoft::WRL::RuntimeClass;
using Microsoft::WRL::RuntimeClassFlags;

constexpr wchar_t kApplicationName[] = L"ImageSquoosher.exe";
constexpr size_t kMaximumCommandLineLength = 30000;
constexpr const wchar_t* kSupportedExtensions[] = {
    L".jpg",
    L".jpeg",
    L".png",
    L".webp",
};

HMODULE g_shell_module = nullptr;

/// DLL と同じディレクトリにあるアプリ本体の絶対パスを取得する
/// @returns 取得した絶対パス (取得失敗時は空)
std::wstring ApplicationPath() {
  std::wstring module_path(32768, L'\0');
  const DWORD length = GetModuleFileNameW(
      g_shell_module, module_path.data(),
      static_cast<DWORD>(module_path.size()));
  if (length == 0 || length == module_path.size()) {
    return {};
  }
  module_path.resize(length);
  const size_t separator = module_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return {};
  }
  module_path.resize(separator + 1);
  module_path.append(kApplicationName);
  return module_path;
}

/// Explorer が渡した項目をアプリで処理できる通常画像として検証する
/// @param path 検証するファイルシステムパス
/// @returns 対応する実在画像なら true
bool IsSupportedImage(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    return false;
  }

  // 拡張子の大文字小文字は Windows の通常のファイル選択と同じように区別しない
  const wchar_t* extension = PathFindExtensionW(path.c_str());
  return std::any_of(
      std::begin(kSupportedExtensions), std::end(kSupportedExtensions),
      [&](const wchar_t* supported_extension) {
        return _wcsicmp(extension, supported_extension) == 0;
      });
}

/// IShellItemArray から対応画像だけを選択順に取得する
/// @param items Explorer が渡した選択項目
/// @param paths 対応画像の格納先
/// @returns IShellItemArray の読み取り結果
HRESULT CollectSupportedPaths(IShellItemArray* items,
                              std::vector<std::wstring>* paths) {
  if (paths == nullptr) {
    return E_POINTER;
  }
  paths->clear();
  if (items == nullptr) {
    return S_OK;
  }

  DWORD count = 0;
  HRESULT result = items->GetCount(&count);
  if (FAILED(result)) {
    return result;
  }
  for (DWORD index = 0; index < count; ++index) {
    Microsoft::WRL::ComPtr<IShellItem> item;
    result = items->GetItemAt(index, &item);
    if (FAILED(result)) {
      return result;
    }

    PWSTR raw_path = nullptr;
    result = item->GetDisplayName(SIGDN_FILESYSPATH, &raw_path);
    if (FAILED(result)) {
      // 仮想項目はファイルシステム上の画像ではないため選択対象から外す
      continue;
    }
    const std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> owned_path(
        raw_path, CoTaskMemFree);
    if (raw_path == nullptr) {
      return E_FAIL;
    }
    std::wstring path(raw_path);
    if (!IsSupportedImage(path)) {
      continue;
    }

    // 同じファイルが複数の Shell Item として現れてもアプリへは一度だけ渡す
    const bool is_duplicate =
        std::any_of(paths->begin(), paths->end(), [&](const auto& existing) {
          return _wcsicmp(existing.c_str(), path.c_str()) == 0;
        });
    if (!is_duplicate) {
      paths->push_back(std::move(path));
    }
  }
  return S_OK;
}

/// CreateProcessW() へ渡す引用符付き引数を組み立てる
/// @param value 1つのファイルパス
/// @returns Windows の引数規則に従う文字列
std::wstring QuoteArgument(const std::wstring& value) {
  // Windows の通常ファイルパスは外側の引用符だけで1引数として保持できる
  return L"\"" + value + L"\"";
}

/// アプリ本体を一つの選択バッチで起動する
/// @param application_path DLL と同じディレクトリにある実行ファイル
/// @param command_line 実行ファイル名と選択画像を含む変更可能なコマンドライン
/// @returns プロセスを作成できた場合は S_OK
HRESULT StartApplication(const std::wstring& application_path,
                         std::wstring command_line) {
  const size_t separator = application_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return HRESULT_FROM_WIN32(ERROR_BAD_PATHNAME);
  }
  const std::wstring application_directory =
      application_path.substr(0, separator);
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  const BOOL is_started = CreateProcessW(
      application_path.c_str(), command_line.data(), nullptr, nullptr, FALSE, 0,
      nullptr, application_directory.c_str(), &startup_info, &process_info);
  if (!is_started) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  // Explorer プロセスには子プロセスのハンドルを残さず、アプリの寿命を独立させる
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  return S_OK;
}

class __declspec(uuid("899D9BF0-62F9-49AC-B592-01EEE3C8CF27"))
    ImageSquoosherExplorerCommand final
    : public RuntimeClass<RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
                          IExplorerCommand> {
 public:
  /// Windows 11 の先頭メニューへ全言語共通のアプリ名を返す
  /// @param items Explorer が渡した選択項目
  /// @param name CoTaskMemFree() で解放する表示名の格納先
  /// @returns 表示名を確保できた場合は S_OK
  IFACEMETHODIMP GetTitle(IShellItemArray* items, LPWSTR* name) override {
    UNREFERENCED_PARAMETER(items);
    if (name == nullptr) {
      return E_POINTER;
    }
    *name = nullptr;

    // パッケージ単独で表示名を解決できるよう、メニューには固定の製品名を使う
    return SHStrDupW(L"ImageSquoosher", name);
  }

  /// アプリ本体のアイコンをメニュー項目へ表示する
  /// @param items Explorer が渡した選択項目
  /// @param icon CoTaskMemFree() で解放するアイコン指定の格納先
  /// @returns アイコン指定を確保できた場合は S_OK
  IFACEMETHODIMP GetIcon(IShellItemArray* items, LPWSTR* icon) override {
    UNREFERENCED_PARAMETER(items);
    if (icon == nullptr) {
      return E_POINTER;
    }
    *icon = nullptr;
    try {
      const std::wstring application_path = ApplicationPath();
      if (application_path.empty()) {
        return E_FAIL;
      }
      return SHStrDupW((application_path + L",0").c_str(), icon);
    } catch (const std::bad_alloc&) {
      return E_OUTOFMEMORY;
    } catch (...) {
      return E_FAIL;
    }
  }

  /// 補足文を空にした単一メニュー項目として扱う
  /// @param items Explorer が渡した選択項目
  /// @param tooltip 補足文の格納先
  /// @returns 補足文なしを示す E_NOTIMPL
  IFACEMETHODIMP GetToolTip(IShellItemArray* items,
                            LPWSTR* tooltip) override {
    UNREFERENCED_PARAMETER(items);
    if (tooltip == nullptr) {
      return E_POINTER;
    }
    *tooltip = nullptr;
    return E_NOTIMPL;
  }

  /// 登録に使用する CLSID をコマンドの固定識別子として返す
  /// @param command_name GUID の格納先
  /// @returns 識別子を格納した場合は S_OK
  IFACEMETHODIMP GetCanonicalName(GUID* command_name) override {
    if (command_name == nullptr) {
      return E_POINTER;
    }
    *command_name = image_squoosher::shell_extension::kExplorerCommandCLSID;
    return S_OK;
  }

  /// 選択項目に対応画像が含まれる場合だけコマンドを表示する
  /// @param items Explorer が渡した選択項目
  /// @param is_slow_allowed Explorer が時間のかかる検査を許可する指定
  /// @param state 表示状態の格納先
  /// @returns 選択項目を判定できた場合は S_OK
  IFACEMETHODIMP GetState(IShellItemArray* items, BOOL is_slow_allowed,
                          EXPCMDSTATE* state) override {
    UNREFERENCED_PARAMETER(is_slow_allowed);
    if (state == nullptr) {
      return E_POINTER;
    }
    *state = ECS_HIDDEN;
    try {
      std::vector<std::wstring> paths;
      const HRESULT result = CollectSupportedPaths(items, &paths);
      if (FAILED(result)) {
        return result;
      }
      *state = paths.empty() ? ECS_HIDDEN : ECS_ENABLED;
      return S_OK;
    } catch (const std::bad_alloc&) {
      return E_OUTOFMEMORY;
    } catch (...) {
      return E_FAIL;
    }
  }

  /// 対応画像をコマンドライン上限内のバッチに分けてアプリへ渡す
  /// @param items Explorer が渡した選択項目
  /// @param bind_context Explorer のバインドコンテキスト
  /// @returns すべての起動要求を作成できた場合は S_OK
  IFACEMETHODIMP Invoke(IShellItemArray* items,
                        IBindCtx* bind_context) override {
    UNREFERENCED_PARAMETER(bind_context);
    try {
      std::vector<std::wstring> paths;
      HRESULT result = CollectSupportedPaths(items, &paths);
      if (FAILED(result) || paths.empty()) {
        return result;
      }
      const std::wstring application_path = ApplicationPath();
      const DWORD application_attributes =
          GetFileAttributesW(application_path.c_str());
      if (application_attributes == INVALID_FILE_ATTRIBUTES ||
          (application_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
      }

      const std::wstring command_prefix = QuoteArgument(application_path);
      std::wstring command_line = command_prefix;
      for (const auto& path : paths) {
        const std::wstring argument = L" " + QuoteArgument(path);
        if (command_prefix.size() + argument.size() + 1 >
            kMaximumCommandLineLength) {
          return HRESULT_FROM_WIN32(ERROR_FILENAME_EXCED_RANGE);
        }

        // 各バッチを余裕のある上限で区切り、CreateProcessW() の終端 NUL も範囲へ収める
        if (command_line.size() + argument.size() + 1 >
            kMaximumCommandLineLength) {
          result = StartApplication(application_path, std::move(command_line));
          if (FAILED(result)) {
            return result;
          }
          command_line = command_prefix;
        }
        command_line.append(argument);
      }
      return StartApplication(application_path, std::move(command_line));
    } catch (const std::bad_alloc&) {
      return E_OUTOFMEMORY;
    } catch (...) {
      return E_FAIL;
    }
  }

  /// 子項目と分割ボタンが空の通常コマンドとして返す
  /// @param flags コマンド属性の格納先
  /// @returns 属性を格納した場合は S_OK
  IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override {
    if (flags == nullptr) {
      return E_POINTER;
    }
    *flags = ECF_DEFAULT;
    return S_OK;
  }

  /// 単一項目としてサブコマンド列挙を空に保つ
  /// @param commands 列挙インターフェースの格納先
  /// @returns サブコマンドがないことを示す E_NOTIMPL
  IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** commands) override {
    if (commands == nullptr) {
      return E_POINTER;
    }
    *commands = nullptr;
    return E_NOTIMPL;
  }
};

CoCreatableClass(ImageSquoosherExplorerCommand);

}  // namespace

/// WRL のクラスファクトリーから Explorer コマンドを生成する
/// @param class_id Explorer が要求した CLSID
/// @param interface_id 要求されたクラスファクトリーのインターフェース
/// @param object 生成したインターフェースの格納先
/// @returns WRL のクラス検索と生成結果
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID class_id,
                                                REFIID interface_id,
                                                void** object) {
  return Microsoft::WRL::Module<Microsoft::WRL::InProc>::GetModule()
      .GetClassObject(class_id, interface_id, object);
}

/// COM オブジェクトとサーバーロックが残っていない場合に DLL の解放を許可する
/// @returns 解放できる場合は S_OK、それ以外は S_FALSE
extern "C" HRESULT __stdcall DllCanUnloadNow() {
  return Microsoft::WRL::Module<Microsoft::WRL::InProc>::GetModule().Terminate()
             ? S_OK
             : S_FALSE;
}

/// アプリ本体の位置を解決するため DLL 自身のモジュールを保持する
/// @param module 読み込まれた DLL モジュール
/// @param reason 呼び出し理由
/// @param reserved Windows が管理する予約ポインター
/// @returns DLL の読み込みを継続する TRUE
BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
  UNREFERENCED_PARAMETER(reserved);
  if (reason == DLL_PROCESS_ATTACH) {
    g_shell_module = module;
    DisableThreadLibraryCalls(module);
  }
  return TRUE;
}
