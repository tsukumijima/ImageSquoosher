#ifndef RUNNER_SHELL_INTEGRATION_H_
#define RUNNER_SHELL_INTEGRATION_H_

#include <windows.h>

#include <string>
#include <vector>

namespace shell_integration {
constexpr ULONG_PTR kSelectionMessage = 0x49535153;
constexpr wchar_t kWindowProperty[] = L"ImageSquoosher.MainWindow";
/// 起動引数から対応する実在画像を取得する。
/// @returns 重複を除いた UTF-16 パス
std::vector<std::wstring> ReadSelectedPaths();
/// プロセス間メッセージから対応する実在画像を取得する。
/// @param data 同期送信中の WM_COPYDATA ペイロード
/// @returns 有効なパスの一覧 (不正なペイロードでは空)
std::vector<std::wstring> DecodeSelection(const COPYDATASTRUCT& data);
/// 選択した画像を起動済みウィンドウへ渡す。
/// @param window アプリ専用プロパティで識別済みのウィンドウ
/// @param paths UTF-16 で表した選択画像
/// @returns 受信先が応答した場合または選択が空の場合は true
bool ForwardSelection(HWND window, const std::vector<std::wstring>& paths);
/// 全対応拡張子の登録先が現在の実行ファイルと一致するか確認する。
/// @returns 4種類すべてが現在の実行ファイルを指す場合は true
bool IsEnabled();
/// 現在のユーザーの Explorer メニュー登録を変更する。
/// @param is_enabled true で登録、false でアプリ専用キーを解除
/// @param label アプリの表示言語に合わせたメニュー名
/// @returns 成功時は ERROR_SUCCESS、失敗時はレジストリのエラーコード
LSTATUS SetEnabled(bool is_enabled, const std::wstring& label);
/// Windows のパスを Dart へ渡す UTF-8 文字列に変換する。
/// @param value UTF-16 のパス
/// @returns UTF-8 文字列
std::string ToUtf8(const std::wstring& value);
}  // namespace shell_integration

#endif
