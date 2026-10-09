local addonName = "DDingUI_RaidHelper"
local messages = {}
local displayApplyCount = 0
local ns = {
    db = {
        showTooltips = false,
        showUpcomingCooldowns = true,
        timelineScale = 1.0,
        timelineWidth = 680,
        timelineHeight = 210,
        backgroundAlpha = 1.0,
        cooldownVisibility = {},
    },
    Registry = {
        GetDataSummary = function()
            return {
                modelCount = 11,
                heroicCount = 9,
                mythicCount = 2,
                latestGeneratedAt = "2026-08-24T10:15:06+00:00",
            }
        end,
    },
    Print = function(_, ...)
        messages[#messages + 1] = table.concat({ ... }, " ")
    end,
    TimelineUI = {
        ApplyDisplaySettings = function()
            displayApplyCount = displayApplyCount + 1
        end,
    },
}

local inCombat = false
InCombatLockdown = function() return inCombat end
GameTooltip = {
    hidden = false,
    Hide = function(self) self.hidden = true end,
}

assert(loadfile("Options.lua"))(addonName, ns)
assert(ns.Options:ShouldShowTooltips() == false)

inCombat = true
local applied, reason = ns.Options:SetTooltipsEnabled(true)
assert(applied == false and reason == "deferred")
assert(ns.db.showTooltips == false)
assert(ns.Options:ShouldShowTooltips() == false)
assert(ns.Options:GetRequestedTooltipSetting() == true)

local upcomingApplied, upcomingReason = ns.Options:SetUpcomingCooldownsEnabled(false)
assert(upcomingApplied == false and upcomingReason == "deferred")
assert(ns.db.showUpcomingCooldowns == true)
assert(ns.Options:ShouldShowUpcomingCooldowns() == true)
assert(ns.Options:GetRequestedUpcomingCooldownSetting() == false)

assert(ns.Options:ApplyPendingSettings() == false)
assert(ns.db.showTooltips == false)

inCombat = false
assert(ns.Options:ApplyPendingSettings() == true)
assert(ns.db.showTooltips == true)
assert(ns.Options.pendingShowTooltips == nil)
assert(ns.db.showUpcomingCooldowns == false)
assert(ns.Options.pendingShowUpcomingCooldowns == nil)

GameTooltip.hidden = false
assert(ns.Options:SetTooltipsEnabled(false) == true)
assert(ns.db.showTooltips == false)
assert(GameTooltip.hidden == true)

assert(ns.Options:SetTimelineScale(1.25) == true)
assert(ns.db.timelineScale == 1.25)
assert(ns.Options:SetTimelineWidth(100) == true)
assert(ns.db.timelineWidth == 200)
assert(ns.Options:SetTimelineWidth(840) == true)
assert(ns.db.timelineWidth == 840)
-- [STYLE] C안: the old four-row height (210) reads as the new default; range is 80~160.
assert(ns.Options:GetRequestedTimelineHeight() == 98)
assert(ns.Options:SetTimelineHeight(140) == true)
assert(ns.db.timelineHeight == 140)
assert(ns.Options:SetBackgroundAlpha(0.55) == true)
assert(ns.db.backgroundAlpha == 0.55)
assert(displayApplyCount == 5)

inCombat = true
local scaleApplied, scaleReason = ns.Options:SetTimelineScale(0.8)
local widthApplied, widthReason = ns.Options:SetTimelineWidth(600)
local heightApplied, heightReason = ns.Options:SetTimelineHeight(120)
local alphaApplied, alphaReason = ns.Options:SetBackgroundAlpha(0.25)
local cooldownApplied, cooldownReason = ns.Options:SetCooldownVisible(257, 120517, false)
assert(scaleApplied == false and scaleReason == "deferred")
assert(widthApplied == false and widthReason == "deferred")
assert(heightApplied == false and heightReason == "deferred")
assert(alphaApplied == false and alphaReason == "deferred")
assert(cooldownApplied == false and cooldownReason == "deferred")
assert(ns.db.timelineScale == 1.25)
assert(ns.db.timelineWidth == 840)
assert(ns.db.timelineHeight == 140)
assert(ns.db.backgroundAlpha == 0.55)
assert(ns.Options:GetRequestedTimelineScale() == 0.8)
assert(ns.Options:GetRequestedTimelineWidth() == 600)
assert(ns.Options:GetRequestedTimelineHeight() == 120)
assert(ns.Options:GetRequestedBackgroundAlpha() == 0.25)
assert(ns.Options:ApplyPendingSettings() == false)
assert(displayApplyCount == 5)
assert(ns.db.cooldownVisibility[257] == nil)

inCombat = false
assert(ns.Options:ApplyPendingSettings() == true)
assert(ns.db.timelineScale == 0.8)
assert(ns.db.timelineWidth == 600)
assert(ns.db.timelineHeight == 120)
assert(ns.db.backgroundAlpha == 0.25)
assert(ns.db.cooldownVisibility[257][120517] == false)
assert(displayApplyCount == 9)
assert(ns.Options:SetTimelineHeight(20) == true and ns.db.timelineHeight == 80)
assert(ns.Options:SetTimelineHeight(165) == true and ns.db.timelineHeight == 160)
assert(ns.Options:SetTimelineHeight(120) == true and ns.db.timelineHeight == 120)

local summaryText
ns.Options.dataSummary = {
    SetText = function(_, value) summaryText = value end,
}
ns.Options:RefreshDataSummary()
assert(summaryText:find("실데이터 11개", 1, true))
assert(summaryText:find("영웅 9", 1, true))
assert(summaryText:find("신화 2", 1, true))

local reloadCount = 0
ReloadUI = function() reloadCount = reloadCount + 1 end
assert(ns.Options:ReloadData() == true)
assert(reloadCount == 1)

inCombat = true
assert(ns.Options:ReloadData() == false)
assert(reloadCount == 1)
assert(#messages == 6)

print("RaidHelper options test OK")
