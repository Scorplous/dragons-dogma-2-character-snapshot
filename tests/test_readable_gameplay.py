from pathlib import Path
from lupa import LuaRuntime
def block(file,marker):return Path('tests/'+file).read_text().split(marker+"=r'''")[1].split("'''",1)[0]
base=block('test_capture.py','setup');gear=block('test_gear.py','gear');extra=block('test_effective_stats.py','extra');fixture=block('test_gameplay_sections.py','fixture')
source=Path('src/AtlasSnapshot-DD2.lua').read_text()
more=r'''
function static(n,args,ret,fn) local m=exact(n,args,ret,fn);m.is_static=function() return true end;return m end
table.insert(types['app.Character'].get_methods(),exact('get_OriginalMaxHp',{},'System.Single',function() return 1000 end))
jobContext=obj({CurrentJob=7});local oldHuman=human.get_field
human.get_field=function(self,n) if n=='<JobContext>k__BackingField' then return field(n,typ('app.JobContext'),jobContext) end return oldHuman(self,n) end
register('app.JobContext',{}, {exact('calcJobRank',{'app.Character.JobEnum'},'System.UInt32',function(o,j) assert(j==7);return 4 end)})
register('app.HumanSkillContext.SkillSlot',{field('None',num,0,true),field('Slot1',num,1,true),field('Slot2',num,2,true)}, {})
register('app.AbilityContext.AbilitySlot',{field('None',num,0,true),field('Slot1',num,1,true)}, {})
skillType.get_methods=function() return {
 exact('getSkillID',{'app.Character.JobEnum','app.HumanSkillContext.SkillSlot'},'app.HumanCustomSkillID',function(o,j,slot) assert(o==skills and j==7);return slot==1 and 71 or 0 end),
 exact('getCustomSkillLevel',{'app.HumanCustomSkillID'},'app.HumanCustomSkillLevelNo',function(o,id) return 2 end)} end
abilityType.get_methods=function() return {exact('getAbility',{'app.Character.JobEnum','app.AbilityContext.AbilitySlot'},'app.HumanAbilityID',function(o,j,slot) assert(o==abilities and j==7);return 81 end)} end
register('app.GUIBase',{}, {
 static('getJobName',{'app.Character.JobEnum'},'System.String',function(o,j) assert(j==7);return 'Test Vocation' end),
 static('getCustomSkillName',{'app.Character.JobEnum','app.HumanCustomSkillID','app.HumanCustomSkillLevelNo'},'System.String',function(o,j,id,lv) assert(id==71 and lv==2);return 'Test Skill' end),
 static('getAbilityName',{'app.HumanAbilityID'},'System.String',function(o,id) assert(id==81);return 'Test Augment' end),
 static('getAIAreaName',{'app.AIAreaDefinition'},'System.String',function(o,id) assert(id==2);return 'Test Region' end)})
qlm={};progressing=true;viewId=10
register('app.QuestLogManager',{}, {exact('isQuestLogProgressing',{'app.QuestDefine.ID'},'System.Boolean',function(o,id) return id==10 and progressing end)})
task=obj({_BaseMsg='test-guid',_IsTimed=false})
view=obj({QuestId=10,QuestName='Test Quest',QuestSummary='Test summary',['<Task>k__BackingField']=task})
types['app.GuiManager'].get_methods=function() return {
 exact('get_TargetQuestId',{},'app.QuestDefine.ID',function() return 10 end),
 exact('getQuestLog',{'app.QuestDefine.ID'},'app.QuestLogManager.QuestLogViewInfo',function(o,id) assert(id==10,'Hidden quest view must never be requested');view.get_field=function(self,n) if n=='QuestId' then return viewId end;return ({QuestName='Test Quest',QuestSummary='Test summary',['<Task>k__BackingField']=task})[n] end;return view end)} end
register('app.MessageManager',{}, {static('getMessage',{'System.Guid'},'System.String',function(o,g) assert(g=='test-guid');return 'Test current objective' end)})
local previousSingleton=sdk.get_managed_singleton
sdk.get_managed_singleton=function(n) if n=='app.QuestLogManager' then return qlm end;return previousSingleton(n) end
'''
def run(edit=''):
 l=LuaRuntime(unpack_returned_tuples=True)
 for s in (base,gear,extra,fixture,more,edit,source):l.execute(s)
 l.execute('frame();now=105;frame()');w=l.globals().writes
 return l,w[len(w)-1]['data']
l,d=run()
assert d['health']['fullMaximum']['value']==1000
assert d['health']['lossGauge']['captureStatus']=='unavailable'
assert d['skills']['vocationName']=='Test Vocation' and d['skills']['vocationRank']==4
assert d['skills']['equipped']['records'][1]['name']=='Test Skill'
assert d['skills']['augments']['records'][1]['name']=='Test Augment'
assert d['skills']['equipped']['records'][2]['captureStatus']=='empty'
assert d['location']['displayName']=='Test Region'
q=d['quests'];assert len(q['activeRecords'])==1 and q['trackedQuest']['title']=='Test Quest'
assert q['trackedQuest']['progress']['objective']=='Test current objective'
assert q['trackedQuest']['progress']['isTimed'] is False
print('PASS native health maximum, current-vocation equipped-only names/rank, tracked quest objective and localized native area')
l,d=run('progressing=false')
assert len(d['quests']['activeRecords'])==0 and d['quests']['trackedQuest']['captureStatus']=='unavailable'
assert 'getQuestLog' not in list(l.globals().invoked.values())
print('PASS unstarted/nonprogressing quests cannot expose names/objectives')
l,d=run('viewId=999')
assert d['quests']['activeRecords'][1]['captureStatus']=='unavailable'
assert d['quests']['activeRecords'][1]['title'] is None
print('PASS mismatched quest identity cannot expose another quest')
l,d=run("types['app.GUIBase']=nil")
assert d['skills']['equipped']['records'][1]['skillId']==71
assert d['skills']['equipped']['records'][1]['name'] is None
assert d['location']['displayName']['captureStatus']=='unavailable'
print('PASS missing localization preserves IDs without invented names')
