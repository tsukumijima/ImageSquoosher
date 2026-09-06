#ifndef WINDOWS_SHELL_REGISTRATION_REGISTRATION_LOGIC_H_
#define WINDOWS_SHELL_REGISTRATION_REGISTRATION_LOGIC_H_

#include <string>
#include <vector>

namespace image_squoosher::shell_registration {

constexpr int kStatusRegisteredHere = 0;
constexpr int kStatusNotRegistered = 1;
constexpr int kStatusDifferentPathOrBroken = 2;
constexpr int kStatusQueryError = 3;

struct RegistrationRecord {
  std::wstring full_name;
  std::wstring installed_path;
  bool is_healthy;
};

/// 比較に影響しない区切り文字と長いパス接頭辞を取り除く
/// @param path 正規化する絶対パス
/// @returns 大文字小文字を区別しない比較に使用できるパス
std::wstring NormalizePathForComparison(std::wstring path);

/// 同じパッケージ ID の登録一覧を、現在の配布フォルダとの関係へ分類する
/// @param registrations PackageManager から得た同名・同発行者の登録一覧
/// @param expected_path 登録元であるべきヘルパーのフォルダ
/// @returns status コマンドの終了コード
int ClassifyRegistrations(const std::vector<RegistrationRecord>& registrations,
                          const std::wstring& expected_path);

/// 内部昇格コマンドへ渡せるイベント接頭辞かを検証する
/// @param prefix コマンドラインから受け取ったイベント接頭辞
/// @returns このヘルパーが生成する固定形式と一致する場合は true
bool IsValidEventPrefix(const std::wstring& prefix);

}  // namespace image_squoosher::shell_registration

#endif  // WINDOWS_SHELL_REGISTRATION_REGISTRATION_LOGIC_H_
