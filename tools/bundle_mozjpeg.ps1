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

# 配布先だけで実行できるよう、エンコーダーのライセンスと MSVC ランタイムを一緒に配置する
foreach ($licenseName in @('LICENSE.md', 'README.ijg', 'LICENSE-zlib.txt')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot "native/mozjpeg/$licenseName") -Destination $destinationDirectory -Force
}
$vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswherePath -PathType Leaf)) {
    throw 'Visual Studio Installer vswhere.exe was not found.'
}
foreach ($runtimeName in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    $runtimePaths = @(& $vswherePath -latest -products '*' -find "VC/Redist/MSVC/*/x64/*/$runtimeName")
    if ($runtimePaths.Count -eq 0) {
        throw "VC++ runtime DLL was not found: $runtimeName."
    }
    # 複数世代のツールセットがある環境でも、古い DLL を同梱して起動時にクラッシュさせない
    $runtimePath = $runtimePaths | Sort-Object -Property {
        $runtimeVersion = (Get-Item -LiteralPath $_).VersionInfo
        [version]::new($runtimeVersion.FileMajorPart, $runtimeVersion.FileMinorPart, $runtimeVersion.FileBuildPart, $runtimeVersion.FilePrivatePart)
    } -Descending | Select-Object -First 1
    Copy-Item -LiteralPath $runtimePath -Destination $AppPath -Force
}

if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
    throw "Bundled cjpeg was not created: $destinationPath."
}

Write-Output "Bundled MozJPEG cjpeg in $destinationPath."
