#!/usr/bin/env bash
# macOS の Developer ID 署名、公証チケットの添付、検証を CI とローカルから扱う

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT

SIGN_MACHO_LIST_PATH=''
SIGN_BUNDLE_LIST_PATH=''

function log() {
    echo "[macos-codesign] $*"
}

function fail() {
    echo "[macos-codesign] ERROR: $*" >&2
    exit 1
}

function require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        fail "Required command is not available: $command_name."
    fi
}

function require_env() {
    local env_name="$1"

    if [ -z "${!env_name:-}" ]; then
        fail "Required environment variable is not set: $env_name."
    fi
}

function decode_base64_file() {
    local input_value="$1"
    local output_path="$2"

    # GitHub Actions の macOS ランナーは BSD base64 なので `-D` を優先する
    if printf '%s' "$input_value" | base64 -D > "$output_path" 2>/dev/null; then
        return
    fi

    # GNU base64 を使うローカル環境でも同じスクリプトを使えるようにする
    printf '%s' "$input_value" | base64 --decode > "$output_path"
}

function setup_keychain() {
    require_command security
    require_env MACOS_CERTIFICATE_P12_BASE64
    require_env MACOS_CERTIFICATE_PASSWORD

    local temp_root="${RUNNER_TEMP:-/tmp}"
    local keychain_password="${MACOS_KEYCHAIN_PASSWORD:-$(openssl rand -base64 32 2>/dev/null || date +%s | shasum -a 256 | awk '{ print $1 }')}"
    local run_identifier="${GITHUB_RUN_ID:-local}-$$"
    local keychain_path="$temp_root/imagesquoosher-macos-signing-$run_identifier.keychain-db"
    local certificate_path="$temp_root/imagesquoosher-macos-certificate-$run_identifier.p12"
    local keychain_entry
    local -a existing_keychains=()

    while IFS= read -r keychain_entry; do
        keychain_entry="${keychain_entry#*\"}"
        keychain_entry="${keychain_entry%\"*}"
        existing_keychains+=("$keychain_entry")
    done < <(security list-keychains -d user)

    # 一時証明書が作成直後から所有者だけに読めるよう、作成時の `umask` も制限する
    (umask 077; decode_base64_file "$MACOS_CERTIFICATE_P12_BASE64" "$certificate_path")
    chmod 600 "$certificate_path"

    # 一時キーチェーンを検索対象の先頭へ追加し、開発者のログインキーチェーンは現在の設定を保つ
    security create-keychain -p "$keychain_password" "$keychain_path"
    security set-keychain-settings -lut 21600 "$keychain_path"
    security unlock-keychain -p "$keychain_password" "$keychain_path"
    security import "$certificate_path" \
        -k "$keychain_path" \
        -P "$MACOS_CERTIFICATE_PASSWORD" \
        -T /usr/bin/codesign \
        -T /usr/bin/security
    security set-key-partition-list \
        -S apple-tool:,apple:,codesign: \
        -s \
        -k "$keychain_password" \
        "$keychain_path" >/dev/null
    # `Bash 3.2` の `set -u` では空配列を展開できないため、既存キーチェーンの有無で呼び出しを分ける
    if [ "${#existing_keychains[@]}" -eq 0 ]; then
        security list-keychains -d user -s "$keychain_path"
    else
        security list-keychains -d user -s "$keychain_path" "${existing_keychains[@]}"
    fi

    if [ -n "${GITHUB_ENV:-}" ]; then
        echo "MACOS_KEYCHAIN_PATH=$keychain_path" >> "$GITHUB_ENV"
    fi

    log "macOS signing certificate imported."
    security find-identity -v -p codesigning "$keychain_path"
}

function detect_codesign_identity() {
    local identity="${MACOS_CODESIGN_IDENTITY:-}"
    local -a find_identity_args=(-v -p codesigning)

    if [ -n "$identity" ]; then
        echo "$identity"
        return
    fi

    # CI では一時キーチェーンだけを検索し、ローカルでは通常の検索対象から証明書を探す
    if [ -n "${MACOS_KEYCHAIN_PATH:-}" ]; then
        find_identity_args+=("$MACOS_KEYCHAIN_PATH")
    fi

    identity="$(
        security find-identity "${find_identity_args[@]}" 2>/dev/null \
            | sed -n 's/^.*"\(Developer ID Application: [^"]*\)".*$/\1/p' \
            | head -n 1
    )"

    if [ -z "$identity" ]; then
        fail "Developer ID Application identity was not found. Set MACOS_CODESIGN_IDENTITY if auto-detection fails."
    fi

    echo "$identity"
}

