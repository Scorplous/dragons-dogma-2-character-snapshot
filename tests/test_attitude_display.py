import importlib.util
spec=importlib.util.spec_from_file_location('display','tools/Read-relationship-attitudes.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
record={'name':'Test NPC','characterId':7,'identityVerified':True,'rawAffinity':{'captureStatus':'captured','value':999,'rank':17}}
rel={'records':[record],'sentimentRankLabels':{'Normal':17,'Love':88},'mainPawnAffinity':{'favorabilityRating':999}}
e={'availability':'recent_unverified_observation','snapshot':{'relationships':rel}}
r=mod.present(e)
assert r['npcAttitudes'][0]['attitude']=='Normal' and r['npcAttitudes'][0]['rawAffinity']==999
assert r['mainPawn']['attitude']=='Unknown attitude'
print('PASS stored rank mapping wins over affinity magnitude; pawn scale never borrowed')
rel['sentimentRankLabels']={};assert mod.present(e)['npcAttitudes'][0]['attitude']=='Unknown attitude'
rel['sentimentRankLabels']={'Like':17,'Love':17};assert mod.present(e)['npcAttitudes'][0]['attitude']=='Unknown attitude'
rel['sentimentRankLabels']={'None':17};assert mod.present(e)['npcAttitudes'][0]['attitude']=='Unknown attitude'
print('PASS missing, ambiguous and None mappings never invent an attitude')
rel['sentimentRankLabels']={'Like':17};record['identityVerified']=False
assert mod.present(e)['npcAttitudes'][0]['attitude']=='Unknown attitude'
record['identityVerified']=True;record['rawAffinity']['captureStatus']='error'
assert mod.present(e)['npcAttitudes'][0]['attitude']=='Unknown attitude'
print('PASS invalid identity or source capture cannot be labeled')
record['rawAffinity']['captureStatus']='captured'
old={'availability':'stale','lastKnownSnapshot':e['snapshot']}
assert mod.present(old)['historicalObservation'] is True
assert mod.present(old)['npcAttitudes'][0]['attitude']=='Like'
assert mod.present(e)['crime']['interpretation'].startswith('Separate crime')
print('PASS stale results visibly historical; crime remains separate')
