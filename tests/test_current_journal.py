"""Regressions: never turn canned reports, probes, or ambiguous states into outcomes."""
from pathlib import Path
import runpy
base=runpy.run_path('tests/test_quest_log_evidence.py')
run=base['run']
fixture=r'''
register('app.QuestLogManager.QuestStatus',{field('Progressing',num,1,true),field('Complete',num,2,true)}, {})
local message=exact('getMessage',{'System.Guid'},'System.String',function(o,g) return 'Synthetic '..g end)
message.is_static=function() return true end
register('app.MessageManager',{}, {message})
local m=types['app.GuiManager'].get_methods()[1];local old=m.call
m.call=function(self,o,id)
 local view=old(self,o,id);local get=view.get_field
 view.get_field=function(self,n)
  if n=='<Report>k__BackingField' then return obj({_BaseMsg='completion',_DetailMsg='report'}) end
  if n=='<Impossible>k__BackingField' then return obj({_BaseMsg='Discontinued',_DetailMsg='failure template'}) end
  return get(self,n)
 end
 return view
end
'''
def journal(d):
 j=d['quests']['currentJournal'];assert j is not None,'Missing usable currentJournal view';return j
def capture(edit=''):
 return run(fixture+edit)
_,d=capture();j=journal(d)
assert len(j['records'])==2 and len(j['nativeComplete'])==1 and len(j['nativeProgressing'])==1
assert len(j['unknown'])==0 and j['nativeComplete'][1]['questId']==30100
c=j['nativeComplete'][1];p=j['nativeProgressing'][1]
assert c['completionReport']['base']=='Synthetic completion'
assert p['completionReport']['captureStatus']=='unavailable'
for r in j['records'].values():
 assert r['outcome']=='unknown' and r['impossible'] is None and r['impossibleDetail'] is None
assert j['playthroughScope']=='observed loaded quest journal' and j['currentPlaythroughValidated'] is False
assert j['lifetimeHistoryGuaranteed'] is False and j['absenceMeansNeverCompleted'] is False
assert j['session']==d['session'] and j['capturedAtEpoch']==d['capturedAtEpoch']
assert j['scanComplete'] is True and j['listCount']==2
raw=d['quests']['logStatusEvidence']['records'][1]
assert raw['report']['diagnosticTemplate'] is True and raw['impossible']['diagnosticTemplate'] is True
assert raw['report']['provesOutcome'] is False and raw['impossible']['provesOutcome'] is False
assert raw['reportInterpretation']=='diagnostic templates only; use currentJournal for gated text'
print('PASS ordered membership, native labels, gated reports, raw compatibility and unknown scope')
for edit in ("statusValue=99", "register('app.QuestLogManager.QuestStatus',{field('Complete',num,2,true),field('Alias',num,2,true)}, {})",
             "types['app.QuestLogManager'].get_methods()[2].call=function() return false end",
             "types['app.QuestLogManager'].get_methods()[1].call=function() return true end"):
 _,d=capture(edit);j=journal(d)
 assert len(j['nativeComplete'])==0 and len(j['unknown'])>=1
 for r in j['unknown'].values():assert r['completionReport']['captureStatus']=='unavailable'
_,d=capture('logCount=0');j=journal(d)
assert len(j['records'])==0 and j['scanComplete'] is True and len(j['nativeComplete'])==0
_,d=capture('logCount=600');assert journal(d)['scanComplete'] is False and journal(d)['truncated'] is True
_,d=capture('wrong=true');j=journal(d)
assert j['scanComplete'] is False and len(j['records'])==0 and j['entryErrors']==2
_,d=capture("local m=types['app.GuiManager'].get_methods()[1];local old=m.call;m.call=function(self,o,id) if id==30110 then return nil end;return old(self,o,id) end")
assert journal(d)['scanComplete'] is True, 'Probe failures must not imply missing journal entries'
for edit in ('inGame=false','logChange=true'):
 _,d=capture(edit);j=journal(d);assert j['captureStatus']=='unavailable' and j['records'] is None
l,d=capture();l.execute('manager=nil;now=110;frame()');w=l.globals().writes
assert journal(w[len(w)-1]['data'])['captureStatus']=='unavailable'
print('PASS ambiguous/conflicting states, empty/truncated/error coverage, probe isolation and player loss')
