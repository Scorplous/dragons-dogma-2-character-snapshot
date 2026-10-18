"""Reject invalid records without pretending unvalidated negative IDs are sentinels."""
import runpy
base=runpy.run_path('tests/test_quest_clear_records.py');run=base['run'];history=base['history']
def raw(edit=''):
 _,d=run(edit);return history(d)['rawRecords']
r=raw("rows[1]=obj({next=-1,key=-1,value=obj({_QuestID=-1,_ClearCount=0})})")
assert r['allSlotsExamined'] is True,'Slot traversal must be separate from record validity'
assert r['validRecordsComplete'] is False and r['scanComplete'] is False
assert r['entryErrors']==1 and r['errorReasonCounts']['invalidQuestId']==1
assert r['entryDiagnostics'][1]['reasonCode']=='invalidQuestId'
assert r['expectedLiveEntries']==2 and len(r['records'])==1, 'Invalid ID must not be subtracted as a known sentinel'
for edit,reason in [('badId=true','recordIdentityMismatch'),('badCount=true','invalidClearCount'),
 ("rows[3]=obj({next=-1,key=101,value=rows[1]:get_field('value')})",'duplicateQuestId'),
 ("rows[1]=obj({next=99,key=101})",'invalidEntryLink')]:
 r=raw(edit)
 assert r['allSlotsExamined'] is True and r['validRecordsComplete'] is False
 assert r['errorReasonCounts'][reason]==1 and r['entryDiagnostics'][1]['reasonCode']==reason
r=raw();assert r['allSlotsExamined'] is True and r['validRecordsComplete'] is True
assert r['entryErrors']==0 and len(r['records'])==2, 'Removed slot is excluded, zero clear count retained'
r=raw('count=600;free=1');assert r['allSlotsExamined'] is False and r['validRecordsComplete'] is False
r=raw("count=40;free=0;for i=1,40 do rows[i]=obj({next=-1,key=-1,value=obj({_QuestID=-1,_ClearCount=0})}) end")
assert r['entryErrors']==40 and r['errorReasonCounts']['invalidQuestId']==40 and len(r['entryDiagnostics'])==16
assert r['allSlotsExamined'] is True and r['validRecordsComplete'] is False
print('PASS invalid-ID categorization, identity/count/duplicate/link reasons, bounded diagnostics and truthful traversal')
