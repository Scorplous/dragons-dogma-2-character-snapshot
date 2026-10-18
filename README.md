# Dragon's Dogma 2 Character Snapshot

AtlasSnapshot writes local observations from Dragon's Dogma 2 so you can inspect them or share them with an assistant for gear, quest and relationship questions. Atlas is the original user's nickname for their assistant; it is not another product you must install.

**v0.21.0-candidate has passed scoped live-read checks and is prepared for experimental release.** It uses REFramework on Windows. It is experimental, unofficial and intended for DD2, not Dragon's Dogma: Dark Arisen. It does not deliberately change saves, gear, quests, affinity or NPC state. Game/framework updates can break reads.

## Start here

Download the source package and checksum from the [v0.21.0 experimental release](https://github.com/Scorplous/dragons-dogma-2-character-snapshot/releases/tag/v0.21.0-experimental). The exporter identifies itself as `0.21.0-candidate`; this release preserves the exact source used for the scoped live checks.

You need the game, a separately installed compatible REFramework build, and this project's source package. Python 3.10+ is needed only for the optional reader tools. No ChatGPT subscription, account or API key is needed to run the exporter. It has no network upload or automatic AI connection.

1. **Close DD2 normally and back up your saves.** Keep the backup outside the game and project folders. Never replace the installed Lua script while DD2 is running.
2. **Find the game folder.** In Steam, open DD2's Properties, then Installed Files, then Browse. The folder should contain `DD2.exe`.
3. **Install REFramework separately.** Use the [current official releases](https://github.com/praydog/REFramework/releases) and [installation instructions](https://github.com/praydog/REFramework/blob/master/README.md). For non-VR use, those instructions specify extracting only `dinput8.dll` into the folder containing `DD2.exe`. Current nightlies use the monolithic `REFramework.zip`; do not assume a separate DD2 archive is always available. If REFramework already works, this exporter update does not require upgrading it. This package contains no framework DLL or game assets. See the tested configuration below; compatibility with other versions is not guaranteed.
4. **Install one exporter.** Extract this project's package. Copy `src/AtlasSnapshot-DD2.lua` into `<DD2>\reframework\autorun\` and name the installed file `AtlasSnapshot-DD2-probe.lua`. Create `autorun` if necessary. Keep only one AtlasSnapshot Lua script active there. Preserve an existing script before replacing it.
5. **Load a save and wait at least ten seconds in a safe place.** Exports appear in `<DD2>\reframework\data\`. The script attempts a new observation every five seconds while its frame callback runs.
6. **Read the result.** Open PowerShell in the extracted project folder. Replace the example path below with the folder containing your `DD2.exe`:

```powershell
$env:ATLAS_DD2_DATA_DIR = 'D:\YourSteamLibrary\steamapps\common\Dragons Dogma 2\reframework\data'
python tools/Read-latest-snapshot.py
# Optional: save an envelope to review or share.
python tools/Read-latest-snapshot.py | Set-Content -Encoding utf8 snapshot-for-sharing.json
```

If `python` is unavailable, install Python 3.10+ separately and reopen PowerShell, or use your Python installation's executable path. Python is not required for the game to export files.

The reader output should identify the snapshot version, age, availability and captured sections. `recent_unverified_observation` is expected: the overall reader does not certify every gameplay field merely because the file is fresh. `stale` means more than 15 seconds old (or a clock mismatch); `lastKnownSnapshot` is historical. `unavailable` means no consistent snapshot could be read. A section can independently be unavailable, partial or in error. Do not interpret any of those states as zero, absence or failure.

If no files appear, check REFramework loaded, the single script's location, and that a save is loaded. If the reader reports unavailable, verify the data-folder path and give the exporter another interval. Do not attach `AtlasSnapshot-DD2-latest.json` alone: it is a publication pointer, not the character data. Do not reinstall or overwrite a running reader to refresh observations.

### Optional installer with verified backups

`tools/Install.ps1` requires the game folder, your Steam user's DD2 save folder named `2054970`, and a backup folder outside the project, game and save folders. Choose the correct Steam user; do not guess if multiple accounts exist. The installer refuses a running game, backs up and hashes save files, preserves the prior reader, copies only the Lua script, and verifies that saves were unchanged. It does not install REFramework or restore saves.

Run from the extracted project folder, replacing all paths:

```powershell
.\tools\Install.ps1 -GameDirectory 'D:\YourSteamLibrary\steamapps\common\Dragons Dogma 2' -SaveDirectory 'C:\Program Files (x86)\Steam\userdata\YOUR_STEAM_USER\2054970' -BackupDirectory 'D:\PrivateBackups\DD2'
```

The game folder and save folder may be on different drives. If PowerShell blocks the script, the manual copy procedure above remains available; no system-wide policy change is required by this project. The installer preserves the expected target filename but does not detect every renamed duplicate script: check `autorun` yourself.

## Use the observation with an assistant

Share the saved reader output by pasting or attaching it where your assistant supports that, or explicitly authorize access to the snapshot folder in an environment with local file tools. An ordinary chat cannot be assumed to read your PC. Voice is an optional way to ask questions, not an automatic connection to the exporter. Source code alone does not contain your character data.

Useful questions include: "Compare my captured equipped weapon with this item tooltip," "Which quests does the loaded journal mark Complete?", and "Explain this NPC's observed relationship values, including unknowns." Ask for the observation's age, section coverage and uncertainty before advice. Share a fresh observation after changes; an attachment does not update itself.

Snapshots may expose character names, quest spoilers, positions, NPC relationships and world-state observations. Share only what you intend the receiving service to process. Screenshots are not captured by this exporter, but a manually shared screenshot can help compare the game's UI with an observation.

## Current capabilities and limits

| Section | Available observations | Limits |
| --- | --- | --- |
| Gear and character | Owner/slot-checked equipment, item names, base and game-calculated enhanced parameters, calculated weight, raw character fields and experimental character calculators | Not a complete character-screen formula or optimal-build calculator; units and upgrade interpretation are not universally verified |
| Player backpack | Bounded owner-checked carried item rows and quantities, separated from equipped gear | Partial scans cannot prove an item is absent |
| Inn storage and pawn bags | Independent bounded scans, item IDs, quantities and available item values; up to three active pawns with identities and owner-checked gear | Scan progress and errors matter; not all inventory locations form one guaranteed complete ownership ledger |
| Health, vocation and skills | Native HP values, localized vocation/rank, runtime-reported skill and augment slots | HP loss interpretation and exact active skill-slot layout are not universally verified |
| Current journal | Ordered native journal records classified as `nativeComplete`, `nativeProgressing` or `unknown`, with IDs/titles and gated completion report text | Observed loaded journal only; not universal current-cycle, lifetime or favorable-outcome history |
| Active objectives | Identity-checked progressing/tracked quests and localized current-task text where readable | No checklist percentages, cutoff guarantees or inferred unlock conditions |
| Area and position | Native area IDs/names and raw world coordinates; readable broad area preferred to technical tokens | No verified map grid, axis directions or navigation routing |
| Relationships | Bounded NPC sentiment/rank observations and runtime rank labels; separate main-pawn favorability values; group crime records | No invented thresholds, romance status, disease diagnosis or universal town reputation |
| NPC life/history | Identity-checked explicit life flags, entity presence and bounded retained history; optional local observation journal | No player-kill attribution, complete roster, original event location or reconstructed world history |

RC wallet balance remains unavailable. Missing entries must never become claims that an item is not owned, an NPC is dead, or a quest was never completed.

### Quest journal contract

Prefer `quests.currentJournal` for usable journal observations. It is derived from the same bounded, identity-checked native evidence; it performs no extra game queries. Only ordered-log members are included. The five explicit investigation probes retained in `logStatusEvidence` are not journal membership or completion evidence.

- `nativeComplete`: exactly one native enum label, `Complete`, with `nativeEnded=true` and `nativeProgressing=false`.
- `nativeProgressing`: exactly one native enum label, `Progressing`, with `nativeProgressing=true` and `nativeEnded=false`.
- `unknown`: missing/ambiguous labels, other native states or conflicting flags. Ended alone does not establish completion.

Only `nativeComplete` receives available completion-report text in this view. That text is a native journal report, not proof of current NPC location/survival, romance, reward receipt, favorable branch or cutoff safety. No state is mapped to a failure outcome. Missing report text leaves the native classification intact.

Legacy `quests.logStatusEvidence` fields are retained for compatibility. Its `report`, `impossible` and `impossibleDetail` are **diagnostic templates**, not realized outcomes. Populated Impossible/Discontinued templates were observed even on Complete and Progressing quests. Template objects now carry explicit diagnostic labels; never use template text alone to conclude success or failure.

Journal coverage includes list count, bounded entries examined, truncation, ordered-entry errors and `scanComplete`; failures of unrelated explicit probes do not reduce journal coverage. A complete scan means the observed bounded collection was read, not that all quests in the game or earlier playthroughs are known. Session and capture time accompany the view. Phase/source changes or player loss withhold it rather than retaining an old journal as current.

`quests.completedHistory.rawRecords` remains raw clear-counter evidence. Retained positive clear counts were observed alongside currently progressing journal states, so counters are not used to classify this loaded journal. Negative IDs, identity mismatches, invalid counts, duplicate IDs and read failures remain categorized diagnostics. `allSlotsExamined` means traversal finished; `validRecordsComplete` and legacy `scanComplete` additionally require error-free matching coverage. A negative-ID row is not silently accepted as a known sentinel. Missing rows do not establish never-completed status.

`currentPlaythroughValidated=false`, unknown lifetime history and unknown outcomes remain intentional. No claim is made that every NG+ transition or every quest resets these sources identically.

## Freshness and optional history

The exporter alternates two slot files and publishes `AtlasSnapshot-DD2-latest.json` only after a slot write succeeds. The reader checks the pointer twice and matches session, sequence and timestamp. Startup schema metadata is not character progress. Saved copies and stale observations are historical; two rotating slots are not a permanent history archive.

Optional readers use Python's standard library:

```powershell
python tools/Read-relationship-attitudes.py
$env:ATLAS_DD2_HISTORY_DIR = 'D:\PrivateHistory\DD2'
python tools/Watch-NPC-history.py
```

The Windows-only watcher records a bounded NPC observation subset, not all NPCs or quests. Its default history folder is `.atlas-dd2` in your home folder if no path is supplied. Stop it with Ctrl+C or create `stop-npc-history.txt` in that history folder; remove that stop file before a deliberate restart. It is not automatically scheduled. It cannot reconstruct earlier events or detect same-session save rollback. Dead-to-alive does not alone prove resurrection; observed dead does not mean killed by the player.

## Validation status

The historical tested Windows combination was Steam DD2 build **25290080** and REFramework **nightly-01432 / d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee**. This is one observed configuration, not a compatibility promise.

Earlier live versions observed advancing captures, owner-checked gear, character fields, coordinates, NPC rank labels, main-pawn identity/favorability, health/vocation/skills, active objectives, player-backpack scans and three active pawn bags. Inn storage can remain partial. Skill-slot meaning, complete UI-stat equivalence and many gameplay interpretations remain unvalidated. One prior startup hang occurred before export initialization; its cause was not established.

**v0.20 live evidence:** native ordered-journal statuses and localized text were readable; Complete and Progressing states were distinguishable, clear counts could remain positive for progressing quests, generic failure templates appeared on non-failed states, invalid clear-record IDs remained rejected, and player loss cleared current evidence. These observations support the narrow view above, not universal NG+ semantics. No private quest identities or captured text are included here.

**v0.21 candidate:** all 21 synthetic regression modules and source-syntax validation passed. After installation, fresh same-session exports advanced, the derived journal matched ordered native membership and exact native status/flag gates, and completion text remained restricted to native Complete records. Populated failure templates remained diagnostic; invalid clear IDs retained partial-validity coverage despite completed slot traversal. Equipped items, the player backpack, three companion bags and a completed inn-storage scan remained readable without inventory entry errors. These are scoped native-read observations, not a performance benchmark or universal gameplay validation. The visible game journal was not independently compared during this run; that UI comparison and universal NG+ behavior remain unverified. Private captures are not bundled.

## Disable or roll back

Quit DD2 normally. Rename `reframework/autorun/AtlasSnapshot-DD2-probe.lua` to end in `.disabled`, or move it outside `autorun`. This disables this exporter only; REFramework is separate. To roll back an update, preserve the current script and restore the previously backed-up **Lua script only**. Do not restore old saves as part of exporter rollback. Stop any separately started history watcher if no longer needed.

## Tests and source privacy

```powershell
python -m pip install -r requirements-test.txt
python tests/run_tests.py
```

Tests use synthetic game objects through Lupa. They cover signatures, identity/ownership, failure isolation, freshness, bounded coverage, concurrency, unknown semantics, journal membership and status-gated reports. No in-game actions or save edits are needed. Do not commit saves, screenshots, snapshots, journals, local install manifests, credentials or proprietary assets.

## References and licensing

- [Public repository](https://github.com/Scorplous/dragons-dogma-2-character-snapshot)
- [REFramework API documentation](https://cursey.github.io/reframework-book/)
- [DD2 Content Editor](https://github.com/kagenocookie/dd2-content-editor)
- [MyDD2Mod](https://github.com/xyzkljl1/MyDD2Mod) and [DD2-LUAModFixes](https://github.com/Zharay/DD2-LUAModFixes)
- [.NET Dictionary implementation](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/Collections/Generic/Dictionary.cs), a layout reference rather than proof of DD2 quest semantics

Third-party source, binaries and game assets are not bundled. Dependencies retain their own licenses. No license has yet been selected for this project's source; public visibility alone does not grant broad reuse rights.

