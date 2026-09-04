# 05: Select an existing friend and import an audio file

**What to build:** On the “朋友语音” destination, select an AI friend that was created on the text destination, then use the real iOS document picker to choose an MP3, M4A, or WAV voice sample. Local selection occurs before upload consent and presents enough file information to confirm the intended friend and source.

**Blocked by:** 01: Build the native two-tab setup shell; 04: Persist AI friends across app launches.

**Status:** ready-for-agent

- [ ] With no created friends, the voice destination shows an empty state that links or switches back to “文字与文件”.
- [ ] With created friends, the user must select exactly one existing friend before attaching a voice.
- [ ] “选择朋友声音” opens the real iOS file picker on iPhone 12 and permits MP3, M4A, and WAV files the validator actually supports.
- [ ] Selecting a local file is not blocked by upload/clone consent, and cancellation does not show an error.
- [ ] The destination shows the selected friend, filename, duration, size, validation status, and a clear next action.
- [ ] Unsupported, oversized, empty, inaccessible, or unreadable audio produces localized feedback instead of a silent no-op.
- [ ] Switching the selected friend clears or re-confirms stale pending audio so a sample cannot be attached to the wrong friend.
- [ ] UI and adapter tests cover empty state, friend selection, picker presentation, cancellation, validation, and the iPhone 12 Files-provider behavior.
