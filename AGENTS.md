# ImageSquoosher - AGENTS

## プロジェクト概要

ImageSquoosher は、JPEG・PNG・WebP の静止画を中央クロップ、リサイズし、MozJPEG で JPEG へ圧縮する Flutter Desktop アプリです。  
対応プラットフォームは macOS 12 以降の Apple Silicon と Windows 11 x64 です。

デスクトップアプリの設計、開発工程、画像変換、元画像の置き換え、Finder Sync、MozJPEG の配布に関する規範は、この文書に定めます。  
利用者向けの操作と配布手順は、[README.md](README.md) と [README_Japanese.md](README_Japanese.md) に記載します。

## 技術スタック

- Flutter 3.35.7 / Dart 3.9.2
- Flutter Desktop for macOS / Windows
- MozJPEG 4.1.1 の `cjpeg`
- macOS Finder Sync Extension
- Windows `MethodChannel` / Win32 API

## アーキテクチャ

```text
lib/
├── main.dart                         # ウィンドウ初期化と起動
├── app.dart                          # MaterialApp とロケール
├── models/                           # 変換設定、画像寸法、キュー状態
├── services/
│   ├── image_conversion_pipeline.dart # 検証済みの画像変換コア
│   ├── image_mozjpeg_encoder.dart     # cjpeg プロセス境界
│   ├── image_metadata.dart            # EXIF / ICC の維持と除去
│   ├── squoosher_controller.dart      # キュー、出力、OS 連携
│   └── settings_service.dart          # 設定の保存
├── ui/                               # 画面、テーマ、ウィジェット
└── utils/                            # 命名と Lanczos リサイズ
macos/
├── Runner/                           # Flutter 本体と日時複製チャネル
└── FinderSync/                       # Finder の右クリック連携
windows/runner/                        # Win32 ウィンドウと日時複製チャネル
windows/shell_extension/               # Windows 11 の IExplorerCommand DLL
windows/shell_registration/            # Explorer 連携の登録と一時昇格
native/mozjpeg/                       # cjpeg の配置先とライセンス
tools/                                # MozJPEG、署名、公証、配布用スクリプト
test/                                 # モデル、命名、変換コアのテスト
```

依存方向は `ui → services → models / utils` とします。  
OS 固有 API は `macos/` と `windows/` に閉じ込め、Dart 側は `MethodChannel` を通じて呼び出します。

## 変更方針

`lib/services/image_conversion_pipeline.dart` と、その直接依存である MozJPEG エンコーダー、メタデータ転送、Lanczos リサイズは変換コアです。  
変換コアの安全条件を維持し、画面・状態管理・OS 連携は要件から組み直せる境界として扱います。

画面とサービスの責務を分け、それぞれの状態所有者を一つにします。  
全面改修では旧経路を残したまま新経路を足さず、呼び出し元、状態所有者、エラー表示の責務を一つずつ確定させます。

## 画像変換の安全条件

### MozJPEG

- JPEG 出力は、配布物へ同梱した MozJPEG 4.1.1 の `cjpeg` だけで生成する
- 開発用バイナリをシステムの固定パスへ依存させず、`native/mozjpeg/` またはアプリバンドルから解決する
- `cjpeg` の終了コード、出力の JPEG シグネチャ、出力寸法を確認してから利用者の出力先へ公開する
- macOS arm64 と Windows x64 の各 CI で、アプリへ配置済みの `cjpeg` を使った実変換テストを通す
- MozJPEG のソースとビルド中間物は一時ディレクトリへ置き、配布に必要な実行ファイルとライセンスだけを保持する

### 元画像の置き換え

元画像の上書きは、起動のたびにオフへ戻る明示的な設定です。  
次の条件をすべて満たした変換だけが元画像を置き換えられます。

