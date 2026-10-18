from pathlib import Path
from lupa import LuaRuntime

def block(file, marker):
    return Path('tests/'+file).read_text().split(marker+"=r'''")[1].split("'''",1)[0]

base=block('test_capture.py','setup'); gear=block('test_gear.py','gear')
extra=block('test_effective_stats.py','extra'); storage=block('test_storage_capture.py','fixture')
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
fixture=r'''
playerCharacter={}; playerId=42; queriedOwner=65535; wrongOwner=false; equippedRow=false
register('app.Character',{}, {exact('get_CharaID',{},'app.CharacterID',function() return playerId end)})
local oldField=human.get_field
human.get_field=function(self,n)
 if n=='<Chara>k__BackingField' then local f=field(n,typ('app.Character'),playerCharacter);f.get_data=function() return playerCharacter end;return f end
 return oldField(self,n)
end
local oldMake=makeStored
makeStored=function(i)
 owner=wrongOwner and queriedOwner==42 and 77 or queriedOwner
 local row=oldMake(i)
 if equippedRow and queriedOwner==42 and i==1 then
  local data=row:get_field('_Param');local get=data.get_field
  data.get_field=function(self,n) if n=='_IsEquipped' then return true end;return get(self,n) end
 end
 return row
end
storageGetter.call=function(self,o,id) queriedOwner=id;return list end
'''
def run(edit=''):
    l=LuaRuntime(unpack_returned_tuples=True)
    for part in (base,gear,extra,storage,fixture,edit,source): l.execute(part)
    l.execute('frame();now=105;frame()')
    return l, latest(l)
def latest(l):
    w=l.globals().writes; return w[len(w)-1]['data']

l,d=run('equippedRow=true')
assert d['inventory']['ownerId']==42, 'Player backpack is not scanned'
assert d['inventory']['scanComplete'] is True and len(d['inventory']['records'])==1
assert len(d['storage']['records'])==2 and d['storage']['ownerId']==65535
print('PASS player carried items exclude equipment and stay separate from inn storage')
l,d=run('wrongOwner=true')
assert len(d['inventory']['records'])==0 and d['inventory']['entryErrors']==2
assert d['inventory']['scanComplete'] is False and d['storage']['scanComplete'] is True
print('PASS another owner cannot become player inventory; inn results survive')
l,d=run('count=70')
assert len(d['inventory']['records'])==32 and d['inventory']['scanComplete'] is False
l.execute('now=110;frame()'); assert len(latest(l)['inventory']['records'])==64
l.execute('now=115;frame()'); assert latest(l)['inventory']['scanComplete'] is True
assert latest(l)['storage']['scanComplete'] is True
print('PASS player scan progresses despite unavailable party, alongside inn scan')
l,d=run('count=70')
l.execute('playerCharacter={};now=110;frame()')
assert len(latest(l)['inventory']['records'])==32
l.execute('playerId=77;now=115;frame()'); assert latest(l)['inventory']['captureStatus']=='unavailable'
l.execute('playerId=42;now=120;frame()'); assert len(latest(l)['inventory']['records'])==32
l.execute('manager=nil;now=125;frame()'); assert latest(l)['inventory']['captureStatus']=='unavailable'
l.execute('manager={};now=130;frame()'); assert len(latest(l)['inventory']['records'])==32
l2,d2=run('count=70'); assert len(d2['inventory']['records'])==32
print('PASS character changes, identity gaps, player loss and new Lua sessions reset player scans')
l,d=run("types['app.CharacterID']=nil")
assert d['inventory']['captureStatus']=='unavailable' and d['storage']['scanComplete'] is True
print('PASS missing player identity fails closed without losing storage')


# Exercise all three ownership domains in one export, including roster cleanup.
l=LuaRuntime(unpack_returned_tuples=True)
party=block('test_party_capture.py','fixture')
for part in (base,gear,extra,storage,party,fixture): l.execute(part)
l.execute(r'''
register('app.Character',{}, {exact('get_CharaID',{},'app.CharacterID',function(o) return o==playerCharacter and playerId or pid end)})
local hf=human.get_field
human.get_field=function(self,n)
 if n=='<Chara>k__BackingField' then local f=field(n,typ('app.Character'),pc);f.get_data=function(self,o) return o==player and playerCharacter or pc end;return f end
 return hf(self,n)
end
''')
l.execute(source);l.execute('frame();now=105;frame()');d=latest(l)
assert d['inventory']['ownerId']==42 and d['storage']['ownerId']==65535
assert d['party']['records'][1]['carriedInventory']['ownerId']==77
assert len(d['inventory']['records'])==2 and len(d['party']['records'][1]['carriedInventory']['records'])==2
print('PASS player backpack, pawn bag and inn storage coexist under distinct verified owners')

