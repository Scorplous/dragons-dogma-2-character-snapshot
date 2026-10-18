from pathlib import Path
from lupa import LuaRuntime
def block(file, marker): return Path('tests/'+file).read_text().split(marker+"=r'''")[1].split("'''",1)[0]
base=block('test_capture.py','setup'); gear=block('test_gear.py','gear'); extra=block('test_effective_stats.py','extra')
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
fixture=r'''
item=obj({_Id=1001,_PhysicalAttack=17})
item.get_type_definition=function() return typ('app.ItemCommonParam') end
count=2; version=1; owner=65535; badId=false; badQuantity=false; duplicateStorageId=false
local sd=types['app.ItemDefine.StorageData']
function makeStored(i)
 local values={_ItemId=badId and 999 or 1001,_StorageId=duplicateStorageId and 1 or i,_Num=badQuantity and -1 or i,_CharaId=owner,_IsEquipped=false,_ItemData=item}
 local s=obj(values);s.get_type_definition=function() return sd end
 s.call=function(self,n) if n=='makeEnhancedParam()' then return enhanced end;if n=='calcWeightPerPiece()' then return 127 end end
 return obj({_Param=s})
end
array={get_size=function() return count end,get_element=function(self,i) return makeStored(i+1) end}
listType=typ('System.Collections.Generic.List`1<app.ItemManager.StorageMasterData>',{})
listType.get_field=function(self,n)
 if n=='_size' then return field(n,num,count) end
 if n=='_version' then return field(n,num,version) end
 if n=='_items' then return field(n,typ('app.ItemManager.StorageMasterData[]'),array) end
end
list={get_type_definition=function() return listType end}
storageGetter=exact('getStorageMasterList',{'app.CharacterID'},'System.Collections.Generic.List`1<app.ItemManager.StorageMasterData>',function(o,id) assert(id==65535);return list end)
itemType.get_methods=function() return {storageGetter} end
'''
def run(edit=''):
 l=LuaRuntime(unpack_returned_tuples=True)
 for s in (base,gear,extra,fixture,edit,source): l.execute(s)
 l.execute('frame();now=105;frame()')
 w=l.globals().writes; return l,w[len(w)-1]['data']
l,d=run();s=d['storage']
assert s is not None, 'Storage section missing'
assert s['scanComplete'] is True and len(s['records'])==2
assert s['records'][1]['name']=='Test Blade' and s['records'][2]['quantity']==2
assert s['records'][1]['storageId']!=s['records'][2]['storageId']
assert s['records'][1]['effectiveItemStats']['fields'][2]['value']==443
print('PASS stored copies, quantities and enhanced stats remain separate from equipped gear')
for edit in ['owner=42','badId=true','badQuantity=true']:
 l,d=run(edit);assert len(d['storage']['records'])==0 and d['storage']['scanComplete'] is False
 assert d['equipment']['slots'][1]['name']=='Test Blade'
print('PASS wrong owner, mismatched item identity and invalid quantity rejected without losing gear')
l,d=run('count=70');assert len(d['storage']['records'])==32 and d['storage']['scanComplete'] is False
l.execute('now=110;frame()');w=l.globals().writes;assert len(w[len(w)-1]['data']['storage']['records'])==64
l.execute('now=115;frame()');w=l.globals().writes;s=w[len(w)-1]['data']['storage'];assert len(s['records'])==70 and s['scanComplete'] is True
print('PASS storage scan spreads bounded batches over updates')
l,d=run('count=70');l.execute('version=2;count=1;now=110;frame()');w=l.globals().writes;s=w[len(w)-1]['data']['storage']
assert len(s['records'])==1 and s['scanComplete'] is True
l.execute('manager=nil;now=115;frame()');w=l.globals().writes;assert w[len(w)-1]['data']['storage']['captureStatus']=='unavailable'
print('PASS list mutation resets accumulated rows; player loss clears current storage')
l,d=run("storageGetter.get_return_type=function() return typ('System.Void') end")
assert d['storage']['captureStatus']=='unavailable' and 'getStorageMasterList' not in list(l.globals().invoked.values())
print('PASS wrong native signature never invoked')
l,d=run('count=0');assert d['storage']['scanComplete'] is True and len(d['storage']['records'])==0
print('PASS verified empty list distinguished from unavailable storage')
l,d=run('duplicateStorageId=true');s=d['storage']
assert len(s['records'])==2 and s['scanComplete'] is True
assert s['records'][1]['recordIndex']!=s['records'][2]['recordIndex']
assert s['records'][2]['storageIdRepeated'] is True
print('PASS repeated storage IDs preserve distinct raw list rows and quantities')
