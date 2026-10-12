"""Read AtlasSnapshot double-buffer output without treating partial/stale data as live."""
import json
import os
import sys
import time
from pathlib import Path

def read_latest(directory, now=None):
    if not directory:
        return {'availability':'unavailable','currentValuesAvailable':False,'reason':'Set ATLAS_DD2_DATA_DIR or supply the data directory'}
    root=Path(directory)
    now=time.time() if now is None else now
    reason='No consistent snapshot available'
    for _ in range(3):
        try:
            pointer=(root/'AtlasSnapshot-DD2-latest.json').read_bytes()
            index=json.loads(pointer)
            if index['file'] not in ('AtlasSnapshot-DD2-slot-0.json','AtlasSnapshot-DD2-slot-1.json'):
                raise ValueError('Unexpected snapshot filename')
            snapshot=json.loads((root/index['file']).read_bytes())
            if pointer != (root/'AtlasSnapshot-DD2-latest.json').read_bytes():
                raise ValueError('Publication changed during read')
            for key in ('sequence','session','capturedAtEpoch'):
                if index[key] != snapshot[key]: raise ValueError('Snapshot does not match publication')
            age=now-snapshot['capturedAtEpoch']
            if age<0 or age>15:
                return {'availability':'stale','ageSeconds':age,'currentValuesAvailable':False,
                        'lastKnownSnapshot':snapshot}
            # Even a recent player reference may persist across menu/loading transitions.
            # Do not relabel these experimental observations as confirmed current gameplay.
            return {'availability':'recent_unverified_observation', 'ageSeconds':age,
                    'currentValuesAvailable':False,'snapshot':snapshot}
        except (OSError,ValueError,KeyError,TypeError) as exc:
            reason=str(exc)
    return {'availability':'unavailable','currentValuesAvailable':False,'reason':reason}

if __name__=='__main__':
    directory=sys.argv[1] if len(sys.argv)>1 else os.environ.get('ATLAS_DD2_DATA_DIR', '')
    print(json.dumps(read_latest(directory),indent=2))

