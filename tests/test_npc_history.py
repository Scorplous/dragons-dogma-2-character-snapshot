import importlib.util
import json
import tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('journal','tools/NPC-history.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
with tempfile.TemporaryDirectory() as directory:
 p=Path(directory)/'history.jsonl'
 s={'session':'run1','sequence':1,'capturedAtUtc':'2026-10-12T12:00:00Z',
    'npcLifeObservations':{'captureStatus':'partial','records':[]}}
 def record(**changes):
  return dict(characterId=44,name='Test NPC',identityVerified=True,stateVerified=True,
              importantVerified=True,state='dead',provenance='verified test source',**changes)
 s['npcLifeObservations']['records']=[record()]
 mod.ingest(s,p);first=p.read_bytes();mod.ingest(s,p);assert p.read_bytes()==first
 s['sequence']=2;mod.ingest(s,p);assert p.read_bytes()==first
 assert not any(x['kind']=='player_kill' for x in map(json.loads,p.read_text().splitlines()))
 print('PASS observed death is not player kill; repeated five-second observations deduplicate')
 s['sequence']=3;s['npcLifeObservations']['records']=[record(cause='player',playerAttributionVerified=True,sourceEventId='event1',attributionProvenance='verified attacker event')]
 mod.ingest(s,p);s['sequence']=4;mod.ingest(s,p)
 events=list(map(json.loads,p.read_text().splitlines()));assert sum(x['kind']=='player_kill' for x in events)==1
 print('PASS verified player event recorded once with identity and attribution provenance')
 s['sequence']=5;s['npcLifeObservations']['records'][0]['state']='alive';mod.ingest(s,p)
 assert json.loads(p.read_text().splitlines()[-1])['transition']=='dead_to_alive'
 assert json.loads(p.read_text().splitlines()[-1])['resurrectionVerified'] is False
 print('PASS dead-to-alive retained without inventing resurrection cause')
 before=p.read_bytes();s['sequence']=2;s['npcLifeObservations']['records'][0]['state']='dead'
 assert mod.ingest(s,p)['status']=='unavailable';assert p.read_bytes()==before
 print('PASS older snapshot cannot reverse later observed state')
 before=p.read_bytes();s['sequence']=6;s['npcLifeObservations']['records']=[];mod.ingest(s,p);assert p.read_bytes()==before
 s['npcLifeObservations']['records']=[record()];s['npcLifeObservations']['records'][0]['identityVerified']=False
 mod.ingest(s,p);assert p.read_bytes()==before
 print('PASS missing/unloaded or unverified NPC never becomes death evidence')
 s['session']='run2';s['sequence']=1;s['npcLifeObservations']['records']=[record()];mod.ingest(s,p)
 assert p.read_bytes().startswith(before)
 events=list(map(json.loads,p.read_text().splitlines()));assert events[-2]['kind']=='world_boundary'
 assert events[-1]['transition']=='first_observed_dead'
 assert sum(x['kind']=='player_kill' for x in events)==1
 print('PASS new run preserves history, invalidates prior current-world state, never invents another kill')
 s['sequence']=2;s['position']={'x':999,'y':999,'z':999}
 s['npcLifeObservations']['records']=[record(cause='player',playerAttributionVerified=True,sourceEventId='event2',attributionProvenance='test attacker',observationLocation={'verified':True,'provenance':'corpse observation','coordinates':{'x':1,'y':2,'z':3}})]
 mod.ingest(s,p);events=list(map(json.loads,p.read_text().splitlines()))
 kill=[e for e in events if e['kind']=='player_kill'][-1]
 assert kill['eventLocation']['captureStatus']=='unavailable'
 s['sequence']=3;s['npcLifeObservations']['records'][0]['sourceEventId']='event3'
 s['npcLifeObservations']['records'][0]['eventLocation']={'verified':True,'provenance':'event payload','coordinates':{'x':0,'y':2,'z':3},'regionName':'Test region'}
 mod.ingest(s,p);events=list(map(json.loads,p.read_text().splitlines()))
 kill=[e for e in events if e['kind']=='player_kill'][-1]
 assert kill['eventLocation']['coordinates']['x']==0 and kill['eventLocation']['regionName']=='Test region'
 print('PASS kill-event location preserved; no backfill from current player/corpse location')
