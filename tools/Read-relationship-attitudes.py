"""Attitude-first presentation of observed NPC relationships; never guesses tiers."""
import argparse
import importlib.util
import json
import os
from pathlib import Path


def present(envelope):
    recent = envelope.get('availability') == 'recent_unverified_observation'
    snapshot = envelope.get('snapshot') if recent else envelope.get('lastKnownSnapshot')
    snapshot = snapshot or {}
    relations = snapshot.get('relationships') or {}
    labels = relations.get('sentimentRankLabels') or {}
    rows = []
    for npc in relations.get('records') or []:
        raw = npc.get('rawAffinity') or {}
        rank = raw.get('rank')
        matches = [name for name, value in labels.items()
                   if isinstance(rank, (int, float)) and not isinstance(rank, bool)
                   and value == rank and name != 'None']
        known = (npc.get('identityVerified') is True and raw.get('captureStatus') == 'captured'
                 and len(matches) == 1)
        label = matches[0] if known else None
        rows.append({'name': npc.get('name'), 'characterId': npc.get('characterId'),
                     'attitude': label or 'Unknown attitude',
                     'attitudeStatus': 'game_rank_identified' if known else 'unavailable',
                     'rawAffinity': raw.get('value'), 'rawRank': rank,
                     'temporaryAffinity': npc.get('temporaryAffinity'),
                     'importance': npc.get('importance'),
                     'basis': 'Stored game rank, not inferred from raw affinity' if known else 'Runtime rank mapping or valid NPC evidence unavailable'})
    pawn = relations.get('mainPawnAffinity') or {}
    return {'availability': envelope.get('availability', 'unavailable'),
            'historicalObservation': not recent, 'capturedAtUtc': snapshot.get('capturedAtUtc'),
            'ageSeconds': envelope.get('ageSeconds'), 'npcAttitudes': rows,
            'coverage': relations.get('coverage', 'Unavailable'), 'completeRoster': False,
            'attitudeCaveat': 'Game rank labels do not prove romance, intended violence, or any past kill; no thresholds or percentages inferred.',
            'mainPawn': {'attitude': 'Unknown attitude', 'attitudeStatus': 'unavailable',
                         'name': pawn.get('name'), 'characterId': pawn.get('characterId'),
                         'favorabilityRating': pawn.get('favorabilityRating'),
                         'accumulatedFavorability': pawn.get('accumulatedFavorability'),
                         'reason': 'Separate pawn scale; attitude thresholds not verified'},
            'crime': {'interpretation': 'Separate crime records; not NPC attitudes or town reputation',
                      'sourceData': relations.get('groupCrime')}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path)
    args = parser.parse_args()
    if args.snapshot:
        envelope = json.loads(args.snapshot.read_text(encoding='utf-8-sig'))
        envelope = {'availability': 'saved_observation',
                    'lastKnownSnapshot': envelope.get('snapshot') or envelope.get('lastKnownSnapshot') or {},
                    'ageSeconds': None}
    else:
        spec = importlib.util.spec_from_file_location('snapshot_reader', Path(__file__).with_name('Read-latest-snapshot.py'))
        reader = importlib.util.module_from_spec(spec); spec.loader.exec_module(reader)
        envelope = reader.read_latest(os.environ.get('ATLAS_DD2_DATA_DIR', ''))
    print(json.dumps(present(envelope), ensure_ascii=False, indent=2))
