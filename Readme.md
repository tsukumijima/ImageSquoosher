# ImageSquoosher

> [!TIP]  
> **🌐 English version is available: [Readme_English.md](Readme_English.md)**

ImageSquoosher は、静止画を容量の小さい JPEG へ変換するデスクトップアプリです。  
複数の JPEG・PNG・WebP 画像に対して、中央クロップ、リサイズ、メタデータ削除、MozJPEG による圧縮をまとめて行えます。

## インストール

対応環境は次のとおりです。

| OS | アーキテクチャ |
| --- | --- |
| Windows 10 / 11 | x64 |
| macOS 12 以降 | Apple Silicon (arm64) |

1. [Releases ページ](https://github.com/tsukumijima/ImageSquoosher/releases) を開きます。
2. 利用する OS の ZIP ファイルをダウンロードします。
   - Windows: `ImageSquoosher-vX.Y.Z-windows.zip`
   - macOS: `ImageSquoosher-vX.Y.Z-macos.zip`
3. ZIP ファイルを展開します。

Windows では展開したフォルダの内容を一緒に置き、`ImageSquoosher.exe` を起動します。  
アプリと同じ場所にある `mozjpeg` フォルダと VC++ ランタイム DLL も動作に必要です。

macOS では `ImageSquoosher.app` をアプリケーションフォルダへ移して起動します。  
配布版は Developer ID 証明書で署名し、Apple の公証を通しています。

## 対応画像形式

| 入力 | 出力 | 備考 |
| --- | --- | --- |
| JPEG (`.jpg`, `.jpeg`) | JPEG (`.jpg`) | 静止画だけに対応 |
| PNG (`.png`) | JPEG (`.jpg`) | 透過部分は白背景と合成 |
| WebP (`.webp`) | JPEG (`.jpg`) | 静止画だけに対応 |

アニメーション PNG と WebP は変換対象外です。  
MozJPEG が利用できない場合は、変換エラーとして表示します。

## 基本的な使い方

1. 画像をウィンドウへドロップするか、［画像を追加］から選びます。
2. 画像ごとに表示される出力寸法とファイル名を確認します。
3. 画質、ファイル名サフィックス、アスペクト比、リサイズ、メタデータの設定を調整します。
4. ［変換開始］を選びます。
5. 完了した画像の行から出力ファイルを開くか、保存先フォルダを表示します。

切り抜き位置は常に中央です。  
元画像のアスペクト比を保つほか、プリセットまたは任意の横対縦の比率を指定できます。  
リサイズは選択した幅または高さを基準とし、クロップ後のアスペクト比を保ちます。

スクロールするのは画像一覧だけで、設定と［変換する画像］の見出しは固定されています。  
［画像を追加］は右上のヘッダー、［すべて外す］は一覧の上部、［変換開始］と［停止］は画面下部に表示されます。  
［画像を追加］はアクセントカラーで表示され、［すべて外す］とともに［変換開始］・［停止］と同じ高さに揃っています。  
これらのボタンは押すと波紋が広がり、選択欄と候補一覧の文字は本文と同じフォントで表示されます。

各画像は、上段に入出力ファイル名とサイズ、下段に変換前後の寸法とアスペクト比を表示します。  
状態はアイコンと文字を小さなバッジにまとめて表示します。  
変換が完了すると、成功通知と同じ緑色で圧縮率と進捗バーが残り、一覧の高さを保ったまま結果を比較できます。  
保存先フォルダは変換前から開けます。

画像カードはマウスを重ねると背景が明るくなり、ダブルクリックすると元ファイルを既定のビューアーで開きます。  
変換後のファイルは、カード右下の［出力ファイルを開く］から開けます。  
上書きなどで元ファイルがなくなっている場合は、通知でお知らせします。

操作後の通知は、結果と補足説明を改行で分けて表示します。  
行間に余裕を持たせ、確認すべき内容を読み取りやすくしています。

アスペクト比とリサイズする辺は、選択欄をクリックして候補一覧から選びます。  
一覧を開いている間は上下キーと Enter でも選択でき、Esc で一覧を閉じられます。

完了した画像は、同じ設定で再度圧縮されることなく一覧に残ります。  
画像を追加すると追加分だけを処理でき、変換設定を変更すると元入力が残っている画像も再び待機状態になります。  
上書きで元入力を削除した PNG・WebP は、完了した結果を保持します。

## 出力ファイル名

既定のサフィックスは `_resized` です。  
たとえば `photo.png` は `photo_resized.jpg` になります。  
同名の出力が存在する場合は、`photo_resized (1).jpg`、`photo_resized (2).jpg` のように Finder と同じ形式の連番を付けます。

入力名の末尾に連番がある場合は、サフィックスの後へ連番を引き継ぎます。  
たとえば `photo (2).png` の出力名は `photo_resized (2).jpg` です。

## 元画像の上書き

［元のファイルを上書きする］は、元画像を置き換える明示的な設定です。  
この設定はアプリを起動するたびにオフへ戻ります。

上書きがオンの間は、直下のサフィックス欄が無効になります。  
入力したサフィックスは保持され、上書きをオフへ戻すと再び使えます。

JPEG 入力では、変換結果を別の一時パスへ書き、MozJPEG の正常終了、JPEG としての妥当性、要求した寸法との一致を確認してから、元画像を原子的に置き換えます。  
途中で失敗した場合は元画像が残ります。

PNG と WebP は元画像と同じパスへ JPEG を保存できません。  
ImageSquoosher は空いている `.jpg` のファイル名を先に選び、JPEG の生成と検証、元画像の日時の反映を完了してから PNG または WebP の元画像を削除します。  
同じベース名の JPEG がすでに存在する場合はそのファイルを残し、出力側へ連番を付けます。

macOS と Windows の両方で、元画像の作成日時と更新日時を出力へ引き継ぎます。  
日時を保持できなかった場合は変換失敗として扱い、元画像の削除へ進みません。

> [!WARNING]
> 代表的な画像で出力を確認するまでは、上書きをオフにした状態で利用してください。  
> 既定の上書きオフでは、すべての元画像が残ります。

## macOS の Finder 連携

macOS 版には Finder Sync Extension が含まれています。

1. ImageSquoosher 右上のパズルの形をした Finder 連携ボタンを選びます。
2. macOS のシステム設定で **ImageSquoosher Finder Sync** 拡張を有効にします。
3. Finder で JPEG・PNG・WebP を1件以上選択します。
4. 選択した画像を右クリックし、［ImageSquoosher で圧縮・リサイズ］を選びます。

ImageSquoosher が開き、対応している選択画像が変換一覧へ入ります。  
Finder 拡張は、対応画像を選択したときの右クリックメニューだけに項目を追加します。

変換中に Finder から別の画像を送ると、実行中の変換が完了または停止した後に一覧を置き換えます。  
その間に何度も選択を送った場合は、最後に送った選択を使います。  
新しい一覧の変換は、［変換開始］を選ぶと始まります。

## プライバシーと変換処理

画像変換はコンピューター内で完結します。  
ImageSquoosher は同梱した MozJPEG の `cjpeg` を実行し、元画像をコンピューター内だけで読み書きします。

メタデータは既定で維持されます。  
カメラ設定や位置情報などの EXIF を JPEG 出力から除きたい場合は、メタデータ削除を有効にしてください。

## 開発

### 必要な環境

- Flutter 3.35.7 と同梱の Dart 3.9.2
- macOS: Xcode、CMake
- Windows: Visual Studio 2022 の「C++ によるデスクトップ開発」、PowerShell、CMake

変更前に [AGENTS.md](AGENTS.md) を読んでください。  
元画像の安全条件、Finder Sync の境界、Debug 実画面の確認、両 OS の完了条件を定めています。

### Debug の開発手順

通常の画面開発には Debug アプリとホットリロードを使います。

```bash
flutter pub get
tools/build_mozjpeg.sh
flutter run -d macos
```

Windows では MozJPEG を PowerShell で準備してから Debug アプリを起動します。

```powershell
flutter pub get
pwsh -File tools/build_mozjpeg.ps1
flutter run -d windows
```

編集後は `format`、`analyze`、`test` の機械検査を実行します。

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

macOS の実バイナリで画像変換を検証するコマンドは次のとおりです。

```bash
IMAGE_SQUOOSHER_CJPEG="$PWD/native/mozjpeg/macos/arm64/cjpeg" \
  flutter test test/services/image_conversion_pipeline_test.dart
```

Windows では同じ環境変数へ `native/mozjpeg/windows/cjpeg.exe` を指定します。

### リリースビルド

補助スクリプトは MozJPEG 4.1.1 を一時ディレクトリへ取得してビルドし、アプリが必要とする実行ファイルだけを `native/mozjpeg/` へ残します。

macOS Apple Silicon:

```bash
tools/build_mozjpeg.sh
flutter build macos --release
tools/bundle_mozjpeg.sh build/macos/Build/Products/Release/ImageSquoosher.app
```

Windows x64:

```powershell
pwsh -File tools/build_mozjpeg.ps1
flutter build windows --release
pwsh -File tools/bundle_mozjpeg.ps1
```

GitHub Actions は format、analyze、test を先に実行します。  
その後で macOS arm64 と Windows x64 をビルドし、各アプリへ配置した `cjpeg` による実変換を確認します。  
Windows の成果物には VC++ ランタイム DLL も含め、両 OS の ZIP を保存します。

タグは `vX.Y.Z` 形式とし、`pubspec.yaml` のバージョンと一致させます。  
タグのリリースでは次の2ファイルだけを公開します。

- `ImageSquoosher-vX.Y.Z-macos.zip`
- `ImageSquoosher-vX.Y.Z-windows.zip`

macOS のリリースには、次の GitHub Actions のシークレットが必要です。

| Secret | 用途 |
| --- | --- |
| `MACOS_CODE_SIGNING_ENABLED` | タグリリースでは `true` が必須 |
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application 証明書と秘密鍵を含む `.p12` の Base64 値 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` の書き出しに使ったパスワード |
| `APPLE_API_KEY_ID` | App Store Connect API キー ID |
| `APPLE_API_ISSUER_ID` | App Store Connect の発行者 ID |
| `APPLE_API_KEY_P8_BASE64` | App Store Connect の `.p8` 秘密鍵を Base64 化した値 |

ワークフローは署名材料を一時キーチェーンへ取り込み、ネストしたフレームワーク、Finder Sync Extension、同梱した `cjpeg`、本体アプリを内側から順に署名します。  
続けて Apple の公証へ提出し、公証チケットの添付、コード署名、Gatekeeper の検証を行います。

## ライセンス

ImageSquoosher は [MIT License](LICENSE) で配布します。  
同梱する MozJPEG バイナリは MozJPEG 4.1.1 の公開ソースからビルドし、ライセンスと帰属表示は [`native/mozjpeg/`](native/mozjpeg/) に収録しています。
