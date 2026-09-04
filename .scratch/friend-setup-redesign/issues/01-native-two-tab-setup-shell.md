# 01: Build the native two-tab setup shell

**What to build:** Replace the oversized setup form with an iPhone-native bottom navigation experience. “文字与文件” owns text-based friend creation, while “朋友语音” owns voice attachment to an existing friend. Each destination remains readable and operable on an iPhone 12 without controls being obscured by the keyboard, safe areas, navigation bars, or tab bar.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [x] A native bottom tab bar switches between clearly labelled “文字与文件” and “朋友语音” destinations.
- [x] Text/file controls appear only on the text destination; voice intake controls appear only on the voice destination.
- [x] The voice destination has no action that creates a new AI friend.
- [ ] Both destinations fit iPhone 12 portrait width, respect safe areas and Dynamic Type, and remain scrollable when content exceeds the viewport.
- [ ] Focusing an input opens the keyboard; tapping outside inputs, using the keyboard Done action, or scrolling dismisses it without blocking navigation.
- [ ] Chinese and English user-facing labels are localized, and UI smoke coverage can find both tabs and primary actions.
