"""Append-only local journal for a future verified NPC observation adapter.

The current v0.8 probe emits no life observations. This journal does not infer
kills from missing NPCs, affinities, or raw unvalidated fields. No game writes.
"""
import argparse
import hashlib
import json
import os
import math
from pathlib import Path


def verified_location(record, prefix):
    value = record.get(prefix)
    if not isinstance(value, dict) or value.get('verified') is not True or not value.get('provenance'):
        return {'captureStatus': 'unavailable', 'reason': 'No verified location for this event/observation'}
    result = {'captureStatus': 'partial', 'provenance': value['provenance']}
    coords = value.get('coordinates')
    if isinstance(coords, dict) and all(isinstance(coords.get(k), (int, float)) and not isinstance(coords[k], bool) and math.isfinite(coords[k]) for k in ('x', 'y', 'z')):
        result['coordinates'] = {k: coords[k] for k in ('x', 'y', 'z')}
    for key in ('regionId', 'regionName', 'coordinateSpace'):
        if value.get(key) is not None:
            result[key] = value[key]
    if not any(k in result for k in ('coordinates', 'regionId', 'regionName')):
        return {'captureStatus': 'unavailable', 'reason': 'Verified source did not provide a usable location'}
    return result


def ingest(snapshot, path):
    path = Path(path)
    history = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()] if path.exists() else []
    seen = {e['id'] for e in history}
    session = snapshot.get('session')
    seq = snapshot.get('sequence')
    when = snapshot.get('capturedAtUtc')
    if not session or not isinstance(seq, int) or not when:
        return {'appended': 0, 'status': 'unavailable', 'reason': 'Snapshot identity/time missing'}
    prior_sequences = [e['sequence'] for e in history if e.get('session') == session]
    if prior_sequences and seq < max(prior_sequences):
        return {'appended': 0, 'status': 'unavailable', 'reason': 'Out-of-order observation; history unchanged'}
    section = snapshot.get('npcLifeObservations') or {}
    if section.get('captureStatus') not in ('captured', 'partial'):
        return {'appended': 0, 'status': 'unavailable', 'reason': section.get('reason', 'No verified source observations')}
    # A new run/load token invalidates prior current-world claims but never
    # erases observations. Historical events are not a claim about this save.
    epoch = str(section.get('worldEpoch', session))
    state = {}
    last_epoch = None
    for event in history:
        if event['kind'] == 'world_boundary':
            last_epoch = event['worldEpoch']; state = {}
        elif event.get('worldEpoch') == epoch and event['kind'] == 'life_observation':
            state[event['characterId']] = event['state']
    pending = []
    def add(event, key):
        event['id'] = hashlib.sha256(key.encode()).hexdigest()
        if event['id'] not in seen:
            seen.add(event['id']); pending.append(event)
    context = {'session': session, 'sequence': seq, 'observedAtUtc': when, 'worldEpoch': epoch}
    if last_epoch != epoch:
        add(dict(context, kind='world_boundary', currentWorldState='unverified_after_load'), 'boundary:' + epoch)
    for record in (section.get('records') or [])[:128]:
        cid = record.get('characterId')
        status = record.get('state')
        provenance = record.get('provenance')
        if cid is None or record.get('identityVerified') is not True or record.get('stateVerified') is not True:
            continue
        if status not in ('alive', 'dead') or not isinstance(provenance, str) or not provenance.strip():
            continue
        if record.get('importantVerified') is not True:
            continue
        cid = str(cid)
        source_id = record.get('sourceEventId')
        attributed = (status == 'dead' and record.get('playerAttributionVerified') is True
                      and record.get('cause') == 'player' and bool(source_id)
                      and bool(record.get('attributionProvenance')))
        # Attribution needs an identifiable event, not an inferred dead-state.
        if attributed:
            add(dict(context, kind='player_kill', characterId=cid, name=record.get('name'),
                     sourceEventId=source_id, provenance=record['attributionProvenance'],
                     eventLocation=verified_location(record, 'eventLocation'),
                     occurredAtUtc=record.get('occurredAtUtc'), currentWorldState='not_implied'),
                'kill:' + cid + ':' + str(source_id))
        previous = state.get(cid)
        if previous == status:
            continue
        transition = 'first_observed_' + status if previous is None else previous + '_to_' + status
        # dead->alive alone does not distinguish resurrection from save rollback.
        add(dict(context, kind='life_observation', characterId=cid, name=record.get('name'),
                 state=status, transition=transition, cause='player' if attributed else 'unknown',
                 resurrectionVerified=record.get('resurrectionVerified') is True,
                 observationLocation=verified_location(record, 'observationLocation'),
                 provenance=provenance), f'life:{epoch}:{seq}:{cid}:{status}')
        state[cid] = status
    if pending:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('a', encoding='utf-8') as stream:
            for event in pending:
                stream.write(json.dumps(event, ensure_ascii=False) + '\n')
    return {'appended': len(pending), 'status': 'partial', 'completeHistory': False,
            'currentWorldCoverageComplete': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--journal', type=Path, default=Path(os.environ.get('ATLAS_DD2_HISTORY_DIR', str(Path.home() / '.atlas-dd2'))) / 'npc-history.jsonl')
    args = parser.parse_args()
    data = json.loads(args.snapshot.read_text(encoding='utf-8-sig'))
    if 'availability' in data:
        if data['availability'] != 'recent_unverified_observation':
            raise SystemExit('Refusing stale/unavailable envelope; journal unchanged')
        data = data['snapshot']
    print(json.dumps(ingest(data, args.journal)))
