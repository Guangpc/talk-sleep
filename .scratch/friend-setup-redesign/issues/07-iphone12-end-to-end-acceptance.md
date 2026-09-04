# 07: Verify the complete setup flow on iPhone 12

**What to build:** Exercise the redesigned flow on a connected iPhone 12 from chat-text intake through real-LLM profile review, AI-friend creation, existing-friend voice attachment, and a voice conversation. Record objective pass/fail evidence and any system-UI limitations without treating build/install success as interaction success.

**Blocked by:** 01: Build the native two-tab setup shell; 02: Paste and import chat text on the text destination; 03: Create an AI friend from a real-LLM editable life profile; 04: Persist AI friends across app launches; 05: Select an existing friend and import an audio file; 06: Bind an authorized cloned voice to the selected friend.

**Status:** ready-for-agent

- [ ] The latest signed build installs and launches on the connected iPhone 12.
- [ ] Both bottom destinations, navigation bars, scroll regions, editors, buttons, errors, and loading states fit the iPhone 12 portrait viewport and safe areas.
- [ ] The user can paste a multiline chat record and separately import a supported text file; keyboard focus and outside-tap dismissal work throughout.
- [ ] The real LLM gateway returns an editable profile containing evidence-supported personality, address/location, workplace, work environment, work content, habits, memories, relationships, preferences, and topics.
- [ ] The user edits the profile and creates an AI friend without a custom voice; terminating and relaunching restores the same friend, which is immediately available after switching to the voice destination.
- [ ] The real Files picker selects a supported voice sample, explicit authorization gates upload, and the cloned voice binds to the intended friend.
- [ ] A live turn verifies trailing silence ends listening, the LLM replies with reviewed friend context, and MiniMax TTS uses the selected friend’s bound voice.
- [ ] Automated Core, gateway, build-for-testing, and device UI suites are green, or every external-system limitation is documented with exact evidence and a manual verification step.
- [ ] Provider keys, gateway tokens, raw chat logs, and raw audio are absent from version control and test output.
