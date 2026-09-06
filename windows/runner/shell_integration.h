#ifndef RUNNER_SHELL_INTEGRATION_H_
#define RUNNER_SHELL_INTEGRATION_H_

#include <windows.h>

#include <cstdint>
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
/// Windows 11 の新しいメニューを利用する OS か確認する。
/// @returns Windows 11 以降では true
bool UsesModernMenu();
/// 登録先と現在の配置を比較し、操作ボタンに必要な状態を取得する。
/// @param state enabled、disabled、repair のいずれかを格納する出力先
/// @returns 成功時は ERROR_SUCCESS、それ以外は確認時のエラー
DWORD GetStatus(std::string& state);
/// 登録ヘルパーを起動し、ウィンドウのメッセージ処理へ制御を戻す。
/// @param is_enabled true で追加または修復、false で解除
/// @param label 表示言語に合わせたメニュー名
/// @param process 起動したプロセス (Windows 10 の同期登録では nullptr)
/// @returns 起動または同期登録に成功した場合は ERROR_SUCCESS
DWORD StartUpdate(bool is_enabled, const std::wstring& label, HANDLE& process);
/// 新メニューの登録成功後に従来の登録を解除し、Explorer へ変更を通知する。
/// @returns 更新できた場合は ERROR_SUCCESS
DWORD CompleteUpdate();
/// Windows 標準の UAC 盾アイコンを PNG として取得する。
/// @returns PNG のバイト列 (取得失敗では空)
std::vector<uint8_t> GetUACShieldIcon();
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
