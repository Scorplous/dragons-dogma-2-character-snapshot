from pathlib import Path
import sys
from lupa import LuaRuntime
fixture=Path('tests/test_effective_stats.py').read_text()
base=Path('tests/test_capture.py').read_text().split("setup=r'''")[1].split("'''",1)[0]
gear=Path('tests/test_gear.py').read_text().split("gear=r'''")[1].split("'''",1)[0]
extra=fixture.split("extra=r'''")[1].split("'''",1)[0]
l=LuaRuntime(unpack_returned_tuples=True)
l.execute(base);l.execute(gear);l.execute(extra)
l.execute('''
valueCalls=0;descriptorCalls=0
enhanceMethod.call=function() descriptorCalls=descriptorCalls+1;error('unboxed receiver') end
weightMethod.call=enhanceMethod.call;elementMethod.call=enhanceMethod.call
equip.call=function(self,n)
 assert(self==equip);valueCalls=valueCalls+1
 if n=='makeEnhancedParam()' then return enhanced end
 if n=='calcWeightPerPiece()' then return 127 end
 if n=='get_WeaponElement()' then return 0 end
 error('Unexpected method')
end
''')
l.execute(Path(sys.argv[1]).read_text());l.execute('frame();now=105;frame()')
w=l.globals().writes;d=w[len(w)-1]['data'];s=d['equipment']['slots'][1]['itemStats']
assert s['effectiveItemStats']['fields'][2]['value']==443
assert s['effectiveWeight']['value']==127
assert s['weaponElement']['value']==0
assert l.globals().descriptorCalls==0 and l.globals().valueCalls==3
assert d['characterTotals']['basic']['fields'][1]['value']==202
print('PASS ValueType uses boxed self:call; managed calculator still uses descriptor; all three item methods captured')
