local ADDON, FX = ...
_G.DDingUI_FX = FX
FX.version = "2.2.0"
FX.active, FX.auraState, FX.soundRegistrations = {}, {}, {}
FX.LSM = LibStub("LibSharedMedia-3.0")
FX.LSM:Register("sound", "DD_Hollow Purple", [[Interface\AddOns\DDingUI_FX\Media\DD_Hollow_Purple.mp3]])
FX.LSM:Register("sound", "DD_Ryoiki_Tenkai", [[Interface\AddOns\DDingUI_FX\Media\DD_Ryoiki_Tenkai.mp3]])
FX.LSM:Register("sound", "DD_Makora", [[Interface\AddOns\DDingUI_FX\Media\DD_Makora.mp3]])
FX.LSM:Register("sound", "DD_Zoltraak", [[Interface\AddOns\DDingUI_FX\Media\DD_Zoltraak.mp3]])
FX.LSM:Register("sound", "DD_Time Rewind", [[Interface\AddOns\DDingUI_FX\Media\DD_Time_Rewind.mp3]])
FX.LSM:Register("sound", "DD_Minazuki", [[Interface\AddOns\DDingUI_FX\Media\DD_Minazuki.mp3]])

function FX.IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

function FX.Number(value, low, high, fallback)
    if FX.IsSecret(value) then return fallback end
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return math.max(low, math.min(high, n))
end

local function Integer(value, low, high)
    local n = FX.Number(value, low, high)
    return n and tonumber(value) == n and n % 1 == 0 and n or nil
end

function FX:Message(text)
    if self.window and self.window.status then self.window.status:SetText(text) end
    self.lastMessage = text
end

function FX:CanEdit()
    if InCombatLockdown() then return false end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or self.IsSecret(restricted) or restricted then return false end
    end
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        for _, kind in ipairs({0, 1, 2}) do
            local ok, restricted = pcall(C_RestrictedActions.IsAddOnRestrictionActive, kind)
            if not ok or self.IsSecret(restricted) or restricted then return false end
        end
    end
    return true
end

function FX:ValidatePreset(source)
    if type(source) ~= "table" then return nil, "TGA 정보를 입력하세요." end
    local name = type(source.name) == "string" and source.name:match("^%s*(.-)%s*$") or ""
    local path = type(source.path) == "string" and source.path:match("^%s*(.-)%s*$"):gsub("/", "\\") or ""
    if name == "" or #name > 120 then return nil, "프리셋 이름을 입력하세요 (최대 120바이트)." end
    if #path > 260 or not path:lower():match("^interface\\.+%.[tT][gG][aA]$")
        or path:find("..", 1, true) or path:find('[%c<>:"|?*]') then
        return nil, "Interface\\ 로 시작하는 TGA 파일 경로를 입력하세요."
    end
    local cols, rows = Integer(source.columns, 1, 32), Integer(source.rows, 1, 32)
    local pages = Integer(source.pages or 1, 1, 16)
    local displayScale = self.Number(source.displayScale or 1, .25, 4)
    local count = cols and rows and pages and Integer(source.frames, 1, cols * rows * pages)
    local fps = self.Number(source.fps, 1, 60)
    if not cols or not rows or not count or not fps or not displayScale then return nil, "행·열·프레임 수·FPS를 확인하세요." end
    -- Reject out-of-range inputs rather than silently changing sheet geometry.
    if tonumber(source.columns) ~= cols or tonumber(source.rows) ~= rows
        or tonumber(source.frames) ~= count or tonumber(source.fps) ~= fps
        or tonumber(source.displayScale or 1) ~= displayScale then
        return nil, "행/열 1~32, 프레임 수는 칸 수 이하, FPS 1~60을 사용하세요."
    end
    return {name=name, path=path, columns=cols, rows=rows, frames=count, fps=fps, pages=pages, displayScale=displayScale}
end

