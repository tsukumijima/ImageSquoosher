import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ja')];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'ImageSquoosher'**
  String get appTitle;

  /// No description provided for @addFiles.
  ///
  /// In ja, this message translates to:
  /// **'画像を追加'**
  String get addFiles;

  /// No description provided for @clearAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて削除'**
  String get clearAll;

  /// No description provided for @start.
  ///
  /// In ja, this message translates to:
  /// **'圧縮を開始'**
  String get start;

  /// No description provided for @settings.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get settings;

  /// No description provided for @quality.
  ///
  /// In ja, this message translates to:
  /// **'画質'**
  String get quality;

  /// No description provided for @ratio.
  ///
  /// In ja, this message translates to:
  /// **'比率'**
  String get ratio;

  /// No description provided for @removeMetadata.
  ///
  /// In ja, this message translates to:
  /// **'位置情報などのメタデータを削除する'**
  String get removeMetadata;

  /// No description provided for @suffix.
  ///
  /// In ja, this message translates to:
  /// **'ファイル名サフィックス'**
  String get suffix;

  /// No description provided for @overwrite.
  ///
  /// In ja, this message translates to:
  /// **'元のファイルを上書きする'**
  String get overwrite;

  /// No description provided for @idle.
  ///
  /// In ja, this message translates to:
  /// **'画像を追加してください'**
  String get idle;

  /// No description provided for @emptyDescription.
  ///
  /// In ja, this message translates to:
  /// **'JPEG・PNG・WebP をドロップするか、画像を追加してください。'**
  String get emptyDescription;

  /// No description provided for @files.
  ///
  /// In ja, this message translates to:
  /// **'ファイル'**
  String get files;

  /// No description provided for @about.
  ///
  /// In ja, this message translates to:
  /// **'ImageSquoosher について'**
  String get about;

  /// No description provided for @checkForUpdates.
  ///
  /// In ja, this message translates to:
  /// **'更新を確認'**
  String get checkForUpdates;

  /// No description provided for @checkingUpdates.
  ///
  /// In ja, this message translates to:
  /// **'更新を確認中…'**
  String get checkingUpdates;

  /// No description provided for @upToDate.
  ///
  /// In ja, this message translates to:
  /// **'最新版を使用しています'**
  String get upToDate;

  /// No description provided for @updateAvailable.
  ///
  /// In ja, this message translates to:
  /// **'新しいバージョンが利用できます'**
  String get updateAvailable;

  /// No description provided for @viewRelease.
  ///
  /// In ja, this message translates to:
  /// **'リリースを見る'**
  String get viewRelease;

  /// No description provided for @releaseOpenFailed.
  ///
  /// In ja, this message translates to:
  /// **'リリースページを開けませんでした'**
  String get releaseOpenFailed;

  /// No description provided for @dismiss.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get dismiss;

  /// No description provided for @close.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get close;

  /// No description provided for @save.
  ///
  /// In ja, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get cancel;

  /// No description provided for @language.
  ///
  /// In ja, this message translates to:
  /// **'表示言語'**
  String get language;

  /// No description provided for @japanese.
  ///
  /// In ja, this message translates to:
  /// **'日本語'**
  String get japanese;

  /// No description provided for @english.
  ///
  /// In ja, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @qualityHint.
  ///
  /// In ja, this message translates to:
  /// **'低いほどファイルサイズを小さくします'**
  String get qualityHint;

  /// No description provided for @originalSize.
  ///
  /// In ja, this message translates to:
  /// **'元の大きさ'**
  String get originalSize;

  /// No description provided for @halfSize.
  ///
  /// In ja, this message translates to:
  /// **'50% に縮小'**
  String get halfSize;

  /// No description provided for @customSize.
  ///
  /// In ja, this message translates to:
  /// **'幅を指定'**
  String get customSize;

  /// No description provided for @maxWidth.
  ///
  /// In ja, this message translates to:
  /// **'最大幅'**
  String get maxWidth;

  /// No description provided for @allowUpscale.
  ///
  /// In ja, this message translates to:
  /// **'小さい画像を拡大する'**
  String get allowUpscale;

  /// No description provided for @overwriteDescription.
  ///
  /// In ja, this message translates to:
  /// **'変換後の画像で元ファイルを置き換えます'**
  String get overwriteDescription;

  /// No description provided for @statusReady.
  ///
  /// In ja, this message translates to:
  /// **'準備完了'**
  String get statusReady;

  /// No description provided for @compressionUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'画像変換エンジンの接続後に圧縮を開始できます'**
  String get compressionUnavailable;

  /// No description provided for @clearConfirmation.
  ///
  /// In ja, this message translates to:
  /// **'追加した画像をすべて削除しました'**
  String get clearConfirmation;

  /// No description provided for @replaceFiles.
  ///
  /// In ja, this message translates to:
  /// **'一覧を置き換え'**
  String get replaceFiles;

  /// No description provided for @dropImages.
  ///
  /// In ja, this message translates to:
  /// **'ここへ画像をドロップ'**
  String get dropImages;

  /// No description provided for @dropImagesDescription.
  ///
  /// In ja, this message translates to:
  /// **'上のボタンから画像を選ぶこともできます。'**
  String get dropImagesDescription;

  /// No description provided for @queueTitle.
  ///
  /// In ja, this message translates to:
  /// **'変換処理プレビュー'**
  String get queueTitle;

  /// No description provided for @sourceSize.
  ///
  /// In ja, this message translates to:
  /// **'元の寸法'**
  String get sourceSize;

  /// No description provided for @outputSize.
  ///
  /// In ja, this message translates to:
  /// **'出力寸法'**
  String get outputSize;

  /// No description provided for @outputName.
  ///
  /// In ja, this message translates to:
  /// **'出力ファイル'**
  String get outputName;

  /// No description provided for @queued.
  ///
  /// In ja, this message translates to:
  /// **'待機中'**
  String get queued;

  /// No description provided for @processing.
  ///
  /// In ja, this message translates to:
  /// **'圧縮中'**
  String get processing;

  /// No description provided for @completed.
  ///
  /// In ja, this message translates to:
  /// **'完了'**
  String get completed;

  /// No description provided for @failed.
  ///
  /// In ja, this message translates to:
  /// **'失敗'**
  String get failed;

  /// No description provided for @stopped.
  ///
  /// In ja, this message translates to:
  /// **'停止'**
  String get stopped;

  /// No description provided for @stop.
  ///
  /// In ja, this message translates to:
  /// **'この画像の後で停止'**
  String get stop;

  /// No description provided for @reset.
  ///
  /// In ja, this message translates to:
  /// **'リセット'**
  String get reset;

  /// No description provided for @openOutput.
  ///
  /// In ja, this message translates to:
  /// **'Finder で表示'**
  String get openOutput;

  /// No description provided for @compressionComplete.
  ///
  /// In ja, this message translates to:
  /// **'圧縮が完了しました'**
  String get compressionComplete;

  /// No description provided for @compressionStopped.
  ///
  /// In ja, this message translates to:
  /// **'圧縮を停止しました'**
  String get compressionStopped;

  /// No description provided for @compressionFailed.
  ///
  /// In ja, this message translates to:
  /// **'一部の画像を圧縮できませんでした'**
  String get compressionFailed;

  /// No description provided for @outputSaved.
  ///
  /// In ja, this message translates to:
  /// **'保存先'**
  String get outputSaved;

  /// No description provided for @filesAdded.
  ///
  /// In ja, this message translates to:
  /// **'画像を一覧へ追加しました'**
  String get filesAdded;

  /// No description provided for @duplicateFilesSkipped.
  ///
  /// In ja, this message translates to:
  /// **'重複した画像を除外しました'**
  String get duplicateFilesSkipped;

  /// No description provided for @noSupportedImages.
  ///
  /// In ja, this message translates to:
  /// **'JPEG・PNG・WebP の画像を選択してください'**
  String get noSupportedImages;

  /// No description provided for @selectImagesFailed.
  ///
  /// In ja, this message translates to:
  /// **'画像ファイルを選択できませんでした'**
  String get selectImagesFailed;

  /// No description provided for @dropFailed.
  ///
  /// In ja, this message translates to:
  /// **'ドロップしたファイルを追加できませんでした'**
  String get dropFailed;

  /// No description provided for @settingsSaved.
  ///
  /// In ja, this message translates to:
  /// **'設定を保存しました'**
  String get settingsSaved;

  /// No description provided for @aboutDescription.
  ///
  /// In ja, this message translates to:
  /// **'JPEG の圧縮とリサイズを行うデスクトップアプリです。'**
  String get aboutDescription;

  /// No description provided for @fileSize.
  ///
  /// In ja, this message translates to:
  /// **'ファイルサイズ'**
  String get fileSize;

  /// No description provided for @unknownSize.
  ///
  /// In ja, this message translates to:
  /// **'不明'**
  String get unknownSize;

  /// No description provided for @outputNotCreated.
  ///
  /// In ja, this message translates to:
  /// **'出力はまだ作成されていません'**
  String get outputNotCreated;

  /// No description provided for @overwriteRestoredOff.
  ///
  /// In ja, this message translates to:
  /// **'元ファイルの上書きは起動時にオフへ戻ります'**
  String get overwriteRestoredOff;

  /// No description provided for @checkFailed.
  ///
  /// In ja, this message translates to:
  /// **'更新を確認できませんでした'**
  String get checkFailed;

  /// No description provided for @statusWaiting.
  ///
  /// In ja, this message translates to:
  /// **'画像を待っています'**
  String get statusWaiting;

  /// No description provided for @statusProgress.
  ///
  /// In ja, this message translates to:
  /// **'{total}件中 {completed}件を圧縮中'**
  String statusProgress(Object completed, Object total);

  /// No description provided for @statusCompleted.
  ///
  /// In ja, this message translates to:
  /// **'圧縮完了：{completed}件成功、{failed}件失敗'**
  String statusCompleted(Object completed, Object failed);

  /// No description provided for @dimensionValue.
  ///
  /// In ja, this message translates to:
  /// **'{width} × {height}'**
  String dimensionValue(Object width, Object height);

  /// No description provided for @fileSizeValue.
  ///
  /// In ja, this message translates to:
  /// **'{size}'**
  String fileSizeValue(Object size);

  /// No description provided for @aspectRatio.
  ///
  /// In ja, this message translates to:
  /// **'切り抜き比率'**
  String get aspectRatio;

  /// No description provided for @originalAspectRatio.
  ///
  /// In ja, this message translates to:
  /// **'元の比率を保つ'**
  String get originalAspectRatio;

  /// No description provided for @resize.
  ///
  /// In ja, this message translates to:
  /// **'リサイズ'**
  String get resize;

  /// No description provided for @resizeByWidth.
  ///
  /// In ja, this message translates to:
  /// **'幅を指定'**
  String get resizeByWidth;

  /// No description provided for @resizeByHeight.
  ///
  /// In ja, this message translates to:
  /// **'高さを指定'**
  String get resizeByHeight;

  /// No description provided for @resizePixels.
  ///
  /// In ja, this message translates to:
  /// **'ピクセル'**
  String get resizePixels;

  /// No description provided for @metadataDescription.
  ///
  /// In ja, this message translates to:
  /// **'カメラ設定などのメタデータを残す'**
  String get metadataDescription;

  /// No description provided for @overwriteWarning.
  ///
  /// In ja, this message translates to:
  /// **'元のファイルを JPEG で置き換えます'**
  String get overwriteWarning;

  /// No description provided for @finderSyncManage.
  ///
  /// In ja, this message translates to:
  /// **'Finder 連携を管理'**
  String get finderSyncManage;

  /// No description provided for @finderSyncEnable.
  ///
  /// In ja, this message translates to:
  /// **'Finder 連携を有効化'**
  String get finderSyncEnable;

  /// No description provided for @restoreDefaults.
  ///
  /// In ja, this message translates to:
  /// **'既定値へ戻す'**
  String get restoreDefaults;

  /// No description provided for @customRatio.
  ///
  /// In ja, this message translates to:
  /// **'カスタム'**
  String get customRatio;

  /// No description provided for @horizontal.
  ///
  /// In ja, this message translates to:
  /// **'横'**
  String get horizontal;

  /// No description provided for @vertical.
  ///
  /// In ja, this message translates to:
  /// **'縦'**
  String get vertical;

  /// No description provided for @removeItem.
  ///
  /// In ja, this message translates to:
  /// **'画像を外す'**
  String get removeItem;

  /// No description provided for @openFile.
  ///
  /// In ja, this message translates to:
  /// **'出力ファイルを開く'**
  String get openFile;

  /// No description provided for @openFolder.
  ///
  /// In ja, this message translates to:
  /// **'出力フォルダを開く'**
  String get openFolder;

  /// No description provided for @clearSelection.
  ///
  /// In ja, this message translates to:
  /// **'すべて外す'**
  String get clearSelection;

  /// No description provided for @exifRemoval.
  ///
  /// In ja, this message translates to:
  /// **'撮影情報と位置情報 (EXIF) を削除'**
  String get exifRemoval;

  /// No description provided for @invalidImage.
  ///
  /// In ja, this message translates to:
  /// **'画像を読み取れませんでした'**
  String get invalidImage;

  /// No description provided for @animatedImage.
  ///
  /// In ja, this message translates to:
  /// **'アニメーション画像には対応していません'**
  String get animatedImage;

  /// No description provided for @unsupportedImage.
  ///
  /// In ja, this message translates to:
  /// **'JPEG・PNG・WebP の静止画だけを変換できます'**
  String get unsupportedImage;

  /// No description provided for @conversionError.
  ///
  /// In ja, this message translates to:
  /// **'画像を変換できませんでした'**
  String get conversionError;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
