from pathlib import Path
import sys
from lupa import LuaRuntime
base=Path('tests/test_capture.py').read_text().split("setup=r'''")[1].split("'''",1)[0]
gear=Path('tests/test_gear.py').read_text().split("gear=r'''")[1].split("'''",1)[0]
extra=Path('tests/test_effective_stats.py').read_text().split("extra=r'''")[1].split("'''",1)[0]
npcs=Path('tests/test_npc_capture.py').read_text().split("npcs=r'''")[1].split("'''",1)[0]
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
more=r'''
mainPawn={}; cachedCharacter={}; mainContext=obj({_FavorabilityRating=0,_AccumulatedFavorability=75.5})
register('app.PawnManager',{field('_MainPawn',typ('app.Pawn'),mainPawn)}, {})
register('app.Pawn',{field('MainPawnDataContext',typ('app.MainPawnDataContext'),mainContext), field('<CachedCharacter>k__BackingField',typ('app.Character'),cachedCharacter)}, {})
register('app.Character',{}, {exact('get_CharaID',{},'app.CharacterID',function(owner) assert(owner==cachedCharacter);return 123 end)})
local oldfield=human.get_field
human.get_field=function(self,n) if n=='<PawnDataContext>k__BackingField' then return {get_data=function(self,owner) error('Human field accessed on non-Human Pawn component') end} end return oldfield(self,n) end
historyType=typ('System.Collections.Generic.List`1<app.NPCManager.NPCHistory>',{})
historyType.get_method=function(self,n)
 if n=='get_Count' then return method(n,0,function() return 200 end) end
 if n=='get_Item' then return method(n,1,function(self,owner,index) return obj({_CharaID=91,_Flag=8}) end) end
end
historyList={get_type_definition=function() return historyType end}
local originalGet=npcmanager.get_field
npcmanager.get_field=function(self,n) if n=='_NPCHistoryList' then return historyList end;return originalGet(self,n) end
'''
def run(edit=''):
 l=LuaRuntime(unpack_returned_tuples=True)
 for s in (base,gear,extra,npcs,more,edit,source):l.execute(s)
 l.execute('frame();now=105;frame()');w=l.globals().writes
 return w[len(w)-1]['data']
d=run();p=d['relationships']['mainPawnAffinity']
assert p['characterId']==123, 'Pawn component must use its cached Character for identity'
assert p['name'] is None, 'Do not invent a pawn name without a validated name path'
assert p['favorabilityRating']==0 and p['accumulatedFavorability']==75.5
assert p['semanticsValidated'] is False
h=d['npcLifeObservations']['retainedHistoryEvidence']
assert h['truncated'] is True and len(h['records'])==128
assert h['records'][1]['rawFlags']==8 and h['playerAttributionVerified'] is False
assert h['historicalEventLocationAvailable'] is False
print('PASS main-pawn identity, real zero and fractional values; bounded historical flags with no invented cause/location')
d=run("types['app.PawnManager']=nil;historyList=nil")
assert d['relationships']['mainPawnAffinity']['captureStatus']=='unavailable'
assert d['npcLifeObservations']['retainedHistoryEvidence']['captureStatus']=='unavailable'
assert d['equipment']['slots'][1]['name']=='Test Blade'
print('PASS absent pawn/history isolated from NPC and equipment capture')

d=run("types['app.Character']=nil")
p=d['relationships']['mainPawnAffinity']
assert p['favorabilityRating']==0 and p['accumulatedFavorability']==75.5
assert p['characterId'] is None and p['identityEvidence']['reason']
print('PASS unavailable optional Character identity does not discard favorability')
