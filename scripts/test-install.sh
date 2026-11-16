#!/bin/bash
# Exercise installation without Xcode, Keychain access, or launching an app.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/project/scripts" "$tmp/home/Applications/Translator.app/Contents/MacOS"
cp "$root/scripts/install.sh" "$root/scripts/local-signing.cnf" "$tmp/project/scripts/"

cat > "$tmp/mock" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$(basename "$0")" in
    xcodegen|xcrun) exit 0 ;;
    open)
        echo "open $*" >> "$HOME/.translator-test-open-log"
        exit 0
        ;;
    codesign)
        if [[ "${1:-}" == "-d" && "${2:-}" == "-r-" ]]; then
            target_bundle="${3:-}"
            if [[ -f "$target_bundle/Contents/MacOS/signing-requirement" ]]; then
                cat "$target_bundle/Contents/MacOS/signing-requirement"
            else
                echo '# designated => cdhash H"0000000000000000000000000000000000000000"'
            fi
        fi
        exit 0
        ;;
    tccutil)
        echo "tccutil $*" >> "$HOME/.translator-test-tccutil-log"
        exit 0
        ;;
    openssl)
        for argument in "$@"; do
            if [[ "$argument" == *.pem || "$argument" == *.p12 ]]; then
                touch "$argument"
            fi
        done
        echo "openssl $*" >> "$HOME/.translator-test-openssl-log"
        exit 0
        ;;
    security)
        subcommand="${1:-}"
        case "$subcommand" in
            find-identity)
                if [[ -f "$HOME/.translator-test-cert-trusted" ]]; then
                    echo '  1) ABCDEF1234567890 "Translator Local Development"'
                    echo '     1 valid identities found'
                else
                    echo '     0 valid identities found'
                fi
                ;;
            default-keychain)
                echo "\"$HOME/Library/Keychains/login.keychain-db\""
                ;;
            import)
                touch "$HOME/.translator-test-cert-imported"
                ;;
            add-trusted-cert)
                if [[ "${INSTALL_TEST_FAIL_TRUST:-0}" == 1 ]]; then
                    exit 1
                fi
                touch "$HOME/.translator-test-cert-trusted"
                ;;
            delete-certificate)
                touch "$HOME/.translator-test-cert-deleted"
                rm -f "$HOME/.translator-test-cert-imported" "$HOME/.translator-test-cert-trusted"
                ;;
        esac
        exit 0
        ;;
    pgrep)
        [[ -e "$HOME/.translator-test-running" ]]
        ;;
    pkill)
        echo "pkill $*" >> "$HOME/.translator-test-pkill-log"
        rm -f "$HOME/.translator-test-running"
        exit 0
        ;;
    xcodebuild)
        [[ "${1:-}" != -version ]] || exit 0
        signing_identity_used="-"
        for argument in "$@"; do
            if [[ "$argument" == CODE_SIGN_IDENTITY=* ]]; then
                signing_identity_used="${argument#CODE_SIGN_IDENTITY=}"
                printf '%s' "$signing_identity_used" > "$HOME/.translator-test-signing-identity"
            fi
        done
        [[ "${INSTALL_TEST_FAIL_BUILD:-0}" != 1 ]] || exit 1
        mkdir -p build/Build/Products/Release/Translator.app/Contents/MacOS
        printf 'new binary' > build/Build/Products/Release/Translator.app/Contents/MacOS/Translator
        if [[ "$signing_identity_used" == "-" ]]; then
            printf '# designated => cdhash H"%s"\n' "${INSTALL_TEST_ADHOC_HASH:-1111111111111111111111111111111111111111}" \
                > build/Build/Products/Release/Translator.app/Contents/MacOS/signing-requirement
        else
            printf 'designated => identifier "co.yuritoledo.translator" and certificate leaf[subject.CN] = "%s"\n' "$signing_identity_used" \
                > build/Build/Products/Release/Translator.app/Contents/MacOS/signing-requirement
        fi
        if [[ "${INSTALL_TEST_START_DURING_BUILD:-0}" == 1 ]]; then
            touch "$HOME/.translator-test-running"
        fi
        ;;
    mv)
        if [[ "${INSTALL_TEST_FAIL_MOVE:-0}" == 1 && "$1" == */.translator-install*/Translator.app ]]; then
            exit 1
        fi
        exec /bin/mv "$@"
        ;;
esac
MOCK
chmod +x "$tmp/mock"
for command in xcodegen xcrun xcodebuild codesign open pgrep pkill mv openssl security tccutil; do
    ln -s "$tmp/mock" "$tmp/bin/$command"
done
export HOME="$tmp/home" PATH="$tmp/bin:$PATH"
app="$HOME/Applications/Translator.app"

assert_signing_identity() {
    local expected_identity="$1"
    local actual_identity
    actual_identity="$(cat "$HOME/.translator-test-signing-identity")"
    if [[ "$actual_identity" != "$expected_identity" ]]; then
        echo "FAIL: expected signing identity '$expected_identity', got: '$actual_identity'" >&2
        exit 1
    fi
}

assert_tcc_reset() {
    if ! grep -Fxq "tccutil reset Accessibility co.yuritoledo.translator" "$HOME/.translator-test-tccutil-log" 2>/dev/null; then
        echo "FAIL: $1" >&2
        exit 1
    fi
}

printf 'old debug library' > "$app/Contents/MacOS/Translator.debug.dylib"
printf '# designated => cdhash H"0000000000000000000000000000000000000000"\n' > "$app/Contents/MacOS/signing-requirement"

