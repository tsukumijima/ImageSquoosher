$ErrorActionPreference = 'Stop'

# cjpeg は配布物に含める実行ファイルだけを native/ に置き、展開したソースと CMake の中間物は一時領域へ閉じ込める
$projectRoot = Split-Path -Parent $PSScriptRoot
$mozJpegVersion = '4.1.1'
$sourceUrl = "https://github.com/mozilla/mozjpeg/archive/refs/tags/v$mozJpegVersion.zip"
$outputDirectory = Join-Path $projectRoot 'native/mozjpeg/windows'
$workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("image-squoosher-mozjpeg-" + [Guid]::NewGuid().ToString('N'))

try {
    if ($null -eq (Get-Command cmake -ErrorAction SilentlyContinue)) {
        throw 'Required command is missing: cmake.'
    }

    New-Item -ItemType Directory -Path $workDirectory | Out-Null
    $archivePath = Join-Path $workDirectory 'mozjpeg.zip'
    Invoke-WebRequest -Uri $sourceUrl -OutFile $archivePath
    Expand-Archive -Path $archivePath -DestinationPath $workDirectory

    $sourceDirectory = Join-Path $workDirectory "mozjpeg-$mozJpegVersion"
    $buildDirectory = Join-Path $workDirectory 'build'

    # MozJPEG 4.1.1 の古い CMake 設定を現行 CMake でも評価できるよう互換ポリシーを指定する
    # JPEG ライブラリと MSVC ランタイムを静的リンクし、cjpeg.exe 単体をアプリへ含められる状態にする
    cmake `
        -S $sourceDirectory `
        -B $buildDirectory `
        -G 'Visual Studio 17 2022' `
        -A x64 `
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 `
        -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded `
        -DWITH_TURBOJPEG=OFF `
        -DENABLE_SHARED=OFF
    cmake --build $buildDirectory --config Release --target cjpeg-static --parallel

    $builtExecutable = Get-ChildItem -Path $buildDirectory -Filter 'cjpeg-static.exe' -Recurse | Select-Object -First 1
    if ($null -eq $builtExecutable) {
        throw "MozJPEG build did not create cjpeg-static.exe: $buildDirectory."
    }

    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    Copy-Item -Path $builtExecutable.FullName -Destination (Join-Path $outputDirectory 'cjpeg.exe') -Force
    Write-Output "Built MozJPEG ${mozJpegVersion}: $(Join-Path $outputDirectory 'cjpeg.exe')."
}
finally {
    if (Test-Path $workDirectory) {
        Remove-Item -Path $workDirectory -Recurse -Force
    }
}
