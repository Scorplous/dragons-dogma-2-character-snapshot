from pathlib import Path
from lupa import LuaRuntime

def block(file, marker):
    return Path('tests/'+file).read_text().split(marker+"=r'''")[1].split("'''",1)[0]
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
parts=[block('test_capture.py','setup'),block('test_gear.py','gear'),
       block('test_effective_stats.py','extra')]
fixture=r'''
function obj(t) return {get_field=function(self,n) return t[n] end} end
count=3;free=1;version=1;change=false;badId=false;badCount=false;missingTitle=false
rows={obj({next=-1,key=101,value=obj({_QuestID=101,_ClearCount=2})}),
      obj({next=-2,key=999,value=obj({_QuestID=999,_ClearCount=10})}),
      obj({next=-1,key=102,value=obj({_QuestID=102,_ClearCount=0})})}
entries={get_size=function() return count end,get_element=function(self,i)
 if change then version=version+1 end
 if badId and i==0 then return obj({next=-1,key=101,value=obj({_QuestID=500,_ClearCount=2})}) end
 if badCount and i==0 then return obj({next=-1,key=101,value=obj({_QuestID=101,_ClearCount=-1})}) end
 if not rows[i+1] then rows[i+1]=obj({next=-1,key=1000+i,value=obj({_QuestID=1000+i,_ClearCount=1})}) end
 return rows[i+1] end}
dict={get_field=function(self,n) return ({_count=count,_freeCount=free,_version=version,_entries=entries})[n] end}
qm={};flow={};gui={};inGame=true
register('app.QuestManager',{field('QuestClearRecordDict',typ('System.Collections.Generic.Dictionary`2<System.Int32,app.QuestManager.QuestClearRecordData>'),dict)}, {})
register('app.MainFlowManager',{}, {exact('get_IsInGamePhase',{},'System.Boolean',function() return inGame end)})
register('app.GuiManager',{}, {exact('getQuestLog',{'app.QuestDefine.ID'},'app.QuestLogManager.QuestLogViewInfo',function(o,id)
 return obj({QuestId=missingTitle and 999 or id,QuestName='Synthetic Quest '..id}) end)})
local prev=sdk.get_managed_singleton
sdk.get_managed_singleton=function(n)
 if n=='app.QuestManager' then return qm elseif n=='app.MainFlowManager' then return flow elseif n=='app.GuiManager' then return gui end
 return prev(n) end
'''
def run(edit=''):
    l=LuaRuntime(unpack_returned_tuples=True)
    for p in (*parts,fixture,edit,source): l.execute(p)
    l.execute('frame();now=105;frame()')
    return l,latest(l)
def latest(l):
    w=l.globals().writes
    return w[len(w)-1]['data']
def history(d):
    h=d['quests']['completedHistory']
    assert h is not None, 'Quest clear capture is missing'
    return h
l,d=run();h=history(d)
assert h['rawRecords']['scanComplete'] is True
assert len(h['rawRecords']['records'])==2
assert h['rawRecords']['records'][1]['rawClearCount']==2
assert h['rawRecords']['records'][2]['rawClearCount']==0
assert h['rawRecords']['records'][1]['title']=='Synthetic Quest 101'
assert h['captureStatus']=='partial' and h['currentPlaythrough']['captureStatus']=='unavailable'
assert h['previousCycles']['captureStatus']=='unavailable' and h['semanticsValidated'] is False
assert h['absenceMeansNeverCompleted'] is False and h['favorableOutcomeInferred'] is False
assert h['session']==d['session'] and h['capturedAtEpoch']==d['capturedAtEpoch']
print('PASS raw clears/zero retained, removed entries skipped, NG+ and outcome claims withheld')
for edit in ('badId=true','badCount=true'):
    _,d=run(edit);h=history(d)
    assert h['rawRecords']['scanComplete'] is False and h['rawRecords']['entryErrors']==1
    assert len(h['rawRecords']['records'])==1
print('PASS wrong record identity and invalid count rejected')
for edit in ('change=true','inGame=false','dict=nil','count=-1','free=4'):
    if edit=='dict=nil': edit="types['app.QuestManager']=nil"
    _,d=run(edit);h=history(d)
    assert h['captureStatus']=='unavailable', edit
    assert h['rawRecords'] is None, edit
print('PASS changing dictionary, absent source, bad bounds and menu phase fail closed')
_,d=run('missingTitle=true');r=history(d)['rawRecords']['records'][1]
assert r['questId']==101 and r['title'] is None and r['titleStatus']=='unavailable'
_,d=run('count=0;free=0;entries=nil');h=history(d)
assert h['rawRecords']['scanComplete'] is True and len(h['rawRecords']['records'])==0
assert h['currentPlaythrough']['captureStatus']=='unavailable'
_,d=run('count=600;free=1');h=history(d)
assert h['rawRecords']['truncated'] is True and h['rawRecords']['scanComplete'] is False
assert h['rawRecords']['examinedSlots']==512
l,d=run();l.execute('manager=nil;now=110;frame()');h=history(latest(l))
assert h['captureStatus']=='unavailable' and h['rawRecords'] is None
print('PASS missing localization, empty records, bounded scans and no-player freshness')
_,d=run("local old=entries.get_element;local reads=0;entries.get_element=function(self,i) reads=reads+1;if reads==4 then rows[1]=obj({next=-1,key=101,value=obj({_QuestID=101,_ClearCount=3})}) end;return old(self,i) end")
assert history(d)['captureStatus']=='unavailable'
for mutation in ("rows[1]=obj({next=-2,key=101,value=obj({_QuestID=101,_ClearCount=2})})",
                 "rows[1]:get_field('value').get_field=function(self,n) return ({_QuestID=101,_ClearCount=3})[n] end"):
    _,d=run("local old=entries.get_element;local reads=0;entries.get_element=function(self,i) reads=reads+1;if reads==4 then "+mutation+" end;return old(self,i) end")
    assert history(d)['captureStatus']=='unavailable'
_,d=run("types['app.MainFlowManager']=nil")
assert history(d)['captureStatus']=='unavailable'
print('PASS same-version record replacement and missing exact phase method fail closed')
