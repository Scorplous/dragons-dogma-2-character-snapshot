-- AtlasSnapshot 0.11.0 staged. Pawn component identity correction; pending live validation.
-- Field names confirmed by the first live probe; semantics remain unvalidated.
local startup, requested, serial = true, false, 0
local next_refresh=os.time()+5
local sequence=0
local session=os.date('!%Y%m%dT%H%M%SZ')..'-'..tostring(math.floor(os.clock()*1000000))
local field_cache, list_cache = {}, {}
local message = 'Automatic local capture every 5 seconds; character semantics unverified.'
local roots = {
    stats='<StatusContext>k__BackingField', stamina='<StaminaContext>k__BackingField',
    vocation='<JobContext>k__BackingField'
}
local function unavailable(reason) return {captureStatus='unavailable',reason=reason} end
local function field(owner,name)
    local key=owner..'/'..name
    if field_cache[key] then return field_cache[key] end
    local td=sdk.find_type_definition(owner)
    local f=td and td:get_field(name)
    if f then field_cache[key]=f end
    return f
end
local function fields(td)
    local name=td:get_full_name()
    if not list_cache[name] then list_cache[name]=td:get_fields() end
    return list_cache[name]
end
local function schema(owner,name)
    local r={owner=owner,field=name,captureStatus='unavailable'}
    local ok,err=pcall(function()
        local f=field(owner,name)
        if not f then r.reason='Field not found';return end
        local td=f:get_type()
        if not td then r.reason='Type unavailable';return end
        r.fieldType=td:get_full_name();r.fields={}
        for i,n in ipairs(td:get_fields()) do
            if i>128 then r.truncated=true;break end
            local nt=n:get_type()
            r.fields[#r.fields+1]={name=n:get_name(),type=nt and nt:get_full_name() or 'unavailable'}
        end
        r.captureStatus=r.truncated and 'partial' or 'captured'
    end)
    if not ok then r.captureStatus='error';r.reason=tostring(err) end
    return r
end
-- Bounded raw field reader: never invokes arbitrary getters, enumerators, or setters.
local function read_fields(obj,td,depth,budget,seen)
    if not obj or not td then return unavailable('Object or type missing') end
    local r={captureStatus='partial',type=td:get_full_name(),fields={},semanticsValidated=false}
    if seen[obj] then r.reason='Repeated object omitted';return r end
    if depth>2 or budget.left<=0 then r.reason='Traversal limit';return r end
    seen[obj]=true
    for i,f in ipairs(fields(td)) do
        if i>64 or budget.left<=0 then r.truncated=true;break end
        if not f:is_static() then
            budget.left=budget.left-1
            local entry={name=f:get_name(),captureStatus='unavailable'}
            local ok,err=pcall(function()
                local ft=f:get_type()
                entry.type=ft and ft:get_full_name() or 'unavailable'
                -- Skip engine pointers, delegates, arrays and collection internals.
                -- Record their schema instead of guessing how to walk them.
                if entry.type:find('%*') or entry.type:find('%[') or
                   entry.type:find('System.Collections',1,true) or
                   entry.type:find('System.Action',1,true) or
                   entry.type:find('System.Func',1,true) or
                   entry.type:find('System.IntPtr',1,true) or
                   entry.type:find('System.UIntPtr',1,true) then
                    entry.reason='Complex/reference data deferred';return
                end
                local v=f:get_data(obj)
                local kind=type(v)
                if kind=='number' or kind=='boolean' or kind=='string' then
                    if kind=='number' and (v~=v or v==math.huge or v==-math.huge) then
                        entry.reason='Non-finite number';return
                    end
                    entry.value=v;entry.captureStatus='captured'
                elseif v==nil then entry.reason='Null field'
                elseif ft and entry.type:match('^app%.') then
                    entry.data=read_fields(v,ft,depth+1,budget,seen)
                    entry.captureStatus='partial'
                else entry.reason='Unsupported value representation' end
            end)
            if not ok then entry.captureStatus='error';entry.reason=tostring(err) end
            r.fields[#r.fields+1]=entry
        end
    end
    return r
end
-- Metadata only: inspect candidate methods without executing calculations or GUI setup.
local calculation_types={
    'app.PlayerStatusCalculator','app.PlayerStatusCalculatorHolder',
    'app.GUIBase.ItemDetail2Ref','app.GUIBase.ItemDetail2Ref.StatusInfo',
    'app.GUIBase.ItemDetail2Ref.ConditionInfo','app.GUIBase.ItemDetail2Ref.ElemInfo',
    'app.GUIBase.ItemWindowRef','app.GUIBase.ItemWindowRef.OwnedInfo',
    'app.ItemDefine.StorageData','app.ItemDefine.EnhanceParam',
    'app.ItemDefine.EquipmentAbilityParam','app.WeaponEnhanceParam','app.ArmorEnhanceParam',
    'app.GuiManager','app.HumanStatusContext'
    ,'app.EquipParam','app.PlayerAttackDefenceStatus','app.PlayerBasicAttackDefenceStatus',
    'app.PlayerStatusCalculatorParameter'
}
local function describe_type(name,focus)
    local td=sdk.find_type_definition(name)
    if not td then return unavailable('Runtime type unavailable') end
    local r={captureStatus='partial',type=name,fields={},methods={},methodsInvoked=false}
    if td.get_parent_type then
        local parent=td:get_parent_type()
        if parent then
            r.parentType=parent:get_full_name();r.parentFields={}
            for i,f in ipairs(fields(parent)) do
                if i>128 then r.parentFieldsTruncated=true;break end
                local ft=f:get_type()
                r.parentFields[#r.parentFields+1]={name=f:get_name(),type=ft and ft:get_full_name() or 'unavailable'}
            end
        end
    end
    for i,f in ipairs(fields(td)) do
        if i>256 then r.fieldsTruncated=true;break end
        local ok,value=pcall(function()
            local ft=f:get_type()
            return {name=f:get_name(),type=ft and ft:get_full_name() or 'unavailable',isStatic=f:is_static()}
        end)
        r.fields[#r.fields+1]=ok and value or {captureStatus='error',reason=tostring(value)}
    end
    if td.get_methods then
        for i,m in ipairs(td:get_methods()) do
            if (not focus and i>256) or #r.methods>=256 then r.methodsTruncated=true;break end
            local selected=not focus
            if focus then
                local label=m:get_name():lower()
                for _,word in ipairs({'sentiment','favor','pawn','npc','name','dead','death','kill','reviv','resurrect','crime','town','area','reputation','context','holder'}) do
                    if label:find(word,1,true) then selected=true;break end
                end
            end
            if selected then
            local e={captureStatus='partial'}
            local ok,err=pcall(function()
                e.name=m:get_name();e.parameterCount=m:get_num_params()
                e.parameterTypes={}
                for j,pt in ipairs(m:get_param_types()) do
                    if j>32 then e.parametersTruncated=true;break end
                    e.parameterTypes[#e.parameterTypes+1]=pt:get_full_name()
                end
                local rt=m:get_return_type()
                e.returnType=rt and rt:get_full_name() or 'unavailable'
                e.isStatic=m:is_static()
            end)
            if not ok then e.captureStatus='error';e.reason=tostring(err) end
            r.methods[#r.methods+1]=e
            end
        end
    end
    return r
end
local function relationship_schema()
    -- Source establishes distinct NPC sentiment and main-pawn favorability, but
    -- current instance paths/signatures are not yet known. Inspect metadata only.
    local r={captureStatus='partial',metadataOnly=true,types={},methodsInvoked=false,
        numericRelationshipValuesCaptured=false,completeRoster=false,absenceMeansZero=false}
    local names={'app.NPCManager','app.NPCHolder','app.NPCManager.CharacterDataEx',
        'app.CharacterManager','app.Human','app.MainPawnDataContext','app.SentimentController',
        'app.CrimeManager','app.HumanStatusContext','app.HumanReviveInteractController',
        'app.CrimeManager.CrimeValue','app.CharacterData.GroupDefine','app.CharacterData.UniqueNPCDefine',
        'app.NPCManager.NPCHistory','app.HitController.DamageInfo','app.PawnManager','app.Pawn',
        'app.NPCManager.NPCHistory.HistoryFlagEnum','app.Character','app.PawnDataContext'}
    for _,name in ipairs(names) do
        local ok,value=pcall(describe_type,name,true)
        r.types[name]=ok and value or {captureStatus='error',reason=tostring(value)}
    end
    -- Include relevant referenced record types, without dereferencing objects or
    -- enumerating a character roster. Bound startup discovery to 12 extra types.
    local extra,seen={},{}
    for _,name in ipairs(names) do seen[name]=true end
    local function add_type(tn)
        -- Preserve generic containers in parent metadata; discover their app
        -- record arguments as types, without opening any collection instance.
        for candidate in (tn or ''):gmatch('app%.[%w_%.]+') do
            if not seen[candidate] and #extra<12 then
                seen[candidate]=true;extra[#extra+1]=candidate
            end
        end
    end
    for _,name in ipairs(names) do
        for _,f in ipairs(r.types[name].fields or {}) do
            local label=(f.name or ''):lower()
            if label:find('sentiment') or label:find('favor') or label:find('mainpawn') or label:find('reputation') or label:find('crime') or label:find('dead') or label:find('death') or label:find('kill') then
                add_type(f.type)
            end
        end
        for _,m in ipairs(r.types[name].methods or {}) do
            local label=(m.name or ''):lower()
            if label:find('sentiment') or label:find('favor') or label:find('mainpawn') or label=='getnpcdata' or label:find('crime') or label:find('dead') or label:find('kill') then
                add_type(m.returnType)
            end
        end
    end
    for _,name in ipairs(extra) do
        local ok,value=pcall(describe_type,name,true)
        r.types[name]=ok and value or {captureStatus='error',reason=tostring(value)}
    end
    return r
end
local function relationship_status()
    return {captureStatus='unavailable',metadataOnly=true,semanticsValidated=false,
        npcAffinity=unavailable('NPC sentiment instance/getter path awaits runtime metadata validation'),
        mainPawnAffinity=unavailable('MainPawnDataContext favorability fields known; active instance path unverified'),
        generalReputation=unavailable('No distinct universal or faction reputation meter established'),
        completeRoster=false,absenceMeansZero=false,records={},
        coverage='No relationship records captured; startup schema probe only',
        spoilerPolicy='Do not infer or display unseen NPC names or story outcomes'}
end
local function calculation_evidence(cm)
    local r={captureStatus='partial',semanticsValidated=false,
        purpose='Cached player calculator fields; not yet mapped to item panel or character totals',
        playerCalculator=unavailable('Calculator holder unavailable')}
    local ok,value=pcall(function()
        local f=field('app.CharacterManager','<PlayerStatusCalculatorHolder>k__BackingField')
        if not f then return unavailable('Calculator holder field unavailable') end
        return read_fields(f:get_data(cm),f:get_type(),0,{left=240},{})
    end)
    r.playerCalculator=ok and value or {captureStatus='error',reason=tostring(value)}
    return r
end
local enums, name_cache = {}, {}
local function enum(name)
    if enums[name] then return enums[name] end
    local td=sdk.find_type_definition(name)
    if not td then return {} end
    local values={}
    for _,f in ipairs(fields(td)) do
        if f:is_static() then
            local v=f:get_data(nil)
            if type(v)=='number' then values[f:get_name()]=v end
        end
    end
    if next(values) then enums[name]=values end
    return values
end
local function checked_method(td,name,count)
    local m=td and td:get_method(name)
    if m and m:get_num_params()==count then return m end
end
-- Allowlisted value calculations only. Never call setup, setters, add/remove, or GUI updates.
-- Signatures were captured from this game's runtime; effects and UI semantics need live testing.
local exact_cache={}
local function exact_method(owner,name,args,return_type)
    local key=owner..'/'..name..'('..table.concat(args,',')..')->'..return_type
    if exact_cache[key] then return exact_cache[key] end
    local td=sdk.find_type_definition(owner)
    if not td or not td.get_methods then return nil end
    for _,m in ipairs(td:get_methods()) do
        if m:get_name()==name and m:get_num_params()==#args and not m:is_static() then
            local rt=m:get_return_type()
            local pts=m:get_param_types() or {}
            local matched=rt and rt:get_full_name()==return_type and #pts==#args
            for i,expected in ipairs(args) do
                if not pts[i] or pts[i]:get_full_name()~=expected then matched=false end
            end
            if matched then exact_cache[key]=m;return m end
        end
    end
end
local function computed_value(obj,owner,name,args,return_type,...)
    local supplied={...}
    local ok,result=pcall(function()
        if not obj then return unavailable('Receiver unavailable') end
        local m=exact_method(owner,name,args,return_type)
        if not m then return unavailable('Exact runtime signature unavailable: '..owner..'.'..name) end
        local value
        if owner=='app.ItemDefine.StorageData' then
            -- REFramework d052e8f ValueType.call boxes its local struct copy.
            -- REMethodDefinition.call passes the raw struct address instead.
            -- All three allowlisted StorageData calculations have zero arguments.
            value=obj:call(name..'()')
        else
            value=m:call(obj,table.unpack(supplied))
        end
        if value==nil then return unavailable('Calculation returned null') end
        local r
        if return_type=='System.Int32' or return_type=='System.Single' or return_type=='app.AttackUserData.ElementType' then
            if type(value)~='number' or value~=value or math.abs(value)==math.huge then
                return unavailable('Result is not a finite number')
            end
            r={captureStatus='partial',value=value,units='unverified source units'}
        else
            local td=sdk.find_type_definition(return_type)
            r=read_fields(value,td,0,{left=160},{})
            -- Some computed records store stats in primitive arrays. Read only bounded
            -- numeric arrays; index-to-stat mapping remains explicit and unverified.
            r.numericArrays={}
            if td then
                for i,f in ipairs(fields(td)) do
                    if i>64 then break end
                    local ft=f:get_type()
                    local tn=ft and ft:get_full_name() or ''
                    if not f:is_static() and (tn=='System.Int32[]' or tn=='System.Single[]' or tn=='System.Double[]') then
                        local arr_ok,arr_result=pcall(function()
                            local arr=f:get_data(value)
                            if not arr then return unavailable('Null numeric array') end
                            local size=arr:get_size()
                            if type(size)~='number' or size<0 or size%1~=0 then return unavailable('Invalid array size') end
                            local a={captureStatus='partial',size=size,entries={},indexMeaning='unverified',truncated=size>128}
                            for j=0,math.min(size,128)-1 do
                                local number=arr:get_element(j)
                                local e={index=j,captureStatus='unavailable'}
                                if type(number)=='number' and number==number and math.abs(number)~=math.huge then
                                    e.value=number;e.captureStatus='captured'
                                else e.reason='Nonfinite or nonnumeric element' end
                                a.entries[#a.entries+1]=e
                            end
                            return a
                        end)
                        r.numericArrays[f:get_name()]=arr_ok and arr_result or {captureStatus='error',reason=tostring(arr_result)}
                    end
                end
            end
            r.parameterEnumLabels=enum('app.EquipParam.ParamEnum')
        end
        r.source=owner..'.'..name;r.semanticsValidated=false;r.panelMatchVerified=false
        return r
    end)
    return ok and result or {captureStatus='error',reason=tostring(result)}
end
local function character_totals(cm,player)
    local ok,result=pcall(function()
        local id=enum('app.CharacterID').ch000000_00
        local f=field('app.CharacterManager','<PlayerStatusCalculatorHolder>k__BackingField')
        local holder=f and f:get_data(cm)
        local get=exact_method('app.PlayerStatusCalculatorHolder','getCalculator',{'app.CharacterID'},'app.PlayerStatusCalculator')
        if id==nil or not holder or not get then return unavailable('Player calculator lookup unavailable') end
        local calc=get:call(holder,id)
        if not calc then return unavailable('Player calculator unavailable') end
        if calc:get_field('CharaID')~=id or calc:get_field('Human')~=player then
            return unavailable('Calculator identity or player reference mismatch')
        end
        return {captureStatus='partial',semanticsValidated=false,playerCharacterId=id,
            source='CharacterManager.PlayerStatusCalculatorHolder.getCalculator(CharacterID.ch000000_00)',
            basic=computed_value(calc,'app.PlayerStatusCalculator','calcBasicAttackDefence',{},'app.PlayerBasicAttackDefenceStatus'),
            withEquipmentAndBuff=computed_value(calc,'app.PlayerStatusCalculator','calcAttackDefenceWithEquipmentAndBuff',{},'app.PlayerAttackDefenceStatus')}
    end)
    return ok and result or {captureStatus='error',reason=tostring(result)}
end
local npc_cursor=0
local npc_name_cache={}
local function safe_get(obj,owner,name,args,ret,...)
    local supplied={...}
    local ok,result=pcall(function()
        local m=exact_method(owner,name,args,ret)
        if not obj or not m then return nil end
        return m:call(obj,table.unpack(supplied))
    end)
    if ok then return result,nil end
    return nil,tostring(result)
end
local function scalar_field(obj,name)
    if not obj then return nil end
    local ok,v=pcall(function() return obj:get_field(name) end)
    if ok and (type(v)=='number' or type(v)=='boolean' or type(v)=='string') then
        if type(v)~='number' or (v==v and math.abs(v)~=math.huge) then return v end
    end
end
local function main_pawn_affinity()
    local ok,value=pcall(function()
        local pm=sdk.get_managed_singleton('app.PawnManager')
        local f=field('app.PawnManager','_MainPawn')
        local pawn=pm and f and f:get_data(pm)
        if not pawn then return unavailable('Main pawn instance unavailable') end
        local cf=field('app.Pawn','MainPawnDataContext')
        local context=cf and cf:get_data(pawn)
        if not context then return unavailable('Main pawn favorability context unavailable') end
        local rating=scalar_field(context,'_FavorabilityRating')
        local accumulated=scalar_field(context,'_AccumulatedFavorability')
        -- app.Pawn is a component, not an app.Human/app.Character receiver.
        -- Resolve optional identity separately so it cannot discard favorability.
        local identity_ok,identity=pcall(function()
            local f=field('app.Pawn','<CachedCharacter>k__BackingField')
            local character=f and f:get_data(pawn)
            if not character then return unavailable('Cached pawn Character unavailable') end
            local id,reason=safe_get(character,'app.Character','get_CharaID',{},'app.CharacterID')
            if id==nil then reason=reason or 'Character ID getter unavailable or signature mismatch' end
            return {characterId=id,reason=reason,source='Pawn.CachedCharacter.get_CharaID'}
        end)
        if not identity_ok then identity={captureStatus='error',reason=tostring(identity)} end
        return {captureStatus='partial',source='PawnManager._MainPawn.MainPawnDataContext',
            characterId=identity.characterId,identityEvidence=identity,
            nameStatus='unavailable; Pawn component is not a Human name-data receiver',
            favorabilityRating=rating,accumulatedFavorability=accumulated,
            scale='raw values; thresholds and normalization unverified',semanticsValidated=false,
            valuesAvailable=type(rating)=='number' or type(accumulated)=='number'}
    end)
    return ok and value or {captureStatus='error',reason=tostring(value)}
end
local function retained_npc_history(manager)
    local ok,value=pcall(function()
        local list=manager:get_field('_NPCHistoryList')
        if not list then return unavailable('Retained NPC history list unavailable') end
        local td=list:get_type_definition()
        local count_method=checked_method(td,'get_Count',0)
        local item_method=checked_method(td,'get_Item',1)
        if not count_method or not item_method then return unavailable('History list getters unavailable') end
        local count=count_method:call(list)
        if type(count)~='number' or count<0 or count%1~=0 then return unavailable('Invalid retained history size') end
        local r={captureStatus='partial',count=count,truncated=count>128,records={},
            source='NPCManager._NPCHistoryList',flagLabels=enum('app.NPCManager.NPCHistory.HistoryFlagEnum'),
            playerAttributionVerified=false,historicalEventLocationAvailable=false,
            interpretation='Raw retained flags, not a verified player-kill history'}
        for i=0,math.min(count,128)-1 do
            local rec_ok,rec=pcall(function()
                local h=item_method:call(list,i)
                return {characterId=scalar_field(h,'_CharaID'),rawFlags=scalar_field(h,'_Flag'),index=i}
            end)
            r.records[#r.records+1]=rec_ok and rec or {captureStatus='error',reason=tostring(rec),index=i}
        end
        return r
    end)
    return ok and value or {captureStatus='error',reason=tostring(value)}
end
local function npc_observations()
    local rel=relationship_status()
    rel.mainPawnAffinity=main_pawn_affinity()
    local life={captureStatus='unavailable',records={},completeRoster=false,absenceMeansDead=false,
        historicalPlayerKillsAvailable=false,playerKillAttributionAvailable=false,
        saveRollbackDetection='unavailable; observations are not a reconstructed current-world ledger'}
    local manager=sdk.get_managed_singleton('app.NPCManager')
    if not manager then return rel,life end
    life.retainedHistoryEvidence=retained_npc_history(manager)
    local ok,err=pcall(function()
        local array=manager:get_field('NPCHolderDic')
        if not array then rel.reason='NPC holder array unavailable';return end
        local size=array:get_size()
        if type(size)~='number' or size<0 or size%1~=0 or size>1000000 then
            rel.reason='NPC holder array size outside bounds';return
        end
        if npc_cursor>=size then npc_cursor=0 end
        local start=npc_cursor
        rel.captureStatus='partial';rel.metadataOnly=false;rel.records={}
        rel.coverage='Current batch of existing NPC holders; encounter history and complete roster unverified'
        rel.npcAffinity={captureStatus='partial',source='NPCHolder.SentimentToPlayer.Value',scale='raw game value; thresholds unverified'}
        rel.batch={startIndex=start,arraySize=size,scanned=0,maxSlots=128,maxRecords=32}
        local batch_seen={}
        life.captureStatus='partial'
        for index=start,math.min(size-1,start+127) do
            if #rel.records>=32 then break end
            npc_cursor=index+1;rel.batch.scanned=rel.batch.scanned+1
            local entry_ok,entry_error=pcall(function()
                local holder=array:get_element(index)
                if not holder then return end
                local id=scalar_field(holder,'CharaID')
                if type(id)~='number' or id<=0 or batch_seen[id] then return end
                local data=safe_get(manager,'app.NPCManager','getNPCData',{'app.CharacterID'},'app.CharacterData',id)
                if not data or scalar_field(data,'ID')~=id then return end
                batch_seen[id]=true
                if not npc_name_cache[id] then
                    local name=safe_get(data,'app.CharacterData','get_Name',{},'System.String')
                    if type(name)=='string' and name~='' then npc_name_cache[id]=name end
                end
                local rec={characterId=id,name=npc_name_cache[id],identityVerified=true,
                    captureStatus='partial',uniqueClass=scalar_field(data,'Unique'),group=scalar_field(data,'Group'),
                    crimeGroup=scalar_field(data,'CrimeGroup'),importance='unclassified',encountered='unverified',
                    rawAffinity=unavailable('No stored player-sentiment record')}
                local sentiment=holder:get_field('SentimentToPlayer')
                if sentiment then
                    local v=scalar_field(sentiment,'Value')
                    if type(v)=='number' then rec.rawAffinity={captureStatus='captured',value=v,
                        source='NPCHolder.SentimentToPlayer.Value',rank=scalar_field(sentiment,'Rank'),
                        scale='raw game value; no normalization'} end
                end
                local temp=holder:get_field('SentimentTempToPlayer')
                rec.temporaryAffinity=scalar_field(temp,'Value')
                local important=safe_get(manager,'app.NPCManager','isNPCQuestLayer',{'app.CharacterID'},'System.Boolean',id)
                if important==true then rec.importance='current quest-layer NPC' end
                rel.records[#rel.records+1]=rec
                local dead,dead_error=safe_get(holder,'app.NPCHolder','isFlagDeadOrCoffin',{},'System.Boolean')
                local entity=holder:get_field('_chara')
                if type(dead)~='boolean' then rec.lifeState=unavailable(dead_error or 'Death flag unavailable');return end
                local state=dead and 'dead' or (entity and 'alive' or nil)
                if not state then rec.lifeState=unavailable('Not flagged dead; entity absent, not classified alive');return end
                rec.lifeState={captureStatus='captured',state=state,source='NPCHolder.isFlagDeadOrCoffin and entity presence'}
                local observation={characterId=id,name=rec.name,identityVerified=true,stateVerified=true,state=state,
                    importantVerified=important==true,importanceBasis=rec.importance,playerAttributionVerified=false,
                    cause='unknown',provenance='NPCHolder.isFlagDeadOrCoffin with verified CharacterData.ID',
                    revivedCount=scalar_field(holder,'RevivedCount'),eventLocation=unavailable('No original death-event location')}
                if entity then
                    local loc_ok,loc=pcall(function()
                        local go=entity:call('get_GameObject');local tr=go and go:call('get_Transform')
                        local p=tr and tr:call('get_UniversalPosition')
                        if p and type(p.x)=='number' and type(p.y)=='number' and type(p.z)=='number' then
                            return {verified=true,provenance='Observed NPC entity transform, not original kill location',
                                coordinateSpace='engine universal/world',coordinates={x=p.x,y=p.y,z=p.z}}
                        end
                    end)
                    if loc_ok then observation.observationLocation=loc end
                end
                life.records[#life.records+1]=observation
            end)
            if not entry_ok then rel.entryErrors=(rel.entryErrors or 0)+1;rel.lastEntryError=tostring(entry_error) end
        end
        rel.batch.nextIndex=npc_cursor
        rel.batch.reachedArrayEnd=npc_cursor>=size
        rel.groupLabels=enum('app.CharacterData.GroupDefine')
        rel.sentimentRankLabels=enum('app.SentimentRank')
        rel.attitudeSource='Stored SentimentToPlayer.Rank matched to runtime SentimentRank enum; no numeric threshold inference'
        rel.uniqueClassLabels=enum('app.CharacterData.UniqueNPCDefine')
        local crime=manager:get_field('CrimeManager')
        rel.groupCrime={captureStatus='partial',interpretation='Crime values by game character group; not general reputation',records={}}
        local count=0
        for label,id in pairs(rel.groupLabels) do
            if count>=32 then rel.groupCrime.truncated=true;break end
            local lower=label:lower()
            if not lower:find('max') and not lower:find('invalid') and lower~='none' then
                count=count+1
                rel.groupCrime.records[#rel.groupCrime.records+1]={groupId=id,groupLabel=label,
                    data=computed_value(crime,'app.CrimeManager','getPlayerCrime',{'app.CharacterData.GroupDefine'},'app.CrimeManager.CrimeValue',id)}
            end
        end
    end)
    if not ok then rel.captureStatus='error';rel.reason=tostring(err) end
    return rel,life
end
local item_fields={
    '_Weight','_PhysicalAttack','_MagicAttack','_SlashRate','_StrikeRate','_StrikeStore',
    '_Element','_ElementStore','_Shake','_Blow','_StaminaReduce','_ShakeGuard','_BlowGuard',
    '_PoisonStore','_SleepStore','_SilentStore','_StoneStore','_WaterStore','_OilStore',
    '_PhysicalDefence','_MagicDefence','_SlashDefenceRate','_StrikeDefenceRate',
    '_FireDefence','_FireResist','_IceDefence','_IceResist','_ThunderDefence','_ThunderResist',
    '_LightDefence','_DarkDefence','_ShakeResistRate','_BlowResistRate',
    '_PoisonResist','_SleepResist','_SilentResist','_StoneResist','_WaterResist',
    '_OilResist','_FaintResist','_Special','_SpecialValue','_SpecialValue2','_SpecialValue3',
    '_EquipCategory','_Lv','_Series','_Job'
}
local instance_schema_cache={}
local function item_stats(item,param)
    local r={captureStatus='partial',baseParameters={captureStatus='partial',
        source='equippedInstance._ItemData',includesEnhancements='unverified',values={}},
        effectiveItemStats=computed_value(item,'app.ItemDefine.StorageData','makeEnhancedParam',{},'app.EquipParam'),
        effectiveWeight=computed_value(item,'app.ItemDefine.StorageData','calcWeightPerPiece',{},'System.Int32'),
        characterTotals=unavailable('Separate top-level characterTotals; never inferred from item fields'),
        partyAndStorageCounts=unavailable('Inventory ownership counts not yet probed'),
        upgradeSummary=unavailable('Raw instance evidence only; upgrade mapping unverified')}
    for _,name in ipairs(item_fields) do
        local e={captureStatus='unavailable',sourceField=name}
        local ok,v=pcall(function() return param:get_field(name) end)
        if not ok then e.captureStatus='error';e.reason=tostring(v)
        elseif type(v)=='number' and v==v and math.abs(v)~=math.huge then
            e.captureStatus='captured';e.value=v;e.units='unverified source units'
        else e.reason='Not present or not a finite numeric field on this item type' end
        r.baseParameters.values[name]=e
    end
    local ok,state=pcall(function()
        local td=item:get_type_definition()
        local type_name=td:get_full_name()
        if not instance_schema_cache[type_name] then
            local description={type=type_name,fields={},methods={},captureStatus='partial'}
            local cur=td
            for depth=1,4 do
                if not cur then break end
                for i,f in ipairs(fields(cur)) do
                    if i>96 then description.truncated=true;break end
                    local ft=f:get_type()
                    description.fields[#description.fields+1]={name=f:get_name(),type=ft and ft:get_full_name() or 'unavailable'}
                end
                if cur.get_parent_type then cur=cur:get_parent_type() else break end
            end
            for _,m in ipairs(td:get_methods()) do
                local n=m:get_name()
                if n:lower():match('attack') or n:lower():match('defen') or n:lower():match('weight') or
                   n:lower():match('enhance') or n:lower():match('blow') or n:lower():match('param') or
                   n:lower():match('resist') or n:lower():match('element') then
                    if #description.methods>=48 then break end
                    description.methods[#description.methods+1]={name=n,parameterCount=m:get_num_params()}
                end
            end
            instance_schema_cache[type_name]=description
        end
        r.instanceSchema=instance_schema_cache[type_name]
        return read_fields(item,td,0,{left=120},{})
    end)
    r.instanceState=ok and state or {captureStatus='error',reason=tostring(state)}
    return r
end
local function gear()
    local id=enum('app.CharacterID').ch000000_00
    if id==nil then return unavailable('Player CharacterID enum unavailable') end
    local manager=sdk.get_managed_singleton('app.ItemManager')
    local get_equipment=checked_method(sdk.find_type_definition('app.ItemManager'),'getEquipData',1)
    if not manager or not get_equipment then return unavailable('Equipment getter unavailable or signature mismatch') end
    local data=get_equipment:call(manager,id)
    if not data then return unavailable('Equipment record unavailable') end
    local get_slot=checked_method(data:get_type_definition(),'get',1)
    if not get_slot then return unavailable('Slot getter unavailable or signature mismatch') end
    local slots,seen={},{}
    for label,value in pairs(enum('app.EquipData.SlotEnum')) do
        local lower=label:lower()
        if value>=0 and value<32 and value%1==0 and not seen[value] and
           not lower:find('max') and not lower:find('count') and not lower:find('invalid') and
           not lower:find('num') and lower~='none' and lower~='end' then
            seen[value]=true;slots[#slots+1]={slot=value,slotEnumLabel=label}
        end
    end
    table.sort(slots,function(a,b) return a.slot<b.slot end)
    if #slots==0 or #slots>16 then return unavailable('Slot enum unavailable or outside bounded limit') end
    local result={captureStatus='partial',source='ItemManager.getEquipData(CharacterID.ch000000_00).get(slot)',
        playerCharacterId=id,userCrossChecked=false,slots={}}
    for _,entry in ipairs(slots) do
        entry.captureStatus='unavailable'
        local ok,err=pcall(function()
            local item=get_slot:call(data,entry.slot)
            if not item then entry.reason='Slot returned no object; not classified as empty';return end
            local param=item:get_field('_ItemData')
            if not param then entry.reason='Item parameter unavailable';return end
            local item_id=param:get_field('_Id')
            if type(item_id)~='number' or item_id%1~=0 or item_id<=0 then
                entry.reason='Item ID unavailable or not positive';entry.rawItemId=item_id;return
            end
            entry.itemId=item_id;entry.captureStatus='partial'
            if not name_cache[item_id] then
                local get_name=checked_method(sdk.find_type_definition('app.GUIBase'),
                    'getElfItemName(System.Int32, System.Boolean)',2)
                if get_name then
                    local name_ok,name=pcall(function() return get_name:call(nil,item_id,false) end)
                    if name_ok and type(name)=='string' and name~='' then name_cache[item_id]=name end
                end
            end
            entry.name=name_cache[item_id]
            entry.nameSource=entry.name and 'game GUIBase.getElfItemName' or 'unavailable; raw ID preserved'
            local stat_ok,stat_result=pcall(item_stats,item,param)
            entry.itemStats=stat_ok and stat_result or {captureStatus='error',reason=tostring(stat_result)}
            if entry.slot==0 or entry.slot==1 then
                entry.itemStats.weaponElement=computed_value(item,'app.ItemDefine.StorageData','get_WeaponElement',{},'app.AttackUserData.ElementType')
            end
        end)
        if not ok then entry.captureStatus='error';entry.reason=tostring(err) end
        result.slots[#result.slots+1]=entry
    end
    return result
end
local function position(player)
    -- Established source: DD2 Content Editor devtools.lua player transform read path.
    local go=player:call('get_GameObject')
    local transform=go and go:call('get_Transform')
    if not transform then return unavailable('Player transform unavailable') end
    local p=transform:call('get_UniversalPosition')
    if not p then return unavailable('Player world position unavailable') end
    for _,v in ipairs({p.x,p.y,p.z}) do
        if type(v)~='number' or v~=v or math.abs(v)==math.huge then return unavailable('Invalid coordinate') end
    end
    if p.x==nil or p.y==nil or p.z==nil then return unavailable('Incomplete coordinate') end
    return {captureStatus='partial',x=p.x,y=p.y,z=p.z,
        source='ManualPlayerHuman.GameObject.Transform.get_UniversalPosition',
        coordinateSpace='engine universal/world position',axisDirections='unverified',units='unverified',
        sceneIdentity=unavailable('Not established'),mapGridConversion='unavailable',
        gameplayStateVerified=false,precision='raw Lua numeric values without rounding'}
end
local function write(result,kind)
    serial=serial+1
    result.tool='AtlasSnapshot-DD2';result.version='0.11.0-experimental'
    result.capturedAtUtc=os.date('!%Y-%m-%dT%H:%M:%SZ')
    result.captureKind=kind;result.semanticsValidated=false
    local path='AtlasSnapshot-DD2-schema-latest.json'
    if kind=='raw_character_fields' then
        sequence=sequence+1
        result.sequence=sequence;result.session=session;result.capturedAtEpoch=os.time()
        result.refreshSeconds=5;result.staleAfterSeconds=15
        result.safeToTreatAsCurrentCharacter=false
        result.gameplayState='unverified; player reference alone does not prove active gameplay'
        path='AtlasSnapshot-DD2-slot-'..(sequence%2)..'.json'
    end
    local ok,saved=pcall(json.dump_file,path,result)
    if ok and saved and kind=='raw_character_fields' then
        -- Publish only after slot write succeeds. Reader verifies pointer twice + slot sequence.
        ok,saved=pcall(json.dump_file,'AtlasSnapshot-DD2-latest.json',
            {session=session,sequence=sequence,file=path,capturedAtEpoch=result.capturedAtEpoch})
    end
    message=(ok and saved) and ('Saved '..kind..': '..path) or ('Export failed: '..tostring(saved))
end
local function capture()
    local result={captureStatus='unavailable',stats=unavailable('Player unavailable'),
        stamina=unavailable('Player unavailable'),vocation=unavailable('Player unavailable'),
        equipment=unavailable('Player unavailable'),position=unavailable('Player unavailable'),inventory=unavailable('Not probed'),
        calculationEvidence=unavailable('Player unavailable'),
        characterTotals=unavailable('Player unavailable'),
        relationships=relationship_status(),
        npcLifeObservations={captureStatus='unavailable',records={},completeRoster=false,
            historicalPlayerKillsAvailable=false,absenceMeansDead=false,
            reason='Death/resurrection and player attribution require runtime schema validation'},
        quests={captureStatus='unavailable',reason='Schema only; progress not read',
            absenceMeansNeverCompleted=false,lifetimeHistoryGuaranteed=false}}
    local capture_ok,capture_error=pcall(function()
    local cm=sdk.get_managed_singleton('app.CharacterManager')
    local pf=field('app.CharacterManager','<ManualPlayerHuman>k__BackingField')
    local player=cm and pf and pf:get_data(cm)
    if player then
        result.captureStatus='partial'
        result.calculationEvidence=calculation_evidence(cm)
        result.characterTotals=character_totals(cm,player)
        local npc_ok,npc_rel,npc_life=pcall(npc_observations)
        if npc_ok then result.relationships=npc_rel;result.npcLifeObservations=npc_life
        else result.relationships={captureStatus='error',reason=tostring(npc_rel),completeRoster=false,absenceMeansZero=false} end
        for section,name in pairs(roots) do
            local ok,value=pcall(function()
                local f=field('app.Human',name)
                if not f then return unavailable('Confirmed field no longer available') end
                return read_fields(f:get_data(player),f:get_type(),0,{left=160},{})
            end)
            result[section]=ok and value or {captureStatus='error',reason=tostring(value)}
        end
        local gear_ok,gear_result=pcall(gear)
        result.equipment=gear_ok and gear_result or {captureStatus='error',reason=tostring(gear_result)}
        local pos_ok,pos_result=pcall(position,player)
        result.position=pos_ok and pos_result or {captureStatus='error',reason=tostring(pos_result)}
        local job_ok,job_labels=pcall(enum,'app.Character.JobEnum')
        if job_ok then
            for _,f in ipairs(result.vocation.fields or {}) do
                if f.name=='CurrentJob' then
                    for label,id in pairs(job_labels) do
                        if f.value==id then result.vocation.currentJobEnumLabel=label;break end
                    end
                end
            end
        end
    end
    end)
    if not capture_ok then result.captureStatus='error';result.reason=tostring(capture_error) end
    write(result,'raw_character_fields')
end
re.on_draw_ui(function()
    if imgui.tree_node('AtlasSnapshot DD2 - experimental probe') then
        imgui.text(message)
        if imgui.button('Capture loaded character') then requested=true end
        imgui.tree_pop()
    end
end)
re.on_frame(function()
    local ok,err=pcall(function()
        if startup then
            startup=false
            local result={captureStatus='partial',fields={},calculationTypes={}}
            local rel_ok,rel_value=pcall(relationship_schema)
            result.relationshipSchema=rel_ok and rel_value or {captureStatus='error',reason=tostring(rel_value)}
            for _,name in ipairs(calculation_types) do
                local ok,value=pcall(describe_type,name)
                result.calculationTypes[name]=ok and value or {captureStatus='error',reason=tostring(value)}
            end
            for _,name in pairs(roots) do result.fields[#result.fields+1]=schema('app.Human',name) end
            for _,name in ipairs({'<SkillContext>k__BackingField','<AbilityContext>k__BackingField',
                '<PawnDataContext>k__BackingField','WeightRankContext'}) do
                result.fields[#result.fields+1]=schema('app.Human',name)
            end
            result.fields[#result.fields+1]=schema('app.ItemManager','WeightDict')
            result.fields[#result.fields+1]=schema('app.CharacterManager','<ManualPlayerHuman>k__BackingField')
            result.fields[#result.fields+1]=schema('app.ItemManager','EquipDict')
            result.fields[#result.fields+1]=schema('app.QuestManager','QuestClearRecordDict')
            result.fields[#result.fields+1]=schema('app.QuestManager','CurrentActiveQuestIDList')
            write(result,'field_type_metadata_only')
        end
        local now=os.time()
        if requested or now>=next_refresh or now<next_refresh-5 then
            requested=false;next_refresh=now+5;capture()
        end
    end)
    if not ok then message='Capture failed: '..tostring(err) end
end)

