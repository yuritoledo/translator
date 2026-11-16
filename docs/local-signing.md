# Local code signing

- `scripts/install.sh` automatically creates and reuses a local **`Translator Local Development`** code-signing certificate in your login Keychain. No paid Apple developer account is needed.
- On your first install, macOS prompts once to trust `Translator Local Development` for code signing. Subsequent updates reuse the same certificate automatically without prompting.
- If certificate setup or trust is canceled, the installer removes any untrusted certificate from your Keychain and falls back to **ad-hoc signing** (`-`).
- A self-signed certificate is not an Apple Developer ID. It does not provide notarization or distribution trust on a friend's Mac.
- Do not share your private key or import another person's key to build this project.

## Use an existing local certificate

- By default, `scripts/install.sh` uses `Translator Local Development`.
- List code-signing identities in your own Keychain:

```sh
security find-identity -v -p codesigning
```

- To override the default with another valid identity in your Keychain, pass `TRANSLATOR_SIGNING_IDENTITY`:

```sh
TRANSLATOR_SIGNING_IDENTITY="Your Local Code Signing Identity" bash scripts/install.sh
```

- Replace the example with the name reported by `security`.
- The installer automatically stops any running copy of Translator before installing and reopens the updated app afterward.
- Keep the same identity on future installations. Do not create a new certificate for every build.
- To use the same identity for development or tests:

```sh
xcodegen generate
xcodebuild -scheme Translator -destination 'platform=macOS' -derivedDataPath build \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Translator Local Development" test
```

## How certificate setup works

- When `Translator Local Development` is not yet present in `security find-identity -v -p codesigning`, `scripts/install.sh` generates a 10-year RSA-2048 code-signing certificate using [`scripts/local-signing.cnf`](../scripts/local-signing.cnf).
- It imports the identity into your default login Keychain with `/usr/bin/codesign` access and marks it trusted for code signing only (`security add-trusted-cert -r trustRoot -p codeSign`).
- [`scripts/local-signing.cnf`](../scripts/local-signing.cnf) contains only the certificate profile (`CN = Translator Local Development`). It contains no certificate, private key, or password.

## Accessibility approval

- Keep the installed app at `~/Applications/Translator.app`.
- Grant permission to that copy, not a separate development build.
- When `scripts/install.sh` replaces an existing `~/Applications/Translator.app`, it compares the designated code requirement (`codesign -d -r-`) of the previous bundle against the new bundle.
- If the designated requirement changed (for example, migrating from an older ad-hoc build to `Translator Local Development`, or between two ad-hoc builds), the installer automatically runs `tccutil reset Accessibility co.yuritoledo.translator` to clear stale entries so you do not have to manually remove and re-add Translator in System Settings.
- When updating between builds signed with the same certificate, the designated requirement is unchanged and Accessibility permission is preserved automatically.

## Inspect a build

```sh
codesign --verify --deep --strict ~/Applications/Translator.app
codesign -d -r- ~/Applications/Translator.app
```

- A certificate-signed build has a designated requirement that includes the bundle identifier and certificate identity.
- An ad-hoc build has a code-hash-based requirement that can change after rebuilding.
- Never commit signing keys, certificates, PKCS#12 files, or Keychain passwords.
