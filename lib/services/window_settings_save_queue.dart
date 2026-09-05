import 'dart:async';

/// ウィンドウサイズの保存をデバウンスし、ファイル書き込みを直列化する。
class WindowSettingsSaveQueue {
  /// 保存処理と失敗通知を受け取り、保存の間隔を設定する。
  /// @param save ウィンドウ状態を保存する処理
  /// @param onError 保存失敗時に呼び出す通知処理
  /// @param debounceDuration 保存をまとめる待機時間
  WindowSettingsSaveQueue({
    required Future<void> Function() save,
    required void Function(Object error, StackTrace stackTrace) onError,
    this.debounceDuration = const Duration(milliseconds: 250),
  }) : _save = save,
       _onError = onError;

  /// ウィンドウ状態を保存する処理。
  final Future<void> Function() _save;

  /// 保存失敗を通知する処理。
  final void Function(Object error, StackTrace stackTrace) _onError;

  /// 保存をまとめる待機時間。
  final Duration debounceDuration;

  /// 次回保存を実行するタイマー。
  Timer? _timer;

  /// 直列化した保存処理の末尾。
  Future<void> _saveTail = Future<void>.value();

  /// 連続したサイズ変更をまとめて保存する。
  void schedule() {
    _timer?.cancel();
    _timer = Timer(debounceDuration, () {
      _timer = null;
      _enqueue();
    });
  }

  /// 保留中の保存を直ちにキューへ積み、先行する保存も完了するまで待つ。
  /// @returns キュー内の保存が完了する Future
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _enqueue();
    return _saveTail;
  }

  /// 次の書き込みを前の書き込みの完了後へ積む。
  void _enqueue() {
    // 失敗を通知して Future を完了扱いへ戻し、次のサイズ変更も同じ直列キューで保存できるようにする
    _saveTail = _saveTail.then((_) => _save()).catchError((error, stackTrace) {
      _onError(error, stackTrace);
    });
  }

  /// 終了時に保存タイマーを破棄する。
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
