exec(open('tests/test_readable_gameplay.py').read())
technical = r'''
table.insert(types['app.AIAreaUtil'].get_methods(),static('getPlayerUILocalArea',{},'app.AILocalAreaDefinition',function() return 3 end))
register('app.AILocalAreaDefinition',{field('Situation_TEST',num,3,true)}, {})
table.insert(types['app.GUIBase'].get_methods(),static('getAILocalAreaName',{'app.AILocalAreaDefinition'},'System.String',function() return 'Situation_TEST' end))
'''
l,d=run(technical)
assert d['location']['displayName']=='Test Region'
assert d['location']['localAreaName']=='Situation_TEST'
print('PASS technical local area label preserved as evidence without overriding readable region')
l,d=run(technical.replace("return 'Situation_TEST'", "return 'Test Local Area'"))
assert d['location']['displayName']=='Test Local Area'
print('PASS localized local area preferred')
