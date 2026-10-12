import sys
from pathlib import Path
from lupa import LuaRuntime
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
setup=r'''
now=100; writes={}; fail_save=false; requested=false; last_text=''
os.time=function() return now end
re={on_frame=function(f) frame=f end,on_draw_ui=function(f) ui=f end}
imgui={tree_node=function() return true end,tree_pop=function() end,
text=function(s) last_text=s end,button=function() local r=requested;requested=false;return r end}
json={dump_file=function(n,v) if fail_save then return false end;writes[#writes+1]={name=n,data=v};return true end}
log={error=function() end}
function typ(name,fields)
 return {get_full_name=function() return name end,get_fields=function() return fields or {} end,
 get_field=function(self,n) for _,f in ipairs(fields or {}) do if f:get_name()==n then return f end end end}
end
function field(n,t,val,static)
 return {get_name=function() return n end,get_type=function() return t end,is_static=function() return static or false end,
 get_data=function() if n=='bad' then error('unreadable') end;return val end}
end
num=typ('System.Int32'); status=typ('app.TestStatus',{field('hp',num,0),field('isDead',typ('System.Boolean'),false),field('ignoredStatic',num,999,true)})
human=typ('app.Human',{field('<StatusContext>k__BackingField',status,{}),field('<StaminaContext>k__BackingField',status,{}),field('<JobContext>k__BackingField',status,{}),field('<EquipItemCtrl>k__BackingField',status,{})})
player={}; cm=typ('app.CharacterManager',{field('<ManualPlayerHuman>k__BackingField',human,player)})
types={['app.Human']=human,['app.CharacterManager']=cm}; manager={}
sdk={find_type_definition=function(n) return types[n] end,get_managed_singleton=function() return manager end}
'''
def new():
 l=LuaRuntime(unpack_returned_tuples=True);l.execute(setup);l.execute(source);return l
def capture(l):
 l.execute('requested=true;ui();frame();ui()')
 return latest(l)
def latest(l):
 w=l.globals().writes
 for i in range(len(w),0,-1):
  if w[i]['data']['captureKind']=='raw_character_fields': return w[i]['data']
l=new();l.execute('frame()');assert len(l.globals().writes)==1
assert l.globals().writes[1]['data']['captureKind']=='field_type_metadata_only'
assert len(l.globals().writes)==1
print('PASS startup metadata only')
l=new();l.execute('frame();manager=nil');d=capture(l)
assert d['captureStatus']=='unavailable';assert d['quests']['absenceMeansNeverCompleted'] is False
print('PASS missing singleton truthfulness')
l=new();l.execute('frame()');d=capture(l)
s=d['stats']['fields'];assert s[1]['value']==0;assert s[2]['value'] is False;assert len(s)==2
assert d['semanticsValidated'] is False and d['quests']['captureStatus']=='unavailable'
assert d['equipment']['captureStatus'] in ('unavailable','error')
l.execute('frame();frame()');assert len(l.globals().writes)==3
print('PASS zero/false retained, statics excluded, no per-frame repeated capture')
l=new();l.execute('frame();fail_save=true');capture(l)
assert 'failed' in l.globals().last_text.lower()
print('PASS failed export visible')
l=new();l.execute("types['app.Human']=nil;frame()")
d=capture(l);assert d['stats']['captureStatus']=='unavailable'
print('PASS missing field owner does not fabricate values')
l=new();l.execute("types['app.Human']=typ('app.Human',{field('<StatusContext>k__BackingField',typ('app.Broken',{field('bad',num,1)}),{})})")
d=capture(l);assert d['stats']['fields'][1]['captureStatus']=='error'
print('PASS individual field exceptions contained')
l=new();l.execute("cycle={}; cyc=typ('app.Cycle',{}); cyc.get_fields=function() return {field('self',cyc,cycle)} end; types['app.Human']=typ('app.Human',{field('<StatusContext>k__BackingField',cyc,cycle)})")
d=capture(l);assert d['stats']['fields'][1]['data']['reason']=='Repeated object omitted'
print('PASS cyclic reference bounded')
l=new();l.execute('frame();now=104;frame()');assert len(l.globals().writes)==1
l.execute('now=105;frame()');assert latest(l)['sequence']==1
l.execute('now=106;frame()');assert latest(l)['sequence']==1
l.execute('manager=nil;now=110;frame()');d=latest(l)
assert d['sequence']==2 and d['captureStatus']=='unavailable'
assert d['stats']['captureStatus']=='unavailable'
assert d['safeToTreatAsCurrentCharacter'] is False
print('PASS 5-second throttle and no-player transition clears current values')
l=new();l.execute('frame();now=105;frame();sdk.get_managed_singleton=function() error("lost manager") end;now=110;frame()')
d=latest(l);assert d['captureStatus']=='error' and d['stats']['captureStatus']=='unavailable'
print('PASS periodic exception publishes error instead of retaining previous character')
print('9 mocked scenarios passed; live game validation still required')









