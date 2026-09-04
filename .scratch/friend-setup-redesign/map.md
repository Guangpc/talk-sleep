# AI friend setup redesign map

## Notes

Tickets are ordered as tracer-bullet vertical slices. Work the frontier: ticket 01 can start immediately; each later ticket starts only after its listed blockers are complete.

## Tickets

| Ticket | Status | Depends on | Demoable result |
|---|---|---|---|
| 01 | in progress | None | Native two-tab shell fits iPhone 12 and separates text from voice setup |
| 02 | ready-for-agent | 01 | Long chat text can be pasted or imported from a text file on-device |
| 03 | ready-for-agent | 02 | Real LLM produces a reviewed editable friend profile, including address and work life, then creates an AI friend |
| 04 | in progress | 03 | Created friends, reviewed profiles, and voice references survive termination and relaunch |
| 05 | ready-for-agent | 01, 04 | Voice tab selects a persisted friend and opens the real iOS audio-file picker |
| 06 | ready-for-agent | 05 | Authorized audio is cloned and bound to the selected existing friend |
| 07 | ready-for-agent | 01, 02, 03, 04, 05, 06 | Full iPhone 12 acceptance path, including relaunch persistence, passes and limitations are recorded |
