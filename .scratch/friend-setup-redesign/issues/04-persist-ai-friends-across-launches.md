# 04: Persist AI friends across app launches

**What to build:** Save every user-confirmed AI friend locally so the friend collection, reviewed profile, and current voice reference survive App termination and relaunch. Restored friends appear on the text destination and are immediately selectable on the voice destination without re-importing chat records or rerunning analysis.

**Blocked by:** 03: Create an AI friend from a real-LLM editable life profile.

**Status:** ready-for-agent

**Implementation seam:** `AIFriendRepository` is the public persistence boundary; the App may use a file-backed implementation, but views and voice/session code must not depend on its storage format.

- [x] A public friend-repository seam saves, loads, updates, and deletes complete AI-friend records by stable UUID without exposing storage details to the UI.
- [ ] The persisted record includes name, reviewed editable profile/context, personality/style summary, confirmed life memories (including address/location and work life when retained), topic preferences, avatar reference, and current voice reference.
- [ ] Raw imported chat text and raw voice audio are not persisted as part of the friend record unless a separate retention feature explicitly authorizes them.
- [ ] Saving a newly created friend and relaunching the App restores the same friend once, with the same identity and reviewed profile.
- [ ] Updating a friend’s voice binding replaces only that friend’s voice reference and survives the next relaunch.
- [ ] Corrupt, missing, unsupported-version, or partially migrated local data does not crash launch; the UI shows a recoverable state and preserves valid records when possible.
- [x] Storage writes are atomic, use iOS data-protection appropriate to sensitive profile data, and never log profile contents or credentials.
- [x] Tests cover save/reload, voice-reference update, and duplicate prevention through the repository interface; remaining corruption/migration and device relaunch coverage are acceptance work.
- [ ] An iPhone 12 relaunch test verifies a created friend remains visible and selectable after terminating and reopening the App.
