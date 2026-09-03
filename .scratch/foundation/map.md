# Foundation implementation map

## Notes

The approved Foundation spec was decomposed into seven dependency-aware tracer tickets. The implementation uses one primary pure-logic seam in `SleepMateCore` and one documented real-device seam for iOS audio/system behavior.

## Decisions-so-far

- Canonical product document is `PRD.md`; the previous project PRD is archived and is not normative.
- Domain core is platform-independent Swift Package Manager code.
- Time-based behavior is driven by an injected `SleepMateClock`; no real sleeps in tests.
- iOS shell and audio integration remain outside the domain core and require simulator/build plus real-device checks.

## Tickets

| Ticket | Status | Depends on | Result |
|---|---|---|---|
| 01 | resolved | — | CONTEXT.md and ADR-0001 |
| 02 | resolved | — | Swift Package and smoke test |
| 03 | resolved | 02 | SwiftUI iOS shell and localized empty state |
| 04 | resolved | 02 | Domain types, clock, product durations |
| 05 | resolved | 04 | Sleep session state machine and tests |
| 06 | resolved | 04 | Friend creation pipeline and tests |
| 07 | resolved | — | Real-device test matrix |