function FX:NormalizeRule(source)
    if type(source) ~= "table" then return end
    local spellID = Integer(source.spellID, 1, 100000000)
    if not spellID then return end
    local trigger = source.trigger
    if trigger ~= "START" and trigger ~= "SUCCESS" and trigger ~= "AURA" then return end
    return {
        spellID=spellID, trigger=trigger, enabled=source.enabled ~= false,
        preset=type(source.preset) == "string" and source.preset or "",
        sound=type(source.sound) == "string" and source.sound or "",
        width=self.Number(source.width, 16, 1024, 256),
        height=self.Number(source.height, 16, 1024, 256),
        scale=self.Number(source.scale, 10, 400, 100),
        opacity=self.Number(source.opacity, 0, 100, 100),
        x=self.Number(source.x, -4096, 4096, 0), y=self.Number(source.y, -4096, 4096, 0),
        speed=self.Number(source.speed, .25, 4, 1),
    }
end

function FX:EffectSize(rule)
    -- Keep legacy dimensions as the 100% baseline, including non-square effects.
    local factor = (rule.scale or 100) / 100
    local preset = self.presets and self.presets[rule.preset]
    factor = factor * (preset and preset.displayScale or 1)
    return rule.width * factor, rule.height * factor
end

function FX:ResolveSpell(input)
    if type(input) ~= "string" then return end
    input = input:match("^%s*(.-)%s*$")
    if input == "" then return end
    local id = tonumber(input)
    if id and (id <= 0 or id % 1 ~= 0 or id > 100000000) then return end
    local ok, info = pcall(C_Spell.GetSpellInfo, id or input)
    if ok and not self.IsSecret(info) and type(info) == "table" and not self.IsSecret(info.spellID) then
        return info.spellID, info
    end
    -- Explicit IDs can be registered before their spell data is cached.
    if id then
        if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end
        return id
    end
end

function FX:SpellName(id)
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and not self.IsSecret(info) and type(info) == "table" and not self.IsSecret(info.name) then
        return info.name or tostring(id), info.iconID
    end
    return "주문 #" .. id
end

function FX:SaveRule(index, source)
    if not self:CanEdit() then return nil, "전투·제한 상태가 끝난 후 저장하세요." end
    local rule = self:NormalizeRule(source)
    if not rule then return nil, "스킬과 발동 조건을 확인하세요." end
    if rule.preset ~= "" and not self.presets[rule.preset] then return nil, "모션 프리셋을 다시 선택하세요." end
    if rule.sound ~= "" and not self.LSM:Fetch("sound", rule.sound, true) then return nil, "효과음 제공 애드온을 확인하세요." end
    if index and not self.db.rules[index] then return nil, "선택한 항목이 없습니다." end
    if not index and #self.db.rules >= 128 then return nil, "최대 128개까지 등록할 수 있습니다." end
    index = index or #self.db.rules + 1
    self:StopLive()
    self.db.rules[index] = rule
    self:Rebuild()
    return index
end

function FX:DeleteRule(index)
    if not self:CanEdit() then return false, "전투·제한 상태가 끝난 후 삭제하세요." end
    if not index or not self.db.rules[index] then return false, "선택한 항목이 없습니다." end
    self:StopLive()
    table.remove(self.db.rules, index)
    self:Rebuild()
    return true
end

function FX:PlaySound(key)
    if not key or key == "" then return end
    local path = self.LSM:Fetch("sound", key, true)
    if not path then return false end
    return PlaySoundFile(path, "Master")
end

function FX:PreviewSoundFile(path)
    self:StopPreviewSound()
    if not path or path == "" then return end
    local played, handle = PlaySoundFile(path, "Master")
    if played then self.previewSoundHandle = handle end
end

function FX:StopPreviewSound()
    if self.previewSoundHandle then StopSound(self.previewSoundHandle); self.previewSoundHandle = nil end
end

function FX:HasNativeSound()
    return C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound
        and Enum and Enum.UnitAuraSoundTrigger
end

function FX:SyncSounds()
    if not self:HasNativeSound() then return end
    if not self:CanEdit() then self.soundPending = true; return end
    local desired = {}
    for _, rule in ipairs(self.db.rules) do
        if rule.enabled and rule.trigger == "AURA" and rule.sound ~= "" then
            local path = self.LSM:Fetch("sound", rule.sound, true)
            if path then desired[rule.spellID .. "\031" .. tostring(path)] = {spellID=rule.spellID, path=path} end
        end
    end
    self.soundPending = false
    for key, id in pairs(self.soundRegistrations) do
        if not desired[key] then
            local ok = pcall(C_UnitAuras.RemoveAuraSound, id)
            if ok then self.soundRegistrations[key] = nil else self.soundPending = true end
        end
    end
    -- If a stale sound could not be removed, do not register its replacement yet.
    if self.soundPending then return end
    for key, item in pairs(desired) do
        if not self.soundRegistrations[key] then
            local info = {unitToken="player", spellID=item.spellID, outputChannel="Master"}
            if type(item.path) == "number" then info.soundFileID = item.path else info.soundFileName = item.path end
            local ok, id = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added, info)
            if ok and not self.IsSecret(id) and type(id) == "number" then
                self.soundRegistrations[key] = id
            else self.soundPending = true end
        end
    end
