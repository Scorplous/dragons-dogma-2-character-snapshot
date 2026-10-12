# Dragon's Dogma 2 Character Snapshot

**AtlasSnapshot** exports live gear, stats, position, relationships and NPC observations. [Public repository](https://github.com/Scorplous/dragons-dogma-2-character-snapshot).

Experimental local character-observation exporter for **Dragon's Dogma 2** using REFramework. It writes JSON every five seconds for local tools and assistants. It does not deliberately change saves, equipment, affinity or NPC state. Runtime calculations are experimental and may fail as the game or framework changes.

**Version 0.10.0-experimental.** This is not an official Capcom product. It targets DD2, not the original Dragon's Dogma: Dark Arisen.

## Current scope

- Equipped item IDs and game-resolved names; base item parameters and calculated enhanced parameters kept separate.
- Character calculation records, stamina/level observations, and raw player world coordinates. Some field meanings, units and display formulas remain unverified.
- Named NPC stored sentiment values with incomplete rotating coverage: up to 128 holder-array slots and 32 NPC records per capture. Unseen or missing NPCs are never assumed to have zero affinity or to be dead.
- Group crime records, explicitly **not** a universal town-reputation score. Group-to-town mappings are not established.
- Explicit NPC dead-state observations. **Observed dead does not mean killed by the player.** The current game reader does not establish historical or future player-kill attribution or original kill locations.
- Local append-only history writer with deduplication, identity/provenance checks, and a Windows watcher. Currently journals only the verified current quest-layer NPC subset; this is not a complete list of important NPCs. Later entity positions are observation locations, not historical death locations.
- Attitude-first local display matches the stored NPC rank to the game's runtime enum labels and retains raw numbers. Unknown, missing or ambiguous mappings stay unknown. No guessed thresholds, percentages, romance status or behavior. Main-pawn favorability uses a separate scale.

The v0.9 equipment, coordinates, named NPC sentiment and history watcher were live-tested on Windows with Steam DD2 build **25290080** and REFramework **nightly-01432 / d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee**. This is an observed combination, not a general compatibility guarantee. **The new v0.10 main-pawn favorability, retained NPC-history fields and attitude rank mapping are pending live validation.** Tests use synthetic data; they do not prove game behavior.

## Install

1. Back up your current saves and quit DD2 normally. Never modify the installed script while the game is running.
2. Install an appropriate [official REFramework build](https://github.com/praydog/REFramework/releases). This repository contains no framework DLL, game binaries or assets. Framework compatibility is your responsibility; the tested version above is evidence, not a promise for other builds.
3. Copy `src/AtlasSnapshot-DD2.lua` to `<DD2>/reframework/autorun/AtlasSnapshot-DD2-probe.lua`. Keep only one AtlasSnapshot autorun script active. For an existing installation, preserve the previous script before replacing it.
4. Launch through Steam, load a save, and wait at least ten seconds in a safe location. Files appear under `<DD2>/reframework/data/`.

Alternatively, `tools/Install.ps1` requires explicit `-GameDirectory`, `-SaveDirectory` (the Steam app's `2054970` folder), and `-BackupDirectory` outside this repository. It refuses a running game, backs up and hashes current saves, preserves the previous reader, installs only the Lua script, and verifies saves are unchanged. It never restores saves or installs REFramework.

## Local readers

Python 3.10+ is required. Readers use the standard library; synthetic Lua tests additionally need Lupa. Set paths locally; do not commit your environment or generated data.

```powershell
$env:ATLAS_DD2_DATA_DIR = '<DD2>\reframework\data'
$env:ATLAS_DD2_HISTORY_DIR = '<private local history folder>'
python tools/Read-latest-snapshot.py
python tools/Read-relationship-attitudes.py
python tools/Watch-NPC-history.py
```

The history directory defaults to `.atlas-dd2` under your home folder. The watcher is Windows-only and runs until `stop-npc-history.txt` is created in that directory, or its process is stopped. Remove that stop file yourself before a deliberate restart. Its lock prevents duplicate writers. It is not automatically scheduled at startup.

`Read-latest-snapshot.py` also accepts the data directory as its first argument. It checks the publication pointer twice and validates session/sequence/time. Observations older than 15 seconds are stale. Even fresh observations do not prove the game is in active gameplay: a player reference can survive loading/menu transitions. `Read-relationship-attitudes.py --snapshot <saved-envelope.json>` explicitly treats a saved file as historical.

## Disable and rollback

Quit DD2 normally. Rename only `reframework/autorun/AtlasSnapshot-DD2-probe.lua` to a filename ending in `.disabled`, or move it outside `autorun`. This disables this exporter. REFramework is a separately installed dependency; consult its own instructions to disable it.

To roll back an update, quit DD2, preserve the current script, and copy the previously backed-up **Lua script only** back to the autorun path. Do not restore old saves as part of an exporter rollback. The optional installer prints its backup location and stores before/after hashes there. No automatic destructive rollback is included.

## Data limits and privacy

Snapshots may contain character names, NPC relationship values, locations and world-state observations. Keep them private unless you intentionally choose to share them. No network upload is built into the exporter or readers. This source repository must not contain saves, screenshots, snapshots, journals, machine-specific manifests, credentials or proprietary assets.

The history records observations across sessions without treating them as a reconstructed current-world ledger. Same-session save rollback detection is unavailable. A dead-to-alive change alone does not prove resurrection. A past player kill requires retained attribution and event-location evidence that this version has not established. Retained NPC flags remain raw evidence, not an inferred kill history.

## Tests

```powershell
python -m pip install -r requirements-test.txt
python tests/run_tests.py
```

The suite checks signature selection, value-type dispatch, failure isolation, bounded coverage, stale/partial files, identity mismatches, unknown affinity, history deduplication and attribution/location separation. No in-game killing or save modification is required.

## References and license status

- [REFramework API documentation](https://cursey.github.io/reframework-book/)
- [ValueType call implementation in the tested framework](https://github.com/praydog/REFramework/blob/d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee/src/mods/bindings/Sdk.cpp): value-type instance calls need the framework's boxed receiver path.
- [DD2 Content Editor](https://github.com/kagenocookie/dd2-content-editor): reference for reflected fields, equipment/name and transform access.
- [MyDD2Mod](https://github.com/xyzkljl1/MyDD2Mod) and [DD2-LUAModFixes](https://github.com/Zharay/DD2-LUAModFixes): reference for NPC name lookup and current quest-layer identification.

Third-party source, binaries and assets are not bundled. Dependencies retain their own licenses. **No license has yet been selected for this project's source. Public visibility alone does not grant a broad reuse license.**
