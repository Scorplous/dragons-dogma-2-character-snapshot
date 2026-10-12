import sys
from pathlib import Path
from lupa import LuaRuntime
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
base=Path('tests/test_capture.py').read_text().split("setup=r'''")[1].split("'''",1)[0]
gear=r'''
types['app.CharacterID']=typ('app.CharacterID',{field('ch000000_00',num,42,true)})
types['app.Character.JobEnum']=typ('app.Character.JobEnum',{field('VerifiedJobLabel',num,8,true)})
types['app.EquipData.SlotEnum']=typ('app.EquipData.SlotEnum',{
field('Weapon',num,0,true),field('Helm',num,2,true),field('MAX',num,99,true)})
human.get_field=function(self,n)
 for _,f in ipairs(self:get_fields()) do if f:get_name()==n then return f end end
end
function method(n,count,callback) return {get_name=function() return n end,
get_num_params=function() return count end,call=callback} end
function obj(values) return {get_field=function(self,n) return values[n] end} end
item=obj({_Id=1001})
equip=obj({_ItemData=item})
slotMethod=method('get',1,function(self,owner,n) if n==2 then return nil end;return equip end)
equipType=typ('app.EquipData',{});equipType.get_method=function(self,n) if n=='get' then return slotMethod end end
collection={get_type_definition=function() return equipType end}
getEquip=method('getEquipData',1,function(self,owner,id) assert(id==42);return collection end)
itemType=typ('app.ItemManager',{});itemType.get_method=function(self,n) if n=='getEquipData' then return getEquip end end
types['app.ItemManager']=itemType
nameCalls=0
nameMethod=method('getElfItemName',2,function(self,owner,id,elf) assert(id==1001 and elf==false);nameCalls=nameCalls+1;return 'Test Blade' end)
gui=typ('app.GUIBase',{});gui.get_method=function() return nameMethod end;types['app.GUIBase']=gui
sdk.get_managed_singleton=function(n) if n=='app.ItemManager' then return {} end;return manager end
'''
def run(extra=''):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute(base);l.execute(gear);l.execute(extra);l.execute(source)
 l.execute('frame();now=105;frame()')
 w=l.globals().writes
 for i in range(len(w),0,-1):
  if w[i]['data']['captureKind']=='raw_character_fields': return l,w[i]['data']
l,d=run();assert d['equipment']['slots'][1]['itemId']==1001
assert d['equipment']['slots'][1]['name']=='Test Blade'
assert len(d['equipment']['slots'])==2 and d['equipment']['slots'][2]['captureStatus']=='unavailable'
assert d['equipment']['userCrossChecked'] is False
l.execute('now=110;frame()');assert l.globals().nameCalls==1
print('PASS runtime slots, direct item ID/name, null slot, name cache')
_,d=run("types['app.CharacterID']=nil");assert d['equipment']['captureStatus']=='unavailable'
print('PASS absent player identity fails closed')
_,d=run("getEquip.get_num_params=function() return 2 end");assert d['equipment']['captureStatus']=='unavailable'
print('PASS mismatched getter rejected')
_,d=run("nameMethod.call=function() error('name unavailable') end")
assert d['equipment']['slots'][1]['itemId']==1001 and d['equipment']['slots'][1]['name']==None
print('PASS failed name retains raw item ID')
_,d=run("slotMethod.call=function() error('slot failed') end")
assert d['equipment']['slots'][1]['captureStatus']=='error'
print('PASS slot error isolated')
coords=r'''
pos={x=1234.567890123,y=-12.00001234,z=0}
tr={call=function(self,n) assert(n=='get_UniversalPosition');return pos end}
go={call=function(self,n) assert(n=='get_Transform');return tr end}
player.call=function(self,n) assert(n=='get_GameObject');return go end
'''
_,d=run(coords);assert d['position']['x']==1234.567890123 and d['position']['y']==-12.00001234 and d['position']['z']==0
assert d['position']['gameplayStateVerified'] is False
print('PASS player-only coordinates retain precision and zero')
_,d=run(coords+';tr=nil');assert d['position']['captureStatus']=='unavailable'
_,d=run(coords+';player.call=function() error("despawn") end');assert d['position']['captureStatus']=='error'
_,d=run(coords+';manager=nil');assert d['position']['captureStatus']=='unavailable'
print('PASS coordinate missing transform, error and no-player states')
_,d=run(coords+';pos.x=0/0');assert d['position']['captureStatus']=='unavailable'
print('PASS invalid numeric coordinate rejected')
_,d=run("human=typ('app.Human',{field('<JobContext>k__BackingField',typ('app.JobContext',{field('CurrentJob',num,8)}),{})});types['app.Human']=human")
assert d['vocation']['currentJobEnumLabel']=='VerifiedJobLabel'
print('PASS runtime enum resolves vocation without hardcoded mapping')







