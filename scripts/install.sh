#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Install XcodeGen first: brew install xcodegen" >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    echo "Install full Xcode, open it once, and select it with xcode-select." >&2
    exit 1
fi
stop_running_translator() {
    if ! pgrep -x Translator >/dev/null; then
        return
    fi
    pkill -x Translator >/dev/null 2>&1 || true
    for _ in {1..50}; do
        if ! pgrep -x Translator >/dev/null; then
            return
        fi
        sleep 0.1
    done
    echo "Could not stop running Translator process." >&2
    exit 1
}

stop_running_translator

mkdir -p "$HOME/Applications"
# Stage a complete bundle. Overlaying Debug and Release apps retains stale dylibs.
staging="$HOME/Applications/.translator-install"
if ! mkdir "$staging"; then
    echo "Another installation is active, or an interrupted installation needs recovery: $staging" >&2
    exit 1
fi
trap '
    if [[ -e "$staging/previous.app" ]]; then
        echo "Previous app retained at: $staging/previous.app" >&2
    else
        rm -rf "$staging"
    fi
' EXIT
default_signing_identity="Translator Local Development"
has_signing_identity() {
    local identity_name="$1"
    security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity_name\""
}

ensure_signing_identity() {
    if [[ -n "${TRANSLATOR_SIGNING_IDENTITY:-}" ]]; then
        printf '%s' "$TRANSLATOR_SIGNING_IDENTITY"
        return
    fi
    if has_signing_identity "$default_signing_identity"; then
        printf '%s' "$default_signing_identity"
        return
    fi
    local certificate_directory="$staging/certificate"
    mkdir -p "$certificate_directory"
    local private_key_path="$certificate_directory/key.pem"
    local certificate_path="$certificate_directory/cert.pem"
    local pkcs12_path="$certificate_directory/identity.p12"
    local export_password="translator-local-signing"
    local login_keychain
    login_keychain="$(security default-keychain -d user 2>/dev/null | tr -d '[:space:]"')"
    local pkcs12_arguments=(-export -out "$pkcs12_path" -inkey "$private_key_path" -in "$certificate_path" -passout "pass:$export_password")
    if openssl pkcs12 -help 2>&1 | grep -q -- -legacy; then
        pkcs12_arguments=(-legacy "${pkcs12_arguments[@]}")
    fi
    if openssl req -x509 -newkey rsa:2048 -nodes -keyout "$private_key_path" -out "$certificate_path" -days 3650 -config scripts/local-signing.cnf >/dev/null 2>&1 \
        && openssl pkcs12 "${pkcs12_arguments[@]}" >/dev/null 2>&1 \
        && security import "$pkcs12_path" -k "$login_keychain" -P "$export_password" -T /usr/bin/codesign >/dev/null 2>&1 \
        && security add-trusted-cert -r trustRoot -p codeSign -k "$login_keychain" "$certificate_path" >/dev/null 2>&1 \
        && has_signing_identity "$default_signing_identity"; then
        rm -rf "$certificate_directory"
        printf '%s' "$default_signing_identity"
        return
    fi
    security delete-certificate -c "$default_signing_identity" "$login_keychain" >/dev/null 2>&1 || true
    rm -rf "$certificate_directory"
    echo "Warning: could not configure local signing certificate; falling back to ad-hoc signing." >&2
    printf '%s' "-"
}

signing_identity="$(ensure_signing_identity)"
xcodegen generate
xcodebuild -scheme Translator -configuration Release -derivedDataPath build \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$signing_identity" build

app="build/Build/Products/Release/Translator.app"
codesign --verify --deep --strict "$app"
ditto "$app" "$staging/Translator.app"
codesign --verify --deep --strict "$staging/Translator.app"
stop_running_translator
designated_requirement() {
    local bundle_path="$1"
    codesign -d -r- "$bundle_path" 2>&1 | grep 'designated =>' || true
}

previous_requirement=""
new_requirement="$(designated_requirement "$staging/Translator.app")"
if [[ -e "$HOME/Applications/Translator.app" ]]; then
    previous_requirement="$(designated_requirement "$HOME/Applications/Translator.app")"
    mv "$HOME/Applications/Translator.app" "$staging/previous.app"
fi
if ! mv "$staging/Translator.app" "$HOME/Applications/Translator.app"; then
    if [[ -e "$staging/previous.app" ]]; then
        mv "$staging/previous.app" "$HOME/Applications/Translator.app"
    fi
    exit 1
fi
codesign --verify --deep --strict "$HOME/Applications/Translator.app"
if [[ -n "$previous_requirement" && -n "$new_requirement" && "$previous_requirement" != "$new_requirement" ]]; then
    tccutil reset Accessibility co.yuritoledo.translator >/dev/null 2>&1 || true
fi
rm -rf "$staging/previous.app"
open "$HOME/Applications/Translator.app"
printf "\nInstalled: %s/Applications/Translator.app\n" "$HOME"
echo "Translator appears in the menu bar, not the Dock."
