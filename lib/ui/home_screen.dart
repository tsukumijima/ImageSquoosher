/// 入力画像の一覧と圧縮操作を提供するメイン画面。
library;

import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/conversion_settings.dart';
import '../services/logging_service.dart';
import '../services/settings_service.dart';
import '../services/squoosher_controller.dart';
import '../services/update_check_service.dart';
import 'theme.dart';
import 'widgets/compression_footer.dart';
import 'widgets/app_snack_bar.dart';
import 'widgets/conversion_settings_panel.dart';
import 'widgets/empty_drop_area.dart';
import 'widgets/home_header.dart';
import 'widgets/queue_header.dart';
import 'widgets/queued_image_row.dart';
import 'widgets/update_banner.dart';

/// 画像の追加・設定・圧縮をまとめる画面です。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialPreferences,
    required this.settingsService,
    required this.onLanguageChanged,
    this.controller,
    this.onExitRequested,
    this.checkForUpdatesOnInitialize = true,
    this.initializePlatformServices = true,
    this.enableDropTarget = true,
  });

  final AppPreferences initialPreferences;
  final SettingsService settingsService;
  final SquoosherController? controller;

  /// 設定保存後にアプリ層が実行する終了処理。
  final Future<void> Function()? onExitRequested;
  final ValueChanged<String> onLanguageChanged;
  final bool checkForUpdatesOnInitialize;
  final bool initializePlatformServices;
  final bool enableDropTarget;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const _finderMethodChannel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');

  late final SquoosherController _controller;
  final ScrollController _queueScrollController = ScrollController();
  final UpdateCheckService _updateCheckService = UpdateCheckService.instance;
  late AppPreferences _preferences;
  UpdateCheckResult? _updateResult;
  bool _showUpdateBanner = true;
  bool _didReceiveFinderSelection = false;
  List<String>? _pendingFinderSelection;
  bool _isDropActive = false;
  bool _isFinderSyncEnabled = false;
  String _applicationVersion = '';
  Timer? _saveTimer;
  Future<void> _saveTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _preferences = widget.initialPreferences;
    _controller = widget.controller ?? SquoosherController();
    _controller.addListener(_refresh);
    if (widget.initializePlatformServices) {
      _listenForFinderSelection();
    }
    _initialize();
  }

  @override
  void dispose() {
    _finderMethodChannel.setMethodCallHandler(null);
    _saveTimer?.cancel();
    _queueScrollController.dispose();
    _controller.removeListener(_refresh);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// 保存設定、Finder 選択、更新情報を並行して初期画面へ取り込みます。
  Future<void> _initialize() async {
    await _controller.updateOutputPlans(_preferences.conversionSettings);
    const debugFiles = String.fromEnvironment('IMAGE_SQUOOSHER_DEBUG_FILES');
    if (debugFiles.isNotEmpty) {
      _controller.replaceFiles(debugFiles.split('|'));
      await _controller.updateOutputPlans(_preferences.conversionSettings);
    }
    if (widget.initializePlatformServices) {
      await _loadFinderSelection();
      await _loadFinderSyncStatus();
      await _loadApplicationVersion();
    }
    if (widget.checkForUpdatesOnInitialize == false) {
      return;
    }

    final updateResult = await _updateCheckService.check();
    if (mounted && updateResult.isUpdateAvailable) {
      setState(() => _updateResult = updateResult);
    }
  }

  /// Finder 拡張から届く選択を、外部からの明示的な置き換えとして扱います。
  void _listenForFinderSelection() {
    _finderMethodChannel.setMethodCallHandler((call) async {
      if (call.method != 'finderSelectedImageURLs') {
        return;
      }
      final paths = _pathsFromPlatformValue(call.arguments);
      if (paths.isEmpty) {
        return;
      }
      _didReceiveFinderSelection = true;
      // 実行中のキューを保ち、変換が終了した時点で最後に選んだ画像を取り込む
      if (_controller.isCompressing) {
        _pendingFinderSelection = paths;
        return;
      }
      _pendingFinderSelection = null;
      _replaceFiles(paths);
    });
  }

  /// 起動時の Finder 選択を取得し、先行イベントがあれば新しい選択を維持します。
  Future<void> _loadFinderSelection() async {
    try {
      final value = await _finderMethodChannel.invokeMethod<dynamic>('getFinderSelectedImageURLs');
      final paths = _pathsFromPlatformValue(value);
      if (_didReceiveFinderSelection == false && paths.isNotEmpty) {
        _replaceFiles(paths);
      }
    } on MissingPluginException {
      // Finder 拡張を含まない開発環境でも通常の画像追加を利用できる
    } catch (error, stackTrace) {
      LoggingService.instance.warning(
        'Failed to load Finder selection.',
        tag: 'Finder',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Finder Sync の有効状態をメニューの次の操作へ反映します。
  Future<void> _loadFinderSyncStatus() async {
    try {
      final isEnabled = await _finderMethodChannel.invokeMethod<bool>('isFinderSyncExtensionEnabled');
      if (mounted) {
        setState(() => _isFinderSyncEnabled = isEnabled ?? false);
      }
    } on MissingPluginException {
      // Finder Sync を含まないプラットフォームでは通常のファイル追加を利用する
    } catch (error, stackTrace) {
      LoggingService.instance.warning(
        'Failed to read Finder Sync status.',
        tag: 'Finder',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// パッケージ情報から配布物と同じバージョン表記を取得します。
  Future<void> _loadApplicationVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _applicationVersion = packageInfo.version);
      }
    } catch (error, stackTrace) {
      LoggingService.instance.warning(
        'Failed to read application version.',
        tag: 'Home',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// コントローラーの変更を画面へ反映します。
  void _refresh() {
    if (mounted) {
      // 完了メッセージが元の変換件数を読み取った後、次の描画で保留中の選択を取り込む
      if (_controller.isCompressing == false && _pendingFinderSelection != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final paths = _pendingFinderSelection;
          if (mounted && _controller.isCompressing == false && paths != null) {
            // 置換もコントローラーの通知を発生させるため、保留値を先に消費する
            _pendingFinderSelection = null;
            _replaceFiles(paths);
          }
        });
      }
      setState(() {});
    }
  }

  /// ネイティブのファイル選択画面から画像を取得します。
  Future<void> _addFiles() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: true,
      );
      if (selection != null) {
        _addSelectedFiles(selection.paths.whereType<String>());
      }
    } catch (error, stackTrace) {
      LoggingService.instance.error('Failed to select image files.', tag: 'Home', error: error, stackTrace: stackTrace);
      if (mounted) {
        _showMessage(l10n.selectImagesFailed, kind: AppNoticeKind.error);
      }
    }
  }

  /// 選択画面で選んだ画像を既存のキューへ追加します。
  void _addSelectedFiles(Iterable<String> paths) {
    final supportedPaths = _supportedPaths(paths).toList();
    // 対応形式が含まれていない場合は、選べる形式を案内する
    if (supportedPaths.isEmpty && paths.isNotEmpty) {
      _showMessage(AppLocalizations.of(context).noSupportedImages);
      return;
    }
    final addedCount = _controller.addFiles(supportedPaths);
    _controller.updateOutputPlans(_preferences.conversionSettings);
    if (addedCount > 0) {
      _showMessage(AppLocalizations.of(context).filesAdded);
    } else if (paths.isNotEmpty) {
      _showMessage(AppLocalizations.of(context).duplicateFilesSkipped);
    }
  }

  /// Finder または置き換え操作で渡された画像だけをキューへ残します。
  void _replaceFiles(Iterable<String> paths) {
    final supportedPaths = _supportedPaths(paths);
    _controller.replaceFiles(supportedPaths);
    _controller.updateOutputPlans(_preferences.conversionSettings);
  }

  /// 許可された静止画形式だけを画像パイプラインへ渡します。
  Iterable<String> _supportedPaths(Iterable<String> paths) {
    return paths.where((path) {
      final lowerPath = path.toLowerCase();
      return lowerPath.endsWith('.jpg') ||
          lowerPath.endsWith('.jpeg') ||
          lowerPath.endsWith('.png') ||
          lowerPath.endsWith('.webp');
    });
  }

  /// 常時表示するフォームの変更を保存し、出力予定と表示言語へすぐ反映します。
  void _savePreferences(AppPreferences preferences) {
    setState(() => _preferences = preferences);
    unawaited(_controller.updateOutputPlans(preferences.conversionSettings));
    widget.onLanguageChanged(preferences.languageCode);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), _queuePreferencesSave);
  }

  /// 連続したフォーム入力では最後の状態だけを直列に保存します。
  void _queuePreferencesSave() {
    _saveTail = _saveTail.then((_) => widget.settingsService.save(_preferences)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      LoggingService.instance.error(
        'Failed to save application preferences.',
        tag: 'Home',
        error: error,
        stackTrace: stackTrace,
      );
    });
  }

  /// 終了と変換開始の直前に、待機中の設定保存を完了させます。
  Future<void> _flushPreferences() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _queuePreferencesSave();
    }
    await _saveTail;
  }

  /// 言語と現在のウィンドウ寸法は保ち、変換条件だけを既定値へ戻します。
  void _restoreDefaults() {
    _savePreferences(
      _preferences.copyWith(conversionSettings: const ConversionSettings()),
    );
  }

  /// 変換を開始し、完了・失敗・停止の要約を画面下部へ表示します。
  Future<void> _startCompression() async {
    // キーボードから開始した場合も数値欄の編集を終え、実効設定を表示する
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_controller.hasPendingImages || _controller.isCompressing) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      await _flushPreferences();
      final isStarted = await _controller.compress(_preferences.conversionSettings);
      if (isStarted == false && mounted) {
        _showMessage(l10n.noSupportedImages);
        return;
      }
      if (mounted) {
        final message = _controller.lastRunWasStopped
            ? l10n.compressionStopped
            : _controller.failedCount == 0
            ? l10n.conversionSucceeded(_controller.completedCount)
            : l10n.statusCompleted(_controller.completedCount, _controller.failedCount);
        _showMessage(
          message,
          kind: _controller.failedCount > 0
              ? AppNoticeKind.error
              : _controller.lastRunWasStopped
              ? AppNoticeKind.info
              : AppNoticeKind.success,
        );
      }
    } catch (error, stackTrace) {
      LoggingService.instance.error(
        'Failed to run image compression.',
        tag: 'Home',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showMessage(l10n.compressionFailed, kind: AppNoticeKind.error);
      }
    }
  }

  /// 一覧見出しの操作で、登録済み画像をすべて外します。
  void _clearFiles() {
    if (_controller.images.isEmpty) {
      return;
    }
    _controller.clear();
    _showMessage(AppLocalizations.of(context).clearConfirmation);
  }

  /// Esc とアプリ層からの閉じる操作を、停止または設定保存後の終了へ分岐します。
  Future<void> handleWindowClose() async {
    if (_controller.isCompressing) {
      _requestStop();
      return;
    }
    await _flushPreferences();
    await widget.onExitRequested?.call();
  }

  /// 停止要求を受けると、現在の画像を完了した境界で圧縮を終了します。
  void _requestStop() {
    _controller.requestStop();
  }

  /// メニューからの更新確認結果を画面へ反映します。
  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.of(context);
    _showMessage(l10n.checkingUpdates);
    final result = await _updateCheckService.check(force: true);
    if (mounted == false) {
      return;
    }
    setState(() {
      _updateResult = result;
      _showUpdateBanner = true;
    });
    if (result.isUpdateAvailable == false) {
      _showMessage(
        result.errorMessage == null ? l10n.upToDate : l10n.checkFailed,
        kind: result.errorMessage == null ? AppNoticeKind.success : AppNoticeKind.error,
      );
    }
  }

  /// Finder Sync のシステム設定画面を開きます。
  Future<void> _openFinderSettings() async {
    try {
      await _finderMethodChannel.invokeMethod<void>('showFinderSyncExtensionManagement');
    } on MissingPluginException {
      // Finder Sync を含まないプラットフォームではメニューの選択を完了扱いにする
    } catch (error, stackTrace) {
      LoggingService.instance.warning(
        'Failed to open Finder Sync extension management.',
        tag: 'Finder',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// システム設定から戻ったときに Finder Sync の有効状態を読み直します。
  Future<void> refreshFinderSyncStatus() => _loadFinderSyncStatus();

  /// 出力先のフォルダを標準ファイルマネージャーで開きます。
  Future<void> _openOutputFolder(QueuedImage queuedImage) async {
    final outputPath = queuedImage.outputPath ?? queuedImage.path;
    try {
      final directoryUri = Uri.directory(File(outputPath).parent.path);
      final opened = await launchUrl(directoryUri, mode: LaunchMode.externalApplication);
      if (opened == false && mounted) {
        _showMessage(AppLocalizations.of(context).openFolderFailed, kind: AppNoticeKind.error);
      }
    } catch (error, stackTrace) {
      LoggingService.instance.warning(
        'Failed to open output folder.',
        tag: 'Home',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage(AppLocalizations.of(context).openFolderFailed, kind: AppNoticeKind.error);
    }
  }

  /// カードの元画像と操作ボタンの出力画像を、それぞれ既定のアプリケーションで開きます。
  Future<void> _openImageFile(QueuedImage queuedImage, {required bool isSource}) async {
    final path = isSource ? queuedImage.path : queuedImage.outputPath;
    if (path == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final errorMessage = isSource ? l10n.openSourceFileFailed : l10n.openFileFailed;
    try {
      // 上書きや外部操作で元画像がなくなった場合も、選ばれたファイルの状態を通知する
      final opened = await File(path).exists() && await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showMessage(errorMessage, kind: AppNoticeKind.error);
    } catch (error, stackTrace) {
      LoggingService.instance.warning(
        'Failed to open image file.',
        tag: 'Home',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage(errorMessage, kind: AppNoticeKind.error);
    }
  }

  /// 通知を1箇所へ集め、画面が有効な間だけ `ScaffoldMessenger` で表示します。
  void _showMessage(String message, {AppNoticeKind kind = AppNoticeKind.info}) {
    if (mounted) {
      showAppSnackBar(context, message, kind: kind);
    }
  }

  /// プラットフォームチャネルの文字列配列だけを画面入力として受け付けます。
  List<String> _pathsFromPlatformValue(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }
    return value.whereType<String>().toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _startCompression,
        const SingleActivator(LogicalKeyboardKey.escape): handleWindowClose,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          // 通知の表示領域を操作ボタンより上に確保し、続けて変換できるようにする
          bottomNavigationBar: SafeArea(
            top: false,
            child: CompressionFooter(
              completedCount: _controller.completedCount,
              failedCount: _controller.failedCount,
              stoppedCount: _controller.stoppedCount,
              progress: _controller.progress,
              imageCount: _controller.images.length,
              hasValidImages: _controller.hasPendingImages,
              isCompressing: _controller.isCompressing,
              isStopping: _controller.isStopping,
              isOverwriteEnabled: _preferences.conversionSettings.overwrite,
              onStart: _startCompression,
              onStop: _requestStop,
            ),
          ),
          body: widget.enableDropTarget
              ? DropTarget(
                  onDragEntered: (details) => setState(() => _isDropActive = true),
                  onDragExited: (details) => setState(() => _isDropActive = false),
                  onDragDone: (details) {
                    setState(() => _isDropActive = false);
                    _addSelectedFiles(details.files.map((file) => file.path));
                  },
                  child: _buildBody(l10n),
                )
              : _buildBody(l10n),
        ),
      ),
    );
  }

  /// ドロップ操作の有無にかかわらず共通の画面本体を構成します。
  Widget _buildBody(AppLocalizations l10n) {
    return Container(
      decoration: getGradientBackground(context),
      child: SafeArea(
        child: Column(
          children: [
            HomeHeader(
              isCompressing: _controller.isCompressing,
              isFinderSyncEnabled: _isFinderSyncEnabled,
              isFinderIntegrationAvailable: Platform.isMacOS,
              onAddFiles: _addFiles,
              onFinderSettings: _openFinderSettings,
              onMenuAction: _handleMenuAction,
            ),
            if (_updateResult?.isUpdateAvailable == true && _showUpdateBanner)
              UpdateBanner(
                result: _updateResult!,
                onDismiss: () => setState(() => _showUpdateBanner = false),
              ),
            // 変換条件を常に見ながら各画像を確認できるよう、設定と一覧見出しを固定する
            ExcludeFocus(
              excluding: _controller.isCompressing,
              child: AbsorbPointer(
                absorbing: _controller.isCompressing,
                child: Opacity(
                  opacity: _controller.isCompressing ? 0.5 : 1,
                  child: ConversionSettingsPanel(
                    settings: _preferences.conversionSettings,
                    onChanged: (settings) {
                      _savePreferences(_preferences.copyWith(conversionSettings: settings));
                    },
                  ),
                ),
              ),
            ),
            QueueHeader(
              imageCount: _controller.images.length,
              canClear: _controller.images.isNotEmpty && _controller.isCompressing == false,
              onClear: _clearFiles,
            ),
            Expanded(
              child: _controller.images.isEmpty
                  ? EmptyDropArea(
                      isDropActive: _isDropActive,
                      isEnabled: _controller.isCompressing == false,
                      onAddFiles: _addFiles,
                    )
                  : ScrollConfiguration(
                      // デスクトップの自動スクロールバーと重複させず、一覧内の操作領域を明示する
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: Scrollbar(
                        key: const ValueKey('image-queue-scrollbar'),
                        controller: _queueScrollController,
                        thumbVisibility: true,
                        child: ListView.separated(
                          key: const ValueKey('image-queue-list'),
                          controller: _queueScrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
                          itemCount: _controller.images.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final queuedImage = _controller.images[index];
                            return QueuedImageRow(
                              key: ValueKey(queuedImage.path),
                              queuedImage: queuedImage,
                              settings: _preferences.conversionSettings,
                              canRemove: _controller.isCompressing == false,
                              onOpenSourceFile: () => _openImageFile(queuedImage, isSource: true),
                              onOpenFile: () => _openImageFile(queuedImage, isSource: false),
                              onOpenFolder: () => _openOutputFolder(queuedImage),
                              onRemove: () => _controller.removeFile(queuedImage.path),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダーメニューの操作を実行します。
  void _handleMenuAction(HomeMenuAction action) {
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case HomeMenuAction.checkForUpdates:
        _checkForUpdates();
      case HomeMenuAction.japanese:
        _savePreferences(_preferences.copyWith(languageCode: 'ja'));
      case HomeMenuAction.english:
        _savePreferences(_preferences.copyWith(languageCode: 'en'));
      case HomeMenuAction.restoreDefaults:
        _restoreDefaults();
        _showMessage(l10n.defaultsRestored, kind: AppNoticeKind.success);
      case HomeMenuAction.about:
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            constraints: const BoxConstraints(maxWidth: 420),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Row(
              children: [
                Image.asset('assets/images/app_icon_1024.png', width: 48, height: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.appTitle, style: Theme.of(context).textTheme.titleLarge),
                      Text(_applicationVersion, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            content: Text(l10n.aboutDescription, style: Theme.of(context).textTheme.bodyMedium),
            actions: [
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: l10n.appTitle,
                  applicationVersion: _applicationVersion,
                ),
                child: Text(l10n.licenses),
              ),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.close)),
            ],
          ),
        );
    }
  }
}
