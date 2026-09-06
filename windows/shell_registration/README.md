# Windows シェル登録ヘルパー

`ImageSquoosherShellRegistration.exe` は、Windows 11 の最初の右クリックメニューへ `ImageSquoosherShell.dll` を登録する小さな GUI サブシステムの実行ファイルです。  
配布フォルダの `AppxManifest.xml` を loose package として現在ユーザーへ登録し、MSIX や自己署名証明書を配布物へ加えずに packaged COM と `IExplorerCommand` を有効にします。

### コマンド

終了コードは呼び出し元のアプリが登録状態と失敗理由を判断するために使います。

| コマンド | 成功時の動作 |
| --- | --- |
| `--register` | 現在の配布フォルダを登録し、登録先と必須ファイルを再照会して終了コード 0 を返す |
| `--unregister` | 同じパッケージ名・発行者の現在ユーザー登録を、アプリデータを保持して解除する |
| `--status` | 現在フォルダの正常な登録は 0、未登録は 1、別フォルダまたは破損は 2、照会失敗は 3 を返す |

`--register` と `--unregister` の失敗時は、Windows の HRESULT または Win32 エラーを HRESULT へ変換した値を返します。  
`--developer-mode` は昇格した同じ実行ファイルだけが使う内部コマンドで、固定形式のイベント名と通常権限の親プロセスが揃った場合だけ処理へ進みます。

### 登録処理

登録状態は `PackageManager.FindPackagesForUser()` から取得し、`ImageSquoosher.ShellExtension` と `CN=tsukumijima` の組だけを対象にします。  
パッケージ状態、登録フォルダ、`AppxManifest.xml`、アプリ本体、COM DLL、アイコンがすべて一致した場合にだけ現在フォルダの正常な登録と判定します。

Developer Mode が有効な端末では、通常権限のプロセスが解除と登録を続けて実行します。  
一時的な有効化が必要な端末では、通常権限の親が推測困難な名前の ready・done イベントを作り、`runas` で起動した子が `AllowDevelopmentWithoutDevLicense` の有無・型・バイト列を保存してから値を 1 にします。  
子が ready を通知した後で、親が現在ユーザーの古い登録を解除して `RegisterPackageAsync()` を実行します。  
子は done、親プロセスの終了、または待機期限の到達を契機に保存値を復元し、親は復元結果を確認してから登録結果を返します。

登録変更と Developer Mode の一時変更は、ユーザーをまたいで共有する名前付きミューテックスで直列化します。  
UAC で別の管理者資格情報が選ばれても、パッケージ登録は通常権限の親に残るため、操作対象はアプリを実行している現在ユーザーです。

### データ境界

登録解除には `RemovalOptions::PreserveApplicationData` を指定し、対象パッケージのデータ領域を保持します。  
このヘルパーが永続的に変更する範囲は、同じパッケージ名・発行者を持つ現在ユーザーのパッケージ登録です。  
利用者の画像、ImageSquoosher 本体の設定、他のパッケージ、他のレジストリ値は処理対象に含まれません。  
Developer Mode の値は登録中だけ変更し、元の値が存在しなかった場合は値を削除して元の状態へ戻します。

### 配布ファイル

登録時は次のファイルが同じフォルダに必要です。

- `ImageSquoosher.exe`
- `ImageSquoosherShell.dll`
- `ImageSquoosherShellRegistration.exe`
- `AppxManifest.xml`
- `app_icon_1024.png`

`AppxManifest.xml` はバージョン `1.0.0.0` の x64 パッケージとして、JPEG、PNG、WebP の `desktop4:fileExplorerContextMenus` と STA の COM surrogate を宣言します。  
CMake はマニフェストとアイコンをヘルパーの隣へコピーし、Flutter の実行時フォルダにも同じ2ファイルをインストールします。

### 検証範囲

単独 CMake テストはパス判定、破損・移動登録の分類、内部イベント名を検証し、パッケージやレジストリを変更しません。  
`MakeAppx pack` による検査では、マニフェストのスキーマと配布ファイル参照を登録前に確認できます。  
loose registration、Developer Mode の復元、Explorer のメニュー表示と実行は Windows 11 実機での登録を伴うため、配布物を使う統合検証で確認します。
