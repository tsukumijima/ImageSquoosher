#include "registration_logic.h"

#include <cwctype>

namespace image_squoosher::shell_registration {
namespace {
constexpr const wchar_t* kEventPrefix =
    L"Local\\ImageSquoosher.ShellRegistration.";
}  // namespace

std::wstring NormalizePathForComparison(std::wstring path) {
  // Win32 API と WinRT が返す同じ場所を、表記の違いだけで別登録と判定しないように揃える
  for (auto& character : path) {
    if (character == L'/') {
      character = L'\\';
    } else {
      character = static_cast<wchar_t>(std::towupper(character));
    }
  }
  if (path.rfind(L"\\\\?\\UNC\\", 0) == 0) {
    path.replace(0, 8, L"\\\\");
  } else if (path.rfind(L"\\\\?\\", 0) == 0) {
    path.erase(0, 4);
  }
  while (path.size() > 3 && path.back() == L'\\') {
    path.pop_back();
  }
  return path;
}

int ClassifyRegistrations(
    const std::vector<RegistrationRecord>& registrations,
    const std::wstring& expected_path) {
  if (registrations.empty()) {
    return kStatusNotRegistered;
  }

  const std::wstring normalized_expected_path =
      NormalizePathForComparison(expected_path);
  bool has_healthy_registration_here = false;
  for (const auto& registration : registrations) {
    // 同じ ID の破損登録や別フォルダの登録が一つでも残る状態は、再登録で直す必要がある
    if (!registration.is_healthy ||
        NormalizePathForComparison(registration.installed_path) !=
            normalized_expected_path) {
      return kStatusDifferentPathOrBroken;
    }
    has_healthy_registration_here = true;
  }
  return has_healthy_registration_here ? kStatusRegisteredHere
                                       : kStatusDifferentPathOrBroken;
}

bool IsValidEventPrefix(const std::wstring& prefix) {
  const std::wstring fixed_prefix = kEventPrefix;
  if (prefix.rfind(fixed_prefix, 0) != 0 ||
      prefix.size() != fixed_prefix.size() + 38) {
    return false;
  }

  const std::wstring guid = prefix.substr(fixed_prefix.size());
  for (size_t index = 0; index < guid.size(); ++index) {
    const wchar_t character = guid[index];
    const bool is_separator = index == 0 || index == 9 || index == 14 ||
                              index == 19 || index == 24 || index == 37;
    if (is_separator) {
      const wchar_t expected = index == 0 ? L'{' : index == 37 ? L'}' : L'-';
      if (character != expected) {
        return false;
      }
      continue;
    }
    if (!std::iswxdigit(character)) {
      return false;
    }
  }
  return true;
}

}  // namespace image_squoosher::shell_registration
