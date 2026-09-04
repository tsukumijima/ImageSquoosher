import 'dart:async';

/// ウィンドウサイズの保存をデバウンスし、ファイル書き込みを直列化します。
class WindowSettingsSaveQueue {
  /// 保存処理と失敗通知を受け取り、保存の間隔を設定します。
  WindowSettingsSaveQueue({
    required Future<void> Function() save,
    required void Function(Object error, StackTrace stackTrace) onError,
    this.debounceDuration = const Duration(milliseconds: 250),
  }) : _save = save,
       _onError = onError;

  final Future<void> Function() _save;
  final void Function(Object error, StackTrace stackTrace) _onError;
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
    // 失敗を通知して Future を完了扱いへ戻し、次のサイズ変更も同じ直列キューで保存できるようにする
    _saveTail = _saveTail.then((_) => _save()).catchError((error, stackTrace) {
      _onError(error, stackTrace);
    });
  }

  /// 終了時に保存タイマーだけを破棄します。
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
