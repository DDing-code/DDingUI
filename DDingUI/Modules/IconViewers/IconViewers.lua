local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

DDingUI.IconViewers = DDingUI.IconViewers or {}
local IconViewers = DDingUI.IconViewers

-- Weak tables to store custom data without tainting Blizzard frames
-- Using weak keys so entries are garbage-collected when frames are destroyed
-- This prevents ADDON_ACTION_FORBIDDEN / secret value errors in EditMode
IconViewers._iconData = IconViewers._iconData or setmetatable({}, { __mode = "k" })
IconViewers._cdData = IconViewers._cdData or setmetatable({}, { __mode = "k" })
IconViewers._texData = IconViewers._texData or setmetatable({}, { __mode = "k" })

-- Shared weak table for viewer-level state (replaces viewer.__cdm* / viewer.__dding* fields)
-- Writing custom fields directly onto EditMode-enabled secure frames causes taint propagation.
local viewerState = setmetatable({}, { __mode = "k" })
local function GetViewerState(viewer)
    local state = viewerState[viewer]
    if not state then
        state = {}
        viewerState[viewer] = state
    end
    return state
end
-- Export for ViewerLayout access
IconViewers._viewerState = viewerState
IconViewers._GetViewerState = GetViewerState

local iconData = IconViewers._iconData

local function GetIconData(frame)
    local d = iconData[frame]
    if not d then d = {}; iconData[frame] = d end
    return d
end

local viewers = DDingUI.viewers or {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

local function IsCooldownIconFrame(frame)
    return frame and (frame.icon or frame.Icon) and frame.Cooldown
end

function IconViewers:ApplyViewerSkin(viewer)
    if not viewer or not viewer.GetName then return end
    -- [FIX] CMC IsReady 패턴: 뷰어 초기화 미완료 시 스킵
    if self.IsViewerReady and not self.IsViewerReady(viewer) then return end
    -- FlightHide: skip all viewer processing during flight
    if DDingUI.FlightHide and DDingUI.FlightHide.isActive then return end
    local name     = viewer:GetName()
    local settings = DDingUI.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    if self.SkinAllIconsInViewer then
        self:SkinAllIconsInViewer(viewer)
    end
    -- [PERF] ApplyViewerLayout 1회만 호출 (이전: SkinAllIcons 전후 2회 중복)
    if self.ApplyViewerLayout then
        self:ApplyViewerLayout(viewer)
    end
    if DDingUI.ResourceBars and DDingUI.ResourceBars.UpdatePowerBar then
        DDingUI.ResourceBars:UpdatePowerBar()
    end
    if DDingUI.ResourceBars and DDingUI.ResourceBars.UpdateSecondaryPowerBar then
        DDingUI.ResourceBars:UpdateSecondaryPowerBar()
    end
    if DDingUI.CastBars and DDingUI.CastBars.UpdateCastBarLayout then
        DDingUI.CastBars:UpdateCastBarLayout()
    end
    
    if not InCombatLockdown() then
        self:ProcessPendingIcons()
    end
end

function IconViewers:ProcessPendingIcons()
    if not DDingUI.__cdmPendingIcons then return end
    if InCombatLockdown() then return end
    -- FlightHide: skip pending icon processing during flight
    if DDingUI.FlightHide and DDingUI.FlightHide.isActive then return end
    -- Skip during EditMode to avoid triggering Blizzard secret value errors
    if EditModeManagerFrame then
        local inEditMode = false
        pcall(function()
            inEditMode = EditModeManagerFrame:IsShown() or EditModeManagerFrame.editModeActive
        end)
        if inEditMode then return end
    end
    
    local processed = {}
    for icon, data in pairs(DDingUI.__cdmPendingIcons) do
        local id = iconData[icon]
        if icon and icon:IsShown() and not (id and id.skinned) then
            local success = pcall(self.SkinIcon, self, icon, data.settings)
            if success then
                if id then id.skinPending = nil end
                processed[icon] = true
            end
        elseif not icon or not icon:IsShown() then
            processed[icon] = true
        end
    end
    
    -- Also process icons that were partially skinned but need border created/updated
    for _, name in ipairs(viewers) do
        local viewer = _G[name]
        if viewer and viewer:IsShown() then
            local container = viewer.viewerFrame or viewer
            for _, child in ipairs({ container:GetChildren() }) do
                local cid = iconData[child]
                if IsCooldownIconFrame(child) and (cid and cid.borderPending) and not InCombatLockdown() then
                    local settings = DDingUI.db.profile.viewers[name]
                    if settings and settings.enabled then
                        -- Re-skin just the border part using texture-based borders (no SetBackdrop = no taint)
                        local iconTexture = child.icon or child.Icon
                        if not cid then cid = GetIconData(child) end
                        if not iconTexture then
                            cid.borderPending = nil
                            cid.skinned = true
                        else
                            local edgeSize = tonumber(settings.borderSize) or 1
                            if DDingUI and DDingUI.ScaleBorder then
                                edgeSize = DDingUI:ScaleBorder(edgeSize)
                            else
                                edgeSize = math.floor(edgeSize + 0.5)
                            end

                            -- Create texture-based borders like BetterCooldownManager
                            cid.borders = cid.borders or {}
                            local borders = cid.borders

                            if #borders == 0 then
                                local function CreateBorderLine()
                                    return child:CreateTexture(nil, "OVERLAY")
                                end
                                local topBorder = CreateBorderLine()
                                topBorder:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 0, 0)
                                topBorder:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 0, 0)

                                local bottomBorder = CreateBorderLine()
                                bottomBorder:SetPoint("BOTTOMLEFT", iconTexture, "BOTTOMLEFT", 0, 0)
                                bottomBorder:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 0, 0)

                                local leftBorder = CreateBorderLine()
                                leftBorder:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 0, 0)
                                leftBorder:SetPoint("BOTTOMLEFT", iconTexture, "BOTTOMLEFT", 0, 0)

                                local rightBorder = CreateBorderLine()
                                rightBorder:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 0, 0)
                                rightBorder:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 0, 0)

                                cid.borders = { topBorder, bottomBorder, leftBorder, rightBorder }
                                borders = cid.borders
                            end

                            local top, bottom, left, right = unpack(borders)
                            if top and bottom and left and right then
                                local r, g, b, a = unpack(settings.borderColor or { 0, 0, 0, 1 })
                                local shouldShow = edgeSize > 0

                                top:SetHeight(edgeSize)
                                bottom:SetHeight(edgeSize)
                                left:SetWidth(edgeSize)
                                right:SetWidth(edgeSize)

                                for _, borderTex in ipairs(borders) do
                                    borderTex:SetColorTexture(r, g, b, a or 1)
                                    borderTex:SetShown(shouldShow)
                                end
                            end

                            cid.borderPending = nil
                            cid.skinned = true
                        end
                    end
                end
            end
        end
    end
    
    for icon in pairs(processed) do
        DDingUI.__cdmPendingIcons[icon] = nil
    end

    if not next(DDingUI.__cdmPendingIcons) then
        DDingUI.__cdmPendingIcons = nil
    end
