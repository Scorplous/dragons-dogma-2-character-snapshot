from pathlib import Path
import sys
from lupa import LuaRuntime
fixture=Path('tests/test_effective_stats.py').read_text()
base=Path('tests/test_capture.py').read_text().split("setup=r'''")[1].split("'''",1)[0]
gear=Path('tests/test_gear.py').read_text().split("gear=r'''")[1].split("'''",1)[0]
extra=fixture.split("extra=r'''")[1].split("'''",1)[0]
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
npcs=r'''
npcdata=obj({ID=91,Unique=1,Group=2,CrimeGroup=2})
sentiment=obj({Value=0,Rank=3})
holderValues={CharaID=91,SentimentToPlayer=sentiment,RevivedCount=2}
npcholder=obj(holderValues)
npcarray={get_size=function() return 300 end,get_element=function(self,i) if i%2==0 then return npcholder end end}
npcmanager=obj({NPCHolderDic=npcarray})
register('app.NPCManager',{}, {
 exact('getNPCData',{'app.CharacterID'},'app.CharacterData',function(self,id) assert(self==npcmanager and id==91);return npcdata end),
 exact('isNPCQuestLayer',{'app.CharacterID'},'System.Boolean',function() return true end)})
register('app.CharacterData',{}, {exact('get_Name',{},'System.String',function() return 'Test NPC' end)})
deadValue=true
register('app.NPCHolder',{}, {exact('isFlagDeadOrCoffin',{},'System.Boolean',function() return deadValue end)})
local original=sdk.get_managed_singleton
sdk.get_managed_singleton=function(n) if n=='app.NPCManager' then return npcmanager end;return original(n) end
'''
def run(edit=''):
 l=LuaRuntime(unpack_returned_tuples=True)
 for s in (base,gear,extra,npcs,edit,source):l.execute(s)
 l.execute('frame();now=105;frame()');w=l.globals().writes
 return l,w[len(w)-1]['data']
l,d=run();r=d['relationships'];life=d['npcLifeObservations']
assert r['records'][1]['name']=='Test NPC' and r['records'][1]['rawAffinity']['value']==0
assert r['completeRoster'] is False and r['absenceMeansZero'] is False
assert r['batch']['scanned']<=128 and len(r['records'])<=32
assert life['records'][1]['state']=='dead' and life['records'][1]['playerAttributionVerified'] is False
assert life['records'][1]['eventLocation']['captureStatus']=='unavailable'
print('PASS verified NPC identity/name, real zero sentiment, bounded coverage, death not player-attributed')
_,d=run('holderValues.SentimentToPlayer=nil')
assert d['relationships']['records'][1]['rawAffinity']['captureStatus']=='unavailable'
print('PASS missing sentiment is unavailable, never zero')
_,d=run('deadValue=false')
assert len(d['npcLifeObservations']['records'])==0
assert d['relationships']['records'][1]['lifeState']['captureStatus']=='unavailable'
print('PASS false death flag plus unloaded entity not fabricated alive/dead')
_,d=run('npcdata=obj({ID=92})')
assert len(d['relationships']['records'])==0
print('PASS mismatched CharacterData identity rejected')
_,d=run("npcholder.get_field=function(self,n) if n=='SentimentToPlayer' then error('despawn') end;return holderValues[n] end")
assert d['relationships']['entryErrors']>0 and d['equipment']['slots'][1]['name']=='Test Blade'
print('PASS NPC record exceptions isolated from working equipment')
l,d=run();start=d['relationships']['batch']['nextIndex'];l.execute('now=110;frame()');w=l.globals().writes
assert w[len(w)-1]['data']['relationships']['batch']['startIndex']==start
print('PASS bounded rotating scan advances without claiming complete coverage')