bash "$tmp/project/scripts/install.sh" >/dev/null
[[ -f "$app/Contents/MacOS/Translator" ]]
if [[ -e "$app/Contents/MacOS/Translator.debug.dylib" ]]; then
    echo 'FAIL: updating retains a stale Debug library' >&2
    exit 1
fi
echo 'PASS: update replaces the whole app bundle'

assert_signing_identity "Translator Local Development"
[[ -f "$HOME/.translator-test-cert-trusted" ]]
echo 'PASS: first install creates and trusts local signing certificate'

assert_tcc_reset 'changing designated requirement from ad-hoc to certificate must reset stale Accessibility entry'
echo 'PASS: migrating from ad-hoc to certificate resets stale Accessibility entry'

rm -f "$HOME/.translator-test-openssl-log" "$HOME/.translator-test-tccutil-log"
bash "$tmp/project/scripts/install.sh" >/dev/null
if [[ -e "$HOME/.translator-test-openssl-log" ]]; then
    echo 'FAIL: subsequent install must reuse existing certificate without calling openssl' >&2
    exit 1
fi
if [[ -e "$HOME/.translator-test-tccutil-log" ]]; then
    echo 'FAIL: matching certificate designated requirement must not reset Accessibility permissions' >&2
    exit 1
fi
echo 'PASS: subsequent install reuses certificate and keeps Accessibility permissions'

rm -f "$HOME/.translator-test-cert-trusted" "$HOME/.translator-test-cert-imported" "$HOME/.translator-test-cert-deleted"
INSTALL_TEST_FAIL_TRUST=1 INSTALL_TEST_ADHOC_HASH=1111111111111111111111111111111111111111 bash "$tmp/project/scripts/install.sh" >/dev/null 2>&1
assert_signing_identity "-"
if [[ ! -f "$HOME/.translator-test-cert-deleted" || -f "$HOME/.translator-test-cert-imported" ]]; then
    echo 'FAIL: trust failure must clean up untrusted certificate from Keychain' >&2
    exit 1
fi
echo 'PASS: canceled trust prompt cleans up untrusted certificate and falls back to ad-hoc signing'

rm -f "$HOME/.translator-test-tccutil-log"
INSTALL_TEST_FAIL_TRUST=1 INSTALL_TEST_ADHOC_HASH=2222222222222222222222222222222222222222 bash "$tmp/project/scripts/install.sh" >/dev/null 2>&1
assert_tcc_reset 'updating between ad-hoc builds with different cdhash must reset stale Accessibility entry'
echo 'PASS: ad-hoc rebuild with changed cdhash resets stale Accessibility entry'

TRANSLATOR_SIGNING_IDENTITY="Custom Developer Identity" bash "$tmp/project/scripts/install.sh" >/dev/null
assert_signing_identity "Custom Developer Identity"
echo 'PASS: explicit TRANSLATOR_SIGNING_IDENTITY override is honored'

printf 'existing install' > "$app/keep-me"
if INSTALL_TEST_FAIL_BUILD=1 bash "$tmp/project/scripts/install.sh" >/dev/null 2>&1; then
    echo 'FAIL: build failure must stop installation' >&2
    exit 1
fi
[[ -f "$app/keep-me" ]]
echo 'PASS: build failure keeps the existing app'

if INSTALL_TEST_FAIL_MOVE=1 bash "$tmp/project/scripts/install.sh" >/dev/null 2>&1; then
    echo 'FAIL: install failure must return an error' >&2
    exit 1
fi
[[ -f "$app/keep-me" ]]
echo 'PASS: failed installation restores the existing app'

rm -f "$HOME/.translator-test-pkill-log" "$HOME/.translator-test-open-log"
touch "$HOME/.translator-test-running"
bash "$tmp/project/scripts/install.sh" >/dev/null
if [[ -e "$HOME/.translator-test-running" ]] \
    || ! grep -Fxq "pkill -x Translator" "$HOME/.translator-test-pkill-log" 2>/dev/null \
    || ! grep -Fxq "open $app" "$HOME/.translator-test-open-log" 2>/dev/null; then
    echo 'FAIL: running app must be stopped before installation and reopened afterward' >&2
    exit 1
fi
echo 'PASS: running app is stopped, updated, and reopened'

rm -f "$HOME/.translator-test-pkill-log" "$HOME/.translator-test-open-log"
INSTALL_TEST_START_DURING_BUILD=1 bash "$tmp/project/scripts/install.sh" >/dev/null
if [[ -e "$HOME/.translator-test-running" ]] \
    || ! grep -Fxq "pkill -x Translator" "$HOME/.translator-test-pkill-log" 2>/dev/null \
    || ! grep -Fxq "open $app" "$HOME/.translator-test-open-log" 2>/dev/null; then
    echo 'FAIL: app started during build must be stopped before replacing bundle and reopened afterward' >&2
    exit 1
fi
echo 'PASS: app started during build is stopped, updated, and reopened'

mkdir "$HOME/Applications/.translator-install"
printf 'another installer' > "$HOME/Applications/.translator-install/keep-lock"
if bash "$tmp/project/scripts/install.sh" >/dev/null 2>&1; then
    echo 'FAIL: overlapping installation must be blocked' >&2
    exit 1
fi
[[ -f "$app/keep-me" && -f "$HOME/Applications/.translator-install/keep-lock" ]]
echo 'PASS: an existing install lock is respected'
