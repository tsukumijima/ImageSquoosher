#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

/// コンソールを作成し、本体と Flutter の標準出力・標準エラーを接続する。
void CreateAndAttachConsole();

/// 終端文字付きの UTF-16 文字列を UTF-8 へ変換する。
/// @param utf16_string 変換元文字列のポインター (nullptr も受け付ける)
/// @returns UTF-8 文字列 (変換失敗や nullptr では空文字列)
std::string Utf8FromUtf16(const wchar_t* utf16_string);

/// 実行ファイル名を除くコマンドライン引数を取得する。
/// @returns UTF-8 の引数一覧 (取得失敗時は空の一覧)
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
