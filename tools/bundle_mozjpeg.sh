#!/usr/bin/env bash

set -euo pipefail

# Flutter の資産領域は実行ファイルとして扱わず、macOS アプリバンドルの `Resources` へ明示的に配置する
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT
readonly APP_PATH="${1:-${PROJECT_ROOT}/build/macos/Build/Products/Release/ImageSquoosher.app}"

if [ ! -d "$APP_PATH" ]; then
  printf 'macOS app bundle does not exist: %s.\n' "$APP_PATH" >&2
  exit 1
fi

readonly SOURCE_PATH="${PROJECT_ROOT}/native/mozjpeg/macos/arm64/cjpeg"
readonly DESTINATION_DIRECTORY="${APP_PATH}/Contents/Resources/mozjpeg"
readonly DESTINATION_PATH="${DESTINATION_DIRECTORY}/cjpeg"

if [ ! -x "$SOURCE_PATH" ]; then
  printf 'MozJPEG cjpeg executable does not exist: %s.\n' "$SOURCE_PATH" >&2
  exit 1
fi

mkdir -p "$DESTINATION_DIRECTORY"
install -m 755 "$SOURCE_PATH" "$DESTINATION_PATH"

if [ ! -x "$DESTINATION_PATH" ]; then
  printf 'Bundled cjpeg is not executable: %s.\n' "$DESTINATION_PATH" >&2
  exit 1
fi

printf 'Bundled MozJPEG cjpeg in %s.\n' "$DESTINATION_PATH"
