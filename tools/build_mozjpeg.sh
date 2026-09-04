#!/usr/bin/env bash

set -euo pipefail

# cjpeg は配布物に含める実行ファイルだけを native/ に置き、展開したソースと CMake の中間物は一時領域へ閉じ込める
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT
readonly MOZJPEG_VERSION='4.1.1'
readonly SOURCE_URL="https://github.com/mozilla/mozjpeg/archive/refs/tags/v${MOZJPEG_VERSION}.tar.gz"
HOST_ARCH="$(uname -m)"
readonly HOST_ARCH
case "$HOST_ARCH" in
  arm64|aarch64)
    readonly TARGET_ARCH='arm64'
    ;;
  x86_64|amd64)
    readonly TARGET_ARCH='x86_64'
    ;;
  *)
    printf 'Unsupported macOS architecture: %s.\n' "$HOST_ARCH" >&2
    exit 1
    ;;
esac
readonly OUTPUT_DIRECTORY="${PROJECT_ROOT}/native/mozjpeg/macos/${TARGET_ARCH}"
WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/image-squoosher-mozjpeg.XXXXXX")"
readonly WORK_DIRECTORY

cleanup() {
  rm -rf "${WORK_DIRECTORY}"
}
trap cleanup EXIT

for required_command in cmake curl tar otool; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    printf 'Required command is missing: %s.\n' "${required_command}" >&2
    exit 1
  fi
done

readonly ARCHIVE_PATH="${WORK_DIRECTORY}/mozjpeg.tar.gz"
readonly SOURCE_DIRECTORY="${WORK_DIRECTORY}/mozjpeg-${MOZJPEG_VERSION}"
readonly BUILD_DIRECTORY="${WORK_DIRECTORY}/build"

curl --fail --location --retry 3 --output "${ARCHIVE_PATH}" "${SOURCE_URL}"
tar -xzf "${ARCHIVE_PATH}" --directory "${WORK_DIRECTORY}"

# MozJPEG 4.1.1 の古い CMake 設定を現行 CMake でも評価できるよう互換ポリシーを指定する
# ENABLE_SHARED を切ると、別途 dylib を配布せず cjpeg 単体を Resources へコピーできる
cmake -S "${SOURCE_DIRECTORY}" -B "${BUILD_DIRECTORY}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="${TARGET_ARCH}" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DENABLE_SHARED=OFF \
  -DWITH_TURBOJPEG=OFF
cmake --build "${BUILD_DIRECTORY}" --config Release --target cjpeg-static --parallel

readonly BUILT_EXECUTABLE="${BUILD_DIRECTORY}/cjpeg-static"
if [[ ! -x "${BUILT_EXECUTABLE}" ]]; then
  printf 'MozJPEG build did not create cjpeg: %s.\n' "${BUILT_EXECUTABLE}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIRECTORY}"
install -m 755 "${BUILT_EXECUTABLE}" "${OUTPUT_DIRECTORY}/cjpeg"

# Apple の基本ライブラリ以外を動的に読む cjpeg はアプリ単体で実行できないため、配布前に検出する
if otool -L "${OUTPUT_DIRECTORY}/cjpeg" | tail -n +2 | grep -E '/(libjpeg|mozjpeg|turbojpeg)' >/dev/null; then
  printf 'cjpeg unexpectedly links a bundled JPEG library.\n' >&2
  exit 1
fi

printf 'Built MozJPEG %s for %s: %s.\n' "${MOZJPEG_VERSION}" "${TARGET_ARCH}" "${OUTPUT_DIRECTORY}/cjpeg"
