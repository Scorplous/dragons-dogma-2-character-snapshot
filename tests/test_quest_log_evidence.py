from pathlib import Path
from lupa import LuaRuntime
def block(f,m):return Path('tests/'+f).read_text().split(m+"=r'''")[1].split("'''",1)[0]
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
parts=[block('test_capture.py','setup'),block('test_gear.py','gear'),block('test_effective_stats.py','extra'),block('test_quest_clear_records.py','fixture')]
fixture=r'''
qlm={};logCount=2;logVersion=1;wrong=false;statusValue=2;logChange=false
logItems={get_size=function() return logCount end,get_element=function(self,i) return i==0 and 30040 or 30100+i-1 end}
logList={get_field=function(self,n) return ({_size=logCount,_version=logVersion,_items=logItems})[n] end}
register('app.QuestLogManager',{field('_OrderedQuestList',typ('System.Collections.Generic.List`1<app.QuestDefine.ID>'),logList)}, {
 exact('isQuestLogProgressing',{'app.QuestDefine.ID'},'System.Boolean',function(o,id) return id==30040 end),
 exact('isQuestLogEnd',{'app.QuestDefine.ID'},'System.Boolean',function(o,id) return id~=30040 end)})
register('app.QuestLogManager.QuestStatus',{field('SyntheticProgress',num,1,true),field('SyntheticEnd',num,2,true)}, {})
register('app.GuiManager',{}, {exact('getQuestLog',{'app.QuestDefine.ID'},'app.QuestLogManager.QuestLogViewInfo',function(o,id)
 if logChange then logVersion=logVersion+1 end
 return obj({QuestId=wrong and 999 or id,QuestName='Synthetic '..id,['<Status>k__BackingField']=id==30040 and 1 or statusValue,
 ['<QuestImpossibleDetailMsg>k__BackingField']='Synthetic detail'}) end)})
local old=sdk.get_managed_singleton
sdk.get_managed_singleton=function(n) if n=='app.QuestLogManager' then return qlm end;return old(n) end
'''
def run(edit=''):
 l=LuaRuntime(unpack_returned_tuples=True)
 for p in (*parts,fixture,edit,source):l.execute(p)
 l.execute('frame();now=105;frame()');w=l.globals().writes
 return l,w[len(w)-1]['data']
def evidence(d):
 e=d['quests']['logStatusEvidence'];assert e is not None,'Missing alternative quest-log capture';return e
_,d=run();e=evidence(d)
assert e['scanComplete'] is True and e['semanticsValidated'] is False
r=next(r for r in e['records'].values() if r['questId']==30100)
assert r['rawStatus']==2 and r['statusEnumLabels'][1]=='SyntheticEnd'
assert r['nativeEnded'] is True and r['completionStatus']=='unknown' and r['outcome']=='unknown'
assert e['session']==d['session'] and e['currentPlaythroughValidated'] is False
print('PASS native status/ended evidence never promoted to successful current-run completion')
_,d=run('wrong=true');e=evidence(d)
assert e['entryErrors']>0 and len(e['records'])==0 and e['scanComplete'] is False
_,d=run('logChange=true');assert evidence(d)['captureStatus']=='unavailable'
_,d=run('logCount=600');assert evidence(d)['truncated'] is True and evidence(d)['scanComplete'] is False
_,d=run("types['app.QuestLogManager.QuestStatus']=nil")
assert evidence(d)['records'][1]['rawStatus']==1 and len(evidence(d)['records'][1]['statusEnumLabels'])==0
_,d=run('inGame=false');assert evidence(d)['captureStatus']=='unavailable'
l,d=run();l.execute('manager=nil;now=110;frame()');w=l.globals().writes
assert evidence(w[len(w)-1]['data'])['captureStatus']=='unavailable'
_,d=run('badId=true');h=d['quests']['completedHistory']['rawRecords']
assert h['entryDiagnostics'][1]['slot']==0 and h['entryDiagnostics'][1]['key']==101
assert h['entryDiagnostics'][1]['recordQuestId']==500
print('PASS identities, concurrent list mutation, bounds, missing enum, phase/player loss and entry diagnostics')
_,d=run("local old=logItems.get_element;local reads=0;logItems.get_element=function(self,i) reads=reads+1;if reads>2 and i==0 then return 999 end;return old(self,i) end")
assert evidence(d)['captureStatus']=='unavailable'
_,d=run("local m=types['app.GuiManager'].get_methods()[1];local old=m.call;local reads=0;m.call=function(self,o,id) if id==30100 then reads=reads+1;if reads>1 then statusValue=3 end end;return old(self,o,id) end")
assert evidence(d)['captureStatus']=='unavailable'
_,d=run("local m=types['app.QuestLogManager'].get_methods()[2];local reads=0;m.call=function(self,o,id) if id==30100 then reads=reads+1;return reads==1 end;return true end")
assert evidence(d)['captureStatus']=='unavailable'
report_fixture=r'''
local message=exact('getMessage',{'System.Guid'},'System.String',function(o,g) return 'Localized '..g end)
message.is_static=function() return true end
register('app.MessageManager',{}, {message})
local m=types['app.GuiManager'].get_methods()[1];local old=m.call
m.call=function(self,o,id)
 local view=old(self,o,id);local get=view.get_field
 view.get_field=function(self,n)
  if n=='<Report>k__BackingField' then return obj({_BaseMsg='report-base',_DetailMsg='report-detail'}) end
  if n=='<Impossible>k__BackingField' then error('Synthetic report failure') end
  return get(self,n)
 end
 return view
end
'''
_,d=run(report_fixture);r=evidence(d)['records'][1]
assert r['report']['base']=='Localized report-base' and r['report']['detail']=='Localized report-detail'
assert r['impossible']['captureStatus']=='unavailable' and r['rawStatus']==1
print('PASS same-version IDs, status/ended mutation, report localization and report-error isolation')
