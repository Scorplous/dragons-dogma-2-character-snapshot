from pathlib import Path
import sys
from lupa import LuaRuntime
base=Path('tests/test_capture.py').read_text().split("setup=r'''")[1].split("'''",1)[0]
gear=Path('tests/test_gear.py').read_text().split("gear=r'''")[1].split("'''",1)[0]
src=Path('src/AtlasSnapshot-DD2.lua').read_text()
extra=r'''
paramValues={_Id=1001,_PhysicalAttack=204,_MagicAttack=665,_SlashRate=0,_Weight=1.31,_PoisonStore=0}
item=obj(paramValues)
paramType=typ('app.ItemWeaponParam',{})
item.get_type_definition=function() return paramType end
instanceType=typ('app.ItemInstance',{field('_UpgradeCount',num,3),field('_ItemData',paramType,item)})
instanceType.get_methods=function() return {} end
equip=obj({_ItemData=item});equip.get_type_definition=function() return instanceType end
'''
def run(extra2=''):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute(base);l.execute(gear);l.execute(extra);l.execute(extra2);l.execute(src)
 l.execute('frame();now=105;frame()')
 w=l.globals().writes
 for i in range(len(w),0,-1):
  if w[i]['data']['captureKind']=='raw_character_fields':return w[i]['data']['equipment']['slots'][1]
s=run();assert s['itemStats']['baseParameters']['values']['_PhysicalAttack']['value']==204
assert s['itemStats']['baseParameters']['values']['_SlashRate']['value']==0
assert s['itemStats']['baseParameters']['values']['_Weight']['value']==1.31
assert s['itemStats']['effectiveItemStats']['captureStatus']=='unavailable'
assert s['itemStats']['partyAndStorageCounts']['captureStatus']=='unavailable'
print('PASS base numbers and zero retained without inventing final stats/counts')
s=run('paramValues._MagicAttack=nil');assert s['itemStats']['baseParameters']['values']['_MagicAttack']['captureStatus']=='unavailable'
print('PASS missing stat explicit unavailable')
s=run('item.get_field=function(self,n) if n=="_Id" then return 1001 end;error("bad field") end')
assert s['itemStats']['baseParameters']['values']['_PhysicalAttack']['captureStatus']=='error'
assert s['name']=='Test Blade'
print('PASS per-field errors do not lose gear names')





