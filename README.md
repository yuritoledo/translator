# Translator

- A small macOS menu bar app for selected text and quick typed translations.
- Built with Swift, SwiftUI, and Apple's on-device Translation framework.
- No API key, subscription, backend, or paid Apple developer account is needed to build it locally.
- An independent project. It is not affiliated with In Translator or Apple.

## Features

- **⌥T:** translate selected text without leaving the current app.
- **Replace ⌥R:** replace the original Selection after reviewing the translation. Works while the selected-text popup is focused.
- Replacement uses Accessibility selected-text support. If the app does not support it or the Selection changes, use Copy instead.
- **⌥⇧T:** open or close the typed popup under the menu bar icon.
- **⌘Return:** translate typed or pasted text.
- English translates to Portuguese. Other detected languages translate to English.
- Copy the result, speak it aloud, or swap the translation direction.
- Choose the selection popup position: **At pointer** or **Below selected text**.
- Reopen the last **five successful translations** from the typed popup, newest first.
- Click a history entry to see its saved result without translating again.
- Clear history from the same popup.
- Optional launch at login.

## Requirements

- **macOS 26 or later.**
- **Full Xcode 26 or later**, including its command-line tools. Command Line Tools alone are not enough.
- [Homebrew](https://brew.sh/) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- Internet access to download the tools and any missing Apple language packs.
- The current build is tested on macOS 27 with Xcode 27.2. Older supported versions need further testing.

## Install from source

- Install Xcode from the Mac App Store or Apple Developer Downloads.
- Open Xcode once. Accept its license and finish component installation.
- Select full Xcode if the command-line tools point elsewhere:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

- Install XcodeGen and clone this repository:

```sh
brew install xcodegen
git clone https://github.com/yuritoledo/translator.git
cd translator
```

- Quit any running copy of Translator from its gear menu.
- Build, install, and open the app:

```sh
bash scripts/install.sh
```

- The script builds a Release app and checks its signature.
- It installs to **`~/Applications/Translator.app`**. It does not require `sudo`.
- Look for the translate symbol in the **menu bar**, not the Dock.
- The default is ad-hoc signing. No certificate from the maintainer is required.
- An existing local signing certificate is optional. See [local signing](docs/local-signing.md).
- There is no notarized download or one-click installer yet. Build locally rather than copying another person's development app.

## First use

- Click the menu bar icon or press **⌥⇧T**.
- Type a sentence. Press **⌘Return** or click **Translate**.
- Approve Apple's language-pack download prompt if it appears.
- To translate a selection, highlight a sentence in an app that supports **⌘C**.
- Press **⌥T**, then release the keys.
- If macOS requests Accessibility access, enable **Translator** in **System Settings → Privacy & Security → Accessibility**.
- Grant access to the installed copy in `~/Applications`, not a separate build copy.
- Retry the shortcut. Restart Translator if macOS does not apply the permission immediately.
- Typed translation does not require Accessibility access.
- Escape or a click outside closes the popup.
- Use the gear menu to set popup position, enable launch at login, or quit.
- If login launch requires approval, check **System Settings → General → Login Items**.

## Update or uninstall

- Quit Translator before updating.
- Pull the latest code and rerun the installer:

```sh
git pull --ff-only
bash scripts/install.sh
```

- If you use a local signing certificate, pass the same identity on every installation. See [local signing](docs/local-signing.md).
- Keep the installed app at the same path. Ad-hoc rebuilds can require a new Accessibility approval.
- The installer blocks overlapping installations. An interrupted installation can leave `~/Applications/.translator-install`.
- Before retrying an interrupted installation, confirm that no installer is running. If `previous.app` exists in that directory, preserve or restore it before removing the directory.
- To uninstall, disable launch at login, clear history, quit, and delete `~/Applications/Translator.app`.
- Deleting the app alone does not delete its preferences or saved history.
- To remove all app preferences and saved history after quitting:

```sh
defaults delete co.yuritoledo.translator
```

## Privacy

- Apple performs translation on the Mac after the required language packs are installed.
- Translator has no translation server, account system, analytics, or cloud history sync.
- The app stores the last five successful translations in **unencrypted local UserDefaults**.
- Each saved entry includes the original text, translated text, and language pair.
- Both selected-text and typed translations enter this history. Failed translations do not.
- Repeating the same text with the same language pair moves its result to the top.
- Click **Clear history** to remove all stored entries.
- Do not translate secrets if you do not want them saved locally. There is no private mode yet.
- Selection capture sends **⌘C**, reads the clipboard, then attempts to restore its previous contents.
- Clipboard restoration is best-effort. Clipboard managers can still observe the temporary copy.
- Translator runs outside the App Sandbox to support cross-app capture.

## Known limitations

- Language direction is fixed. There is no language picker yet.
- Short text can be hard to identify. Try a full sentence.
- Apple does not support every language pair. Unsupported pairs or declined downloads show an error.
- Password fields and apps that do not support copying cannot provide selected text.
- Selection capture fails in **Pi running inside Orca**, including with Shift-drag. The cause is not confirmed.
- Selection capture works in Slack, Apple Terminal, and a normal Orca shell in local checks. These checks do not guarantee support in every app.
- Use **⌥⇧T** and paste text when selection capture does not work.
- Slow copy operations and concurrent clipboard changes can interfere. Avoid copying other items during capture.
- **Below selected text** uses Accessibility selection bounds when available. Otherwise it falls back to the pointer.
- **⌥T** and **⌥⇧T** are fixed shortcuts. They take precedence over those character shortcuts while Translator runs.
- Quit other apps that reserve the same shortcuts. The gear menu reports registration failures.
- The app has no Safari extension, double-copy trigger, cloud engine, or notarized release.

## Develop and test

- `project.yml` is the source of truth. XcodeGen generates the Xcode project and app metadata.
- Generated files, build output, local keys, and certificates are not committed.
- Build and open a Debug app:

```sh
make build
open build/Build/Products/Debug/Translator.app
```

- Or generate the project and open it in Xcode:

```sh
make project
open Translator.xcodeproj
```

- Do not run the Debug and installed copies at the same time. They use the same bundle ID and shortcuts.
- Run unit tests and lint checks before pushing:

```sh
make test
make lint
```

- Tests cover history limits, persistence, deduplication, language pairs, clearing, invalid saved data, popup position, shortcut definitions, and language detection.
- Installer regression checks cover whole-bundle replacement, build failure, replacement rollback, running-app checks before and after building, and an existing install lock.
- A native popup test checks opening, editor focus, and closing. Run tests in a logged-in desktop session.
- Tests do not download language packs or verify Apple's translation quality.
- Live history-row interaction, below-selection placement, clipboard restoration, speech, login launch, and permission retention still need broader manual testing.
- Lint uses Xcode's `swift-format` with `.swift-format`, plus Bash syntax checks for the installer.

## Project notes

- Bundle identifier: `co.yuritoledo.translator`.
- [Domain glossary](GLOSSARY.md).
- [On-device translation and capture decision](docs/adr/0001-on-device-engine-outside-app-store.md).
- [Local signing and Accessibility permissions](docs/local-signing.md).
- [MIT license](LICENSE).