end

function IconViewers:HookViewers()
    for _, name in ipairs(viewers) do
        local viewer = _G[name]
        if viewer and not GetViewerState(viewer).hooked then
            GetViewerState(viewer).hooked = true

            viewer:HookScript("OnShow", function(f)
                IconViewers:ApplyViewerSkin(f)
                -- Custom anchor: re-apply on show (EditMode may have reset position)
                if IconViewers.ApplyViewerLayout then
                    C_Timer.After(0.05, function()
                        if f:IsShown() then
                            IconViewers:ApplyViewerLayout(f)
                        end
                    end)
                end
            end)

            -- Skinning will be handled by RefreshAll call in main initialization

            viewer:HookScript("OnSizeChanged", function(f)
                if GetViewerState(f).layoutSuppressed or GetViewerState(f).layoutRunning then
                    return
                end
                if IconViewers.ApplyViewerLayout then
                    IconViewers:ApplyViewerLayout(f)
                end
            end)

            -- Event-based updates instead of OnUpdate for better performance
            if name == "BuffIconCooldownViewer" then
                -- Buff viewer: hook into UNIT_AURA events for immediate updates
                local state = GetViewerState(viewer)
                if not state.auraHook then
                    state.auraHook = CreateFrame("Frame")
                    state.auraHook:RegisterUnitEvent("UNIT_AURA", "player")
                    state.auraHook:SetScript("OnEvent", function(_, event, unit)
                        if unit == "player" and viewer:IsShown() then
                            -- Throttled rescan to avoid spam (reduced delay for timer accuracy)
                            if not GetViewerState(viewer).rescanPending then
                                GetViewerState(viewer).rescanPending = true
                                C_Timer.After(0.01, function()
                                    GetViewerState(viewer).rescanPending = nil
                                    if viewer:IsShown() and IconViewers.RescanViewer then
                                        IconViewers:RescanViewer(viewer)
                                    end
                                end)
                            end
                        end
                    end)
                end

                -- Minimal OnUpdate for pending icons only
                local lastProcessTime = 0
                viewer:HookScript("OnUpdate", function(f, elapsed)
                    lastProcessTime = lastProcessTime + elapsed
                    if lastProcessTime > 1.0 and not InCombatLockdown() then -- Process once per second
                        lastProcessTime = 0
                        IconViewers:ProcessPendingIcons()
                    end
                end)
            else
                -- Other viewers: use SPELL_UPDATE_COOLDOWN and other events
                local state = GetViewerState(viewer)
                if not state.cooldownHook then
                    state.cooldownHook = CreateFrame("Frame")
                    state.cooldownHook:RegisterEvent("SPELL_UPDATE_COOLDOWN")
                    state.cooldownHook:RegisterEvent("BAG_UPDATE_COOLDOWN")
                    state.cooldownHook:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
                    state.cooldownHook:SetScript("OnEvent", function(_, event)
                        if viewer:IsShown() then
                            -- Throttled rescan to avoid spam during heavy cooldown usage
                            if not GetViewerState(viewer).rescanPending then
                                GetViewerState(viewer).rescanPending = true
                                C_Timer.After(0.2, function()
                                    GetViewerState(viewer).rescanPending = nil
                                    if viewer:IsShown() and IconViewers.RescanViewer then
                                        IconViewers:RescanViewer(viewer)
                                    end
                                end)
                            end
                        end
                    end)
                end

                -- Minimal OnUpdate for pending icons only
                local lastProcessTime = 0
                viewer:HookScript("OnUpdate", function(f, elapsed)
                    lastProcessTime = lastProcessTime + elapsed
                    if lastProcessTime > 2.0 and not InCombatLockdown() then -- Process every 2 seconds
                        lastProcessTime = 0
                        IconViewers:ProcessPendingIcons()
                    end
                end)
            end

            self:ApplyViewerSkin(viewer)
        end
    end
