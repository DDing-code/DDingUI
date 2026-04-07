local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupEngine = {}
DDingUI.GroupEngine = GroupEngine

local pairs = pairs
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown

-- Registry of active providers
GroupEngine.providers = {}

function GroupEngine:RegisterProvider(name, provider)
    self.providers[name] = provider
end

-- ============================================================
-- Debounced Queue System (Ayije 3-tier pattern)
-- ============================================================
local updateQueue = {}
local isProcessing = false

function GroupEngine:RequestUpdate(groupName, delay)
    if isProcessing then return end
    
    local d = delay or 0.05
    if not updateQueue[groupName] then
        updateQueue[groupName] = true
        C_Timer.After(d, function()
            updateQueue[groupName] = nil
            if not isProcessing then
                GroupEngine:ExecuteUpdate(groupName)
            end
        end)
    end
end

-- Force update all groups (e.g., Spec Change)
function GroupEngine:RequestUpdateAll(delay)
    local gs = DDingUI.GroupSystem and DDingUI.GroupSystem.db
    if not gs or not gs.groups then return end
    
    for groupName, settings in pairs(gs.groups) do
        if settings.enabled then
            self:RequestUpdate(groupName, delay)
        end
    end
end

-- ============================================================
-- Execution Pipeline
-- ============================================================
function GroupEngine:ExecuteUpdate(groupName)
    isProcessing = true
    
    local pool = DDingUI.GroupPool
    local renderer = DDingUI.GroupRenderer
    local gs = DDingUI.GroupSystem and DDingUI.GroupSystem.db
    
    if not pool or not renderer or not gs then
        isProcessing = false
        return
    end
    
    local settings = gs.groups[groupName]
    if not settings or not settings.enabled then
        pool:HideGroup(groupName)
        isProcessing = false
        return
    end
    
    local container = pool:GetContainer(groupName)
    if not container then
        isProcessing = false
        return
    end
    
    -- 1. Get active icons from providers
    local activeIcons = {}
    for _, provider in pairs(self.providers) do
        if provider.GetIconsForGroup then
            local icons = provider:GetIconsForGroup(groupName, settings)
            if icons then
                for _, icon in ipairs(icons) do
                    activeIcons[#activeIcons + 1] = icon
                end
            end
        end
    end
    
    -- 2. Sort icons if needed (Stable sort)
    table.sort(activeIcons, function(a, b)
        local aSort = a._cdmStableSortID or a.layoutIndex or 0
        local bSort = b._cdmStableSortID or b.layoutIndex or 0
        return aSort < bSort
    end)
    
    -- 3. Layout Mathematics (Stateless)
    local totalW, totalH = renderer:CalculateAndSetPositions(container, activeIcons, settings)
    
    -- 4. Set Container Size (Combat Safe)
    if not InCombatLockdown() then
        local minW, minH = renderer:GetPhantomSize(settings)
        local finalW = math.max(totalW, minW)
        local finalH = math.max(totalH, minH)
        container:SetSize(finalW, finalH)
        
        if #activeIcons > 0 then
            container:Show()
        else
            container:Hide()
        end
    end
    
    -- 5. Apply Style
    if DDingUI.GroupStyle then
        DDingUI.GroupStyle:ApplyToGroup(activeIcons, settings)
    end
    
    isProcessing = false
end

-- ============================================================
-- Event Frame
-- ============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Execute pending container resizes/show/hide after combat
        GroupEngine:RequestUpdateAll(0.1)
    end
end)
GroupEngine.eventFrame = eventFrame
