from pathlib import Path
from lupa import LuaRuntime
def block(file, marker): return Path('tests/'+file).read_text().split(marker+"=r'''")[1].split("'''",1)[0]
base=block('test_capture.py','setup');gear=block('test_gear.py','gear');extra=block('test_effective_stats.py','extra')
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
fixture=r'''
pawn={};pc={};ph={};partyCount=1;partyVersion=1;pid=77;humanId=77;equipOwner=77
ctx=obj({_Name='Synthetic Pawn',_PossessionLv=0})
register('app.Pawn',{field('<CachedCharacter>k__BackingField',typ('app.Character'),pc),field('<CachedHuman>k__BackingField',typ('app.Human'),ph),field('CachedContextHolder',typ('app.ContextHolder'),{})}, {})
register('app.Character',{}, {exact('get_CharaID',{},'app.CharacterID',function(o) return o==pc and pid or humanId end)})
register('app.ContextHolder',{}, {exact('getContext',{},'app.PawnDataContext',function() return ctx end)})
local previousHumanField=human.get_field
human.get_field=function(self,n)
 if n=='<Chara>k__BackingField' then return field(n,typ('app.Character'),{}) end
 return previousHumanField(self,n)
end
partyArray={get_size=function() return partyCount end,get_element=function(self,i) return pawn end}
partyType=typ('System.Collections.Generic.List`1<app.Pawn>')
partyType.get_field=function(self,n)
 if n=='_size' then return field(n,num,partyCount) end
 if n=='_items' then return field(n,typ('app.Pawn[]'),partyArray) end
 if n=='_version' then local f=field(n,num,partyVersion);f.get_data=function() return partyVersion end;return f end
end
partyList={get_type_definition=function() return partyType end}
register('app.PawnManager',{field('_MainPawn',typ('app.Pawn'),pawn)}, {exact('get_PartyPawnList',{},'System.Collections.Generic.List`1<app.Pawn>',function() return partyList end)})
local priorGetEquip=getEquip.call
getEquip.call=function(self,o,id) if id==77 then return collection end;return priorGetEquip(self,o,id) end
local priorItemField=equip.get_field
equip.get_field=function(self,n) if n=='_CharaId' then return equipOwner end;return priorItemField(self,n) end
'''
def run(edit=''):
 l=LuaRuntime(unpack_returned_tuples=True)
 for s in (base,gear,extra,fixture,edit,source):l.execute(s)
 l.execute('frame();now=105;frame()');w=l.globals().writes;return l,w[len(w)-1]['data']
l,d=run();p=d['party'];assert p is not None,'Party section missing'
assert p['rosterComplete'] is True and len(p['records'])==1
r=p['records'][1];assert r['characterId']==77 and r['name']=='Synthetic Pawn' and r['role']=='main pawn'
assert r['equipment']['slots'][1]['name']=='Test Blade'
assert r['dragonsplague']['rawPossessionLevel']==0 and r['dragonsplague']['status']=='unknown'
assert r['inclination']['captureStatus']=='unavailable'
assert r['carriedInventory']['captureStatus']=='unavailable'
print('PASS current pawn identity, owned gear, name and raw plague zero without clean-health inference')
l,d=run('humanId=88');r=d['party']['records'][1]
assert r['skills']['captureStatus']=='unavailable' and r['equipment']['slots'][1]['name']=='Test Blade'
print('PASS Human identity mismatch blocks skills without losing independently verified gear')
l,d=run('equipOwner=88');assert d['party']['records'][1]['equipment']['slots'][1]['name'] is None
print('PASS another owner equipment cannot be attributed to pawn')
l,d=run('partyCount=4');assert d['party']['rosterComplete'] is False and len(d['party']['records'])<=3
l,d=run('partyCount=2');assert d['party']['rosterComplete'] is False
l,d=run('partyCount=0');assert d['party']['rosterComplete'] is True and len(d['party']['records'])==0
l.execute('manager=nil;now=110;frame()');w=l.globals().writes;assert w[len(w)-1]['data']['party']['captureStatus']=='unavailable'
print('PASS bounded party roster, duplicate identity rejection, empty party and player loss')

l,d=run("ctx=obj({_Name='Synthetic Pawn',_PossessionLv=9,_Personality=2}); types['app.PersonalityDefine.PersonalityID']=typ('app.PersonalityDefine.PersonalityID',{field('RuntimePersonality',num,2,true)})")
r=d['party']['records'][1]
assert r['inclination']['rawId']==2 and r['inclination']['enumLabel']=='RuntimePersonality'
assert r['dragonsplague']['status']=='unknown' and r['dragonsplague']['transmissionConfirmed'] is False
print('PASS runtime inclination enum and positive raw sickness never imply confirmed spread')

# Exercise carried scans with the same native list shape as inn storage.
storageFixture=block('test_storage_capture.py','fixture')
l=LuaRuntime(unpack_returned_tuples=True)
for part in (base,gear,extra,fixture,storageFixture,"owner=77; count=70; storageGetter.call=function(self,o,id) if id==77 then return list end end",source):l.execute(part)
l.execute('frame();now=105;frame()');w=l.globals().writes;d=w[len(w)-1]['data']
assert len(d['party']['records'][1]['carriedInventory']['records'])==32
l.execute('now=110;frame();now=115;frame()');w=l.globals().writes;c=w[len(w)-1]['data']['party']['records'][1]['carriedInventory']
assert c['scanComplete'] is True and len(c['records'])==70
print('PASS pawn carried inventory progresses in bounded owner-specific batches')

l.execute('count=70; now=120;frame(); partyCount=0;now=125;frame(); partyCount=1;now=130;frame()');w=l.globals().writes
assert len(w[len(w)-1]['data']['party']['records'][1]['carriedInventory']['records'])==32
print('PASS leaving and rejoining roster clears carried scan')
l,d=run("partyVersion=1; getEquip.call=function(self,o,id) partyVersion=2;return collection end")
assert d['party']['captureStatus']=='unavailable'
print('PASS roster mutation discards captured party')

l,d=run("pid=-1294967295; humanId=pid; equipOwner=pid; getEquip.call=function(self,o,id) return collection end")
assert len(d['party']['records'])==1 and d['party']['records'][1]['characterId']==-1294967295
print('PASS synthetic signed CharacterID accepted')

l=LuaRuntime(unpack_returned_tuples=True)
for part in (base,gear,extra,fixture,storageFixture,"owner=77;count=70;storageGetter.call=function(self,o,id) if id==77 then return list end end",source):l.execute(part)
l.execute('frame();now=105;frame();partyCount=17;now=110;frame();partyCount=1;now=115;frame()');w=l.globals().writes
assert len(w[len(w)-1]['data']['party']['records'][1]['carriedInventory']['records'])==32
l.execute("partyType.get_full_name=function() error('roster lost') end;now=120;frame();partyType.get_full_name=function() return 'System.Collections.Generic.List`1<app.Pawn>' end;now=125;frame()")
w=l.globals().writes
assert len(w[len(w)-1]['data']['party']['records'][1]['carriedInventory']['records'])==32
print('PASS invalid and throwing roster gaps discard carried caches')

l,d=run("pid=3000000001; humanId=pid; equipOwner=pid; getEquip.call=function(self,o,id) return collection end")
assert len(d['party']['records'])==1 and d['party']['records'][1]['characterId']==3000000001
print('PASS synthetic unsigned CharacterID retained without reinterpretation')
