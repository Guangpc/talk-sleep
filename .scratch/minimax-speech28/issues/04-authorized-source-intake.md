# 04: Authorized friend-voice source intake and consent

**What to build:** Give the user a consent-gated way to select a voice recording, validate it against MiniMax limits, disclose cloud processing, and upload it only after explicit confirmation.

**Blocked by:** 01: MiniMax Speech 2.8 provider contract and compliance gate; 02: Secure MiniMax Speech gateway.

**Status:** partially implemented — consent-gated App intake and Core validation are green; real-device and provider-side lifecycle gates remain open

- [x] The user sees an AI voice-cloning explanation, authorization confirmation, intended use, cloud-processing disclosure, retention/deletion statement, and can cancel before upload in the setup UI.
- [x] The App/Core seam accepts only `mp3/m4a/wav`, 10 seconds–5 minutes, and ≤20 MB for clone audio; prompt-audio policy remains server-only for now.
- [x] The App rejects unsupported, unreadable, empty, over-limit, or invalid-duration files locally with actionable errors and never uploads them.
- [x] The audio picker and upload are gated by explicit consent; the gateway receives only the selected clone material and bounded metadata.
- [x] Local preparation and upload/clone progress, failure, and retry are visible; Task cancellation is supported and raw audio is not placed in diagnostics or fixtures.

## Current implementation evidence

- The Swift/Core seam is covered by deterministic validator/client tests and the App generic build.
- Remaining unchecked items require provider-side lifecycle policy, profile persistence/provenance, preview confirmation, cache deletion, and connected-iPhone verification.