end

function FX:ReadAura(id)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local predicate = C_Secrets and (C_Secrets.ShouldSpellAuraBeSecret or C_Secrets.ShouldAurasBeSecret)
    if predicate then
        local ok, restricted = pcall(predicate, id)
        if not ok or self.IsSecret(restricted) or restricted then return nil end
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok or self.IsSecret(aura) then return nil end
    if aura == nil then return false end
    if type(aura) ~= "table" or self.IsSecret(aura.spellId) or self.IsSecret(aura.isHelpful) then return nil end
    return aura.spellId == id and aura.isHelpful == true
end

function FX:ScanAuras(baseline)
    -- ponytail: at most 128 configured rules; index more finely only if this grows.
    for id, rules in pairs(self.auraRules) do
        local state = self:ReadAura(id)
        local previous = self.auraState[id]
        if state == true and previous == false and not baseline then
            for _, rule in ipairs(rules) do self:FireRule(rule, self:HasNativeSound()) end
        end
        self.auraState[id] = state
    end
end

function FX:Rebuild()
    self.spellRules, self.auraRules, self.auraState = {START={}, SUCCESS={}}, {}, {}
    for _, rule in ipairs(self.db.rules) do
        if rule.enabled then
            local list = rule.trigger == "AURA" and self.auraRules or self.spellRules[rule.trigger]
            list[rule.spellID] = list[rule.spellID] or {}
            table.insert(list[rule.spellID], rule)
        end
    end
    self:ScanAuras(true)
    self:SyncSounds()
end

function FX:GetCurrentSpecialization()
    local api = C_SpecializationInfo
    if api and api.IsInitialized then
        local ok, ready = pcall(api.IsInitialized)
        if not ok or self.IsSecret(ready) or not ready then return end
    end
    local getIndex = api and api.GetSpecialization or GetSpecialization
    local getInfo = api and api.GetSpecializationInfo or GetSpecializationInfo
    if not getIndex or not getInfo then return end
    local ok, index = pcall(getIndex)
    if not ok or not Integer(index, 1, 100) then return end
    local valid, id, name = pcall(getInfo, index)
    if not valid or not Integer(id, 1, 100000000) then return end
    return id, not self.IsSecret(name) and type(name) == "string" and name or ("전문화 #" .. id)
end

