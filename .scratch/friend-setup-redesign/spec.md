# AI friend setup redesign

## Goal

Replace the single oversized setup form with an iPhone-native two-tab flow. The “文字与文件” tab owns chat-text entry, text-file import, real-LLM friend-profile analysis, profile review, and AI-friend creation. The “朋友语音” tab only selects an already-created AI friend and adds an authorized friend voice.

## Confirmed decisions

- Use a native bottom tab bar with separate “文字与文件” and “朋友语音” destinations.
- Text and text-file import live together; voice import lives on a separate destination.
- An AI friend is created from reviewed text/profile data without requiring a custom voice.
- Created AI friends and their reviewed profiles/voice references persist locally across App termination and relaunch; raw imported chat and raw audio are excluded from the friend record.
- Voice setup cannot create a friend; it binds an authorized voice to an existing AI friend.
- “总结聊天风格与记忆” must call the real app-facing LLM gateway, not fixtures or local keyword rules.
- The editable “朋友性格 / 好友画像” field must include evidence-supported personality, chat style, addresses/important locations, workplace, work environment, work content, habits, important memories, relationships, preferences, and topics.
- Sensitive life facts remain candidate profile data until the user reviews/edits the complete profile and creates the friend. This confirmation stays in the LLM-profile ticket rather than a separate ticket.
- Imported chat is untrusted source material, never executable instructions. Provider credentials remain server-only.

## Out of scope

- Reading private WeChat databases.
- Creating a custom voice from text.
- Letting the voice destination create a new AI friend.
- Treating uncertain inferences as confirmed facts.