end

function IconViewers:ForceRefreshBuffIcons()
    local viewer = _G["BuffIconCooldownViewer"]
    if viewer and viewer:IsShown() then
        GetViewerState(viewer).iconCount = nil
        if self.RescanViewer then
            self:RescanViewer(viewer)
        end
        if not InCombatLockdown() then
            self:ProcessPendingIcons()
        end
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: |cff00ff00Force refreshed BuffIconCooldownViewer|r") -- [STYLE]
    end
end

function IconViewers:AutoLoadBuffIcons(retryCount)
    retryCount = retryCount or 0
    local maxRetries = 5
    
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then
        if retryCount < maxRetries then
            -- [PERF] 3개 중복 타이머 → 1개만 (지수적 타이머 폭풍 방지)
            C_Timer.After(1.0 + retryCount * 0.5, function() IconViewers:AutoLoadBuffIcons(retryCount + 1) end)
        end
        return
    end
    
    GetViewerState(viewer).initialLoading = true

    -- [FIX] 뷰어가 아직 안 보이면 Show()해서 스킨 적용 가능하게 함
    -- Raise() 제거 — 다른 프레임 위로 올릴 이유 없음
    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer and not buffViewer:IsShown() then
        buffViewer:Show()
    end
    
    local settings = DDingUI.db.profile.viewers["BuffIconCooldownViewer"]
    if not settings or not settings.enabled then
        GetViewerState(viewer).initialLoading = nil
        return
    end
    
    local function collectAllIcons(container)
        local icons = {}
        if not container or not container.GetNumChildren then return icons end
        
        local n = container:GetNumChildren() or 0
        for i = 1, n do
            local child = select(i, container:GetChildren())
            if child and IsCooldownIconFrame(child) then
                table.insert(icons, child)
            elseif child and child.GetNumChildren then
                local m = child:GetNumChildren() or 0
                for j = 1, m do
                    local grandchild = select(j, child:GetChildren())
                    if grandchild and IsCooldownIconFrame(grandchild) then
                        table.insert(icons, grandchild)
                    end
                end
            end
        end
        return icons
    end
    
    local container = viewer.viewerFrame or viewer
    local icons = collectAllIcons(container)
    
    local skinnedCount = 0
    local pendingCount = 0
    for _, icon in ipairs(icons) do
        -- [FIX] icon:Show() 제거 — CDM이 추적 중인 아이콘만 자체적으로 Show함.
        -- 무조건 Show()하면 추적 대상 아닌 버프까지 전부 표시되는 버그 발생.
        local iid = iconData[icon]
        if not (iid and iid.skinned) and not InCombatLockdown() then
            local success = pcall(self.SkinIcon, self, icon, settings)
            if success then
                skinnedCount = skinnedCount + 1
            end
        elseif not (iid and iid.skinned) then
            if not (iid and iid.skinPending) then
                GetIconData(icon).skinPending = true
                if not DDingUI.__cdmPendingIcons then
                    DDingUI.__cdmPendingIcons = {}
                end
                DDingUI.__cdmPendingIcons[icon] = { icon = icon, settings = settings, viewer = viewer }
                pendingCount = pendingCount + 1
            end
        end
    end
    
    if #icons > 0 and self.ApplyViewerLayout then
        self:ApplyViewerLayout(viewer)
    end
    
    -- [PERF] 3개 중복 타이머 → 1개만 (지수적 타이머 폭풍 방지)
    local shouldRetry = false
    if #icons == 0 and retryCount < maxRetries then
        shouldRetry = true
        C_Timer.After(0.5 + retryCount * 0.5, function() IconViewers:AutoLoadBuffIcons(retryCount + 1) end)
    elseif skinnedCount > 0 and retryCount < maxRetries then
        shouldRetry = true
        C_Timer.After(1.0, function() IconViewers:AutoLoadBuffIcons(retryCount + 1) end)
    end
    
    if not shouldRetry then
        GetViewerState(viewer).initialLoading = nil
        -- [FIX] 뷰어를 Hide()하지 않음. 기존 코드가 BuffIconCooldownViewer를 2초 후 Hide()해서
        -- 전투 진입 or 설정 창 오픈 전까지 버프가 안 보이는 버그 유발.
        -- 뷰어 visibility는 Blizzard/CDM 자체 로직이 관리하므로 AutoLoad에서 건드리지 않음.
    end
