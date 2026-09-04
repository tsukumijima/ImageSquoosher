/// ファイルとコンソールへアプリケーションログを出力するサービス
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// ログの重要度
enum LogLevel { debug, info, warning, error }

/// OS ごとのアプリケーションデータ領域でログを管理する。
class LoggingService {
  /// アプリ全体で共有するログ出力先を作成する。
  LoggingService._();

  /// アプリ全体で共有するシングルトンインスタンス
  static final LoggingService instance = LoggingService._();

  /// 保持するログファイルの最大数
  static const int _maxLogFiles = 30;

  File? _logFile;
  IOSink? _logSink;
  bool _isInitialized = false;

  /// 起動ごとのログファイルを作成し、古い世代を整理する。
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      final logDirectory = _resolveLogDirectory();
      await logDirectory.create(recursive: true);

      final now = DateTime.now();
      final fileName =
          '${now.year}${_padZero(now.month)}${_padZero(now.day)}_'
          '${_padZero(now.hour)}${_padZero(now.minute)}${_padZero(now.second)}.log';
      _logFile = File(p.join(logDirectory.path, fileName));
      _logSink = _logFile!.openWrite(mode: FileMode.append);
      _isInitialized = true;

      await _cleanupOldLogs(logDirectory, _logFile!.path);
      info('Application started.', tag: 'Main');
      info('Log file: ${_logFile!.path}.', tag: 'Main');
      info('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}.', tag: 'Main');
    } catch (error, stackTrace) {
      // ファイル出力を開けない環境でもコンソールへ初期化失敗の詳細を残す
      stderr.writeln('Failed to initialize logging: $error');
      stderr.writeln(stackTrace);
    }
  }

  /// デバッグログを出力する。
  void debug(String message, {String? tag}) => _write(LogLevel.debug, message, tag: tag);

  /// 情報ログを出力する。
  void info(String message, {String? tag}) => _write(LogLevel.info, message, tag: tag);

  /// 警告ログを出力する。
  void warning(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _write(LogLevel.warning, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// エラーログを出力する。
  void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _write(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// 未書き込みのログをファイルへ反映する。
  Future<void> flush() async {
    await _logSink?.flush();
  }

  /// 終了ログを反映してファイルを閉じる。
  Future<void> dispose() async {
    if (_isInitialized == false) {
      return;
    }

    info('Application terminated.', tag: 'Main');
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    _logFile = null;
    _isInitialized = false;
  }

  /// 現在のログファイルのパスを取得する。
  String? get logFilePath => _logFile?.path;

  /// ログディレクトリのパスを取得する。
  String get logDirectoryPath => _resolveLogDirectory().path;

  /// ログ本文、例外、スタックトレースを同じ出力先へ記録する。
  void _write(LogLevel level, String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${_padZero(now.month)}-${_padZero(now.day)} '
        '${_padZero(now.hour)}:${_padZero(now.minute)}:${_padZero(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final tagText = tag == null ? '' : ' [$tag]';
    final line = '$timestamp ${level.name.toUpperCase().padRight(7)}$tagText $message';

    stdout.writeln(line);
    _logSink?.writeln(line);
    if (error != null) {
      stderr.writeln('  Error: $error');
      _logSink?.writeln('  Error: $error');
    }
    if (stackTrace != null) {
      stderr.writeln('  StackTrace:\n$stackTrace');
      _logSink?.writeln('  StackTrace:\n$stackTrace');
    }
  }

  /// 現在のログを含めて新しい30世代だけを保持する。
  Future<void> _cleanupOldLogs(Directory logDirectory, String currentLogPath) async {
    try {
      final logFiles = <({File file, DateTime modified})>[];
      await for (final entity in logDirectory.list()) {
        if (entity is! File || entity.path.toLowerCase().endsWith('.log') == false) {
          continue;
        }
        if (p.equals(entity.path, currentLogPath)) {
          continue;
        }
        final stat = await entity.stat();
        logFiles.add((file: entity, modified: stat.modified));
      }

      logFiles.sort((first, second) => second.modified.compareTo(first.modified));
      final maximumOldLogs = _maxLogFiles - 1;
      if (logFiles.length <= maximumOldLogs) {
        return;
      }

      for (final entry in logFiles.skip(maximumOldLogs)) {
        try {
          await entry.file.delete();
        } catch (error, stackTrace) {
          warning(
            'Failed to delete old log file: ${entry.file.path}.',
            tag: 'Logging',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } catch (error, stackTrace) {
      warning('Failed to clean up old log files.', tag: 'Logging', error: error, stackTrace: stackTrace);
    }
  }

  /// OS ごとのアプリケーションデータ領域からログディレクトリを決定する。
  Directory _resolveLogDirectory() {
    final String basePath;
    if (Platform.isMacOS) {
      basePath = p.join(Platform.environment['HOME'] ?? Directory.systemTemp.path, 'Library', 'Application Support');
    } else if (Platform.isWindows) {
      basePath =
          Platform.environment['APPDATA'] ??
          p.join(Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path, 'AppData', 'Roaming');
    } else {
      basePath = p.join(Platform.environment['HOME'] ?? Directory.systemTemp.path, '.local', 'share');
    }
    return Directory(p.join(basePath, 'ImageSquoosher', 'Logs'));
  }

  /// 数値を2桁へゼロ埋めする。
  static String _padZero(int value) => value.toString().padLeft(2, '0');
}
