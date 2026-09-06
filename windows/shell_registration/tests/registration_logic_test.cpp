#include "../registration_logic.h"

#include <iostream>
#include <vector>

using image_squoosher::shell_registration::ClassifyRegistrations;
using image_squoosher::shell_registration::IsValidEventPrefix;
using image_squoosher::shell_registration::RegistrationRecord;

/// パッケージやレジストリを変更せず、状態終了コードと内部引数の境界を検証する
/// @returns 全検証に成功した場合は0、それ以外は1
int main() {
  bool is_success = true;
  const auto check = [&](bool condition, const char* message) {
    if (!condition) {
      std::cerr << message << '\n';
      is_success = false;
    }
  };

  const std::wstring expected_path = L"C:\\配布 フォルダ\\ImageSquoosher";
  check(ClassifyRegistrations({}, expected_path) == 1,
        "An absent registration was not classified as status 1.");
  check(ClassifyRegistrations(
            {{L"package", L"c:/配布 フォルダ/ImageSquoosher/", true}},
            expected_path) == 0,
        "The current folder registration was not classified as status 0.");

  // パスの移動、破損、同じ ID の競合をすべて修復対象へ分類する
  check(ClassifyRegistrations({{L"package", L"D:\\Moved", true}},
                              expected_path) == 2,
        "A moved registration was not classified as status 2.");
  check(ClassifyRegistrations({{L"package", expected_path, false}},
                              expected_path) == 2,
        "A broken registration was not classified as status 2.");
  check(ClassifyRegistrations(
            {{L"package-v1", expected_path, true},
             {L"package-v2", L"D:\\Old", true}},
            expected_path) == 2,
        "Conflicting registrations were not classified as status 2.");

  const std::wstring valid_prefix =
      L"Local\\ImageSquoosher.ShellRegistration."
      L"{12345678-1234-ABCD-9876-0123456789ab}";
  check(IsValidEventPrefix(valid_prefix),
        "A valid event prefix was rejected.");
  check(!IsValidEventPrefix(valid_prefix + L".Done"),
        "An event name with an injected suffix was accepted.");
  check(!IsValidEventPrefix(
            L"Global\\ImageSquoosher.ShellRegistration."
            L"{12345678-1234-ABCD-9876-0123456789ab}"),
        "An event prefix outside the current session was accepted.");
  check(!IsValidEventPrefix(
            L"Local\\ImageSquoosher.ShellRegistration."
            L"{12345678-1234-ABCD-9876-0123456789az}"),
        "A malformed GUID was accepted.");
  return is_success ? 0 : 1;
}
