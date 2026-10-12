# Dragon's Dogma 2 Character Snapshot

**AtlasSnapshot** creates local snapshots of your Dragon's Dogma 2 character so you can share concrete game observations with **ChatGPT** for gear comparisons, stat explanations and relationship discussions. You can also inspect the files yourself or use another compatible tool. [Public repository](https://github.com/Scorplous/dragons-dogma-2-character-snapshot).

**Atlas is the original user's nickname for their AI assistant; AtlasSnapshot is this project's branding.** Atlas is not a separate AI product you need to install or subscribe to.

Experimental local character-observation exporter for **Dragon's Dogma 2** using REFramework. It writes JSON every five seconds for local tools and assistants. It does not deliberately change saves, equipment, affinity or NPC state. Runtime calculations are experimental and may fail as the game or framework changes.

**Version 0.11.0-experimental.** This is not an official Capcom product. It targets DD2, not the original Dragon's Dogma: Dark Arisen.

## Why this is useful

This project grew out of playing DD2 while talking with ChatGPT by voice: asking the assistant to check the character's actual equipment and stats instead of repeatedly opening menus and reading numbers aloud. A snapshot reduces manual copying and gives the conversation a concrete reference, so advice can be tied to your captured gear and state rather than assumptions about a generic build.

It also makes less-visible relationship information easier to discuss. The relationship reader tries to present game rank labels as understandable attitudes while keeping the underlying values and unknowns visible. The stored-rank-to-label mapping has been observed working in a live v0.10 session; those labels do not establish romance or future behavior. For NPC history, the useful answer may be "we observed this NPC dead, but do not know the cause" rather than an invented account of what happened.

You can ask about gear, captured vocation fields or equipment weight where the data supports an answer. For a comparison with an unequipped item, provide that item's details too: the exporter does not read your entire inventory. Party composition and skill loadouts also need extra context; this is not a complete party export or an optimal-build calculator.

## Example: ask while you play

1. **Let the game export.** Load your character with REFramework and the exporter running. It attempts a local snapshot every five seconds.
2. **Give the assistant the relevant data.** Share the reader's output, or authorize the snapshot folder in an assistant environment that supports local file access. Voice is a convenient way to ask questions, but text works too.
3. **Ask a question.** For example: "What do my current gear and stats suggest I should improve?", "What enhanced stats and weight are reported for my equipped weapon?", or "What relationship information do we have for this NPC?"
4. **Have it check before advising.** Ask the assistant to read a fresh observation when possible, report its timestamp and availability, and use only the fields relevant to the question. Missing NPC records remain unknown. Raw coordinates can provide position context, but do not support verified map directions; quest progress and player-kill attribution are not available in this version.
5. **Use the answer in play, then refresh when needed.** After changing equipment or returning later, ask it to check again or share a new file. Five-second exports are not an automatic stream into ChatGPT, and no background AI model silently watches each export.

Saying "look at this" may also be useful in a separately configured assistant session that can take screenshots with your authorization. **Screenshot capture is not provided by this exporter.** A screenshot or an extra item tooltip can supplement the snapshot when your question needs information it does not contain.

## How ChatGPT fits in

The exporter runs locally inside DD2 through REFramework and writes files independently of ChatGPT. **Running the exporter requires no ChatGPT account, subscription, OpenAI API key or automatic AI connection.** There is no built-in upload, ChatGPT plugin or background chat integration. Choosing to use ChatGPT for interpretation is a separate step, subject to the features available in your account and session.

1. Install the exporter below, load your game and allow a snapshot to be written.
2. Run `Read-latest-snapshot.py` to obtain a consistent observation with its availability and age. Its output includes the captured data or a clearly marked last-known snapshot. The relationships reader provides a smaller attitude-focused view.
3. Share the reader's output with ChatGPT by pasting it or attaching a saved copy where file attachments are supported. OpenAI documents [sharing files and data exports with ChatGPT](https://learn.chatgpt.com/docs/use-chatgpt). Alternatively, if your particular assistant environment offers local file tools, explicitly authorize access to the relevant snapshot folder. This repository neither supplies nor enables that access; ordinary chats must not be assumed to read your computer.
4. Ask a specific question, such as: "Explain the captured equipment stats, distinguish base values from enhanced values, and list anything unknown." Ask the assistant to preserve timestamps and uncertainty rather than fill missing fields with guesses.
5. Share a new observation when the game changes. An attached copy does not update itself, and the five-second export interval does not refresh a ChatGPT conversation automatically.

Only share data you intend the receiving service to process. A snapshot can contain character names, positions and NPC relationship or world-state information. Sharing source code alone does not give ChatGPT your current character data.

## What a snapshot contains

Each section reports what could actually be read. Fields can be partial, unavailable or in error; a section's presence does not mean every value is known. Missing values must not become zero, a clean bill of health, a dead NPC, or a never-completed quest.

