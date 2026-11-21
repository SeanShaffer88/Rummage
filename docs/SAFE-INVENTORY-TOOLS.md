# Safe Inventory Tools: Interfaces And Verification

These modules use the existing Lua 5.1/WoW runtime with no additional addon dependencies. Copyright 2026 Malikor, GPL-3.0-or-later, as in the root LICENSE.

- `Junk:PreviewRule(query)` returns a preview or `nil,error`; it is read-only with respect to inventory, rules, favorites and reserves. `EnableRule(preview)` is a separate single-use action bound to that exact query. The preview shares the live bag planner, eligibility, reserve budgets and buyback batch cap with sales.
- `Junk:SetKeep(itemID,quantity)` validates positive finite integral IDs up to 2147483647 and whole quantities 0..1000000; zero removes. Reserves are account-wide, current carried bags only. A partial sale owns a bounded state machine and returns only a matching addon-owned cursor item on cancellation. No background timer remains after termination.
- `ActionHistory:Record(action,status,details)`, `Page(filter,page,size)`, `Clear()` form a small bounded record model. Records are sanitized, max 100, with session-local unique IDs. History never drives actions; it is excluded from configuration export and profile snapshots. Record module import does not create UI or start work.
- `Extras:SetContextMapping(context,profileOrNil)` validates nine canonical contexts and saved profile identity; `ApplyContext()` owns precedence and combat deferral. Missing imported profile references are inert and visible.
- `Tools:Show(tab)` lazily creates one native themed panel. Options and slash commands compose the domain APIs. Geometry uses the canonical anchor validator, clamping and font-derived paged layout.

Example consumption inside the addon: `local preview, err = Rummage.Junk:PreviewRule("q:poor"); if preview then Rummage.Tools:Show("preview") end`. Enabling requires a separate deliberate call to `Rummage.Junk:EnableRule(preview)`; displaying a preview does not authorize selling.

## Verification

The integrated suite has 98 cases (71 baseline plus 27 new feature groups). Stateful inventory fixtures model source/cursor/destination, exact vendor money changes, delayed acknowledgement and rejection. Cases cover reserve aggregation/protected stock, 18-of-30 and 13-of-20 oracles, consent bounds, split failures, concurrency, cursor ownership, truthful history, strict query validation, UI callbacks, atomic maps, fonts 6..24, paging and category content extent. Full native Lua 5.1 gate, TOC and package checks are recorded with delivery evidence; CI also runs the existing lupa backend.

The patch is kept in one integrated PR because the rule, reserve, history and native UI contracts share the same additive DB migration and TOC load graph. Atomic domain, UI and verification/documentation commits remain separately reviewable; an intermediate main branch exposing incomplete workflows would be misleading. The size exceeds the review skill's usual inspection trigger, so final independent review covers every source slice and all verification evidence.

No additional standalone library/package boundary is introduced: domain modules are internal to the existing addon and depend explicitly on its host API adapter. Package/static checks establish install payload contents, not actual server behavior. Live protected actions, taint, real acknowledgements and screen-reader behavior require separately observed client evidence.
