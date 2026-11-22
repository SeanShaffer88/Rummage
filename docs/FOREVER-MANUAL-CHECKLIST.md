# Forever Followup Manual Checklist

User requested offline tests only for 1.12.1. Every live result below is **Unperformed**; the offline suites do not qualify server acknowledgement, taint, secure templates, accessibility or real performance. Previous 1.12.0 observations remain historical evidence and were not repeated for this followup.

Before a future authorized run, record the exact values of `GetBuildInfo()` (version, build, date, Interface), addon TOC Version/X-Build, `/rum apicheck export` output, enabled integrations, UI scale, font size, bag/bank layout and character/session context. Current declared target: Forever 1.60.1.71037, Interface 16001. Back up owned SavedVariables and restore any temporary test settings or inventory afterward.

| Scenario | Required Observations | Live Result |
|---|---|---|
| Buyback synchronous/delayed/out-of-order | Exact link/count/price; signature multiplicity decreases by one, quantity returns and money decreases by that price before Observed/log removal | Unperformed |
| Buyback unknown/wrong/no acknowledgement | Unknown price/count, insufficient funds, unrelated list shrink or wrong quantity/money never authorize or confirm; timeout releases ticker and preserves ledger | Unperformed |
| History Buy Back | Paging/new records/reload/reorder cannot change captured sale; Pending blocks repeats; ambiguous old records disabled; fonts 6/12/24 keep action separate | Unperformed |
| Merchant lifecycle and reentrancy | Closing/reopening, combat/cursor interruption or cancellation cannot resume old queue; next independent operation can start | Unperformed |
| Bank empty/merge placement | Exact source and destination full link/count, including delayed/locked response and compatible partial-stack merge; no success before evidence | Unperformed |
| Bank interruption | Close/reopen while queued or awaiting acknowledgement, combat before/after request, changed/locked source and preoccupied cursor stop safely | Unperformed |
| Mail placement | Send/Inbox transition, close/reopen, full slots, wrong/missing link/count API, delayed/no ack, bound/changed source, combat/cursor interruption; Observed means placement only | Unperformed |
| Trade placement | First six slots only, no seventh will-not-trade slot, exact target link/count/source removal; full/changed/closed targets and delayed/no ack remain safe | Unperformed |
| Recovery | Operation/ticker flags released after every stop/timeout; only a matching addon-owned cursor may be returned; no stale callbacks affect later work | Unperformed |

Offline evidence: 122 native Lua 5.1 cases, including stateful source/cursor/destination and independent merchant/bag/money channels; 19 fake-adapter publication cases. Separate final delivery evidence records actual gate exits, package hashes, mutation results and independent review. No tag/release is created to test the publisher.
