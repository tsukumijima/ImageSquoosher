/// GitHub Releases を確認する更新通知サービス。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../models/github_release.dart';
import '../utils/version_utils.dart';
import 'logging_service.dart';

/// 更新確認の結果。
class UpdateCheckResult {
  /// 更新確認結果を作成する。
  /// @param isUpdateAvailable 新しいバージョンが利用できるかどうか
  /// @param currentVersion 実行中のアプリケーションバージョン
  /// @param latestVersion 最新リリースのバージョン
  /// @param latestRelease 最新リリースの情報
  /// @param errorMessage 更新確認に失敗した場合のエラーメッセージ
  const UpdateCheckResult({
    required this.isUpdateAvailable,
    required this.currentVersion,
    this.latestVersion,
    this.latestRelease,
    this.errorMessage,
  });

  /// 新しいバージョンが利用できるかどうか。
  final bool isUpdateAvailable;

  /// 実行中のアプリケーションバージョン。
  final String currentVersion;

  /// 最新リリースのバージョン。
  final String? latestVersion;

  /// 最新リリースの情報。
  final GitHubRelease? latestRelease;

  /// 更新確認に失敗した場合のエラーメッセージ。
  final String? errorMessage;

  /// 更新確認が成功したかを判定する。
  /// @returns エラーがない場合は `true`
  bool get isSuccess => errorMessage == null;

  /// UI が参照するリリースページの URL を取得する。
  /// @returns 最新リリースの URL。取得できない場合は `null`
  String? get releaseURL => latestRelease?.htmlURL;
}

/// 更新確認を多重実行せず、取得結果をアプリ全体で共有する。
class UpdateCheckService {
  /// アプリ全体で共有する更新確認サービスを作成する。
  UpdateCheckService._();

  /// アプリ全体で共有するシングルトンインスタンス。
  static final UpdateCheckService instance = UpdateCheckService._();

  /// ImageSquoosher の最新リリースを取得する GitHub API エンドポイント。
  static const _releaseEndpoint = 'https://api.github.com/repos/tsukumijima/ImageSquoosher/releases/latest';

  /// 更新確認のログ出力先。
  final LoggingService _log = LoggingService.instance;

  /// 最新の更新確認結果。
  UpdateCheckResult? _cachedResult;

  /// 多重実行中の確認を共有する完了通知。
  Completer<UpdateCheckResult>? _checkCompleter;

  /// キャッシュされた更新確認結果を取得する。
  /// @returns キャッシュされた結果。未確認の場合は `null`
  UpdateCheckResult? get cachedResult => _cachedResult;

  /// GitHub の最新リリースを取得し、進行中の確認があれば同じ結果を待つ。
  /// @param force キャッシュを無視して確認するかどうか
  /// @returns 更新確認の結果
  Future<UpdateCheckResult> check({bool force = false}) async {
    if (force == false && _cachedResult != null) {
      _log.debug('Returning cached update check result.', tag: 'Update');
      return _cachedResult!;
    }

    if (_checkCompleter != null) {
      _log.debug('Update check already in progress, waiting.', tag: 'Update');
      return _checkCompleter!.future;
    }

    _checkCompleter = Completer<UpdateCheckResult>();
    _log.info('Checking for updates.', tag: 'Update');
    try {
      final result = await _performUpdateCheck();
      _cachedResult = result;
      _checkCompleter!.complete(result);
      return result;
    } catch (error, stackTrace) {
      _log.warning('Update check failed.', tag: 'Update', error: error, stackTrace: stackTrace);
      final result = UpdateCheckResult(
        isUpdateAvailable: false,
        currentVersion: await _loadCurrentVersion(),
        errorMessage: 'Failed to check for updates.',
      );
      _cachedResult = result;
      _checkCompleter!.complete(result);
      return result;
    } finally {
      _checkCompleter = null;
    }
  }

  /// PackageInfo のバージョンと GitHub の最新リリースを比較する。
  /// @returns 更新確認の結果
  Future<UpdateCheckResult> _performUpdateCheck() async {
    final currentVersion = await _loadCurrentVersion();
    final response = await http
        .get(
          Uri.parse(_releaseEndpoint),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      final message = response.statusCode == 404
          ? 'No releases found.'
          : 'GitHub API returned HTTP ${response.statusCode}.';
      _log.warning(message, tag: 'Update');
      return UpdateCheckResult(isUpdateAvailable: false, currentVersion: currentVersion, errorMessage: message);
    }

    final release = GitHubRelease.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    final isUpdateAvailable =
        release.isPrerelease == false &&
        release.isDraft == false &&
        isNewerVersionAvailable(currentVersion, release.version);
    _log.info(
      isUpdateAvailable
          ? 'New version available: ${release.version} (current: $currentVersion).'
          : 'No update available.',
      tag: 'Update',
    );
    return UpdateCheckResult(
      isUpdateAvailable: isUpdateAvailable,
      currentVersion: currentVersion,
      latestVersion: release.version,
      latestRelease: release,
    );
  }

  /// パッケージ情報から実行中のアプリケーションバージョンを取得する。
  /// @returns アプリケーションバージョン。取得失敗時は `unknown`
  Future<String> _loadCurrentVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (error, stackTrace) {
      _log.warning('Failed to load the application version.', tag: 'Update', error: error, stackTrace: stackTrace);
      return 'unknown';
    }
  }

  /// 次回の確認で GitHub API から新しい結果を取得する。
  void clearCache() {
    _cachedResult = null;
  }
}
