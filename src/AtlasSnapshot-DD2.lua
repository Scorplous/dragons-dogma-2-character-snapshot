-- AtlasSnapshot 0.21.0-candidate. Status-gated loaded journal; no lifetime/NG+ guarantee.
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
            if (not focus and i>256) or (type(focus)=='table' and i>4096) or #r.methods>=256 then r.methodsTruncated=true;break end
            local selected=not focus
            if focus then
                local label=m:get_name():lower()
                for _,word in ipairs(type(focus)=='table' and focus or {'sentiment','favor','pawn','npc','name','dead','death','kill','reviv','resurrect','crime','town','area','reputation','context','holder','hp','health','recover','loss','skill','ability','job','quest','location','rank','title','task','log','message'}) do
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
local function gear(ownerId)
    local id=ownerId or enum('app.CharacterID').ch000000_00
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
            if ownerId and item:get_field('_CharaId')~=ownerId then
                entry.reason='Equipment owner does not match pawn';return
            end
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
-- Combined gameplay discovery. Only known read accessors are invoked; unresolved
-- field semantics remain diagnostic evidence, never equipped skills or progress.
local function field_value(obj,owner,name)
    if not obj then return nil end
    local f=field(owner,name)
    return f and f:get_data(obj)
end
local function static_get(owner,name,args,ret,...)
    local supplied={...}
    local ok,value=pcall(function()
        local td=sdk.find_type_definition(owner);local selected
        for _,m in ipairs(td and td.get_methods and td:get_methods() or {}) do
            if m:get_name()==name and m:is_static() and m:get_num_params()==#args then
                local rt=m:get_return_type();local pts=m:get_param_types() or {}
                local match=rt and rt:get_full_name()==ret and #pts==#args
                for i,a in ipairs(args) do if not pts[i] or pts[i]:get_full_name()~=a then match=false end end
                if match then if selected then return nil end;selected=m end
            end
        end
        return selected and selected:call(nil,table.unpack(supplied))
    end)
    if ok then return value end
end
local function readable(value)
    if type(value)=='string' and value:match('%S') then return value end
end
local function health_observation(player)
    local character=field_value(player,'app.Human','<Chara>k__BackingField')
    if not character then return unavailable('Player Character unavailable') end
    local function number(name)
        local value,reason=safe_get(character,'app.Character',name,{},'System.Single')
        if type(value)=='number' and value==value and math.abs(value)~=math.huge and value>=0 then
            return {captureStatus='captured',value=value,source='Character.'..name}
        end
        return unavailable(reason or 'Expected finite nonnegative health value/signature unavailable')
    end
    return {captureStatus='partial',current=number('get_Hp'),reducedMaximum=number('get_ReducedMaxHp'),
        fullMaximum=number('get_OriginalMaxHp'),
        recoverableMaximum=unavailable('Recoverable maximum semantics pending validation'),
        lossGauge=unavailable('No inferred subtraction; native loss meaning pending validation'),
        semanticsValidated=false}
