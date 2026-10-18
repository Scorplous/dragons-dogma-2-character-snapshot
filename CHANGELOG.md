# Changelog

## 0.16.1-experimental

- Add bounded inn-storage observations with ownership and list-consistency checks.
- Add up to three active pawns, main/recruited identity, owned gear, vocation, raw skill slots, carried items and raw inclination evidence.
- Accept unsigned 32-bit pawn identifiers as well as signed representations; retain identity and equipment ownership guards.
- Clear carried caches on invalid or changed rosters; separate carried items from equipped gear and inn storage.
- Preserve unknown disease/transmission meaning; no infection diagnosis or automatic alerting.
- Prefer readable broad area names over untranslated technical sub-area labels.
- Add synthetic area-display, storage and party regressions, including ownership mismatches and unsigned identifiers.
- Live verified complete three-pawn identity capture, owner-matched populated equipment and carried scans. Active skill-slot interpretation, inclination display mapping and full inn-storage completion remain limited; see README.
