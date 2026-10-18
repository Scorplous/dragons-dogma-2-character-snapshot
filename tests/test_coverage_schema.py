from pathlib import Path
from lupa import LuaRuntime
base=Path('tests/test_capture.py').read_text().split("setup=r'''")[1].split("'''",1)[0]
extra=Path('tests/test_effective_stats.py').read_text().split("extra=r'''")[1].split("'''",1)[0]
gear=Path('tests/test_gear.py').read_text().split("gear=r'''")[1].split("'''",1)[0]
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
l=LuaRuntime(unpack_returned_tuples=True)
for part in (base,gear,extra): l.execute(part)
l.execute(r'''
calls=0; methods={}
for i=1,300 do methods[i]=exact('unrelated'..i,{},'System.Void',function() calls=calls+1 end) end
methods[301]=exact('get_RiftBalance',{},'System.Int32',function() calls=calls+1;return 999 end)
methods[302]=exact('set_RiftBalance',{'System.Int32'},'System.Void',function() calls=calls+1 end)
register('app.Player',{},methods)
''')
l.execute(source);l.execute('frame()')
s=l.globals().writes[1]['data']['coverageSchema']
assert s is not None, 'Bundled metadata missing'
assert s['metadataOnly'] is True and s['methodsInvoked'] is False
m=s['types']['app.Player']['methods']
assert any(x['name']=='get_RiftBalance' for x in m.values())
assert l.globals().calls==0
assert s['types']['app.TimeManager']['captureStatus']=='unavailable'
assert l.globals().writes[1]['data']['wallet'] is None
print('PASS late currency metadata is retained without invoking getters/setters or inventing a wallet balance')