end
local function array_evidence(array,limit)
    if not array then return unavailable('Array unavailable') end
    local count=array:get_size()
    if type(count)~='number' or count<0 or count%1~=0 or count>100000 then return unavailable('Invalid array size') end
    local r={captureStatus='partial',count=count,truncated=count>limit,entries={},semanticsValidated=false}
    for i=0,math.min(count,limit)-1 do
        local ok,value=pcall(function()
            local item=array:get_element(i)
            if type(item)=='number' or type(item)=='boolean' or type(item)=='string' then return {index=i,value=item} end
            if not item then return {index=i,captureStatus='unavailable'} end
            local td=item:get_type_definition()
            return {index=i,data=read_fields(item,td,0,{left=48},{}),type=td:get_full_name()}
        end)
        r.entries[#r.entries+1]=ok and value or {index=i,captureStatus='error',reason=tostring(value)}
    end
    return r
end
local function skill_observations(player)
    local job=field_value(player,'app.Human','<JobContext>k__BackingField')
    local jobId=scalar_field(job,'CurrentJob')
    if type(jobId)~='number' or jobId<0 or jobId%1~=0 then return unavailable('Current vocation unavailable') end
    local r={captureStatus='partial',vocationId=jobId,
        vocationName=readable(static_get('app.GUIBase','getJobName',{'app.Character.JobEnum'},'System.String',jobId)),
        vocationRank=safe_get(job,'app.JobContext','calcJobRank',{'app.Character.JobEnum'},'System.UInt32',jobId),
        source='CurrentJob with context slot getters; never learned-skill catalogs',semanticsValidated=false}
    for _,spec in ipairs({{'equipped','<SkillContext>k__BackingField','app.HumanSkillContext','SkillSlot','getSkillID','app.HumanCustomSkillID'},
                         {'augments','<AbilityContext>k__BackingField','app.AbilityContext','AbilitySlot','getAbility','app.HumanAbilityID'}}) do
        local context=field_value(player,'app.Human',spec[2])
        local slots,seen={},{}
        for label,id in pairs(enum(spec[3]..'.'..spec[4])) do
            local lower=label:lower()
            if id>=0 and id<16 and id%1==0 and not seen[id] and lower~='none' and lower~='end' and
               not lower:find('max') and not lower:find('count') and not lower:find('invalid') and not lower:find('num') then
                seen[id]=true;slots[#slots+1]={id=id,label=label}
            end
        end
        table.sort(slots,function(a,b) return a.id<b.id end)
        local section={captureStatus='partial',records={},source=spec[3]..'.'..spec[5],currentVocationOnly=true}
        if not context or #slots==0 then section=unavailable('Context or runtime slot enum unavailable')
        else
            for _,slot in ipairs(slots) do
                local ok,record=pcall(function()
                    local id,reason=safe_get(context,spec[3],spec[5],{'app.Character.JobEnum',spec[3]..'.'..spec[4]},spec[6],jobId,slot.id)
                    local rec={slot=slot.id,slotLabel=slot.label,captureStatus='unavailable',reason=reason}
                    if type(id)~='number' or id%1~=0 then return rec end
                    if id<=0 then rec.captureStatus='empty';rec.rawId=id;return rec end
                    rec.captureStatus='partial'
                    if spec[1]=='equipped' then
                        rec.skillId=id
                        rec.level=safe_get(context,spec[3],'getCustomSkillLevel',{'app.HumanCustomSkillID'},'app.HumanCustomSkillLevelNo',id)
                        if type(rec.level)=='number' then rec.name=readable(static_get('app.GUIBase','getCustomSkillName',
                            {'app.Character.JobEnum','app.HumanCustomSkillID','app.HumanCustomSkillLevelNo'},'System.String',jobId,id,rec.level)) end
                    else
                        rec.abilityId=id;rec.name=readable(static_get('app.GUIBase','getAbilityName',{'app.HumanAbilityID'},'System.String',id))
                    end
                    rec.nameStatus=rec.name and 'captured' or 'unavailable'
                    return rec
                end)
                section.records[#section.records+1]=ok and record or {slot=slot.id,captureStatus='error',reason=tostring(record)}
            end
        end
        r[spec[1]]=section
    end
    return r
end
-- Evidence capture, not a claim of current-cycle or lifetime completion.
-- Runtime schema confirms these fields; live UI comparison must establish scope.
local function quest_clear_observations()
    local flow=sdk.get_managed_singleton('app.MainFlowManager')
    if safe_get(flow,'app.MainFlowManager','get_IsInGamePhase',{},'System.Boolean')~=true then
        return unavailable('Loaded in-game phase not verified')
    end
    local qm=sdk.get_managed_singleton('app.QuestManager')
    local dict=field_value(qm,'app.QuestManager','QuestClearRecordDict')
    if not dict then return unavailable('Quest clear dictionary unavailable') end
    local function integer(v) return type(v)=='number' and v==v and v>=0 and v<=2147483647 and v%1==0 end
    local count,free,version=scalar_field(dict,'_count'),scalar_field(dict,'_freeCount'),scalar_field(dict,'_version')
    local entries=dict:get_field('_entries')
    if not integer(count) or not integer(free) or free>count or not integer(version) or
        (count>0 and (not entries or count>entries:get_size())) then
        return unavailable('Quest clear dictionary bounds unavailable or inconsistent')
    end
    local r={captureStatus='partial',semanticsValidated=false,source='app.QuestManager.QuestClearRecordDict',
        session=session,capturedAtEpoch=os.time(),playthroughScope='unknown',
        currentPlaythrough=unavailable('Clear-record reset/carryover behavior in New Game Plus not validated'),
        previousCycles=unavailable('No validated previous-cycle or lifetime history source'),
        absenceMeansNeverCompleted=false,lifetimeHistoryGuaranteed=false,favorableOutcomeInferred=false,
        limitations={'Raw clear counts are not a validated current-playthrough completion list',
            'Quest completion does not establish branch outcome, NPC survival, rewards, or cutoff safety',
            'Counts and titles require live verification; missing titles preserve quest IDs'}}
    local raw={captureStatus='partial',records={},allocatedSlots=count,expectedLiveEntries=count-free,
        examinedSlots=math.min(count,512),truncated=count>512,entryErrors=0,entryDiagnostics={},errorReasonCounts={},
        scanComplete=false,allSlotsExamined=false,validRecordsComplete=false,
        collectionLayout='CoreLib dictionary next >= -1; live layout validation pending'}
    r.rawRecords=raw
    local seen,observed={},{}
    local gui=sdk.get_managed_singleton('app.GuiManager')
    for i=0,math.min(count,512)-1 do
        local diagnostic={slot=i}
        local ok,rec=pcall(function()
            local function invalid(code)
                diagnostic.reasonCode=code;error(code)
            end
            local e=entries:get_element(i)
            local nextValue=scalar_field(e,'next')
            diagnostic.nextValue=nextValue;diagnostic.key=scalar_field(e,'key')
            if type(nextValue)~='number' or nextValue%1~=0 or nextValue < -2147483648 or nextValue>=count then invalid('invalidEntryLink') end
            if nextValue < -1 then return nil end
            local id=scalar_field(e,'key');local value=e:get_field('value')
            local rid=scalar_field(value,'_QuestID');local clears=scalar_field(value,'_ClearCount')
            diagnostic.recordQuestId=rid;diagnostic.rawClearCount=clears
            if not integer(id) then invalid('invalidQuestId') end
            if id~=rid then invalid('recordIdentityMismatch') end
            if not integer(clears) then invalid('invalidClearCount') end
            if seen[id] then invalid('duplicateQuestId') end
            seen[id]=true
            observed[#observed+1]={slot=i,value=value,id=id,count=clears,nextValue=nextValue}
            local record={questId=id,rawClearCount=clears,playthroughScope='unknown',
                completionStatus='unvalidated',outcome='unknown',titleStatus='unavailable'}
            local view=safe_get(gui,'app.GuiManager','getQuestLog',{'app.QuestDefine.ID'},'app.QuestLogManager.QuestLogViewInfo',id)
            if view and scalar_field(view,'QuestId')==id then
                record.title=readable(scalar_field(view,'QuestName'))
                if record.title then record.titleStatus='captured' end
            end
            return record
        end)
        if not ok then raw.entryErrors=raw.entryErrors+1
            diagnostic.reasonCode=diagnostic.reasonCode or 'readError'
            raw.errorReasonCounts[diagnostic.reasonCode]=(raw.errorReasonCounts[diagnostic.reasonCode] or 0)+1
            diagnostic.reason=tostring(rec);if #raw.entryDiagnostics<16 then raw.entryDiagnostics[#raw.entryDiagnostics+1]=diagnostic end
        elseif rec then raw.records[#raw.records+1]=rec end
    end
    -- Recheck values as well as version: Dictionary removals/value replacements may
    -- not increment version. No cross-capture cache or save mutation is used.
    for _,o in ipairs(observed) do
        local e=entries:get_element(o.slot)
        local value=e and e:get_field('value')
        if not e or scalar_field(e,'key')~=o.id or scalar_field(e,'next')~=o.nextValue or value~=o.value or
            scalar_field(value,'_QuestID')~=o.id or scalar_field(value,'_ClearCount')~=o.count then
            return unavailable('Quest clear records changed while reading')
        end
    end
    if sdk.get_managed_singleton('app.QuestManager')~=qm or field_value(qm,'app.QuestManager','QuestClearRecordDict')~=dict or
        dict:get_field('_entries')~=entries or scalar_field(dict,'_count')~=count or scalar_field(dict,'_freeCount')~=free or
        scalar_field(dict,'_version')~=version or safe_get(flow,'app.MainFlowManager','get_IsInGamePhase',{},'System.Boolean')~=true then
        return unavailable('Quest clear source changed while reading')
    end
    raw.scanComplete=not raw.truncated and raw.entryErrors==0 and #raw.records==count-free
    raw.allSlotsExamined=not raw.truncated
    raw.validRecordsComplete=raw.scanComplete
    raw.captureStatus=raw.scanComplete and 'captured' or 'partial'
    return r
end
-- Independent of clear counters. Native ended/status labels are evidence, not
-- successful completion or proof that this list is isolated to the current cycle.
local function quest_log_evidence()
    local flow=sdk.get_managed_singleton('app.MainFlowManager')
    if safe_get(flow,'app.MainFlowManager','get_IsInGamePhase',{},'System.Boolean')~=true then return unavailable('In-game phase not verified') end
    local qlm=sdk.get_managed_singleton('app.QuestLogManager')
    local list=field_value(qlm,'app.QuestLogManager','_OrderedQuestList')
    if not list then return unavailable('Ordered quest-log list unavailable') end
    local count,version=scalar_field(list,'_size'),scalar_field(list,'_version')
    local items=list:get_field('_items')
    if type(count)~='number' or count<0 or count%1~=0 or count>2147483647 or type(version)~='number' or
        not items or count>items:get_size() then return unavailable('Quest-log bounds unavailable') end
    local r={captureStatus='partial',source='QuestLogManager._OrderedQuestList and identity-checked GuiManager.getQuestLog',
        capturedAtEpoch=os.time(),session=session,records={},entryErrors=0,orderedEntryErrors=0,entryDiagnostics={},
        listCount=count,examinedListEntries=math.min(count,256),truncated=count>256,scanComplete=false,
        semanticsValidated=false,currentPlaythroughValidated=false,absenceMeansNeverCompleted=false,
        completionStatus='unknown',playthroughScope='unknown',
        limitations={'Native ended status does not establish success or favorable outcomes',
            'Current-cycle reset and list coverage require live comparison',
            'Explicit probes are not proof of membership in the ordered log'}}
    local labels=enum('app.QuestLogManager.QuestStatus')
    local gui=sdk.get_managed_singleton('app.GuiManager')
    local ids,seen,listIds,observed={},{},{},{}
    for i=0,math.min(count,256)-1 do
        local id=items:get_element(i)
        if type(id)~='number' then id=scalar_field(id,'value__') or scalar_field(id,'m_value') end
        if type(id)~='number' or id<0 or id>2147483647 or id%1~=0 then return unavailable('Invalid quest-log ID') end
        listIds[i+1]=id
        if not seen[id] then seen[id]=true;ids[#ids+1]={id=id,origin='ordered log'} end
    end
    -- Small explicit investigation set; never treated as completed or as list members.
    for _,id in ipairs({30100,30110,20082,30040,30070}) do
        if not seen[id] then seen[id]=true;ids[#ids+1]={id=id,origin='explicit diagnostic probe'} end
    end
    for _,candidate in ipairs(ids) do
        local id=candidate.id
        local ok,rec=pcall(function()
            local view=safe_get(gui,'app.GuiManager','getQuestLog',{'app.QuestDefine.ID'},'app.QuestLogManager.QuestLogViewInfo',id)
            if not view or scalar_field(view,'QuestId')~=id then error('Missing or mismatched quest view') end
            local status=scalar_field(view,'<Status>k__BackingField')
            if type(status)~='number' or status%1~=0 then error('Quest status unavailable') end
            local names={};for name,value in pairs(labels) do if value==status then names[#names+1]=name end end;table.sort(names)
            local progressing=safe_get(qlm,'app.QuestLogManager','isQuestLogProgressing',{'app.QuestDefine.ID'},'System.Boolean',id)
            local ended=safe_get(qlm,'app.QuestLogManager','isQuestLogEnd',{'app.QuestDefine.ID'},'System.Boolean',id)
            local record={questId=id,origin=candidate.origin,title=readable(scalar_field(view,'QuestName')),
                rawStatus=status,statusEnumLabels=names,nativeProgressing=progressing,nativeEnded=ended,
                completionStatus='unknown',outcome='unknown',playthroughScope='unknown',
                impossibleDetail=readable(scalar_field(view,'<QuestImpossibleDetailMsg>k__BackingField')),
                reportInterpretation='diagnostic templates only; use currentJournal for gated text'}
            local function reportText(fieldName)
                local data=view:get_field(fieldName)
                if not data then return unavailable('No report object observed; no outcome inferred') end
                local function textOf(n)
                    local guid=data:get_field(n)
                    return guid and readable(static_get('app.MessageManager','getMessage',{'System.Guid'},'System.String',guid)) or nil
                end
                return {captureStatus='partial',base=textOf('_BaseMsg'),detail=textOf('_DetailMsg'),
                    diagnosticTemplate=true,provesOutcome=false}
            end
            for _,spec in ipairs({{'report','<Report>k__BackingField'},{'impossible','<Impossible>k__BackingField'}}) do
                local text_ok,value=pcall(reportText,spec[2])
                record[spec[1]]=text_ok and value or unavailable('Report text read failed; status retained')
            end
            observed[#observed+1]={id=id,status=status,progressing=progressing,ended=ended}
            return record
        end)
        if ok then r.records[#r.records+1]=rec else
            r.entryErrors=r.entryErrors+1
            if candidate.origin=='ordered log' then r.orderedEntryErrors=r.orderedEntryErrors+1 end
            if #r.entryDiagnostics<16 then r.entryDiagnostics[#r.entryDiagnostics+1]={questId=id,origin=candidate.origin,reason=tostring(rec)} end
        end
    end
    for _,o in ipairs(observed) do
        local view=safe_get(gui,'app.GuiManager','getQuestLog',{'app.QuestDefine.ID'},'app.QuestLogManager.QuestLogViewInfo',o.id)
        if not view or scalar_field(view,'QuestId')~=o.id or scalar_field(view,'<Status>k__BackingField')~=o.status or
            safe_get(qlm,'app.QuestLogManager','isQuestLogProgressing',{'app.QuestDefine.ID'},'System.Boolean',o.id)~=o.progressing or
            safe_get(qlm,'app.QuestLogManager','isQuestLogEnd',{'app.QuestDefine.ID'},'System.Boolean',o.id)~=o.ended then
            return unavailable('Quest-log status changed while reading')
        end
    end
    for i,id in ipairs(listIds) do
        local current=items:get_element(i-1)
        if type(current)~='number' then current=scalar_field(current,'value__') or scalar_field(current,'m_value') end
        if current~=id then return unavailable('Quest-log IDs changed while reading') end
    end
    if sdk.get_managed_singleton('app.QuestLogManager')~=qlm or field_value(qlm,'app.QuestLogManager','_OrderedQuestList')~=list or
        list:get_field('_items')~=items or scalar_field(list,'_size')~=count or scalar_field(list,'_version')~=version or
        safe_get(flow,'app.MainFlowManager','get_IsInGamePhase',{},'System.Boolean')~=true then return unavailable('Quest-log source changed while reading') end
    r.scanComplete=not r.truncated and r.entryErrors==0
    return r
end
-- A presentation of the observed loaded journal, not a reconstructed history.
local function current_journal(evidence)
    if not evidence or not evidence.records or evidence.captureStatus=='unavailable' or evidence.captureStatus=='error' then
        return unavailable('Quest-log evidence unavailable; no prior journal retained')
    end
    local r={captureStatus='partial',source=evidence.source,session=evidence.session,capturedAtEpoch=evidence.capturedAtEpoch,
        records={},nativeComplete={},nativeProgressing={},unknown={},listCount=evidence.listCount,
        examinedListEntries=evidence.examinedListEntries,truncated=evidence.truncated,
        entryErrors=evidence.orderedEntryErrors,scanComplete=not evidence.truncated and evidence.orderedEntryErrors==0,
        playthroughScope='observed loaded quest journal',currentPlaythroughValidated=false,
        lifetimeHistoryGuaranteed=false,absenceMeansNeverCompleted=false,favorableOutcomeInferred=false,
        limitations={'Native journal classification is not universal NG+ reset or lifetime history validation',
            'Completion report text does not establish rewards, NPC survival or favorable outcomes',
            'Unknown or conflicting native states remain unclassified; explicit probes are excluded'}}
    for _,e in ipairs(evidence.records) do
        if e.origin=='ordered log' then
            local state='unknown'
            if #e.statusEnumLabels==1 then
                if e.statusEnumLabels[1]=='Complete' and e.nativeEnded==true and e.nativeProgressing==false then state='nativeComplete'
                elseif e.statusEnumLabels[1]=='Progressing' and e.nativeProgressing==true and e.nativeEnded==false then state='nativeProgressing' end
            end
            local record={questId=e.questId,title=e.title,titleStatus=e.title and 'captured' or 'unavailable',
                journalState=state,orderedLogMember=true,rawStatus=e.rawStatus,statusEnumLabels=e.statusEnumLabels,
                nativeProgressing=e.nativeProgressing,nativeEnded=e.nativeEnded,outcome='unknown',
                completionReport=unavailable('No completion report presented for this native state')}
            if state=='nativeComplete' and e.report and (e.report.base or e.report.detail) then
                record.completionReport={captureStatus=e.report.captureStatus,base=e.report.base,detail=e.report.detail,
                    source='Native Complete journal report',provesFavorableOutcome=false}
            elseif state=='nativeComplete' then record.completionReport=unavailable('Native completion report text unavailable') end
            r.records[#r.records+1]=record;r[state][#r[state]+1]=record
        end
    end
    return r
end
local function active_quest_observations()
    local qm=sdk.get_managed_singleton('app.QuestManager')
    local list=field_value(qm,'app.QuestManager','CurrentActiveQuestIDList')
    if not list then return unavailable('Active quest list unavailable') end
    local td=list:get_type_definition()
    local sf=td:get_field('_size');local af=td:get_field('_items')
    local count=sf and sf:get_data(list);local items=af and af:get_data(list)
    if type(count)~='number' or count<0 or count%1~=0 or not items or count>items:get_size() then
        return unavailable('Active quest list inconsistent or unavailable')
    end
    local gui=sdk.get_managed_singleton('app.GuiManager')
    local qlm=sdk.get_managed_singleton('app.QuestLogManager')
    local tracked=safe_get(gui,'app.GuiManager','get_TargetQuestId',{},'app.QuestDefine.ID')
    local r={captureStatus='partial',source='QuestManager.CurrentActiveQuestIDList',
        count=count,truncated=count>64,activeRecords={},completeRoster=false,
        trackedQuestId=type(tracked)=='number' and tracked>=0 and tracked or nil,
        trackedStatus=tracked==-1 and 'none' or (type(tracked)=='number' and 'captured' or 'unavailable'),
        completedHistory=unavailable('Completed record semantics not yet validated'),
        absenceMeansNeverCompleted=false,lifetimeHistoryGuaranteed=false}
    local function quest_record(id)
            local progressing=safe_get(qlm,'app.QuestLogManager','isQuestLogProgressing',{'app.QuestDefine.ID'},'System.Boolean',id)
            if type(progressing)~='boolean' then r.filterUnavailable=true end
            if progressing~=true then return nil end
            local view,err=safe_get(gui,'app.GuiManager','getQuestLog',{'app.QuestDefine.ID'},'app.QuestLogManager.QuestLogViewInfo',id)
            if not view or scalar_field(view,'QuestId')~=id then return {questId=id,captureStatus='unavailable',reason=err or 'Quest view identity unavailable/mismatched'} end
            local task=view:get_field('<Task>k__BackingField')
            local progress=unavailable('Current task unavailable; no progress percentage inferred')
            if task then
                local function translate(fieldName)
                    local ok,guid=pcall(function() return task:get_field(fieldName) end)
                    return ok and guid and readable(static_get('app.MessageManager','getMessage',{'System.Guid'},'System.String',guid)) or nil
                end
                progress={captureStatus='partial',objective=translate('_BaseMsg'),detail=translate('_DetailMsg'),
                    isTimed=scalar_field(task,'_IsTimed'),source='Verified progressing quest current Task',
                    completionPercentage=unavailable('Not inferred from task text'),
                    checklist=unavailable('Checklist counters/conditions not validated')}
            end
            return {questId=id,tracked=id==r.trackedQuestId,captureStatus='partial',progressingVerified=true,
                title=readable(scalar_field(view,'QuestName')),summary=readable(scalar_field(view,'QuestSummary')),
                progress=progress,rawStatus=scalar_field(view,'<Status>k__BackingField')}
    end
    r.trackedQuest=unavailable('No verified progressing tracked quest')
    r.source='CurrentActiveQuestIDList filtered by QuestLogManager.isQuestLogProgressing'
    local seen={}
    for i=0,math.min(count,64)-1 do
        local ok,rec=pcall(function()
            local id=items:get_element(i)
            if type(id)~='number' then id=scalar_field(id,'value__') or scalar_field(id,'m_value') end
            if type(id)~='number' or id<0 or id%1~=0 or seen[id] then return nil end
            seen[id]=true;return quest_record(id)
        end)
        if ok and rec then r.activeRecords[#r.activeRecords+1]=rec;if rec.questId==r.trackedQuestId then r.trackedQuest=rec end
        elseif not ok then r.entryErrors=(r.entryErrors or 0)+1 end
    end
    if r.trackedQuestId and not seen[r.trackedQuestId] then
        local ok,rec=pcall(quest_record,r.trackedQuestId)
        if ok and rec then r.trackedQuest=rec end
    end
    if sf:get_data(list)~=count or af:get_data(list)~=items then return unavailable('Quest list changed while reading') end
    if r.filterUnavailable then
        r.filterStatus='partial or unavailable; omitted IDs are not confirmed inactive'
        if #r.activeRecords==0 then r.captureStatus='unavailable' end
    else r.filterStatus='captured for evaluated IDs' end
    return r
end
local function native_area_observation()
    local r={captureStatus='partial',source='AIAreaUtil player queries',displayName=unavailable('Localized area mapping pending validation'),
        coordinateConversion='No coordinate mapping used',semanticsValidated=false}
    for _,spec in ipairs({{'areaId','areaEnumLabel','getPlayerArea','app.AIAreaDefinition'},
                         {'localAreaId','localAreaEnumLabel','getPlayerUILocalArea','app.AILocalAreaDefinition'}}) do
        local td=sdk.find_type_definition('app.AIAreaUtil')
        local selected
        for _,m in ipairs(td and td.get_methods and td:get_methods() or {}) do
            local rt=m:get_return_type()
            if m:get_name()==spec[3] and m:get_num_params()==0 and m:is_static() and rt and rt:get_full_name()==spec[4] then
                if selected then selected=nil;break end
                selected=m
            end
        end
        if selected then
            local ok,id=pcall(function() return selected:call(nil) end)
            if ok and type(id)=='number' and id>=0 and id%1==0 then
                r[spec[1]]=id
                for name,value in pairs(enum(spec[4])) do if id==value then r[spec[2]]=name end end
            end
        end
    end
    r.areaName=r.areaId and readable(static_get('app.GUIBase','getAIAreaName',{'app.AIAreaDefinition'},'System.String',r.areaId)) or nil
    r.localAreaName=r.localAreaId and readable(static_get('app.GUIBase','getAILocalAreaName',{'app.AILocalAreaDefinition'},'System.String',r.localAreaId)) or nil
    local localName=r.localAreaName~=r.localAreaEnumLabel and r.localAreaName or nil
    local areaName=r.areaName~=r.areaEnumLabel and r.areaName or nil
    r.displayName=localName or areaName or unavailable('Native localized name unavailable')
    return r
end
local function gameplay_schema()
    local r={captureStatus='partial',metadataOnly=true,methodsInvoked=false,types={}}
    for _,name in ipairs({'app.Character','app.HitController','app.HitPointContext','app.HumanSkillContext',
        'app.HumanSkillContext.SkillSlot','app.HumanSkillContext.EquipedSkill','app.AbilityContext',
        'app.AbilityContext.AbilitySlot','app.AbilityContext.EquipedAbility','app.JobContext',
        'app.GUIBase','app.GuiManager','app.QuestManager','app.QuestLogManager',
        'app.QuestLogManager.QuestLogViewInfo','app.QuestLogManager.QuestLogInfo','app.QuestLogManager.QuestStatus',
        'app.QuestLogResource.QuestLogReportData','app.QuestLogResource.QuestLogImpossibleData','app.QuestLogResource.QuestLogInfoDataBase',
        'app.QuestManager.QuestClearRecordData','app.QuestLogResource','app.QuestLogResource.QuestLogTaskData','app.QuestLogResource.QuestLogTaskCheckListData',
        'app.AIAreaUtil','app.AIAreaManager','app.UIAreaManager','app.UIAreaMapData',
        'app.MessageManager'}) do
        local ok,value=pcall(describe_type,name,true)
        r.types[name]=ok and value or {captureStatus='error',reason=tostring(value)}
    end
    return r
end
-- Storage owner and accessor documented by MyDD2Mod and Inventory-Manager.
-- Only the read accessor is used; no transfer, grant, delete or quantity setters.
local storage_scans={}
local player_inventory_scans={}
local function stored_items(carriedOwner,identity,scanCache)
    local storage_scans=scanCache or storage_scans
    local owner=carriedOwner or 65535
    local manager=sdk.get_managed_singleton('app.ItemManager')
    local listType='System.Collections.Generic.List`1<app.ItemManager.StorageMasterData>'
    local getter=exact_method('app.ItemManager','getStorageMasterList',{'app.CharacterID'},listType)
    if not manager or not getter then storage_scans[owner]=nil;return unavailable('Storage list exact signature unavailable; inspect storageSchema') end
    local list=getter:call(manager,owner)
    if not list then storage_scans[owner]=nil;return unavailable('Storage list unavailable') end
    local td=list:get_type_definition()
    if td:get_full_name()~=listType then storage_scans[owner]=nil;return unavailable('Unexpected storage list type') end
    local sf,af,vf=td:get_field('_size'),td:get_field('_items'),td:get_field('_version')
    if not sf or not af or not vf then storage_scans[owner]=nil;return unavailable('Storage list consistency fields unavailable') end
    local count,items,version=sf:get_data(list),af:get_data(list),vf:get_data(list)
    local function integer(n,minimum) return type(n)=='number' and n==n and n<math.huge and n%1==0 and n>=minimum end
    if not integer(count,0) or count>65536 or not integer(version,0) or not items or items:get_size()<count then
        storage_scans[owner]=nil;return unavailable('Invalid storage list bounds/version')
    end
    local s=storage_scans[owner]
    if not s or s.list~=list or s.items~=items or s.version~=version or s.count~=count or s.finished or s.identity~=identity then
        s={list=list,items=items,version=version,count=count,next=0,records={},seen={},errors=0,startedAtEpoch=os.time(),identity=identity};storage_scans[owner]=s
    end
    for i=s.next,math.min(s.next+32,count,4096)-1 do
        local ok,record=pcall(function()
            local master=items:get_element(i)
            local data=master and master:get_field('_Param')
            if not data or data:get_type_definition():get_full_name()~='app.ItemDefine.StorageData' then error('Stored instance unavailable/type mismatch') end
            local id,quantity,storageId=data:get_field('_ItemId'),data:get_field('_Num'),data:get_field('_StorageId')
            if data:get_field('_CharaId')~=owner then error('Storage ownership mismatch') end
            local equipped=data:get_field('_IsEquipped')
            if carriedOwner and equipped==true then return nil end
            if equipped~=false then error('Storage equipped state mismatch') end
            if not integer(id,1) or not integer(quantity,1) or not integer(storageId,0) then error('Invalid stored identity or quantity') end
            local param=data:get_field('_ItemData')
            if not param or param:get_field('_Id')~=id then error('Stored item parameter identity mismatch') end
            local rec={recordIndex=i,itemId=id,storageId=storageId,storageIdRepeated=s.seen[storageId]==true,
                quantity=quantity,observedAtEpoch=os.time(),captureStatus='partial',source='StorageMasterData._Param'}
            if not name_cache[id] then
                local nameMethod=checked_method(sdk.find_type_definition('app.GUIBase'),'getElfItemName(System.Int32, System.Boolean)',2)
                if nameMethod then
                    local good,name=pcall(function() return nameMethod:call(nil,id,false) end)
                    if good and type(name)=='string' and name~='' then name_cache[id]=name end
                end
            end
            rec.name=name_cache[id];rec.nameStatus=rec.name and 'captured' or 'unavailable'
            rec.effectiveItemStats=unavailable('Not verified as equipment')
            local hasEquipmentFields=false
            for _,key in ipairs({'_PhysicalAttack','_PhysicalDefence'}) do
                local good,value=pcall(function() return param:get_field(key) end)
                if good and type(value)=='number' then hasEquipmentFields=true end
            end
            if hasEquipmentFields then
                rec.effectiveItemStats=computed_value(data,'app.ItemDefine.StorageData','makeEnhancedParam',{},'app.EquipParam')
            end
            rec.effectiveWeight=computed_value(data,'app.ItemDefine.StorageData','calcWeightPerPiece',{},'System.Int32')
            s.seen[storageId]=true
            return rec
        end)
        if ok then s.records[#s.records+1]=record else s.errors=s.errors+1;s.lastError=tostring(record) end
    end
    if sf:get_data(list)~=count or vf:get_data(list)~=version or af:get_data(list)~=items then
        storage_scans[owner]=nil;return unavailable('Storage changed during batch; accumulated scan discarded')
    end
    s.next=math.min(s.next+32,count,4096);s.finished=s.next>=count or s.next>=4096
    local records={};for i,rec in ipairs(s.records) do records[i]=rec end
    return {captureStatus='partial',source='ItemManager.getStorageMasterList(storage owner)',ownerId=owner,
        records=records,scanned=s.next,totalRows=count,scanComplete=s.next==count and s.errors==0,
        truncated=count>4096,entryErrors=s.errors,lastError=s.lastError,
        startedAtEpoch=s.startedAtEpoch,lastBatchAtEpoch=os.time(),batchLimit=32,
        consistency='List version checked; individual item values can change across batches',
        atomicSnapshot=false,ownershipSemanticsLiveValidated=false,
        absenceMeansNotOwned=false,scope=carriedOwner and 'Carried items only; equipped items excluded' or 'Inn storage only; not carried or pawn inventory'}
end
local function player_inventory(player)
    local expected=enum('app.CharacterID').ch000000_00
    local character=field_value(player,'app.Human','<Chara>k__BackingField')
    local id=safe_get(character,'app.Character','get_CharaID',{},'app.CharacterID')
    if type(expected)~='number' or expected%1~=0 or expected < -2147483648 or expected>4294967295 or
       expected==65535 or id~=expected then
        player_inventory_scans={};return unavailable('Player inventory identity unavailable or mismatched')
    end
    local result=stored_items(id,character,player_inventory_scans)
    if safe_get(character,'app.Character','get_CharaID',{},'app.CharacterID')~=id or
       field_value(player,'app.Human','<Chara>k__BackingField')~=character then
        player_inventory_scans={};return unavailable('Player identity changed during inventory capture')
    end
    result.scope='Player carried items only; equipped items, pawn bags and inn storage excluded'
    return result
end
-- Active roster only. A cached Human is trusted only after matching character IDs.
local function party_observations()
    local manager=sdk.get_managed_singleton('app.PawnManager')
    local listType='System.Collections.Generic.List`1<app.Pawn>'
    local list=safe_get(manager,'app.PawnManager','get_PartyPawnList',{},listType)
    -- Clear carried caches if a roster cannot be established; never reuse across gaps.
    local function clearCarried()
        for owner in pairs(storage_scans) do if owner~=65535 then storage_scans[owner]=nil end end
    end
    if not list then clearCarried();return unavailable('Current party list unavailable') end
    local td=list:get_type_definition()
    if td:get_full_name()~=listType then clearCarried();return unavailable('Party list type mismatch') end
    local sf,af,vf=td:get_field('_size'),td:get_field('_items'),td:get_field('_version')
    if not sf or not af or not vf then clearCarried();return unavailable('Party consistency fields unavailable') end
    local count,items,version=sf:get_data(list),af:get_data(list),vf:get_data(list)
    if type(count)~='number' or count%1~=0 or count<0 or count>16 or not items or items:get_size()<count or type(version)~='number' then
        clearCarried();return unavailable('Invalid party bounds/version')
    end
    local main=field_value(manager,'app.PawnManager','_MainPawn')
    local result={captureStatus='partial',records={},rosterComplete=count<=3,totalRows=count,
        source='PawnManager.get_PartyPawnList',semanticsValidated=false}
    local seen={}
    for i=0,math.min(count,3)-1 do
        local ok,record=pcall(function()
            local pawn=items:get_element(i)
            local character=field_value(pawn,'app.Pawn','<CachedCharacter>k__BackingField')
            local id=safe_get(character,'app.Character','get_CharaID',{},'app.CharacterID')
            if type(id)~='number' or id%1~=0 or id < -2147483648 or id>4294967295 or id==65535 or
                id==enum('app.CharacterID').ch000000_00 or seen[id] then error('Missing or duplicate pawn identity') end
            seen[id]=true
            local r={characterId=id,role=pawn==main and 'main pawn' or 'recruited pawn',captureStatus='partial',
                equipment=unavailable('Not read'),skills=unavailable('Human identity unavailable'),
                inclination=unavailable('Inclination semantics not validated'),
                carriedInventory=unavailable('Carried inventory reader pending'),
                dragonsplague={status='unknown',captureStatus='unavailable',transmissionConfirmed=false}}
            local human=field_value(pawn,'app.Pawn','<CachedHuman>k__BackingField')
            local humanChar=field_value(human,'app.Human','<Chara>k__BackingField')
            local humanId=safe_get(humanChar,'app.Character','get_CharaID',{},'app.CharacterID')
            local context
            if humanId==id then
                local good,value=pcall(skill_observations,human)
                r.skills=good and value or {captureStatus='error',reason=tostring(value)}
                context=field_value(human,'app.Human','<PawnDataContext>k__BackingField')
            end
            if not context then
                local holder=field_value(pawn,'app.Pawn','CachedContextHolder')
                context=safe_get(holder,'app.ContextHolder','getContext',{},'app.PawnDataContext')
            end
            r.name=scalar_field(context,'_Name')
            local personality=scalar_field(context,'_Personality')
            if type(personality)=='number' and personality%1==0 then
                r.inclination={captureStatus='partial',rawId=personality,source='PawnDataContext._Personality',semanticsValidated=false}
                for label,value in pairs(enum('app.PersonalityDefine.PersonalityID')) do
                    if value==personality then r.inclination.enumLabel=label;break end
                end
            end
            local level=scalar_field(context,'_PossessionLv')
            if type(level)=='number' then
                r.dragonsplague.rawPossessionLevel=level
                r.dragonsplague.captureStatus='partial'
                r.dragonsplague.reason='Raw field only; disease and transmission interpretation unvalidated'
            end
            local inventoryOk,inventory=pcall(stored_items,id,pawn)
            r.carriedInventory=inventoryOk and inventory or {captureStatus='error',reason=tostring(inventory)}
            if not inventoryOk then storage_scans[id]=nil end
            local good,value=pcall(gear,id)
            r.equipment=good and value or {captureStatus='error',reason=tostring(value)}
            if r.equipment.slots then
                r.equipment.playerCharacterId=nil;r.equipment.characterId=id
                r.equipment.source='ItemManager.getEquipData(verified pawn CharacterID).get(slot)'
            end
            if safe_get(character,'app.Character','get_CharaID',{},'app.CharacterID')~=id then error('Pawn identity changed during capture') end
            return r
        end)
        if ok then result.records[#result.records+1]=record
        else result.rosterComplete=false;result.lastError=tostring(record) end
    end
    if sf:get_data(list)~=count or vf:get_data(list)~=version or af:get_data(list)~=items then
        clearCarried();return unavailable('Party changed during capture; records discarded')
    end
    for owner in pairs(storage_scans) do
        if owner~=65535 and not seen[owner] then storage_scans[owner]=nil end
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
    result.tool='AtlasSnapshot-DD2';result.version='0.21.0-candidate'
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
        equipment=unavailable('Player unavailable'),position=unavailable('Player unavailable'),inventory=unavailable('Player unavailable'),storage=unavailable('Player unavailable'),
        health=unavailable('Player unavailable'),skills=unavailable('Player unavailable'),location=unavailable('Player unavailable'),
        calculationEvidence=unavailable('Player unavailable'),party=unavailable('Player unavailable'),
        characterTotals=unavailable('Player unavailable'),
        relationships=relationship_status(),
        npcLifeObservations={captureStatus='unavailable',records={},completeRoster=false,
            historicalPlayerKillsAvailable=false,absenceMeansDead=false,
            reason='Death/resurrection and player attribution require runtime schema validation'},
        quests={captureStatus='unavailable',reason='Schema only; progress not read',completedHistory=unavailable('Player unavailable'),logStatusEvidence=unavailable('Player unavailable'),currentJournal=unavailable('Player unavailable'),
            absenceMeansNeverCompleted=false,lifetimeHistoryGuaranteed=false}}
    local capture_ok,capture_error=pcall(function()
    local cm=sdk.get_managed_singleton('app.CharacterManager')
    local pf=field('app.CharacterManager','<ManualPlayerHuman>k__BackingField')
    local player=cm and pf and pf:get_data(cm)
    if not player then storage_scans={};player_inventory_scans={} end
    if player then
        result.captureStatus='partial'
        local storage_ok,storage_result=pcall(stored_items)
        result.storage=storage_ok and storage_result or {captureStatus='error',reason=tostring(storage_result)}
        if not storage_ok then storage_scans[65535]=nil end
        local inventory_ok,inventory_result=pcall(player_inventory,player)
        result.inventory=inventory_ok and inventory_result or {captureStatus='error',reason=tostring(inventory_result)}
        if not inventory_ok then player_inventory_scans={} end
        for _,spec in ipairs({{'party',party_observations},{'health',health_observation},{'skills',skill_observations},
                              {'quests',active_quest_observations},{'location',native_area_observation}}) do
            local ok,value=pcall(spec[2],player)
            result[spec[1]]=ok and value or {captureStatus='error',reason=tostring(value)}
            if spec[1]=='party' and (not ok or value.captureStatus=='unavailable' or value.captureStatus=='error') then
                for owner in pairs(storage_scans) do if owner~=65535 then storage_scans[owner]=nil end end
            end
        end
        result.quests.absenceMeansNeverCompleted=false;result.quests.lifetimeHistoryGuaranteed=false
        local clear_ok,clear_result=pcall(quest_clear_observations)
        result.quests.completedHistory=clear_ok and clear_result or {captureStatus='error',reason=tostring(clear_result)}
        local log_ok,log_result=pcall(quest_log_evidence)
        result.quests.logStatusEvidence=log_ok and log_result or {captureStatus='error',reason=tostring(log_result)}
        local journal_ok,journal_result=pcall(current_journal,result.quests.logStatusEvidence)
        result.quests.currentJournal=journal_ok and journal_result or {captureStatus='error',reason=tostring(journal_result)}
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
            result.coverageSchema={metadataOnly=true,methodsInvoked=false,valuesRead=false,types={},
                purpose='Candidate signatures only; no wallet balance or gameplay semantics inferred',
                maxTypes=14,maxMethodsExaminedPerType=4096,maxMethodsRetainedPerType=256}
            local coverageWords={'money','wallet','cash','gold','rim','rift','currency','exp','level','rank',
                'job','skill','ability','weight','capacity','time','hour','minute','day','status','health',
                'special','subskill','personality','debil','save','player','phase','pause'}
            for _,name in ipairs({'app.Player','app.CharacterManager','app.GuiManager','app.GUIParameterData',
                'app.ItemManager','app.ItemCashData','app.JobContext','app.HumanSkillContext','app.AbilityContext',
                'app.PawnDataContext','app.PawnManager','app.TimeManager','app.MainFlowManager','app.Human'}) do
                local good,value=pcall(describe_type,name,coverageWords)
                result.coverageSchema.types[name]=good and value or {captureStatus='error',reason=tostring(value)}
            end
            result.storageSchema={metadataOnly=true,methodsInvoked=false,types={}}
            for _,name in ipairs({'app.ItemManager','app.ItemManager.StorageMasterData','app.ItemDefine.StorageData',
                'System.Collections.Generic.List`1<app.ItemManager.StorageMasterData>',
                'app.PersonalityDefine.PersonalityID','app.Personality','app.PawnDataContext','app.ContextHolder'}) do
                local ok,value=pcall(describe_type,name,false)
                result.storageSchema.types[name]=ok and value or {captureStatus='error',reason=tostring(value)}
            end
            local discovery_ok,discovery=pcall(gameplay_schema)
            result.gameplaySchema=discovery_ok and discovery or {captureStatus='error',reason=tostring(discovery)}
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

