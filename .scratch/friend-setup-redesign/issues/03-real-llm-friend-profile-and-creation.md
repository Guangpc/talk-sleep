# 03: Create an AI friend from a real-LLM editable life profile

**What to build:** On the “文字与文件” destination, “总结聊天风格与记忆” sends the named friend’s imported or pasted chat record through the real app-facing LLM gateway. It returns an evidence-supported, structured friend profile and writes the human-readable result into the editable “朋友性格 / 好友画像” field above the source-material controls. After review and edits, the user creates an AI friend from that confirmed profile without needing a custom voice.

**Blocked by:** 02: Paste and import chat text on the text destination.

**Status:** ready-for-agent

- [ ] Pressing “总结聊天风格与记忆” invokes the production gateway-backed LLM analysis seam; fixtures, local keyword matching, and fabricated summaries are not used in the App path.
- [ ] The analysis uses the highest configured profiling reasoning tier and focuses on the named friend’s messages without blending in the user’s style.
- [ ] The structured result covers personality, emotional and communication style, chat style, catchphrases, habits, important memories, relationships, preferences, topics, addresses/important locations, workplace, work environment, job/industry, and work content or daily responsibilities when supported by source evidence.
- [ ] Explicit facts, uncertain possibilities, and items needing user confirmation remain distinguishable; the LLM does not invent missing addresses, employers, occupations, or duties.
- [ ] The complete result appears in the editable “朋友性格 / 好友画像” field above the import/editor area, including address, workplace, work environment, and work content entries.
- [ ] Editing or deleting any candidate fact changes the exact profile context used to create the friend; deleted facts cannot leak from the original analysis into later conversation context.
- [ ] Changing the friend name or source chat invalidates stale analysis, and an in-flight result for old input cannot overwrite the current profile.
- [ ] Loading, completion, failure, cancellation, malformed JSON, empty output, incomplete stream, and retry states are localized and do not log raw chat records or provider credentials.
- [ ] Imported chat is marked as untrusted data in the analysis prompt and cannot override system/developer instructions.
- [ ] Creating the AI friend requires a reviewed nonempty profile, stores the created friend in the shared friend collection, and makes it immediately selectable from the voice destination without requiring voice setup.
- [ ] Contract, pipeline, UI, and gateway tests prove the real request parameters and all required life-profile fields; the end-to-end call is exercised on iPhone 12 with a configured gateway.