1. 変換結果を元画像と別の一時パスへ書き出していること
2. `cjpeg` が正常終了していること
3. 出力がデコード可能な JPEG で、要求した寸法と一致すること
4. 作成日時と更新日時を出力へ反映できること
5. JPEG 入力では検証済みの一時出力を原子的に置き換えること
6. PNG / WebP 入力では既存の同名 JPEG を避けて出力を確定し、その成功後にだけ元入力を削除すること

変換、検証、日時反映の途中で失敗した場合は元画像を残し、失敗をキューとログへ伝えます。  
同名の既存ファイルを暗黙に置き換える処理や、先に元画像を削除する処理は禁止です。

### 出力名

- 通常は `{元のベース名}{サフィックス}.jpg` を使う
- 既存名と衝突した場合は Finder と同じ ` (1)`、` (2)` の連番を使う
- 既定のサフィックスは `_resized`
- JPEG の明示的な上書き時だけ元のパスを使う
- PNG / WebP の上書き時は空いている JPEG 名を確定し、既存 JPEG を保持する

### ファイル日時

変換後の作成日時と更新日時は元画像から引き継ぎます。  
macOS は `URLResourceValues`、Windows は `MethodChannel` 経由の `GetFileTime` / `SetFileTime` を使います。  
ネイティブ処理が失敗した場合は変換処理へエラーを返します。

## Windows の Explorer 連携

Windows 11 では、対応画像の最初の右クリックメニューへ直接項目を表示します。  
［その他のオプションを確認］を開いた後の表示だけでは完成条件を満たしません。

配布は Portable ZIP とし、`IExplorerCommand` の DLL と `AppxManifest.xml` を同梱します。  
Windows 11 の登録は展開済みフォルダを Package Manager へ登録する方式を使い、登録中に必要な開発者モードの変更だけを UAC 付きヘルパーへ任せます。  
登録処理自体は通常権限の現在のユーザーとして実行し、開発者モードは成功・失敗のどちらでも変更前の状態へ戻します。

右上の操作は実際の登録状態に応じて追加・削除・配置移動後の修復へ切り替えます。  
実機検証では、開発者モードを戻した後の最初のメニュー、複数画像の受け渡し、登録解除、UAC キャンセルを確認します。

## Finder Sync

Finder Sync Extension は、Finder で選択した対応画像を本体アプリのキューへ渡す macOS 専用機能です。  
右クリックメニューは対応画像の選択時だけ表示し、フォルダ背景やツールバーへ追加しません。

本体と拡張の受け渡しは App Group とカスタム URL を使います。  
署名時は本体、Finder Sync の `.appex`、ネストしたフレームワーク、`cjpeg` を内側から順に署名し、本体と拡張へそれぞれ正しい `entitlements` ファイルを適用します。

Debug と Release は署名条件が異なります。  
Debug の修正で Release 用の `entitlements` ファイルを流用したり、署名エラーを避けるため Finder Sync をビルド対象から外したりしません。

## 開発工程

### 1. 要件を固定する

実装前に、変更ごとに次の4点を作業メモへ書き出します。

- 利用者が行う操作
- 実画面または出力ファイルで観測できる完了状態
- 守るデータ安全条件
- macOS と Windows の検証範囲

README と確定済みの会話から見た目と操作を決め、変更した仕様は同じ作業で README とテストへ反映します。

### 2. 実装単位を縦に切る

代表的な一つの操作が入力から結果表示まで通る単位で実装します。  
変換コアを変更する場合は、失敗時に元画像と既存出力が残ることを先にテストします。

### 3. Debug で反復する

日常の画面開発は `flutter run -d macos` または `flutter run -d windows` を使い、ホットリロードで確認します。  
文言、余白、状態遷移、ダイアログ、エラー表示は代表画像を投入した実画面で確認します。

リリースビルドは配布境界と OS 固有の組み込みを確認する節目だけで実行します。

### 4. 機械検査を通す

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

MozJPEG または変換コアを変更した場合は、対象 OS の `cjpeg` を指定して実変換テストを行います。

