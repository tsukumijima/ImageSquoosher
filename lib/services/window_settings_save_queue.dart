import 'dart:async';

/// ウィンドウサイズの保存をデバウンスし、ファイル書き込みを直列化します。
class WindowSettingsSaveQueue {
  WindowSettingsSaveQueue({
    required Future<void> Function() save,
    this.debounceDuration = const Duration(milliseconds: 250),
  }) : _save = save;

  final Future<void> Function() _save;
  final Duration debounceDuration;
  Timer? _timer;
  Future<void> _saveTail = Future<void>.value();

  /// 連続したサイズ変更をまとめて保存します。
  void schedule() {
    _timer?.cancel();
    _timer = Timer(debounceDuration, () {
      _timer = null;
      _enqueue();
    });
  }

  /// 保留中の保存を直ちにキューへ積み、先行する保存も完了するまで待ちます。
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _enqueue();
    return _saveTail;
  }

  /// 次の書き込みを前の書き込みの完了後へ積みます。
  void _enqueue() {
    _saveTail = _saveTail.then((_) => _save());
  }

  /// 終了時に保存タイマーだけを破棄します。
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
