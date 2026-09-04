param(
    [string]$AppPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/windows/x64/runner/Release')
)

$ErrorActionPreference = 'Stop'

# Flutter の資産領域は実行ファイルとして扱わず、Windows のリリース出力の隣へ明示的に配置する
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'native/mozjpeg/windows/cjpeg.exe'
$destinationDirectory = Join-Path $AppPath 'mozjpeg'
$destinationPath = Join-Path $destinationDirectory 'cjpeg.exe'

if (-not (Test-Path -LiteralPath $AppPath -PathType Container)) {
    throw "Windows release directory does not exist: $AppPath."
}

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "MozJPEG cjpeg executable does not exist: $sourcePath."
}

New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force

if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
    throw "Bundled cjpeg was not created: $destinationPath."
}

Write-Output "Bundled MozJPEG cjpeg in $destinationPath."