function is_macho_file() {
    local target_path="$1"

    file -b "$target_path" | grep -q 'Mach-O'
}

function should_skip_individual_codesign() {
    local target_path="$1"

    # アプリと Finder Sync の `.appex` にあるメイン実行ファイルは、バンドル署名で `entitlements` を適用する
    [[ "$target_path" == *.app/Contents/MacOS/* || "$target_path" == *.appex/Contents/MacOS/* ]]
}

function collect_macho_files() {
    local app_path="$1"
    local output_path="$2"

    : > "$output_path"
    while IFS= read -r -d '' target_path; do
        if is_macho_file "$target_path" && ! should_skip_individual_codesign "$target_path"; then
            printf '%s\t%s\n' "${#target_path}" "$target_path" >> "$output_path"
        fi
    done < <(find "$app_path" -type f -print0)

    sort -rn "$output_path" | cut -f2- > "$output_path.sorted"
}

function collect_bundle_paths() {
    local app_path="$1"
    local output_path="$2"

    # 最も内側の `.framework`、Finder Sync の `.appex`、`.app` の順に署名する
    find "$app_path" -depth -type d \( -name '*.framework' -o -name '*.appex' -o -name '*.app' \) -print \
        > "$output_path"
}

function run_codesign() {
    local output

    # 成功時の `replacing existing signature` を隠し、失敗時だけ詳細を表示する
    if ! output="$(codesign "$@" 2>&1)"; then
        echo "$output" >&2
        return 1
    fi
}

function sign_file() {
    local target_path="$1"
    local identity
    identity="$(detect_codesign_identity)"
    local -a arguments=(--force)

    if [ "$identity" != "-" ]; then
        arguments+=(--options runtime --timestamp)
    fi
    arguments+=(--sign "$identity")

    run_codesign "${arguments[@]}" "$target_path"
}

function sign_bundle() {
    local bundle_path="$1"
    local entitlements_path=''
    local identity
    identity="$(detect_codesign_identity)"
    local -a arguments=(--force)

    if [ "$identity" != "-" ]; then
        arguments+=(--options runtime --timestamp)
    fi
    arguments+=(--sign "$identity")

    if [[ "$bundle_path" == *.app ]]; then
        entitlements_path="${MACOS_CODESIGN_ENTITLEMENTS:-${PROJECT_ROOT}/macos/Runner/Distribution.entitlements}"
    elif [[ "$bundle_path" == *.appex ]]; then
        entitlements_path="${MACOS_CODESIGN_FINDER_SYNC_ENTITLEMENTS:-${PROJECT_ROOT}/macos/FinderSync/FinderSync.entitlements}"
    fi

    if [ -n "$entitlements_path" ]; then
        if [ ! -f "$entitlements_path" ]; then
            fail "Entitlements file does not exist: $entitlements_path."
        fi
        arguments+=(--entitlements "$entitlements_path")
    fi

    run_codesign "${arguments[@]}" "$bundle_path"
}

function sign_app() {
    local app_path="$1"

    require_command codesign
    require_command file

    if [ ! -d "$app_path" ]; then
        fail "App bundle does not exist: $app_path."
    fi

    local temp_root="${RUNNER_TEMP:-/tmp}"
    SIGN_MACHO_LIST_PATH="$temp_root/imagesquoosher-macho-files-$$.txt"
    SIGN_BUNDLE_LIST_PATH="$temp_root/imagesquoosher-bundles-$$.txt"
    trap 'rm -f "$SIGN_MACHO_LIST_PATH" "$SIGN_MACHO_LIST_PATH.sorted" "$SIGN_BUNDLE_LIST_PATH"' EXIT

    collect_macho_files "$app_path" "$SIGN_MACHO_LIST_PATH"
    collect_bundle_paths "$app_path" "$SIGN_BUNDLE_LIST_PATH"

    log "Signing Mach-O files in app bundle."
    while IFS= read -r target_path; do
        sign_file "$target_path"
    done < "$SIGN_MACHO_LIST_PATH.sorted"

    log "Signing nested frameworks, Finder Sync extension bundles, and the app bundle."
    while IFS= read -r bundle_path; do
        sign_bundle "$bundle_path"
    done < "$SIGN_BUNDLE_LIST_PATH"

    verify_code_signature "$app_path"
}

function setup_notary_api_key() {
    require_env APPLE_API_KEY_ID
    require_env APPLE_API_KEY_P8_BASE64

    local temp_root="${RUNNER_TEMP:-/tmp}"
    local api_key_path="$temp_root/AuthKey_${APPLE_API_KEY_ID}.p8"
    # 一時 API キーが作成直後から所有者だけに読めるよう、作成時の `umask` も制限する
    (umask 077; decode_base64_file "$APPLE_API_KEY_P8_BASE64" "$api_key_path")
    chmod 600 "$api_key_path"

    if [ -n "${GITHUB_ENV:-}" ]; then
        echo "APPLE_API_KEY_PATH=$api_key_path" >> "$GITHUB_ENV"
    fi

    echo "$api_key_path"
}

function notarize_app() {
    local app_path="$1"

    require_command ditto
    require_command xcrun
    require_env APPLE_API_KEY_ID
    require_env APPLE_API_ISSUER_ID

    if [ ! -d "$app_path" ]; then
        fail "App bundle does not exist: $app_path."
    fi

    local api_key_path
    api_key_path="${APPLE_API_KEY_PATH:-$(setup_notary_api_key)}"
    local temp_root="${RUNNER_TEMP:-/tmp}"
    local archive_path
    archive_path="$temp_root/$(basename "$app_path").notarize-$$.zip"
    log "Creating ZIP archive for app notarization."
    ditto -c -k --keepParent "$app_path" "$archive_path"
    log "Submitting app bundle for notarization."
    xcrun notarytool submit "$archive_path" \
        --key "$api_key_path" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" \
        --wait
    log "Stapling notarization ticket to app bundle."
    xcrun stapler staple "$app_path"
    xcrun stapler validate "$app_path"
}

function verify_code_signature() {
    local app_path="$1"

    require_command codesign

    if [ ! -d "$app_path" ]; then
        fail "App bundle does not exist: $app_path."
    fi

    log "Verifying app bundle code signature."
    codesign --verify --deep --strict --verbose=4 "$app_path"
}

function verify_app() {
    local app_path="$1"

    require_command codesign
    require_command spctl

    if [ ! -d "$app_path" ]; then
        fail "App bundle does not exist: $app_path."
    fi

    verify_code_signature "$app_path"
    log "Verifying Gatekeeper assessment."
    spctl --assess --type execute --verbose=4 "$app_path"
    log "App bundle signature and Gatekeeper assessment are valid."
}

function usage() {
    cat <<'USAGE'
Usage:
  tools/codesign_macos.bash setup-keychain
  tools/codesign_macos.bash sign-app <image_squoosher.app>
  tools/codesign_macos.bash verify-app <image_squoosher.app>
  tools/codesign_macos.bash verify-signature <image_squoosher.app>
  tools/codesign_macos.bash notarize-app <image_squoosher.app>
USAGE
}

command_name="${1:-}"
shift || true

case "$command_name" in
    setup-keychain)
        setup_keychain "$@"
        ;;
    sign-app)
        [ "$#" -eq 1 ] || { usage; exit 1; }
        sign_app "$1"
        ;;
    verify-app)
        [ "$#" -eq 1 ] || { usage; exit 1; }
        verify_app "$1"
        ;;
    verify-signature)
        [ "$#" -eq 1 ] || { usage; exit 1; }
        verify_code_signature "$1"
        ;;
    notarize-app)
        [ "$#" -eq 1 ] || { usage; exit 1; }
        notarize_app "$1"
        ;;
    *)
        usage
        exit 1
        ;;
esac