end

function IconViewers:RefreshAll()
    -- [FIX] 뷰어 재생성 대응: HookViewers도 다시 호출하여 새 뷰어에 훅 설치
    -- weak table 기반이므로 이미 훅된 뷰어는 자동 스킵됨
    self:HookViewers()

    for _, name in ipairs(viewers) do
        local viewer = _G[name]
        if viewer then
            self:ApplyViewerSkin(viewer)
        end
    end

    if self.BuffBarCooldownViewer and self.BuffBarCooldownViewer.Refresh then
        self.BuffBarCooldownViewer:Refresh()
    end
end

DDingUI.ApplyViewerSkin = function(self, viewer) return IconViewers:ApplyViewerSkin(viewer) end
DDingUI.HookViewers = function(self) return IconViewers:HookViewers() end
DDingUI.AutoLoadBuffIcons = function(self, retryCount) return IconViewers:AutoLoadBuffIcons(retryCount) end
DDingUI.ForceRefreshBuffIcons = function(self) return IconViewers:ForceRefreshBuffIcons() end
DDingUI.ProcessPendingIcons = function(self) return IconViewers:ProcessPendingIcons() end

-- 전투 종료 시 즉시 센터링 (anchor 조정 로직 제거됨)
-- 이유: anchor 조정이 넛지 설정을 덮어씀.
--       viewer의 anchor point가 CENTER면 아이콘 CENTER 배치만으로 충분함.
do
    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if IconViewers.CenterBuffIconsImmediate then
                IconViewers.CenterBuffIconsImmediate()
            end
        end
    end)
end

-- [REFACTOR] EditMode taint sanitizer
-- Blizzard's CooldownViewer.lua:898 does `if self.allowAvailableAlert then`
-- which crashes on secret boolean values tainted by other addons (ElvUI etc).
-- This sanitizer cleans secret booleans from icon frames to prevent cascading errors.
do
    local function SanitizeViewerIcons()
        if not issecretvalue then return end
        for _, name in ipairs(viewers) do
            local viewer = _G[name]
            if viewer then
                local ok, result = pcall(function() return { viewer:GetChildren() } end)
                if ok and result then
                    for _, child in ipairs(result) do
                        -- Sanitize known secret-boolean-prone fields
                        local fields = { "allowAvailableAlert", "allowOnCooldownAlert" }
                        for _, field in ipairs(fields) do
                            local fOk, val = pcall(function() return child[field] end)
                            if fOk and val ~= nil and issecretvalue(val) then
                                child[field] = false
                            end
                        end
                    end
                end
            end
        end
    end

    -- Hook EditModeManagerFrame to sanitize after entering EditMode
    -- (post-hook: prevents errors on subsequent RefreshLayout calls within EditMode)
    local sanitizeFrame = CreateFrame("Frame")
    sanitizeFrame:RegisterEvent("PLAYER_LOGIN")
    sanitizeFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if EditModeManagerFrame then
            -- Sanitize when EditMode frame shows
            EditModeManagerFrame:HookScript("OnShow", function()
                C_Timer.After(0, SanitizeViewerIcons) -- next frame, after initial layout
            end)
            -- Also hook EnterEditMode if available
            if EditModeManagerFrame.EnterEditMode then
                hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
                    SanitizeViewerIcons()
                end)
            end
        end
    end)

    -- Export for debug/manual use
    IconViewers.SanitizeViewerIcons = SanitizeViewerIcons
end

