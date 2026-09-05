// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'ImageSquoosher';

  @override
  String get addFiles => '画像を追加';

  @override
  String get clearAll => 'すべて削除';

  @override
  String get start => '圧縮を開始';

  @override
  String get settings => '設定';

  @override
  String get quality => '画質';

  @override
  String get ratio => '比率';

  @override
  String get removeMetadata => '位置情報などのメタデータを削除する';

  @override
  String get suffix => 'ファイル名サフィックス';

  @override
  String get overwrite => '元のファイルを上書きする';

  @override
  String get idle => '画像を追加してください';

  @override
  String get emptyDescription => 'JPEG・PNG・WebP をここへドロップするか、右上のボタンから選べます。';

  @override
  String get files => 'ファイル';

  @override
  String get about => 'ImageSquoosher について';

  @override
  String get checkForUpdates => '更新を確認';

  @override
  String get checkingUpdates => '更新を確認中…';

  @override
  String get upToDate => '最新版を使用しています';

  @override
  String get updateAvailable => '新しいバージョンが利用できます';

  @override
  String get viewRelease => 'リリースを見る';

  @override
  String get releaseOpenFailed => 'リリースページを開けませんでした';

  @override
  String get dismiss => '閉じる';

  @override
  String get close => '閉じる';

  @override
  String get save => '保存';

  @override
  String get cancel => 'キャンセル';

  @override
  String get language => '表示言語';

  @override
  String get japanese => '日本語';

  @override
  String get english => 'English';

  @override
  String get qualityHint => '低いほどファイルサイズを小さくします';

  @override
  String get originalSize => '元の大きさ';

  @override
  String get halfSize => '50% に縮小';

  @override
  String get customSize => '幅を指定';

  @override
  String get maxWidth => '最大幅';

  @override
  String get allowUpscale => '小さい画像を拡大する';

  @override
  String get overwriteDescription => '変換後の画像で元ファイルを置き換えます';

  @override
  String get statusReady => '準備完了';

  @override
  String get compressionUnavailable => '画像変換エンジンの接続後に圧縮を開始できます';

  @override
  String get clearConfirmation => '追加した画像をすべて削除しました';

  @override
  String get replaceFiles => '一覧を置き換え';

  @override
  String get dropImages => 'ここへ画像をドロップ';

  @override
  String get dropImagesDescription => '上のボタンから画像を選ぶこともできます。';

  @override
  String get queueTitle => '変換処理プレビュー';

  @override
  String get sourceSize => '元の寸法';

  @override
  String get outputSize => '出力';

  @override
  String get outputName => '出力ファイル';

  @override
  String get queued => '待機中';

  @override
  String get processing => '圧縮中';

  @override
  String get completed => '完了';

  @override
  String get failed => '失敗';

  @override
  String get stopped => '停止';

  @override
  String get stop => 'この画像の後で停止';

  @override
  String get reset => 'リセット';

  @override
  String get openOutput => 'Finder で表示';

  @override
  String get compressionComplete => '圧縮が完了しました';

  @override
  String get compressionStopped => '圧縮を停止しました';

  @override
  String get compressionFailed => '一部の画像を圧縮できませんでした';

  @override
  String get outputSaved => '保存先';

  @override
  String get filesAdded => '画像を一覧へ追加しました';

  @override
  String get duplicateFilesSkipped => '重複した画像を除外しました';

  @override
  String get noSupportedImages => 'JPEG・PNG・WebP の画像を選択してください';

  @override
  String get selectImagesFailed => '画像ファイルを選択できませんでした';

  @override
  String get dropFailed => 'ドロップしたファイルを追加できませんでした';

  @override
  String get settingsSaved => '設定を保存しました';

  @override
  String get aboutDescription => 'JPEG の圧縮とリサイズを行うデスクトップアプリです。';

  @override
  String get fileSize => 'ファイルサイズ';

  @override
  String get unknownSize => '不明';

  @override
  String get outputNotCreated => '出力はまだ作成されていません';

  @override
  String get overwriteRestoredOff => '元ファイルの上書きは起動時にオフへ戻ります';

  @override
  String get checkFailed => '更新を確認できませんでした';

  @override
  String get statusWaiting => '画像を待っています';

  @override
  String statusProgress(Object completed, Object total) {
    return '$total件中 $completed件を圧縮中';
  }

  @override
  String statusCompleted(Object completed, Object failed) {
    return '圧縮完了：$completed件成功、$failed件失敗';
  }

  @override
  String dimensionValue(Object width, Object height) {
    return '$width × $height';
  }

  @override
  String fileSizeValue(Object size) {
    return '$size';
  }

  @override
  String get aspectRatio => '切り抜き比率';

  @override
  String get originalAspectRatio => '元の比率を保つ';

  @override
  String get resize => 'リサイズ';

  @override
  String get resizeByWidth => '幅を指定';

  @override
  String get resizeByHeight => '高さを指定';

  @override
  String get resizePixels => 'ピクセル';

  @override
  String get metadataDescription => 'カメラ設定などのメタデータを残す';

  @override
  String get overwriteWarning => '元のファイルを JPEG で置き換えます';

  @override
  String get finderSyncManage => 'Finder 連携を管理';

  @override
  String get finderSyncEnable => 'Finder 連携を有効化';

  @override
  String get restoreDefaults => '既定値へ戻す';

  @override
  String get customRatio => 'カスタム';

  @override
  String get horizontal => '横';

  @override
  String get vertical => '縦';

  @override
  String get removeItem => '画像を外す';

  @override
  String get openFile => '出力ファイルを開く';

  @override
  String get openFolder => '出力フォルダを開く';

  @override
  String get clearSelection => 'すべて外す';

  @override
  String get exifRemoval => '撮影情報と位置情報 (EXIF) を削除';

  @override
  String get invalidImage => '画像を読み取れませんでした';

  @override
  String get animatedImage => 'アニメーション画像には対応していません';

  @override
  String get unsupportedImage => 'JPEG・PNG・WebP の静止画だけを変換できます';

  @override
  String get conversionError => '画像を変換できませんでした';
}