function FX:RefreshSpecialization()
    local id, name = self:GetCurrentSpecialization()
    -- Login may precede specialization data; leave saved rules intact until it is ready.
    if not id then return false end
    self.specName = name
    local db = self.db
    if db.specID == id then return false end
    local reopen = (self.editor and self.editor:IsShown()) or self.testing
    self:FlushInputs()
    -- OnHide finishes edits against the old specialization before swapping its rules.
    if self.editor then self.editor:HideImmediately() end
    self:StopLive(); self:StopPreviewSound()
    if self.window then self:HideHover(); self.Controls.CloseDropdowns() end
    if db.specID then
        -- Only inactive lists live in specRules, avoiding duplicate SavedVariables arrays.
        db.specRules[db.specID] = db.rules
        db.rules = db.specRules[id] or {}
        db.specRules[id] = nil
    end
    -- Legacy character-wide rules belong to the first known specialization.
    db.specID = id
    self:Rebuild()
    if self.window then
        self.window.search:SetText("")
        self:SelectRule(#db.rules > 0 and 1 or nil)
        if reopen then self.window:Show() end
    end
    return true
end

function FX:Initialize()
    local db = type(DDingUI_FXDB) == "table" and DDingUI_FXDB or {}
    db.rules = type(db.rules) == "table" and db.rules or {}
    db.presets = type(db.presets) == "table" and db.presets or {}
    db.nextPreset = math.floor(self.Number(db.nextPreset, 0, 100000000, 0))
    -- Keep invalid saved entries available for recovery instead of deleting them.
    db.invalidRules = type(db.invalidRules) == "table" and db.invalidRules or {}
    db.invalidPresets = type(db.invalidPresets) == "table" and db.invalidPresets or {}
    db.specID = Integer(db.specID, 1, 100000000)
    db.specRules = type(db.specRules) == "table" and db.specRules or {}
    local function NormalizeRules(sources)
        local rules = {}
        if type(sources) ~= "table" then
            db.invalidRules[#db.invalidRules+1] = sources
            return rules
        end
        for _, source in ipairs(sources) do
            local rule = self:NormalizeRule(source)
            if rule then rules[#rules+1] = rule else db.invalidRules[#db.invalidRules+1] = source end
        end
        return rules
    end
    db.rules = NormalizeRules(db.rules)
    for id, rules in pairs(db.specRules) do db.specRules[id] = NormalizeRules(rules) end
    for key, source in pairs(db.presets) do
        local preset = self:ValidatePreset(source)
        if type(key) == "string" and preset then db.presets[key] = preset
        else db.invalidPresets[key] = source; db.presets[key] = nil end
    end
    DDingUI_FXDB, self.db = db, db
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    db.minimap.minimapPos = self.Number(db.minimap.minimapPos, 0, 360, 225)
    -- [STYLE] Title-bar "GUI 크기" (series standard 50~150%, default 100%).
    db.guiScale = self.Number(db.guiScale, .5, 1.5, 1)
    self.presets = {}
    -- Retain early-version saved presets; shipped assets are defined in Presets.lua.
    for key, preset in pairs(db.presets) do self.presets[key] = preset end
    for key, source in pairs(self.Catalog) do
        local preset = self:ValidatePreset(source)
        if type(key) == "string" and key ~= "" and preset then self.presets[key] = preset end
    end
    if not self:RefreshSpecialization() then self:Rebuild() end
    self:CreateMinimapButton()
end

local events = CreateFrame("Frame")
FX.events = events
events:RegisterEvent("ADDON_LOADED")
for _, event in ipairs({"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA"}) do
    events:RegisterUnitEvent(event, "player")
end
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ADDON_RESTRICTION_STATE_CHANGED", "SPELL_DATA_LOAD_RESULT"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, unit, guid, spellID)
    if event == "ADDON_LOADED" then
        if unit == ADDON then FX:Initialize() end
        return
    end
    if not FX.db then return end
    if event == "UNIT_AURA" then
        if not FX.IsSecret(unit) and unit == "player" then FX:ScanAuras() end
    elseif event:find("^UNIT_SPELLCAST") then
        if FX.IsSecret(unit) or unit ~= "player" or FX.IsSecret(spellID) or type(spellID) ~= "number" then return end
        local kind = event == "UNIT_SPELLCAST_SUCCEEDED" and "SUCCESS" or "START"
        for _, rule in ipairs(FX.spellRules[kind][spellID] or {}) do FX:FireRule(rule) end
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        if FX.RefreshList then FX:RefreshList() end
        if FX.editor and FX.editor:IsShown() then FX:RefreshEditRulePicker() end
    else
        if event == "PLAYER_SPECIALIZATION_CHANGED" and (FX.IsSecret(unit) or unit ~= "player") then return end
        FX:RefreshSpecialization()
        if FX.editor and FX.editor:IsShown() and not FX:CanEdit() then FX:CloseEditMode(false) end
        if event == "PLAYER_ENTERING_WORLD" then FX:StopLive() end
        FX:ScanAuras(true)
        FX:SyncSounds()
        if FX.RefreshStatus then FX:RefreshStatus() end
    end
end)
FX.LSM.RegisterCallback(FX, "LibSharedMedia_Registered", function(_, kind)
    if kind == "sound" and FX.db then
        FX:SyncSounds()
        if FX.RefreshSounds then FX:RefreshSounds() end
    end
end)
SLASH_DDINGUI_FX1 = "/dfx"
SLASH_DDINGUI_FX2 = "/ddingfx"
-- [STYLE] C12: "/dfx edit" toggles edit mode; anything else toggles the settings window.
SlashCmdList.DDINGUI_FX = function(msg)
    local command = type(msg) == "string" and msg:match("^%s*(%S*)"):lower() or ""
    if command == "edit" then FX:ToggleEditMode() else FX:ToggleUI() end
end
