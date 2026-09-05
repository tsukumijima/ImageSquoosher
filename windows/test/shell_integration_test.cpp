#include "../runner/shell_integration.h"

#include <filesystem>
#include <fstream>
#include <iostream>

namespace {
/// UTF-16 の選択一覧を実際の受信形式でデコードする。
/// @param payload 終端 NUL を含むペイロード
/// @returns 検証後の選択画像
std::vector<std::wstring> Decode(std::wstring& payload) {
  COPYDATASTRUCT data{shell_integration::kSelectionMessage,
                      static_cast<DWORD>(payload.size() * sizeof(wchar_t)),
                      payload.data()};
  return shell_integration::DecodeSelection(data);
}
}  // namespace

/// レジストリを書き換えず、プロセス間の入力境界を実ファイルで検証する。
/// @returns 全検証に成功した場合は0、それ以外は1
int main() {
  const auto directory =
      std::filesystem::temp_directory_path() /
      (L"ImageSquoosher native " + std::to_wstring(GetCurrentProcessId()) +
       L" " + std::to_wstring(GetTickCount64()));
  std::filesystem::create_directory(directory);
  const auto first = directory / L"日本語 空白.png";
  const auto second = directory / L"second.webp";
  const auto unsupported = directory / L"unsupported.txt";
  std::ofstream(first).put('a');
  std::ofstream(second).put('b');
  std::ofstream(unsupported).put('c');

  bool is_success = true;
  const auto check = [&](bool condition, const char* message) {
    if (!condition) {
      std::cerr << message << '\n';
      is_success = false;
    }
  };
  std::wstring payload = first.wstring();
  payload.push_back(L'\0');
  payload.append(second.wstring());
  payload.push_back(L'\0');
  check(Decode(payload) ==
            std::vector<std::wstring>{first.wstring(), second.wstring()},
        "Unicode multi-file selection failed.");

  // 非対応ファイルと重複を除き、対応画像の順序を維持する
  payload.append(unsupported.wstring());
  payload.push_back(L'\0');
  payload.append(first.wstring());
  payload.push_back(L'\0');
  check(Decode(payload).size() == 2, "Filtering and deduplication failed.");

  // 途中の空要素や末尾の欠損を含む場合は、ペイロード全体を不正として扱う
  auto malformed = payload;
  malformed.pop_back();
  check(Decode(malformed).empty(), "Unterminated payload was accepted.");
  malformed = first.wstring();
  malformed.append(2, L'\0');
  malformed.append(second.wstring());
  malformed.push_back(L'\0');
  check(Decode(malformed).empty(), "Interior empty item was accepted.");
  COPYDATASTRUCT invalid{shell_integration::kSelectionMessage, 3,
                         payload.data()};
  check(shell_integration::DecodeSelection(invalid).empty(),
        "Odd byte count was accepted.");
  invalid = COPYDATASTRUCT{shell_integration::kSelectionMessage, 2, nullptr};
  check(shell_integration::DecodeSelection(invalid).empty(),
        "Null payload was accepted.");
  invalid = COPYDATASTRUCT{
      0, static_cast<DWORD>(payload.size() * sizeof(wchar_t)), payload.data()};
  check(shell_integration::DecodeSelection(invalid).empty(),
        "Unknown message was accepted.");

  // 検証専用に作成した数バイトのファイルを、その一時ディレクトリ内で片付ける
  std::filesystem::remove_all(directory);
  return is_success ? 0 : 1;
}
