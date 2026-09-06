#include "shell_extension.h"

#include <shlobj.h>
#include <windows.h>
#include <wrl.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <string>
#include <thread>
#include <vector>

namespace {

using DllCanUnloadNowFunction = HRESULT(__stdcall*)();
using DllGetClassObjectFunction =
    HRESULT(__stdcall*)(REFCLSID, REFIID, void**);

/// 実在するパスから Explorer と同じ IShellItemArray を構築する
/// @param paths 選択項目として渡すパス
/// @returns 構築した IShellItemArray (失敗時は空)
Microsoft::WRL::ComPtr<IShellItemArray> CreateSelection(
    const std::vector<std::wstring>& paths) {
  std::vector<PIDLIST_ABSOLUTE> item_identifier_lists;
  for (const auto& path : paths) {
    PIDLIST_ABSOLUTE item_identifier_list = nullptr;
    if (FAILED(SHParseDisplayName(path.c_str(), nullptr,
                                  &item_identifier_list, 0,
                                  nullptr))) {
      // 途中まで確保した ITEMIDLIST も COM の割り当て規則に従って解放する
      for (const auto existing_identifier_list : item_identifier_lists) {
        CoTaskMemFree(existing_identifier_list);
      }
      return {};
    }
    item_identifier_lists.push_back(item_identifier_list);
  }

  Microsoft::WRL::ComPtr<IShellItemArray> selection;
  std::vector<PCIDLIST_ABSOLUTE> immutable_identifier_lists(
      item_identifier_lists.begin(), item_identifier_lists.end());
  const HRESULT result = SHCreateShellItemArrayFromIDLists(
      static_cast<UINT>(immutable_identifier_lists.size()),
      immutable_identifier_lists.data(), &selection);
  for (const auto item_identifier_list : item_identifier_lists) {
    CoTaskMemFree(item_identifier_list);
  }
  return SUCCEEDED(result) ? selection : nullptr;
}

/// 模擬アプリが保存したプロセス別ログから全パスを読み取る
/// @param log_directory ログファイルを格納したディレクトリ
/// @param process_count 完全に読み取れたプロセス数の格納先
/// @param path_count 完全に読み取れたパス数の格納先
/// @returns 読み取れたパスの集合
std::set<std::wstring> ReadInvokedPaths(
    const std::filesystem::path& log_directory, size_t* process_count,
    size_t* path_count) {
  std::set<std::wstring> paths;
  *process_count = 0;
  *path_count = 0;
  for (const auto& entry : std::filesystem::directory_iterator(log_directory)) {
    if (entry.path().extension() != L".bin") {
      continue;
    }
    std::ifstream stream(entry.path(), std::ios::binary);
    uint32_t serialized_path_count = 0;
    // 模擬アプリがファイルを閉じた完成版だけを読み取る
    if (!stream.read(reinterpret_cast<char*>(&serialized_path_count),
                     sizeof(serialized_path_count))) {
      continue;
    }
    std::vector<std::wstring> process_paths;
    bool is_complete = true;
    for (uint32_t index = 0; index < serialized_path_count; ++index) {
      uint32_t path_length = 0;
      if (!stream.read(reinterpret_cast<char*>(&path_length),
                       sizeof(path_length))) {
        is_complete = false;
        break;
      }
      std::wstring path(path_length, L'\0');
      if (path_length > 0 &&
          !stream.read(reinterpret_cast<char*>(path.data()),
                       path_length * sizeof(wchar_t))) {
        is_complete = false;
        break;
      }
      process_paths.push_back(std::move(path));
    }
    if (is_complete) {
      ++*process_count;
      *path_count += process_paths.size();
      paths.insert(process_paths.begin(), process_paths.end());
    }
  }
  return paths;
}

}  // namespace

