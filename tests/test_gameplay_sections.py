from pathlib import Path
from lupa import LuaRuntime
base=Path('tests/test_capture.py').read_text().split("setup=r'''")[1].split("'''",1)[0]
gear=Path('tests/test_gear.py').read_text().split("gear=r'''")[1].split("'''",1)[0]
extra=Path('tests/test_effective_stats.py').read_text().split("extra=r'''")[1].split("'''",1)[0]
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
fixture=r'''
chara={}; hp=0; reduced=800
local originalField=human.get_field
human.get_field=function(self,n)
 if n=='<Chara>k__BackingField' then return field(n,typ('app.Character'),chara) end
 if n=='<SkillContext>k__BackingField' then return field(n,skillType,skills) end
 if n=='<AbilityContext>k__BackingField' then return field(n,abilityType,abilities) end
 return originalField(self,n)
end
register('app.Character',{}, {
 exact('get_Hp',{},'System.Single',function(o) assert(o==chara);return hp end),
 exact('get_ReducedMaxHp',{},'System.Single',function(o) assert(o==chara);return reduced end)})
function arr(values) return {get_size=function() return #values end,get_element=function(self,i) return values[i+1] end} end
slotType=register('app.HumanSkillContext.SkillSlot',{field('UnmappedID',num,12)}, {})
slot={get_type_definition=function() return slotType end}
skills={}; abilities={}
skillType=register('app.HumanSkillContext',{field('SkillSlotValues',typ('app.HumanSkillContext.SkillSlot[]'),arr({slot}))}, {})
abilityType=register('app.AbilityContext',{field('AbilitySlotValues',typ('app.AbilityContext.AbilitySlot[]'),arr({}))}, {})
activeItems=arr({10,20}); questManager={}; gui={}
active={}
listType=typ('System.Collections.Generic.List`1<app.QuestDefine.ID>',{})
listType.get_field=function(self,n)
 if n=='_items' then return field(n,typ('app.QuestDefine.ID[]'),activeItems) end
 if n=='_size' then return field(n,num,2) end
end
active.get_type_definition=function() return listType end
register('app.QuestManager',{field('CurrentActiveQuestIDList',listType,active)}, {})
viewType=register('app.QuestLogManager.QuestLogViewInfo',{field('UnmappedText',typ('System.String'),'Test objective')}, {})
register('app.GuiManager',{}, {
 exact('get_TargetQuestId',{},'app.QuestDefine.ID',function(o) assert(o==gui);return 10 end),
 exact('getQuestLog',{'app.QuestDefine.ID'},'app.QuestLogManager.QuestLogViewInfo',function(o,id) assert(id==10 or id==20);return {} end)})
local area=exact('getPlayerArea',{},'app.AIAreaDefinition',function(o) assert(o==nil);return 2 end)
area.is_static=function() return true end
register('app.AIAreaUtil',{}, {area})
register('app.AIAreaDefinition',{field('Area_Test',num,2,true)}, {})
local singleton=sdk.get_managed_singleton
sdk.get_managed_singleton=function(n)
 if n=='app.QuestManager' then return questManager end
 if n=='app.GuiManager' then return gui end
 return singleton(n)
end
'''
def run(edit=''):
 l=LuaRuntime(unpack_returned_tuples=True)
 for s in (base,gear,extra,fixture,edit,source):l.execute(s)
 l.execute('frame();now=105;frame()');w=l.globals().writes
 return l,w[len(w)-1]['data']
l,d=run()
assert d['health']['current']['value']==0
assert d['health']['reducedMaximum']['value']==800
assert d['health']['lossGauge']['captureStatus']=='unavailable'
assert d['skills']['captureStatus']=='unavailable'
assert d['skills']['reason']=='Current vocation unavailable'
assert len(d['quests']['activeRecords'])==0 and d['quests']['filterUnavailable'] is True
assert d['quests']['trackedQuestId']==10
assert d['quests']['trackedQuest']['captureStatus']=='unavailable'
assert d['quests']['absenceMeansNeverCompleted'] is False
assert d['location']['areaId']==2 and d['location']['areaEnumLabel']=='Area_Test'
assert d['location']['displayName']['captureStatus']=='unavailable'
print('PASS health zero and reduced maximum; no inferred loss; active-only quest views; native area ID not a guessed location')
l,d=run('hp=0/0; activeItems=arr({10})')
assert d['health']['current']['captureStatus']=='unavailable'
assert d['quests']['captureStatus']=='unavailable'
assert d['equipment']['slots'][1]['name']=='Test Blade'
print('PASS nonfinite health and inconsistent quest list rejected without losing gear')
l,d=run();l.execute('manager=nil;now=110;frame()');w=l.globals().writes;d=w[len(w)-1]['data']
for key in ['health','skills','quests','location']:assert d[key]['captureStatus']=='unavailable'
print('PASS player loss clears all new current sections')
l,d=run("types['app.Character'].get_methods()[1].get_return_type=function() return typ('System.Void') end; types['app.AIAreaUtil'].get_methods()[1].is_static=function() return false end")
assert d['health']['current']['captureStatus']=='unavailable'
assert d['location']['areaId'] is None
assert 'get_Hp' not in list(l.globals().invoked.values())
assert 'getPlayerArea' not in list(l.globals().invoked.values())
print('PASS wrong health return or area static signature is never called')
l,d=run("activeItems=arr({});for i=1,100 do activeItems[i]=i end;activeItems.get_size=function() return 100 end;activeItems.get_element=function(self,i) return 10 end;listType.get_field=function(self,n) if n=='_items' then return field(n,typ('app.QuestDefine.ID[]'),activeItems) end;if n=='_size' then return field(n,num,100) end end")
assert len(d['quests']['activeRecords'])==0 and d['quests']['truncated'] is True
assert d['quests']['completeRoster'] is False
print('PASS active quest capture bounded; truncation cannot become complete history')
