# 02: Paste and import chat text on the text destination

**What to build:** Let the user enter a friend name and paste a long chat record or import a supported text file on the “文字与文件” destination. Imported content appears in the same editable text area and remains available for profile analysis without truncation, silent failure, or keyboard obstruction.

**Blocked by:** 01: Build the native two-tab setup shell.

**Status:** ready-for-agent

- [ ] The chat editor accepts normal iOS paste actions and long multiline chat records, preserving line breaks and allowing continued edits.
- [ ] Tapping the chat editor opens the keyboard; tapping outside it dismisses the keyboard without preventing text selection, copy, or paste.
- [ ] The text-file button opens the real iOS document picker and accepts only documented text types that the app can decode.
- [ ] A selected text file is read through its security-scoped URL and its decoded content populates the editable chat field.
- [ ] Cancellation is silent, while empty, unsupported, unreadable, or invalidly encoded files show a localized actionable error.
- [ ] Tests cover paste-ready editor behavior, imported text propagation, cancellation, and decoding/error boundaries; the path is exercised on iPhone 12.
