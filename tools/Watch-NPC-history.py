"""Local journal watcher. Prepared for the v0.9 observation reader; not auto-started.
Stop by creating stop-npc-history.txt in ATLAS_DD2_HISTORY_DIR. No writes to game or save files.
"""
import importlib.util
import json
import os
import msvcrt
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parent
def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

if __name__ == '__main__':
    reader = load('snapshot_reader', 'Read-latest-snapshot.py')
    journal = load('npc_journal', 'NPC-history.py')
    history_root = Path(os.environ.get('ATLAS_DD2_HISTORY_DIR', str(Path.home() / '.atlas-dd2')))
    history_root.mkdir(parents=True, exist_ok=True)
    if not os.environ.get('ATLAS_DD2_DATA_DIR'):
        raise SystemExit('Set ATLAS_DD2_DATA_DIR to the game reframework/data directory')
    lock = (history_root / 'npc-history-watcher.lock').open('a+b')
    lock.seek(0)
    if lock.read(1) == b'':
        lock.write(b'0'); lock.flush()
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        raise SystemExit('An NPC history watcher already owns the lock')
    previous = None
    data_root = Path(os.environ.get('ATLAS_DD2_DATA_DIR', ''))
    while not (history_root / 'stop-npc-history.txt').exists():
        try:
            result = reader.read_latest(data_root)
            if result['availability'] == 'recent_unverified_observation':
                snapshot = result['snapshot']
                key = (snapshot['session'], snapshot['sequence'])
                if key != previous:
                    journal.ingest(snapshot, history_root / 'npc-history.jsonl')
                    previous = key
        except Exception as error:
            (history_root / 'npc-history-watcher-error.txt').write_text(str(error), encoding='utf-8')
        time.sleep(1)
