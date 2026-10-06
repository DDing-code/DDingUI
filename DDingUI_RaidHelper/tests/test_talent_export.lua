local addonName = "DDingUI_RaidHelper"
local profile = {
    specID = 105,
    talentBuilds = {
        {
            talents = {
                { nodeID = 100, talentID = 1001, points = 1 },
                { nodeID = 101, talentID = 1002, points = 1 },
                { nodeID = 102, talentID = 1004, points = 1 },
            },
        },
    },
}
local ns = {
    IsSecret = function() return false end,
    Engine = {
        playerSpecID = 105,
        GetHealerProfile = function() return profile end,
    },
}

C_ClassTalents = {
    GetActiveConfigID = function() return 1 end,
}
C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 10 } } end,
    GetLoadoutSerializationVersion = function() return 2 end,
    GetTreeHash = function()
        return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
    end,
    GetTreeNodes = function() return { 100, 101, 102 } end,
    GetNodeInfo = function(_, nodeID)
        if nodeID == 100 then
            return { maxRanks = 1, ranksGranted = 1, type = 0, entryIDs = { 1001 } }
        elseif nodeID == 101 then
            return { maxRanks = 2, ranksGranted = 0, type = 0, entryIDs = { 1002 } }
        end
        return { maxRanks = 1, ranksGranted = 0, type = 2, entryIDs = { 1003, 1004 } }
    end,
    GetEntryInfo = function(_, entryID) return { definitionID = entryID + 10000 } end,
    GetDefinitionInfo = function(definitionID) return { spellID = definitionID + 10000 } end,
}
Enum = { TraitNodeType = { Selection = 2 } }
ExportUtil = {
    MakeExportDataStream = function()
        local values = {}
        return {
            AddValue = function(_, width, value)
                values[#values + 1] = { width, value }
            end,
            GetExportString = function()
                return "EXPORT:" .. tostring(#values)
            end,
        }
    end,
}

assert(loadfile("Runtime/TalentExport.lua"))(addonName, ns)
local exportString, errorText = ns.TalentExport:Generate()
assert(errorText == nil)
assert(exportString == "EXPORT:30")

ns.Engine.playerSpecID = 257
local mismatchString, mismatchError = ns.TalentExport:Generate()
assert(mismatchString == nil)
assert(mismatchError ~= nil)

print("RaidHelper talent export test OK")
