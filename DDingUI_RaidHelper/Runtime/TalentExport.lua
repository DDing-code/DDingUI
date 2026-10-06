local _, ns = ...

local TalentExport = {}
ns.TalentExport = TalentExport

local HEADER_VERSION_BITS = 8
local SPEC_ID_BITS = 16
local PURCHASED_RANK_BITS = 6
local TREE_HASH_BYTES = 16

local function AsNumber(value)
    if ns:IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function BuildTargets(talents)
    local targets = {}
    local count = 0
    for _, talent in ipairs(talents or {}) do
        local nodeID = AsNumber(talent.nodeID)
        local talentID = AsNumber(talent.talentID)
        local points = AsNumber(talent.points)
        if nodeID and talentID and points and nodeID > 0 and talentID > 0 and points > 0 then
            local target = targets[nodeID]
            if not target then
                target = { ranks = 0, entries = {} }
                targets[nodeID] = target
                count = count + 1
            end
            target.ranks = target.ranks + points
            target.entries[talentID] = points
        end
    end
    return targets, count
end

local function FindChoiceIndex(configID, nodeInfo, target)
    for index, entryID in ipairs(nodeInfo.entryIDs or {}) do
        if target.entries[entryID] then return index end

        local entryInfo = C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID, entryID)
        local definitionID = entryInfo and entryInfo.definitionID
        if definitionID and target.entries[definitionID] then return index end

        local definitionInfo = definitionID and C_Traits.GetDefinitionInfo
            and C_Traits.GetDefinitionInfo(definitionID)
        local spellID = definitionInfo and definitionInfo.spellID
        if spellID and target.entries[spellID] then return index end
    end
    return nil
end

local function WritePurchasedNode(stream, nodeInfo, target, isChoiceNode, choiceIndex)
    local maxRanks = math.max(1, AsNumber(nodeInfo.maxRanks) or target.ranks)
    local purchasedRanks = math.max(1, math.min(maxRanks, target.ranks))
    local partiallyRanked = purchasedRanks < maxRanks
    stream:AddValue(1, partiallyRanked and 1 or 0)
    if partiallyRanked then
        stream:AddValue(PURCHASED_RANK_BITS, purchasedRanks)
    end
    stream:AddValue(1, isChoiceNode and 1 or 0)
    if isChoiceNode then
        stream:AddValue(2, choiceIndex - 1)
    end
end

function TalentExport:GetProfile()
    return ns.Engine and ns.Engine:GetHealerProfile() or nil
end

function TalentExport:GetBuild(profile, buildIndex)
    profile = profile or self:GetProfile()
    return profile and profile.talentBuilds and profile.talentBuilds[buildIndex or 1] or nil
end

function TalentExport:Generate(profile, buildIndex)
    profile = profile or self:GetProfile()
    local build = self:GetBuild(profile, buildIndex)
    if not profile or not build or not next(build.talents or {}) then
        return nil, "수집된 대표 특성 빌드가 없습니다."
    end
    if not C_ClassTalents or not C_Traits or not ExportUtil then
        return nil, "게임 특성 API를 불러오지 못했습니다."
    end

    local specID = AsNumber(profile.specID)
    local playerSpecID = ns.Engine and ns.Engine.playerSpecID
    if not specID or specID ~= playerSpecID then
        return nil, "현재 전문화와 수집된 특성 빌드가 다릅니다."
    end

    local configID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    configID = AsNumber(configID)
    local configInfo = configID and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
    local treeID = configInfo and configInfo.treeIDs and AsNumber(configInfo.treeIDs[1])
    if not configID or not treeID then
        return nil, "현재 전문화의 특성 트리를 찾지 못했습니다."
    end

    local serializationVersion = C_Traits.GetLoadoutSerializationVersion
        and AsNumber(C_Traits.GetLoadoutSerializationVersion())
    if serializationVersion ~= 1 and serializationVersion ~= 2 then
        return nil, "지원하지 않는 특성 코드 버전입니다."
    end

    local treeHash = C_Traits.GetTreeHash and C_Traits.GetTreeHash(treeID)
    if type(treeHash) ~= "table" or #treeHash < TREE_HASH_BYTES then
        return nil, "현재 특성 트리 해시를 읽지 못했습니다."
    end

    local targets, targetCount = BuildTargets(build.talents)
    local treeNodes = C_Traits.GetTreeNodes and C_Traits.GetTreeNodes(treeID)
    if type(treeNodes) ~= "table" or not next(treeNodes) then
        return nil, "현재 특성 트리 노드를 읽지 못했습니다."
    end

    local stream = ExportUtil.MakeExportDataStream and ExportUtil.MakeExportDataStream()
    if not stream or not stream.AddValue or not stream.GetExportString then
        return nil, "특성 코드 생성기를 불러오지 못했습니다."
    end

    stream:AddValue(HEADER_VERSION_BITS, serializationVersion)
    stream:AddValue(SPEC_ID_BITS, specID)
    for index = 1, TREE_HASH_BYTES do
        stream:AddValue(8, treeHash[index])
    end

    local matchedTargets = 0
    local selectionType = Enum and Enum.TraitNodeType and Enum.TraitNodeType.Selection
    for _, nodeID in ipairs(treeNodes) do
        local nodeInfo = C_Traits.GetNodeInfo and C_Traits.GetNodeInfo(configID, nodeID)
        local target = targets[nodeID]
        local selected = nodeInfo ~= nil and target ~= nil
        stream:AddValue(1, selected and 1 or 0)
        if selected then
            matchedTargets = matchedTargets + 1
            local isChoiceNode = selectionType ~= nil and nodeInfo.type == selectionType
            local choiceIndex = isChoiceNode and FindChoiceIndex(configID, nodeInfo, target) or 1
            if isChoiceNode and not choiceIndex then
                return nil, "특성 선택지 정보가 현재 패치와 맞지 않습니다."
            end

            local grantedRanks = AsNumber(nodeInfo.ranksGranted) or 0
            if serializationVersion == 2 then
                local purchased = grantedRanks <= 0
                stream:AddValue(1, purchased and 1 or 0)
                if purchased then
                    WritePurchasedNode(stream, nodeInfo, target, isChoiceNode, choiceIndex)
                end
            else
                WritePurchasedNode(stream, nodeInfo, target, isChoiceNode, choiceIndex)
            end
        end
    end

    if matchedTargets ~= targetCount then
        return nil, "수집된 특성 노드가 현재 패치의 트리와 맞지 않습니다. 데이터를 갱신해 주세요."
    end

    local exportString = stream:GetExportString()
    if type(exportString) ~= "string" or exportString == "" then
        return nil, "특성 코드를 만들지 못했습니다."
    end
    return exportString
end
