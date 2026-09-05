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
  String get start => '変換開始';

  @override
  String get settings => '設定';

  @override
  String get quality => '画質';

  @override
  String get ratio => 'アスペクト比';

  @override
  String get removeMetadata => '位置情報などのメタデータを削除する';

  @override
  String get suffix => 'ファイル名サフィックス';

  @override
  String get overwrite => '元のファイルを上書きする';

  @override
  String get idle => '画像を追加してください';

  @override
  String get emptyDescription => 'JPEG・PNG・WebP をここへドロップするか、クリックして選べます。';

  @override
  String get files => 'ファイル';

  @override
  String get about => 'バージョン情報';

  @override
  String get checkForUpdates => '更新を確認';

  @override
  String get checkingUpdates => '新しいバージョンを確認しています。';

  @override
  String get upToDate => '最新バージョンをご利用いただいています。';

  @override
  String get updateAvailable => '新しいバージョンが利用できます';

  @override
  String get viewRelease => 'リリースを見る';

  @override
  String get releaseOpenFailed => 'ページを開けませんでした。時間をおいて、もう一度お試しください。';

  @override
  String get dismiss => '閉じる';

  @override
  String get close => '閉じる';

  @override
  String get save => '保存';

  @override
  String get cancel => 'キャンセル';

  @override
  String get language => '言語';

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
  String get statusReady => '待機中';

  @override
  String get compressionUnavailable => '画像変換エンジンの接続後に圧縮を開始できます';

  @override
  String get clearConfirmation => '画像をすべて一覧から外しました。この操作でファイルが削除されることはありません。';

  @override
  String get replaceFiles => '一覧を置き換え';

  @override
  String get dropImages => 'ここへ画像をドロップ';

  @override
  String get dropImagesDescription => '上のボタンから画像を選ぶこともできます。';

  @override
  String get queueTitle => '変換する画像';

  @override
  String get sourceSize => '元の寸法';

  @override
  String get outputSize => '出力';

  @override
  String get outputName => '出力ファイル';

  @override
  String get queued => '待機中';

  @override
  String get processing => '変換中';

  @override
  String get completed => '完了';

  @override
  String get failed => '失敗';

  @override
  String get stopped => '停止';

  @override
  String get stop => '停止';

  @override
  String get reset => 'リセット';

  @override
  String get openOutput => 'Finder で表示';

  @override
  String get compressionComplete => '変換完了';

  @override
  String get compressionStopped => '変換を停止しました。完了した画像は保存されています。';

  @override
  String get compressionFailed => '画像を変換できませんでした。各画像のエラーをご確認ください。';

  @override
  String get outputSaved => '保存先';

  @override
  String get filesAdded => '画像を追加しました。設定を確認したら、変換を始められます。';

  @override
  String get duplicateFilesSkipped => '選択した画像はすでに一覧に追加されています。';

  @override
  String get noSupportedImages => 'JPEG・PNG・WebP の画像を選んでください。';

  @override
  String get selectImagesFailed => '画像を選択できませんでした。もう一度お試しください。';

  @override
  String get dropFailed => '画像を追加できませんでした。もう一度お試しください。';

  @override
  String get settingsSaved => '設定を保存しました。';

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
  String get checkFailed => '更新を確認できませんでした。時間をおいて、もう一度お試しください。';

  @override
  String get statusWaiting => '待機中';

  @override
  String statusProgress(Object completed, Object total) {
    return '$total件中 $completed件完了';
  }

  @override
  String statusCompleted(Object completed, Object failed) {
    return '$completed件の画像を変換しました。$failed件の画像でエラーが発生したため、一覧をご確認ください。';
  }

  @override
  String dimensionValue(Object width, Object height) {
    return '$width×$height';
  }

  @override
  String fileSizeValue(Object size) {
    return '$size';
  }

  @override
  String get aspectRatio => 'アスペクト比';

  @override
  String get originalAspectRatio => '元のアスペクト比を保つ';

  @override
  String get resize => 'リサイズ';

  @override
  String get resizeByWidth => '横幅を指定';

  @override
  String get resizeByHeight => '縦幅を指定';

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
  String get restoreDefaults => '変換設定を既定値に戻す';

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

  @override
  String conversionSucceeded(int count) {
    return '$count件の画像を変換できました。ファイルや保存先は一覧から開けます。';
  }

  @override
  String compressionReduction(String percent) {
    return '$percent% 圧縮!';
  }

  @override
  String sizeIncrease(String percent) {
    return '$percent% 増加';
  }

  @override
  String get licenses => 'ライセンスを表示';

  @override
  String get openFileFailed => 'ファイルを開けませんでした。保存先にファイルがあるかご確認ください。';

  @override
  String get openFolderFailed => '保存先を開けませんでした。フォルダがあるかご確認ください。';

  @override
  String get defaultsRestored => '変換設定を既定値に戻しました。';

  @override
  String get conversionFailedStatus => '変換失敗';

  @override
  String get stopping => '停止中';
}