/// 登録を使わず DLL の実エクスポートと Explorer の選択境界を検証する
/// @param argument_count DLL パスを含む引数の数
/// @param arguments DLL パスを含む引数
/// @returns 全検証に成功した場合は0、それ以外は1
int wmain(int argument_count, wchar_t** arguments) {
  if (argument_count != 2) {
    std::cerr << "The shell extension DLL path is required.\n";
    return 1;
  }

  bool is_success = true;
  const auto check = [&](bool is_condition_met, const char* message) {
    if (!is_condition_met) {
      std::cerr << message << '\n';
      is_success = false;
    }
  };
  const HRESULT initialization_result =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(initialization_result)) {
    std::cerr << "COM initialization failed.\n";
    return 1;
  }

  HMODULE module = LoadLibraryW(arguments[1]);
  check(module != nullptr, "The shell extension DLL could not be loaded.");
  if (module == nullptr) {
    CoUninitialize();
    return 1;
  }
  const auto get_class_object = reinterpret_cast<DllGetClassObjectFunction>(
      GetProcAddress(module, "DllGetClassObject"));
  const auto can_unload = reinterpret_cast<DllCanUnloadNowFunction>(
      GetProcAddress(module, "DllCanUnloadNow"));
  check(get_class_object != nullptr,
        "DllGetClassObject was not exported by name.");
  check(can_unload != nullptr, "DllCanUnloadNow was not exported by name.");
  if (get_class_object == nullptr || can_unload == nullptr) {
    FreeLibrary(module);
    CoUninitialize();
    return 1;
  }
  // 実 DLL の2つの COM エクスポートとクラス識別子を直接検証する
  check(can_unload() == S_OK, "A newly loaded DLL could not be unloaded.");

  Microsoft::WRL::ComPtr<IClassFactory> class_factory;
  const CLSID unknown_class = {0x16d2252f,
                               0x2206,
                               0x48bd,
                               {0x97, 0x91, 0xf7, 0xa2, 0xb2, 0x84, 0x75, 0x14}};
  check(get_class_object(unknown_class, IID_PPV_ARGS(&class_factory)) ==
            CLASS_E_CLASSNOTAVAILABLE,
        "An unknown CLSID was accepted.");
  check(SUCCEEDED(get_class_object(
            image_squoosher::shell_extension::kExplorerCommandCLSID,
            IID_PPV_ARGS(&class_factory))),
        "The Explorer command class factory was not created.");

  Microsoft::WRL::ComPtr<IExplorerCommand> command;
  check(class_factory != nullptr &&
            SUCCEEDED(class_factory->CreateInstance(
                nullptr, IID_PPV_ARGS(&command))),
        "The Explorer command COM object was not created.");
  check(class_factory != nullptr &&
            SUCCEEDED(class_factory->LockServer(TRUE)),
        "The COM server could not be locked.");
  check(can_unload() == S_FALSE,
        "The DLL allowed unloading while the COM server was locked.");
  check(class_factory != nullptr &&
            SUCCEEDED(class_factory->LockServer(FALSE)),
        "The COM server could not be unlocked.");
  class_factory.Reset();
  check(can_unload() == S_FALSE,
        "The DLL allowed unloading while a COM object was active.");

  // メニューを単一項目として描画するための表示名、アイコン、固定識別子、属性を検証する
  LPWSTR title = nullptr;
  check(command != nullptr && SUCCEEDED(command->GetTitle(nullptr, &title)) &&
            title != nullptr && wcscmp(title, L"ImageSquoosher") == 0,
        "The menu label was not the fixed application name.");
  CoTaskMemFree(title);
  LPWSTR icon = nullptr;
  check(command != nullptr && SUCCEEDED(command->GetIcon(nullptr, &icon)) &&
            icon != nullptr && wcsstr(icon, L"ImageSquoosher.exe,0") != nullptr,
        "The application icon location was not returned.");
  CoTaskMemFree(icon);
  GUID canonical_name{};
  check(command != nullptr &&
            SUCCEEDED(command->GetCanonicalName(&canonical_name)) &&
            canonical_name ==
                image_squoosher::shell_extension::kExplorerCommandCLSID,
        "The canonical command CLSID did not match.");
  EXPCMDFLAGS flags = ECF_HASSUBCOMMANDS;
  check(command != nullptr && SUCCEEDED(command->GetFlags(&flags)) &&
            flags == ECF_DEFAULT,
        "The command was not exposed as a single menu item.");

  const auto test_directory =
      std::filesystem::temp_directory_path() /
      (L"ImageSquoosher shell " + std::to_wstring(GetCurrentProcessId()) +
       L" " + std::to_wstring(GetTickCount64()));
  const auto log_directory = test_directory / L"invocations";
  std::filesystem::create_directories(log_directory);
  const auto supported = test_directory / L"日本語 空白.jpg";
  const auto supported_jpeg = test_directory / L"uppercase.JPEG";
  const auto supported_png = test_directory / L"transparent.png";
  const auto supported_webp = test_directory / L"animation.webp";
  const auto unsupported = test_directory / L"document.txt";
  std::ofstream(supported).put('a');
  std::ofstream(supported_jpeg).put('a');
  std::ofstream(supported_png).put('a');
  std::ofstream(supported_webp).put('a');
  std::ofstream(unsupported).put('b');

  // フォルダと非対応ファイルだけなら隠し、対応画像を1件でも含む選択では有効にする
  EXPCMDSTATE state = ECS_DISABLED;
  auto selection = CreateSelection({unsupported.wstring(),
                                    test_directory.wstring()});
  check(selection != nullptr &&
            SUCCEEDED(command->GetState(selection.Get(), TRUE, &state)) &&
            state == ECS_HIDDEN,
        "Unsupported files and folders did not hide the command.");
  selection = CreateSelection(
      {unsupported.wstring(), supported.wstring(), test_directory.wstring()});
  check(selection != nullptr &&
            SUCCEEDED(command->GetState(selection.Get(), TRUE, &state)) &&
            state == ECS_ENABLED,
        "A mixed selection containing an image did not enable the command.");
  for (const auto& image :
       {supported, supported_jpeg, supported_png, supported_webp}) {
    selection = CreateSelection({image.wstring()});
    check(selection != nullptr &&
              SUCCEEDED(command->GetState(selection.Get(), TRUE, &state)) &&
              state == ECS_ENABLED,
          "A supported image extension did not enable the command.");
  }

  // 長い実在パスを十分に用意し、複数プロセスへ分割した後も全項目が一度ずつ届くことを確認する
  std::vector<std::wstring> expected_paths;
  for (int index = 0; index < 400; ++index) {
    const auto path =
        test_directory /
        (L"image_" + std::to_wstring(index) + L"_" +
         std::wstring(80, static_cast<wchar_t>(L'a' + index % 26)) + L".webp");
    std::ofstream(path).put('c');
    expected_paths.push_back(path.wstring());
  }
  std::vector<std::wstring> invoked_selection_paths = expected_paths;
  invoked_selection_paths.push_back(unsupported.wstring());
  invoked_selection_paths.push_back(test_directory.wstring());
  invoked_selection_paths.push_back(expected_paths.front());
  selection = CreateSelection(invoked_selection_paths);
  check(selection != nullptr,
        "The large Explorer selection could not be constructed.");
  check(SetEnvironmentVariableW(L"IMAGE_SQUOOSHER_SHELL_TEST_LOG",
                                log_directory.c_str()) != FALSE,
        "The test log directory could not be configured.");
  check(selection != nullptr &&
            SUCCEEDED(command->Invoke(selection.Get(), nullptr)),
        "The large Explorer selection could not be invoked.");

  std::set<std::wstring> invoked_paths;
  size_t process_count = 0;
  size_t invoked_path_count = 0;
  const auto timeout = std::chrono::steady_clock::now() +
                       std::chrono::seconds(10);
  while (std::chrono::steady_clock::now() < timeout) {
    invoked_paths = ReadInvokedPaths(log_directory, &process_count,
                                     &invoked_path_count);
    if (invoked_paths.size() == expected_paths.size()) {
      break;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  SetEnvironmentVariableW(L"IMAGE_SQUOOSHER_SHELL_TEST_LOG", nullptr);
  check(process_count > 1,
        "The command-line limit did not produce multiple launch batches.");
  check(invoked_path_count == expected_paths.size(),
        "Unsupported or duplicate items reached the application.");
  check(invoked_paths ==
            std::set<std::wstring>(expected_paths.begin(), expected_paths.end()),
        "The batched launch did not preserve every selected image.");
  check(std::all_of(expected_paths.begin(), expected_paths.end(),
                    [](const auto& path) {
                      return std::filesystem::exists(path);
                    }),
        "Invoking the shell command changed a selected image.");

  command.Reset();
  selection.Reset();
  check(can_unload() == S_OK,
        "The DLL could not unload after releasing every COM object.");
  FreeLibrary(module);
  CoUninitialize();

  // 検証専用に作成した小さな入力画像とログを一時ディレクトリ内で片付ける
  std::filesystem::remove_all(test_directory);
  return is_success ? 0 : 1;
}