| Section | Exported observations and limits |
| --- | --- |
| Equipped gear | Slot IDs and game enum labels, item IDs and game-resolved names. Base parameters are separate from game-calculated enhanced equipment parameters, calculated weight and weapon element where available. Numeric fields can include attack, magic, defence, knockdown-related values, damage types and resistances. Raw instance state is retained, but upgrade-level interpretation and units are not universally verified. Inventory and storage ownership counts are not captured. |
| Character stats | Bounded raw status, stamina and vocation fields, including level-related observations and a current vocation label where resolved. Separate calculator records capture basic attack/defence and values incorporating equipment/buffs where the runtime methods work. These are experimental source values, not a guarantee that every number exactly matches the final character-screen formula. Item stats are not silently substituted for character totals. |
| Position | Raw player world `x`, `y`, `z` coordinates without deliberate rounding. Coordinate units, axis directions, scene identity and conversion to a map grid are unverified or unavailable. A position does not establish that active gameplay is underway. |
| NPC relationships | Verified character ID, game-resolved name where available, stored sentiment value and rank, temporary sentiment, group identifiers and current quest-layer classification. A rotating scan checks at most 128 holder-array slots and emits at most 32 NPC records per capture. This is neither a complete roster nor proof that you have encountered every listed NPC. |
| NPC attitudes | The display attempts an exact match between the stored rank and runtime game enum labels, retaining the raw values. Missing or ambiguous matches produce "Unknown attitude." It does not invent affinity thresholds, percentages, romance status or intended behavior. The stored rank and runtime labels were matched successfully in a live v0.10 session; this does not validate behavioral interpretations or guessed thresholds. |
| Main pawn | Character ID resolved through the main pawn component's cached Character, plus raw `favorabilityRating` and `accumulatedFavorability` from the main pawn context. Pawn name is currently unavailable. This is a separate scale from NPC sentiment; thresholds and normalization are unverified, so the display leaves pawn attitude unknown. The v0.11 receiver correction was live-verified across advancing captures: Character identity and both favorability fields were readable without the previous exception. The numbers are not percentages or verified attitude tiers. |
| Crime | Up to 32 game character-group crime records, with their identifiers and runtime labels, where readable. These are separate from NPC affinity; group-to-town mappings and a universal town-reputation score are not established. |
| NPC life observations | Explicit dead/coffin flag evidence and entity presence support bounded alive/dead observations after identity checks. An absent entity without a dead flag stays unknown. Records may include raw revival count and an observed entity position, with provenance and cause marked unknown. This does not identify who killed an NPC or where a death originally happened. |
| Retained NPC evidence | Up to 128 entries from the game's retained NPC-history list: character IDs, raw flags and available enum labels, plus count/truncation information. The bounded list read was observed working in a live v0.10 session. Its runtime flag labels describe sub-NPC/costume classification. These flags are not a verified player-kill ledger and provide no established original event locations. |
| Capture metadata | Exporter version, capture kind/status, UTC capture time, epoch timestamp, session ID, sequence number, refresh/staleness settings and source/error details. Startup schema metadata describes reflected fields and methods; it is not itself character progress. Quest progress and lifetime completion history are not read by this version. |

## Timing, freshness and history

The script attempts a character export every five seconds while its REFramework frame callback runs. It alternates between `AtlasSnapshot-DD2-slot-0.json` and `AtlasSnapshot-DD2-slot-1.json`, then publishes `AtlasSnapshot-DD2-latest.json` as a pointer to the completed slot. The pointer alone is not a character snapshot. Startup metadata goes to `AtlasSnapshot-DD2-schema-latest.json`.

The reader checks the pointer twice and matches session, sequence and timestamp before returning data. It marks observations older than 15 seconds stale; partial writes and inconsistent files are rejected. A recent file is still an **unverified observation**, because player references can persist through menus or loading. Saved copies are historical evidence, not a live feed. The rotating slot files do not preserve every earlier capture.

The optional Windows history watcher maintains a separate local append-only journal with deduplication and session boundaries. It currently journals verified life observations for the current quest-layer NPC subset, not all important NPCs. It cannot reconstruct events before observation, detect same-session save rollback or infer a resurrection from a dead-to-alive change alone. **Observed dead does not mean killed by the player.** A later NPC position is an observation location, and the player's current position cannot stand in for an original kill location.

## Validation status

The v0.9 equipment, coordinates, named NPC sentiment and history watcher were live-tested on Windows with Steam DD2 build **25290080** and REFramework **nightly-01432 / d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee**. This is an observed combination, not a general compatibility guarantee. **Live v0.10 validation confirmed advancing five-second captures, continued equipment/stat/position reads, stored NPC rank-to-label matching, bounded retained-history reads and the local journal watcher. Live v0.11 validation additionally confirmed main-pawn Character identity and separate favorability fields after correcting the Pawn/Character receiver mismatch; existing gear, character scalar stats, position, NPC rank mapping and journal continued working.** Some character calculator numeric-array elements also remain explicitly unavailable; no complete character-panel equivalence is claimed. Tests use synthetic data; they do not prove game behavior.

## Install

1. Back up your current saves and quit DD2 normally. Never modify the installed script while the game is running.
2. Install an appropriate [official REFramework build](https://github.com/praydog/REFramework/releases). This repository contains no framework DLL, game binaries or assets. Framework compatibility is your responsibility; the tested version above is evidence, not a promise for other builds.
3. Copy `src/AtlasSnapshot-DD2.lua` to `<DD2>/reframework/autorun/AtlasSnapshot-DD2-probe.lua`. Keep only one AtlasSnapshot autorun script active. For an existing installation, preserve the previous script before replacing it.
4. Launch through Steam, load a save, and wait at least ten seconds in a safe location. Files appear under `<DD2>/reframework/data/`.

Alternatively, `tools/Install.ps1` requires explicit `-GameDirectory`, `-SaveDirectory` (the Steam app's `2054970` folder), and `-BackupDirectory` outside this repository. It refuses a running game, backs up and hashes current saves, preserves the previous reader, installs only the Lua script, and verifies saves are unchanged. It never restores saves or installs REFramework.

## Local readers

Python 3.10+ is required for these optional local readers, not for the Lua exporter itself. Readers use the standard library; synthetic Lua tests additionally need Lupa. Set paths locally; do not commit your environment or generated data.

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
