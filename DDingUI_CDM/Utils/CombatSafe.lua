-- ============================================================
-- DDingUI CombatSafe — 전투 중 안전한 프레임 조작 래퍼
-- ============================================================
local AddonName, ns = ...
local DDingUI = LibStub("AceAddon-3.0"):GetAddon("DDingUI")

DDingUI.CombatSafe = {}
local CS = DDingUI.CombatSafe

local pendingActions = {}
local isRegistered = false

local function FlushPendingActions()
    if InCombatLockdown() then return end
    local actions = pendingActions
    pendingActions = {}
    for _, action in ipairs(actions) do
        pcall(action.fn, unpack(action.args))
    end
end

local function EnsureEvent()
    if isRegistered then return end
    isRegistered = true
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function() FlushPendingActions() end)
end

function CS.DeferIfCombat(fn, ...)
    if not InCombatLockdown() then fn(...); return end
    EnsureEvent()
    table.insert(pendingActions, { fn = fn, args = { ... } })
end

function CS.SafeSetSize(frame, w, h)
    if not frame or not frame.SetSize then return end
    CS.DeferIfCombat(frame.SetSize, frame, w, h)
end

function CS.SafeShow(frame, alphaOnly)
    if not frame then return end
    if alphaOnly then
        frame:SetAlpha(1)
        if not frame:IsShown() and not InCombatLockdown() then frame:Show() end
    else
        CS.DeferIfCombat(frame.Show, frame)
    end
end

function CS.SafeHide(frame, alphaOnly)
    if not frame then return end
    if alphaOnly then frame:SetAlpha(0)
    else CS.DeferIfCombat(frame.Hide, frame) end
end

function CS.InCombat() return InCombatLockdown() end
function CS.GetPendingCount() return #pendingActions end
function CS.ClearPending() table.wipe(pendingActions) end
