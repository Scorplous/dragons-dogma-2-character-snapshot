# Changelog

## 0.21.0-candidate — scoped live reads verified, experimental release candidate

- Add `quests.currentJournal`, derived from identity-checked ordered-log evidence, with nativeComplete/nativeProgressing/unknown classification. Require exact native labels and agreeing ended/progressing flags; exclude explicit investigation probes.
- Present completion-report text only for nativeComplete. Preserve legacy diagnostic report fields with explicit template labels; never infer failure or favorable outcomes from canned text.
- Carry capture freshness and journal-specific coverage. Explicit-probe failures remain independent of ordered-journal errors; source/player loss withholds the view.
- Categorize clear-record errors and distinguish all allocated slots examined from valid complete records. Negative IDs remain invalid; no sentinel semantics are assumed.
- Add synthetic membership, ambiguity/conflict, report-template, empty/truncated/error, invalid-entry and freshness regressions. Update newcomer setup, sharing, rollback and capability documentation.
- Scoped live checks observed advancing fresh exports, ordered membership/status/report gates, truthful invalid-entry coverage and continued equipment, backpack, companion-bag and completed inn-storage reads. The visible game journal was not independently compared; current-cycle reset behavior, lifetime history, rewards, NPC outcomes and universal NG+ behavior remain unvalidated. Private captures are excluded.

## 0.20.0-discovery — limited live observations

- Added bounded ordered quest-log status/label and ended/progressing evidence, explicit diagnostic probes, and localized report objects independently of clear counters.
- Live observations showed native journal distinctions, retained clear counts on progressing states, populated generic failure templates across other statuses, rejected invalid IDs, and clearing after player loss.
- These observations validate limited source reads, not universal playthrough scope or favorable outcomes.

## 0.19.0-discovery

- Added bounded read-only quest-clear records, ID/title checks, raw counts, source/session/freshness, coverage and concurrency safeguards.
- No validated current-cycle or lifetime completion mapping; RC wallet source remains unverified.

## 0.18.0-discovery

- Continued runtime metadata discovery without validating RC wallet or quest-history semantics.

## 0.17.0-experimental

- Added owner-verified player backpack scanning, separate from equipped gear, pawn bags and inn storage.
- Reset scans across identity changes and player loss; incomplete scans never prove absence. Complete player-backpack scans were later observed live.

## 0.16.1-experimental

- Added bounded inn storage and three-pawn identity, owner-checked gear and carried-item observations.
- Accepted signed/unsigned runtime identifiers while preserving identity guards; corrected preference for readable broader area names.
- Live observations included complete pawn-bag reads; inn storage could remain partial. Skill layout, inclination and disease interpretations remain limited. A prior startup hang's cause was not established.
