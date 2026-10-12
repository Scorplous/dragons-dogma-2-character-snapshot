import importlib.util,json,tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('reader','tools/Read-latest-snapshot.py')
reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)
with tempfile.TemporaryDirectory() as d:
 p=Path(d);idx={'file':'AtlasSnapshot-DD2-slot-1.json','session':'test','sequence':1,'capturedAtEpoch':100}
 data=dict(idx,captureStatus='partial');data.pop('file')
 (p/idx['file']).write_text(json.dumps(data));(p/'AtlasSnapshot-DD2-latest.json').write_text(json.dumps(idx))
 assert reader.read_latest(p,101)['availability']=='recent_unverified_observation'
 assert reader.read_latest(p,101)['currentValuesAvailable'] is False
 assert reader.read_latest(p,120)['availability']=='stale'
 assert reader.read_latest(p,99)['availability']=='stale'
 data['sequence']=2;(p/idx['file']).write_text(json.dumps(data))
 assert reader.read_latest(p,101)['availability']=='unavailable'
 (p/idx['file']).write_text('{')
 assert reader.read_latest(p,101)['availability']=='unavailable'
 (p/'AtlasSnapshot-DD2-latest.json').write_text('{')
 assert reader.read_latest(p,101)['availability']=='unavailable'
print('PASS recent observation, stale age, future timestamp, sequence mismatch, partial slot, partial pointer')
