# Translator

A macOS menu bar app that translates text the user selects in any other app.

## Language

**Selection**:
The text the user has highlighted in another app when they ask for a translation.
_Avoid_: Input, clipboard text, query

**Trigger**:
The key combination (⌥T) that starts a translation of the current Selection.
_Avoid_: Shortcut, hotkey

**Popup**:
The small floating panel near the Selection that shows the translation.
_Avoid_: Window, bubble, tooltip

**Engine**:
The service that turns source text into translated text.
_Avoid_: Provider, backend, API

**Source Language**:
The language of the Selection. The app detects it automatically.
_Avoid_: From language, input language

**Target Language**:
The language of the translation. The default is English; English selections translate to Portuguese. The user can swap it with the Source Language.
_Avoid_: To language, output language

**Speech**:
Spoken audio of a Selection or its translation.
_Avoid_: TTS, voice, read-aloud

**Origin Focus**:
The external application, window, and UI element that held focus before Translator was opened.
_Avoid_: Previous window, source window, active app
