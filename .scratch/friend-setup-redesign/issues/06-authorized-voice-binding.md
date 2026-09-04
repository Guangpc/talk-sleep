# 06: Bind an authorized cloned voice to the selected friend

**What to build:** After selecting an existing AI friend and a valid local voice sample, collect explicit authorization, upload and clone through the server gateway, and bind the returned voice reference only to that selected friend. The voice destination reports progress, success, retryable failure, and the friend’s current voice status.

**Blocked by:** 05: Select an existing friend and import an audio file.

**Status:** in progress

- [x] Upload and clone controls stay disabled until an existing friend, valid audio, and explicit authorization are all present.
- [x] Provider audio never leaves the device before authorization, and provider credentials remain server-only.
- [ ] Uploading, cloning, success, failure, cancellation, and retry states identify the selected friend and remain usable after tab switches.
- [x] A successful clone binds the returned voice reference to exactly the selected friend and does not modify other friends.
- [x] Changing friends during in-flight work cannot apply a stale result to the new selection.
- [x] The text destination remains the only place to create a friend; the voice destination only adds or replaces voice configuration.
- [ ] Tests cover consent gating, friend identity propagation, stale-result rejection, provider errors, successful binding, and subsequent TTS use of the bound voice.
