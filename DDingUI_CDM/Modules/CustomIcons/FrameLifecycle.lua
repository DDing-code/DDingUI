local ns = select(2, ...)
local DDingUI = ns.Addon

local FrameLifecycle = {}
DDingUI.CustomIconFrameLifecycle = FrameLifecycle

function FrameLifecycle.Create(
    runtime,
    CustomIcons,
    SL,
    ApplyIconSettings,
    EnsureLoadConditions,
    FALLBACK_ITEM_ICON,
    FALLBACK_RACIAL_ICON,
    FALLBACK_SLOT_ICON,
    FALLBACK_SPELL_ICON,
    GetDynamicDB,
    GetPlayerRacialSpellID,
    GetStoredIconTexture,
    HandleCooldownDone,
    ResolveItemTexture,
    ResolveSpellTexture,
    SetStableIconTexture,
    UpdateAuraIcon,
    UpdateItemIcon,
    UpdateRacialIconFrame,
    UpdateSlotIcon,
    UpdateSpellIconFrame,
    UpdateTrinketProcIcon
)
    local function GetAnchorFrame(anchorName)
        if not anchorName or anchorName == "" then
            return UIParent
        end
        return _G[anchorName] or UIParent
    end

    local function IsSpellInPlayerBook(spellID)
        if not spellID then return false end

        -- Use the new Dragonflight API that checks if spell is actually known for current spec
        -- Includes handling of spell overrides/replacements
        if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.FindBaseSpellByID and C_SpellBook.FindSpellOverrideByID and Enum and Enum.SpellBookSpellBank then
            local bank = Enum.SpellBookSpellBank.Player

            -- Direct check first
            local ok, result = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
            if ok and result then
                return true
            end

            -- Check base spell if this might be an override
            ok, result = pcall(C_SpellBook.FindBaseSpellByID, spellID)
            if ok and result and result ~= spellID then
                ok, result = pcall(C_SpellBook.IsSpellKnown, result, bank)
                if ok and result then
                    return true
                end
            end

            -- Check override spell if this might be a base
            ok, result = pcall(C_SpellBook.FindSpellOverrideByID, spellID)
            if ok and result and result ~= spellID then
                ok, result = pcall(C_SpellBook.IsSpellKnown, result, bank)
                if ok and result then
                    return true
                end
            end

            return false
        end

        -- Fallback to old API for backward compatibility
        if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
            local ok, result = pcall(C_SpellBook.IsSpellInSpellBook, spellID)
            if ok then
                return result == true
            end
        end

        -- Fallback: assume available if API missing/failed
        return true
    end

    local function IsIconLoadable(iconData)
        if not iconData then return false end
        if iconData.type == "spell" then
            if iconData.settings and iconData.settings.customID == true then
                return true
            end
            return IsSpellInPlayerBook(iconData.id)
        elseif iconData.type == "racial" then
            local racialID = GetPlayerRacialSpellID()
            return racialID ~= nil
        end
        return true
    end

    -- (moved above UpdateSpellIconFrame via forward declaration)

    local function GetCurrentSpecID()
        local specIndex = GetSpecialization and GetSpecialization()
        if specIndex then
            local id = GetSpecializationInfo(specIndex)
            return id
        end
        return nil
    end

    local function ShouldIconSpawn(iconData)
        if not iconData then return false end
        -- Spellbook gating
        if iconData.type == "spell"
            and not (iconData.settings and iconData.settings.customID == true)
            and not IsSpellInPlayerBook(iconData.id)
        then
            return false
        elseif iconData.type == "racial" then
            local racialID = GetPlayerRacialSpellID()
            if not racialID then return false end
        end

        EnsureLoadConditions(iconData)
        local lc = iconData.settings.loadConditions or {}
        if not lc.enabled then
            return true
        end


        -- Spec conditions
        if lc.specs then
            local anySpecSet = false
            for _, v in pairs(lc.specs) do
                if v then anySpecSet = true break end
            end
            if anySpecSet then
                local currentSpec = GetCurrentSpecID()
                if not currentSpec or not lc.specs[currentSpec] then
                    return false
                end
            end
        end

        return true
    end

    -- ------------------------
    -- Base icon creation
    -- ------------------------
    local function CreateBaseIcon(name, parent)
        local frame = CreateFrame("Button", name, parent, "BackdropTemplate")
        frame:SetSize(40, 40)
        frame:Hide()

        -- [FIX] ARTWORK 레이어 사용: BackdropTemplate의 backdrop이 BACKGROUND 레이어를 차지하므로
        -- BACKGROUND에 icon을 만들면 backdrop에 가려져 투명하게 보임
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(frame)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Border frame (texture-based, no SetBackdrop = no taint)
        local border = CreateFrame("Frame", nil, frame)
        border:SetFrameLevel(frame:GetFrameLevel() + 1)
        border:SetAllPoints(frame)
        border:Hide()

        local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cd:SetAllPoints(frame)
        cd:SetFrameLevel(frame:GetFrameLevel() + 1)
        -- Edge highlight is enabled dynamically (e.g. charge recharge), default off.
        cd:SetDrawEdge(false)
        cd:SetDrawSwipe(true)
        cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        cd:SetSwipeColor(0, 0, 0, 0.8)
        cd:SetHideCountdownNumbers(false)
        cd:SetReverse(false)

        -- Probe cooldown: used for cooldown-state checks without being affected by user "Hide Cooldown" setting.
        local cdProbe = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cdProbe:SetAllPoints(frame)
        cdProbe:SetDrawEdge(false)
        cdProbe:SetDrawSwipe(true)
        cdProbe:SetSwipeColor(0, 0, 0, 0)
        cdProbe:SetHideCountdownNumbers(true)
        cdProbe:SetReverse(false)
        cdProbe:SetAlpha(0)

        -- Charge probe: used to detect whether a charge is recharging (show swipe) without affecting main cooldown state.
        local cdChargeProbe = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cdChargeProbe:SetAllPoints(frame)
        cdChargeProbe:SetDrawEdge(false)
        cdChargeProbe:SetDrawSwipe(true)
        cdChargeProbe:SetSwipeColor(0, 0, 0, 0)
        cdChargeProbe:SetHideCountdownNumbers(true)
        cdChargeProbe:SetReverse(false)
        cdChargeProbe:SetAlpha(0)

        cd:SetScript("OnCooldownDone", HandleCooldownDone)
        cdProbe:SetScript("OnCooldownDone", HandleCooldownDone)
        cdChargeProbe:SetScript("OnCooldownDone", HandleCooldownDone)

        local countLayer = CreateFrame("Frame", nil, frame)
        countLayer:SetFrameLevel(frame:GetFrameLevel() + 2)
        countLayer:SetAllPoints(frame)

        -- [FIX] Define template "NumberFontNormal" to prevent "Font not set" on SetText before SetFont is executed.
        local count = countLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetJustifyH("RIGHT")
        count:SetTextColor(1, 1, 1, 1)
        count:SetShadowOffset(0, 0)
        count:SetShadowColor(0, 0, 0, 1)

        frame.icon = icon
        frame.cooldown = cd
        frame.Cooldown = cd
        frame.cooldownProbe = cdProbe
        frame.cooldownChargeProbe = cdChargeProbe
        frame.count = count
        frame.Applications = countLayer
        countLayer.Applications = count
        frame.border = border
        if DDingUI.CustomIconActiveEffectOverlay then
            DDingUI.CustomIconActiveEffectOverlay:PrepareFrame(frame)
        end

        frame:EnableMouse(true)
        return frame
    end

    local function ResetDynamicIconFrame(frame)
        if not frame then return end

        local totems = DDingUI.CustomIconTotems
        if frame._type == "totem" and totems and totems.UnregisterFrame then
            totems:UnregisterFrame(frame)
        end

        local bridge = DDingUI.DynamicIconBridge
        if bridge and bridge.ReleaseFrame and (frame._ddIsManaged or frame._ddIconKey) then
            bridge:ReleaseFrame(frame, frame._ddIconKey or frame._iconKey)
        end

        if frame._cdmDesatUpdater then
            frame._cdmDesatUpdater:Hide()
            frame._cdmDesatUpdater.spellID = nil
            frame._cdmDesatUpdater.durObj = nil
            frame._cdmDesatUpdater.targetIcon = nil
        end

        if frame._DDingUIAssistFlipbook then
            frame._DDingUIAssistFlipbook:SetAlpha(0)
            if frame._DDingUIAssistFlipbook.Anim and frame._DDingUIAssistFlipbook.Anim:IsPlaying() then
                frame._DDingUIAssistFlipbook.Anim:Stop()
            end
        end
        if SL then
            if SL.HidePixelGlow then
                SL.HidePixelGlow(frame, "_DDingUIAssistGlow")
                SL.HidePixelGlow(frame, "_DDingUICustomGlow")
            end
            if SL.HideAutocastGlow then
                SL.HideAutocastGlow(frame, "_DDingUIAssistGlow")
                SL.HideAutocastGlow(frame, "_DDingUICustomGlow")
            end
            if SL.HideButtonGlow then
                SL.HideButtonGlow(frame)
            end
        end
        CustomIcons:StopTrackedTrinketEffectGlow(frame)
        if DDingUI.IconCustomization and DDingUI.IconCustomization.ClearDynamicIconGlow then
            DDingUI.IconCustomization:ClearDynamicIconGlow(frame)
        end
        if DDingUI.CustomIconActiveEffectOverlay then
            DDingUI.CustomIconActiveEffectOverlay:ResetFrame(frame)
        end
        local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
        if LCG and LCG.ProcGlow_Stop then
            LCG.ProcGlow_Stop(frame, "_DDingUIAssistGlow")
            LCG.ProcGlow_Stop(frame, "_DDingUICustomGlow")
        end

        if frame.cooldown then
            frame.cooldown:SetScript("OnCooldownDone", HandleCooldownDone)
            frame.cooldown:Clear()
            frame.cooldown:Hide()
            frame.cooldown:SetDrawEdge(false)
            frame.cooldown:SetDrawSwipe(true)
            frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
            frame.cooldown:SetHideCountdownNumbers(false)
            frame.cooldown.noCooldownCount = nil
        end
        if frame.cooldownProbe then
            frame.cooldownProbe:SetScript("OnCooldownDone", HandleCooldownDone)
            frame.cooldownProbe:Clear()
            frame.cooldownProbe:Hide()
        end
        if frame.cooldownChargeProbe then
            frame.cooldownChargeProbe:SetScript("OnCooldownDone", HandleCooldownDone)
            frame.cooldownChargeProbe:Clear()
            frame.cooldownChargeProbe:Hide()
        end
        if frame.count then
            frame.count:SetText("")
            frame.count:Hide()
        end
        CustomIcons.HideManagedIconBorderLayers(frame)
        if frame.icon then
            frame.icon:ClearAllPoints()
            frame.icon:SetAllPoints(frame)
            frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            frame.icon:SetTexture(nil)
            frame.icon:SetAlpha(1)
            frame.icon:SetDesaturation(0)
        end

        frame:Hide()
        frame:ClearAllPoints()
        frame:SetParent(nil)
        frame:SetSize(40, 40)
        frame:SetScale(1)
        frame:SetAlpha(1)
        frame:EnableMouse(true)

        frame._type = nil
        frame._itemID = nil
        frame._spellID = nil
        frame._slotID = nil
        frame._totemSlot = nil
        frame._iconKey = nil
        frame._groupSettings = nil
        frame._textureCacheKey = nil
        frame._fallbackTexture = nil
        frame._lastResolvedTexture = nil
        frame._originalTexture = nil
        frame._cachedSpellItemID = nil
        frame._cachedSpellID = nil
        frame._auraWasActive = nil
        frame._wasVisibleInGroup = nil
        frame._ddManagedAuraExpired = nil
        frame._ddIsManaged = nil
        frame._ddIconKey = nil
        frame._ddOrigState = nil
        frame._ddContainerRef = nil
        frame._ddTargetPoint = nil
        frame._ddTargetRelPoint = nil
        frame._ddTargetX = nil
        frame._ddTargetY = nil
        frame._ddTargetWidth = nil
        frame._ddTargetHeight = nil
        frame._ddSuppressed = nil
        frame._ddSourceViewer = nil
        frame._DDingUIAssistViewerName = nil
        frame._DDingUIAssistGlowActive = nil
        frame._ddCustomIconActive = nil
        frame._ddCustomIconReady = nil
        frame._ddItemCountEmpty = nil
        frame._ddHideWhenEmptySuppressed = nil
        frame._ddTotemActive = nil
        frame._ddTotemStateInitialized = nil
        frame._ddInactiveGray = nil
        frame._ddForcedInactiveGray = nil
        frame._ddInactiveAlpha = nil
        frame._ddInactivePlaceholder = nil
        frame._ddNeedsInitialUpdate = nil
    end

    local function AcquireDynamicIconFrame(name, parent)
        local frame = table.remove(runtime.iconFramePool)
        if frame then
            frame._ddInIconPool = nil
            frame:SetParent(parent)
            frame:SetSize(40, 40)
            frame:SetScale(1)
            frame:SetAlpha(1)
            frame:EnableMouse(true)
        else
            frame = CreateBaseIcon(name, parent)
        end
        frame:Hide()
        frame:ClearAllPoints()
        frame._ddNeedsInitialUpdate = true
        return frame
    end

    local function ReleaseDynamicIconFrame(iconKey, frame)
        if not frame or frame._ddInIconPool then return end
        ResetDynamicIconFrame(frame)
        frame._ddInIconPool = true
        runtime.iconFramePool[#runtime.iconFramePool + 1] = frame
    end

    -- ------------------------
    -- Icon creation per type
    -- ------------------------
    local function CreateItemIcon(iconKey, iconData, parent)
        local itemID = iconData.id
        if not itemID then return nil end

        -- [FIX] CDM 방식: 프레임은 항상 생성, 텍스처만 나중에 업데이트
        -- GetItemInfo가 nil이어도 프레임은 만들어야 GroupSystem이 추적 가능
        local itemName = GetItemInfo(itemID)
        if not itemName and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end

        local frame = AcquireDynamicIconFrame("DDingUI_DynItem_" .. iconKey, parent)
        frame._type = "item"
        frame._itemID = itemID
        frame._iconKey = iconKey
        frame._textureCacheKey = "item:" .. tostring(itemID)
        frame._fallbackTexture = FALLBACK_ITEM_ICON
        SetStableIconTexture(frame, ResolveItemTexture(itemID), true)
        if DDingUI.CustomIconActiveEffectOverlay then
            DDingUI.CustomIconActiveEffectOverlay:MarkDirty()
        end
        return frame
    end

    local function CreateSpellIcon(iconKey, iconData, parent)
        local spellID = iconData.id
        if not spellID then return nil end
        -- [FIX] 스펠북 체크는 IsIconActive에서 하므로 여기서는 프레임만 생성
        -- 유저가 추가한 스펠이 현재 특성에 없더라도 프레임은 존재해야 함

        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        if not spellInfo then
            if C_Spell and C_Spell.RequestLoadSpellData then
                C_Spell.RequestLoadSpellData(spellID)
            end
        end

        local frame = AcquireDynamicIconFrame("DDingUI_DynSpell_" .. iconKey, parent)
        frame._type = "spell"
        frame._spellID = spellID
        frame._iconKey = iconKey
        frame._textureCacheKey = "spell:" .. tostring(spellID)
        frame._fallbackTexture = GetStoredIconTexture(iconData) or FALLBACK_SPELL_ICON
        SetStableIconTexture(frame, ResolveSpellTexture(spellID, frame._fallbackTexture), true)
        return frame
    end

    local function CreateSlotIcon(iconKey, iconData, parent)
        local slotID = iconData.slotID
        if not slotID then return nil end

        local prefix = (iconData.type == "trinketProc") and "DDingUI_DynTrinket_" or "DDingUI_DynSlot_"
        local frame = AcquireDynamicIconFrame(prefix .. iconKey, parent)
        frame._type = iconData.type or "slot"
        frame._slotID = slotID
        frame._iconKey = iconKey
        frame._textureCacheKey = (iconData.type or "slot") .. ":" .. tostring(slotID)
        frame._fallbackTexture = FALLBACK_SLOT_ICON

        -- [FIX] 텍스처 항상 설정 — GetItemInfo 캐시 미스 시에도 아이콘 보이도록
        local itemID = CustomIcons.GetEquippedSlotItemID(frame, slotID)
        local tex = nil
        if itemID then
            -- GetItemInfo보다 GetInventoryItemTexture가 더 신뢰할 수 있음 (캐시 불필요)
            tex = GetInventoryItemTexture("player", slotID)
            if not tex then
                local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                tex = itemTexture
            end
            if not tex and C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(itemID)
            end
        end
        SetStableIconTexture(frame, tex or ResolveItemTexture(itemID, slotID), true)
        return frame
    end

    local function CreateAuraIcon(iconKey, iconData, parent)
        local spellID = iconData.id
        if not spellID then return nil end

        local frame = AcquireDynamicIconFrame("DDingUI_DynAura_" .. iconKey, parent)
        frame._type = "aura"
        frame._spellID = spellID
        frame._iconKey = iconKey
        frame._textureCacheKey = "aura:" .. tostring(spellID)
        frame._fallbackTexture = GetStoredIconTexture(iconData) or FALLBACK_SPELL_ICON

        -- 텍스처: C_Spell.GetSpellTexture → GetSpellInfo.iconID 폴백
        SetStableIconTexture(frame, ResolveSpellTexture(spellID, frame._fallbackTexture), true)
        return frame
    end

    local function CreateTotemIcon(iconKey, iconData, parent)
        local slot = tonumber(iconData.totemSlot)
        if not slot or slot < 1 then return nil end

        local totems = DDingUI.CustomIconTotems
        local fallback = totems and totems.GetPlaceholderIcon and totems:GetPlaceholderIcon() or 310731
        local frame = AcquireDynamicIconFrame("DDingUI_DynTotem_" .. iconKey, parent)
        frame._type = "totem"
        frame._totemSlot = slot
        frame._iconKey = iconKey
        frame._textureCacheKey = "totem:" .. tostring(slot)
        frame._fallbackTexture = fallback
        SetStableIconTexture(frame, fallback, true)
        frame.cooldown:SetScript("OnCooldownDone", nil)
        frame.cooldownProbe:SetScript("OnCooldownDone", nil)
        frame.cooldownChargeProbe:SetScript("OnCooldownDone", nil)
        if totems and totems.RegisterFrame then
            totems:RegisterFrame(frame, iconData)
        end
        return frame
    end

    local function CreateDynamicIcon(iconKey, iconData, parent)
        if iconData.type == "item" then
            return CreateItemIcon(iconKey, iconData, parent)
        elseif iconData.type == "spell" then
            local frame = CreateSpellIcon(iconKey, iconData, parent)
            if frame and CustomIcons:IsCurrentRacialSpellIcon(iconData) then
                frame._type = "racial"
                frame._racialSpellID = GetPlayerRacialSpellID()
                UpdateRacialIconFrame(frame, iconData)
            end
            return frame
        elseif iconData.type == "slot" then
            return CreateSlotIcon(iconKey, iconData, parent)
        elseif iconData.type == "trinketProc" then
            return CreateSlotIcon(iconKey, iconData, parent)  -- Reuse slot icon frame
        elseif iconData.type == "aura" then
            return CreateAuraIcon(iconKey, iconData, parent)
        elseif iconData.type == "totem" then
            return CreateTotemIcon(iconKey, iconData, parent)
        elseif iconData.type == "racial" then
            local racialID = GetPlayerRacialSpellID()
            if not racialID then return nil end
            -- 임시 테이블로 CreateSpellIcon을 호출하여 데이터 오염 방지
            local frame = CreateSpellIcon(iconKey, {id = racialID, settings = iconData.settings}, parent)
            if frame then
                frame._type = "racial"
                frame._racialSpellID = racialID
                frame._fallbackTexture = FALLBACK_RACIAL_ICON
                UpdateRacialIconFrame(frame, iconData)
            end
            return frame
        end
        return nil
    end

    local function UpdateDynamicIcon(iconKey)
        local db = GetDynamicDB()
        local iconData = db.iconData[iconKey]
        local frame = runtime.iconFrames[iconKey]
        if not iconData or not frame then return end

        -- Group settings are stored on the frame during LayoutGroup
        ApplyIconSettings(frame, iconData, frame._groupSettings)
        frame._ddCustomIconProcActive = false
        if iconData.type == "item" then
            UpdateItemIcon(frame, iconData)
        elseif iconData.type == "spell" then
            if CustomIcons:IsCurrentRacialSpellIcon(iconData) then
                UpdateRacialIconFrame(frame, iconData)
            else
                UpdateSpellIconFrame(frame, iconData)
            end
        elseif iconData.type == "racial" then
            UpdateRacialIconFrame(frame, iconData)
        elseif iconData.type == "slot" then
            UpdateSlotIcon(frame, iconData)
        elseif iconData.type == "trinketProc" then
            UpdateTrinketProcIcon(frame, iconData)
        elseif iconData.type == "aura" then
            UpdateAuraIcon(frame, iconData)
        elseif iconData.type == "totem" then
            local totems = DDingUI.CustomIconTotems
            if totems and totems.UpdateFrame then
                totems:UpdateFrame(frame, iconData, true, false)
            end
        end
        if DDingUI.CustomIconActiveEffectOverlay then
            DDingUI.CustomIconActiveEffectOverlay:ApplyFrame(frame, iconData)
            if iconData.type == "item" then
                frame._ddCustomIconProcActive = frame._ddCustomIconProcActive == true
                    or DDingUI.CustomIconActiveEffectOverlay:IsProcActive(iconData)
            end
        end
        CustomIcons:UpdateDynamicIconProcGlow(frame, iconData)
        CustomIcons:UpdateDynamicIconStateGlow(frame, iconData)
        if frame._ddIsManaged then
            CustomIcons.ApplyManagedGroupTextOptions(frame)
        end
        if DDingUI.CustomIconActiveEffectOverlay then
            DDingUI.CustomIconActiveEffectOverlay:SyncTextStyle(frame, iconData)
        end
    end

    runtime.UpdateDynamicIcon = UpdateDynamicIcon


    return GetAnchorFrame, IsIconLoadable, ShouldIconSpawn,
        ReleaseDynamicIconFrame, CreateDynamicIcon, UpdateDynamicIcon
end
