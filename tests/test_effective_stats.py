from pathlib import Path
import sys
from lupa import LuaRuntime
base=Path('tests/test_capture.py').read_text().split("setup=r'''")[1].split("'''",1)[0]
gear=Path('tests/test_gear.py').read_text().split("gear=r'''")[1].split("'''",1)[0]
source=Path(sys.argv[1] if len(sys.argv)>1 else 'src/AtlasSnapshot-DD2.lua').read_text()
extra=r'''
invoked={}
function exact(n,args,ret,fn)
 return {get_name=function() return n end,get_num_params=function() return #args end,
 get_param_types=function() local p={} for _,a in ipairs(args) do p[#p+1]=typ(a) end return p end,
 get_return_type=function() return typ(ret) end,is_static=function() return false end,
 call=function(self,owner,...) invoked[#invoked+1]=n;return fn(owner,...) end}
end
function register(n,fs,ms)
 local t=typ(n,fs);t.get_methods=function() return ms end;types[n]=t;return t
end
enhanced={};total={};basic={};holderObject={};calculator=obj({CharaID=42,Human=player})
enhancedType=register('app.EquipParam',{field('SampleAttack',num,17),field('SampleMagic',num,443)}, {})
register('app.PlayerAttackDefenceStatus',{field('SampleAttack',num,219),field('SampleMagic',num,702)}, {})
register('app.PlayerBasicAttackDefenceStatus',{field('SampleAttack',num,202)}, {})
enhanceMethod=exact('makeEnhancedParam',{},'app.EquipParam',function(owner) assert(owner==equip);return enhanced end)
weightMethod=exact('calcWeightPerPiece',{},'System.Int32',function(owner) assert(owner==equip);return 127 end)
elementMethod=exact('get_WeaponElement',{},'app.AttackUserData.ElementType',function(owner) return 0 end)
storage=register('app.ItemDefine.StorageData',{}, {enhanceMethod,weightMethod,elementMethod})
equip.get_type_definition=function() return storage end
equip.call=function(self,n,...)
 if n=='makeEnhancedParam()' then return enhanceMethod:call(self,...) end
 if n=='calcWeightPerPiece()' then return weightMethod:call(self,...) end
 if n=='get_WeaponElement()' then return elementMethod:call(self,...) end
 error('Unexpected value-type method')
end
getCalc=exact('getCalculator',{'app.CharacterID'},'app.PlayerStatusCalculator',function(owner,id) assert(owner==holderObject and id==42);return calculator end)
wrongOverload=exact('getCalculator',{'app.Character'},'app.PlayerStatusCalculator',function() error('wrong overload') end)
holder=register('app.PlayerStatusCalculatorHolder',{}, {wrongOverload,getCalc})
calcTotal=exact('calcAttackDefenceWithEquipmentAndBuff',{},'app.PlayerAttackDefenceStatus',function(owner) assert(owner==calculator);return total end)
calcBasic=exact('calcBasicAttackDefence',{},'app.PlayerBasicAttackDefenceStatus',function(owner) assert(owner==calculator);return basic end)
register('app.PlayerStatusCalculator',{}, {calcTotal,calcBasic})
cm=typ('app.CharacterManager',{field('<ManualPlayerHuman>k__BackingField',human,player),field('<PlayerStatusCalculatorHolder>k__BackingField',holder,holderObject)})
types['app.CharacterManager']=cm
'''
def run(edit=''):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute(base);l.execute(gear);l.execute(extra);l.execute(edit);l.execute(source)
 l.execute('frame();now=105;frame()')
 w=l.globals().writes
 return l,w[len(w)-1]['data']
l,d=run();s=d['equipment']['slots'][1]['itemStats']
assert s['effectiveItemStats']['fields'][2]['value']==443
assert s['effectiveWeight']['value']==127 and s['effectiveWeight']['units']=='unverified source units'
assert d['characterTotals']['withEquipmentAndBuff']['fields'][2]['value']==702
assert d['characterTotals']['basic']['fields'][1]['value']==202
assert d['characterTotals']['semanticsValidated'] is False
print('PASS exact overload, correct receiver and character ID; separate synthetic item/character values')
l,d=run("enhanceMethod.get_return_type=function() return typ('System.Void') end")
assert d['equipment']['slots'][1]['itemStats']['effectiveItemStats']['captureStatus']=='unavailable'
assert 'makeEnhancedParam' not in list(l.globals().invoked.values())
print('PASS mismatched return signature never invoked')
l,d=run("enhanceMethod.call=function() error('compute failed') end")
s=d['equipment']['slots'][1]
assert s['name']=='Test Blade' and s['itemStats']['effectiveItemStats']['captureStatus']=='error'
assert s['itemStats']['effectiveWeight']['value']==127
assert d['characterTotals']['withEquipmentAndBuff']['captureStatus']=='partial'
print('PASS item call exception isolated from name, weight and character totals')
l,d=run("calculator=obj({CharaID=99,Human=player})")
assert d['characterTotals']['captureStatus']=='unavailable'
assert 'calcAttackDefenceWithEquipmentAndBuff' not in list(l.globals().invoked.values())
print('PASS wrong character calculator rejected')
l,d=run("calculator=obj({CharaID=42,Human={}})")
assert d['characterTotals']['captureStatus']=='unavailable'
print('PASS mismatched player reference rejected')
l,d=run("weightMethod.call=function() return 0/0 end;calcTotal.call=function() return nil end")
assert d['equipment']['slots'][1]['itemStats']['effectiveWeight']['captureStatus']=='unavailable'
assert d['characterTotals']['withEquipmentAndBuff']['captureStatus']=='unavailable'
assert d['characterTotals']['basic']['fields'][1]['value']==202
print('PASS nonfinite/null results isolated')
l,d=run("enhancedType.get_fields=function() return {field('Values',typ('System.Single[]'),{get_size=function() return 200 end,get_element=function(self,i) return i==0 and 0 or i+10 end})} end")
a=d['equipment']['slots'][1]['itemStats']['effectiveItemStats']['numericArrays']['Values']
assert len(a['entries'])==128 and a['truncated'] is True
assert a['entries'][1]['index']==0 and a['entries'][1]['value']==0
assert a['indexMeaning']=='unverified'
print('PASS computed numeric arrays bounded, zero preserved, no guessed stat labels')
l,d=run();l.execute('manager=nil;now=110;frame()');w=l.globals().writes;d=w[len(w)-1]['data']
assert d['characterTotals']['captureStatus']=='unavailable'
assert d['equipment']['captureStatus']=='unavailable'
print('PASS losing player clears effective observations')