```bash
IMAGE_SQUOOSHER_CJPEG="$PWD/native/mozjpeg/macos/arm64/cjpeg" \
  flutter test test/services/image_conversion_pipeline_test.dart
```

Windows では同じ環境変数へ `native/mozjpeg/windows/cjpeg.exe` またはアプリへ配置済みの `cjpeg.exe` を指定します。

### 5. 実画面を確認する

少なくとも次の状態を Debug アプリの実画面で確認します。

- 画像がない初期状態
- JPEG・PNG・WebP を追加した変換前プレビュー
- クロップ、リサイズ、画質、メタデータ、サフィックスの変更
- 変換成功、複数ファイルの進捗、停止、個別失敗
- 同名出力の連番と、明示的な上書きチェックによる置き換え
- 日本語と英語
- macOS の Finder 右クリック起動

エージェントがアプリを起動できる環境では、エージェントが実画面確認まで担当します。  
確認できない OS は未確認として報告し、CI の成果物または実機を使う次の検証地点を明示します。

### 6. 両 OS の配布境界を確認する

- macOS arm64: `.app` 内の Finder Sync、`Contents/Resources/mozjpeg/cjpeg`、Developer ID 署名、公証チケットの添付、Gatekeeper
- Windows x64: リリースフォルダ内の `mozjpeg/cjpeg.exe`、VC++ ランタイム DLL、作成日時の複製、最大化無効
- 両 OS: アプリへ配置済みの `cjpeg` による JPEG・PNG・WebP の実変換

## CI とリリース

`.github/workflows/build.yml` は Flutter 3.35.7 に固定し、format、analyze、test を先に通します。  
品質検査に成功した後で macOS arm64 と Windows x64 を別ジョブで構築し、両方の ZIP を成果物として保存します。

タグは `vX.Y.Z` の形式に限定し、`pubspec.yaml` のバージョンと一致させます。  
タグ時の配布名は次の2つに固定します。

- `ImageSquoosher-vX.Y.Z-macos.zip`
- `ImageSquoosher-vX.Y.Z-windows.zip`

macOS のタグリリースは Developer ID 署名と Apple 公証が成功した場合だけ公開します。  
署名用証明書、App Store Connect API キー、キーチェーンはリポジトリへ保存しません。

## コーディング規約

- コメントとドキュメントコメントは日本語で書き、何をするかより理由と制約を残す
- ログ本文は英語で書き、ピリオドで終える
- 利用者向け文言は ARB へ置き、日本語と英語を同時に更新する
- `bool` は `is`、`has`、`can`、`should` で始める
- Dart の `enum` 値は lowerCamelCase を使う
- 複数行の Dart 引数とコレクションには末尾カンマを付ける
- OS 固有コードのパスは UTF-8 / UTF-16、空白、日本語を含む場合を考慮する
- 依存バージョンの変更は、必要性と両 OS への影響を説明できる作業に限定する

## 禁止事項

- 変換成功前に元画像を削除または置き換えること
- 既存の同名 JPEG を暗黙に上書きすること
- `cjpeg` が見つからない状態を別の JPEG エンコーダーで黙って代替すること
- `format`、`analyze`、`test` の失敗を除外設定や `continue-on-error` で隠すこと
- Debug の実画面確認を省略し、リリースビルドの成功だけで画面完成とすること
- macOS だけの確認で Windows 対応完了、または Windows だけの確認で macOS 対応完了とすること
- 実行可能な QA を利用者へ手順として押し戻すこと
- 使われない旧画面や旧サービスを、新実装の保険として並行維持すること

## 完了条件

変更は、要件に対応する実装、故障を捕捉するテスト、Debug 実画面の確認、対象 OS の配布境界確認がそろった時点で完了です。  
完了報告には実行したコマンド、実画面で確認した状態、未確認の OS、生成した成果物名を具体的に記載します。
