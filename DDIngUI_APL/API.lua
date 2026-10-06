-- [12.1] This boundary discards secret values instead of caching or coercing them.
local _, A = ...
local API = {}
A.API = API
function API.Public(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end
function API.Query(fn, ...)
    if type(fn) ~= "function" then return nil,nil,false end
    local ok,a,b = pcall(fn,...)
    if not ok then return nil,nil,false end
    if not API.Public(a) then return nil,nil,false end
    if not API.Public(b) then b=nil end
    return a,b,true
end
local function num(v)
    if not API.Public(v) or type(v) ~= "number" then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
API.Number = num
function API.Aliases(raw)
    if raw ~= nil and (type(raw) ~= "string" or #raw > 8192) then return nil,"aliases must be text up to 8192 bytes" end
    local result,line = {},0
    for text in ((raw or "").."\n"):gmatch("(.-)\n") do
        line=line+1
        text=text:gsub("#.*$",""):match("^%s*(.-)%s*$")
        if text ~= "" then
            local key,id=text:match("^([%a_][%w_]*)%s*=%s*(%d+)$")
            id=tonumber(id)
            if not key or not id or id < 1 or id > 10000000 then return nil,"alias line "..line..": name=spellID" end
            if result[key] then return nil,"duplicate alias: "..key end
            result[key]=id
        end
    end
    return result
end
function API.Resolve(token, aliases, aura)
    if aliases and aliases[token] then return aliases[token] end
    local explicit=token:match("^spell_(%d+)$")
    if explicit then
        local id=tonumber(explicit)
        if id and id >= 1 and id <= 10000000 then return id end
        return nil
    end
    local candidates=A.Packs.spells[token]
    if not candidates then return nil end
    if aura and #candidates == 1 then return candidates[1] end
    local found,unreadable
    for _,id in ipairs(candidates) do
        local known=API.Query(IsPlayerSpell,id)
        if known == true then
            if found and found ~= id then return nil end -- ambiguity requires an explicit alias
            found=id
        elseif known ~= false then unreadable=true end
    end
    -- False is evidence of an unlearned action; nil is a missing/ambiguous mapping.
    if not found and not aura and not unreadable then return false end
    return found
end
function API.Bind(pack, aliases)
    local bindings={}
    for token,isSpell in pairs(pack.actions) do
        if isSpell then bindings[token]=API.Resolve(token,aliases) end
    end
    for ref in pairs(pack.refs) do
        local category,token=ref:match("^([%w_]+)%.([%w_]+)%.")
        if token and (category == "buff" or category == "cooldown") then
            bindings[category.."."..token]=API.Resolve(token,aliases,category == "buff")
        end
    end
    return bindings
end
local powers={mana=0,rage=1,focus=2,energy=3,combo_points=4,runic_power=6,soul_shards=7,
    astral_power=8,holy_power=9,maelstrom=11,chi=12,insanity=13,arcane_charges=16,fury=17,pain=18,essence=19}
local function cooldown(id, now)
    if not id then return nil end
    local info=API.Query(C_Spell and C_Spell.GetSpellCooldown,id)
    if type(info) ~= "table" then return nil end
    if not API.Public(info.isEnabled) then return nil end
    local enabled=info.isEnabled
    if enabled == false then return nil,false end
    if enabled ~= true then return nil end
    -- 12.1 exposes isActive even when the numeric timing fields are secret.
    -- Do not require those fields to establish that a spell is ready.
    if API.Public(info.isActive) and info.isActive == false then return 0,true end
    local active=API.Public(info.isActive) and info.isActive == true
    local start,duration,rate=num(info.startTime),num(info.duration),num(info.modRate)
    if active and (not start or not duration or not rate or rate <= 0) then return nil,false end
    if not start or not duration or not rate or rate <= 0 or enabled ~= true then return nil end
    local remaining=math.max(0,start+duration/rate-now)
    return remaining,remaining <= 0
end
local function aura(id, now)
    if not id then return {} end
    local data,_,readOK=API.Query(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID,id)
    if type(data) ~= "table" then
        -- A restricted lookup returning nil does not prove that a buff is absent.
        if readOK and API.Query(C_Secrets and C_Secrets.ShouldSpellAuraBeSecret,id) == false then
            return {up=false,down=true,remains=0,stack=0}
        end
        return {}
    end
    if num(data.spellId) ~= id then return {} end
    local stacks=num(data.applications)
    local result={up=true,down=false,stack=stacks and math.max(1,stacks)}
    local expiration,duration=num(data.expirationTime),num(data.duration)
    if expiration and duration then
        -- Infinite duration is deliberately unresolved for arithmetic comparisons.
        if duration > 0 then result.remains=math.max(0,expiration-now) end
    end
    return result
end
function API.Snapshot(pack, bindings, config)
    local now=GetTime()
    local result={values={active_enemies=config.targets},ready={},disabled={},reasons={}}
    local values,cds,auras=result.values,{},{}
    for ref in pairs(pack.refs) do
        local resource,field=ref:match("^([%w_]+)%.([%w_]+)$")
        resource=resource or ref
        local power=powers[resource]
        if power then
            local current=num(API.Query(UnitPower,"player",power))
            local maximum=num(API.Query(UnitPowerMax,"player",power))
            if not field then values[ref]=current
            elseif field == "max" then values[ref]=maximum
            elseif field == "deficit" and current and maximum then values[ref]=maximum-current
            elseif field == "pct" and current and maximum and maximum > 0 then values[ref]=current/maximum*100 end
        elseif ref == "in_combat" then values[ref]=API.Query(UnitAffectingCombat,"player")
        else
            local category,token,attribute=ref:match("^([%w_]+)%.([%w_]+)%.([%w_]+)$")
            if category == "cooldown" then
                if not cds[token] then
                    local remains,ready=cooldown(bindings["cooldown."..token],now)
                    cds[token]={remains=remains,ready=ready,up=ready}
                end
                values[ref]=cds[token][attribute]
            elseif category == "buff" then
                if not auras[token] then auras[token]=aura(bindings["buff."..token],now) end
                values[ref]=auras[token][attribute]
            end
            -- All other operands, including unmodeled talents/TTD, remain unknown.
        end
    end
    for token in pairs(pack.actions) do
        local id=bindings[token]
        if id == false then result.ready[token]=false; result.disabled[token]=true
        elseif id then
            local known=API.Query(IsPlayerSpell,id)
            local usable=API.Query(C_Spell and C_Spell.IsSpellUsable,id)
            local _,ready=cooldown(id,now)
            if known == false or usable == false or ready == false then
                result.ready[token]=false
                result.disabled[token]=known == false or ready == false
            elseif known == true and usable == true and ready == true then
                local harmful=API.Query(C_Spell and C_Spell.IsSpellHarmful,id)
                if harmful == false then result.ready[token]=true
                elseif harmful == true then
                    local target=API.Query(UnitCanAttack,"player","target")
                    local dead=API.Query(UnitIsDeadOrGhost,"target")
                    local range=API.Query(C_Spell and C_Spell.IsSpellInRange,id,"target")
                    if API.Query(C_Spell and C_Spell.SpellHasRange,id) == false then range=true end
                    if target == false or dead == true or range == false then result.ready[token]=false
                    elseif target == true and dead == false and range == true then result.ready[token]=true
                    else result.reasons[token]="target/range unavailable: "..token end
                end
            else
                result.reasons[token]=(known == nil and "learned status" or usable == nil and "usability" or "cooldown").." unavailable: "..token
            end
        else result.reasons[token]="spell ID unresolved: "..token
        end
    end
    return result
end
function API.Native()
    if not C_AssistedCombat then return nil,"Assisted Combat API unavailable","unavailable" end
    -- [FIX] Query the recommendation directly, independently of action-button visibility.
    -- IsAvailable describes the native assistant's setup; do not let it discard a valid sample.
    local value,_,readOK=API.Query(C_AssistedCombat.GetNextCastSpell,false)
    local id=num(value)
    if id and id > 0 then return id,nil,"ready" end
    if not readOK then return nil,"native recommendation restricted or failed","unreadable" end
    local available,reason=API.Query(C_AssistedCombat.IsAvailable)
    if available ~= true then return nil,type(reason) == "string" and reason or "Assisted Combat unavailable","unavailable" end
    return nil,"no native recommendation","empty"
end
function API.Spec()
    local index=num(API.Query(GetSpecialization))
    if index then return num(API.Query(GetSpecializationInfo,index)) end
end
function API.Keys()
    local keys={}
    local bars={[1]="ACTIONBUTTON",[3]="MULTIACTIONBAR3BUTTON",[4]="MULTIACTIONBAR4BUTTON",
        [6]="MULTIACTIONBAR1BUTTON",[5]="MULTIACTIONBAR2BUTTON",[13]="MULTIACTIONBAR5BUTTON",
        [14]="MULTIACTIONBAR6BUTTON",[15]="MULTIACTIONBAR7BUTTON"}
    -- Standard action slots only; macros and override bars need a separate verified mapping.
    for slot=1,180 do
        local kind,id=API.Query(GetActionInfo,slot)
        id=num(id)
        local bar=math.floor((slot-1)/12)+1
        if kind == "spell" and id and bars[bar] and (bar ~= 1 or API.Query(GetActionBarPage) == 1) then
            local key=API.Query(GetBindingKey,bars[bar]..((slot-1)%12+1))
            if type(key) == "string" and not keys[id] then keys[id]=key end
        end
    end
    return keys
end
