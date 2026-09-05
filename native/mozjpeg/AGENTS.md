# MozJPEG 実行ファイル

このディレクトリには、`tools/build_mozjpeg.sh` または `tools/build_mozjpeg.ps1` が生成する MozJPEG 4.1.1 の `cjpeg` を置きます。  
アプリ本体は FFI を使わず、生成された実行ファイルを `Process.start()` で起動します。

macOS は arm64 のみをビルドし、出力先は `native/mozjpeg/macos/arm64/cjpeg` です。  
Windows は x64 のみをビルドし、出力先は `native/mozjpeg/windows/cjpeg.exe` です。

`tools/bundle_mozjpeg.sh` は macOS app bundle の `Contents/Resources/mozjpeg/` へ、`tools/bundle_mozjpeg.ps1` は Windows release 出力の `mozjpeg/` へコピーします。

配布ビルドでは各実行ファイルをアプリの Resources へコピーし、実行権限を保ったまま署名します。  
`cjpeg` は PPM P6 を入力に取り、`-quality 1..100 -progressive -optimize` と、必要時の `-icc` を受け取ります。

MozJPEG と基盤の libjpeg-turbo には、修正 BSD 3 条項ライセンス、Independent JPEG Group ライセンス、zlib ライセンスが適用されます。  
配布物には、修正 BSD 3 条項ライセンスと帰属表示をまとめた [`LICENSE.md`](LICENSE.md)、Independent JPEG Group の [`README.ijg`](README.ijg)、zlib の [`LICENSE-zlib.txt`](LICENSE-zlib.txt) を同梱します。  
対応する上流ソースは [Mozilla/mozjpeg の v4.1.1 タグ](https://github.com/mozilla/mozjpeg/tree/v4.1.1) で確認できます。
