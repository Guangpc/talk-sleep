# 05: Authorized MiniMax voice clone and AI-profile binding

**What to build:** Turn an already consented source recording into a MiniMax `voice_id`, bind it to a pending AI friend profile, and let the user preview and confirm the resulting voice without pretending it is the real friend.

**Blocked by:** 02: Secure MiniMax Speech gateway; 04: Authorized friend-voice source intake and consent.

**Status:** partially implemented — authorized upload/clone and in-memory profile binding are green; preview/deletion/persistence gates remain open

- [x] The gateway uploads the authorized source, calls the verified clone operation, and surfaces stable provider success/failure; optional prompt-audio flow remains open.
- [x] A successful clone returns a voice ID that is bound to the in-memory AI friend only after both requests succeed; failed/cancelled clone cannot become ready. Persistent provenance/revocation fields remain open.
- [ ] The setup UI binds the successful clone directly for the MVP; preview-confirm before activation remains open.
- [x] The UI keeps an explicit AI label and never claims the system is the real friend.
- [ ] The deletion behavior for local source, local cache, voice configuration, and MiniMax-side asset is visible and honest; unsupported provider deletion remains a documented blocker.

## Current implementation evidence

- The Swift/Core seam is covered by deterministic validator/client tests, production `createServerFromEnv` composition tests, and the App generic build.
- Remaining unchecked items require provider-side lifecycle policy, profile persistence/provenance, preview confirmation, cache deletion, and connected-iPhone verification.
