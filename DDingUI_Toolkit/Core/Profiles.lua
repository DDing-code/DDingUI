local addonName, ns = ...

local originalInitDB = ns.InitDB

local PROFILE_CODE_PREFIX = "DDTK1"
local PROFILE_CODE_SCHEMA = 1
local MAX_PROFILE_CODE_BYTES = 512 * 1024
local MAX_SERIALIZED_BYTES = 2 * 1024 * 1024
local MAX_PROFILE_DEPTH = 32
local MAX_PROFILE_ENTRIES = 50000
local MAX_PROFILE_STRING_BYTES = 2 * 1024 * 1024

ns.PROFILE_CODE_MAX_BYTES = MAX_PROFILE_CODE_BYTES

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function CharacterKey()
    local name, realm = UnitFullName("player")
    name = name or UnitName("player") or "Unknown"
    realm = realm or GetNormalizedRealmName() or GetRealmName() or "Unknown"
    return name .. " - " .. realm
end

local function AddonVersion()
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(getMetadata) ~= "function" then return "?" end

    local ok, version = pcall(getMetadata, addonName, "Version")
    if ok and type(version) == "string" and version ~= "" then
        return version
    end
    return "?"
end

local function ProfileCodeLibraries()
    if not LibStub then return nil, nil end
    return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

local function CopyTransferValue(value, state, depth, isNotepad)
    local valueType = type(value)
    if valueType == "string" then
        state.stringBytes = state.stringBytes + #value
        if state.stringBytes > MAX_PROFILE_STRING_BYTES then
            return nil, "data_size"
        end
        return value
    end
    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, "data_type"
        end
        return value
    end
    if valueType == "boolean" then
        return value
    end
    if valueType ~= "table" then
        return nil, "data_type"
    end
    if depth >= MAX_PROFILE_DEPTH then
        return nil, "data_depth"
    end
    if state.seen[value] then
        return nil, "data_cycle"
    end

    state.seen[value] = true
    local copy = {}
    for key, item in pairs(value) do
        local skip = state.excludeNotes and isNotepad and key == "savedNotes"
        if not skip then
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" and keyType ~= "boolean" then
                state.seen[value] = nil
                return nil, "data_type"
            end

            state.entries = state.entries + 1
            if state.entries > MAX_PROFILE_ENTRIES then
                state.seen[value] = nil
                return nil, "data_size"
            end

            local copiedKey, keyError = CopyTransferValue(key, state, depth + 1, false)
            if keyError then
                state.seen[value] = nil
                return nil, keyError
            end
            local childIsNotepad = depth == 0 and key == "Notepad"
            local copiedItem, itemError = CopyTransferValue(item, state, depth + 1, childIsNotepad)
            if itemError then
                state.seen[value] = nil
                return nil, itemError
            end
            copy[copiedKey] = copiedItem
        end
    end
    state.seen[value] = nil
    return copy
end

local function CopyTransferProfile(profile, excludeNotes)
    if type(profile) ~= "table" then return nil, "profile_missing" end
    return CopyTransferValue(profile, {
        entries = 0,
        stringBytes = 0,
        seen = {},
        excludeNotes = excludeNotes == true,
    }, 0, false)
end

local function StripRetiredProfileData(profile)
    local retiredModules = {
        "BuffChecker",
        "BuffReminder",
        "KeystoneTracker",
    }
    for _, moduleName in ipairs(retiredModules) do
        if type(profile.modules) == "table" then
            profile.modules[moduleName] = nil
        end
        profile[moduleName] = nil
    end
end

local function PrepareImportedProfile(self, profile)
    local imported, copyError = CopyTransferProfile(profile, false)
    if not imported then return nil, copyError end

    if type(imported.modules) ~= "table" then
        imported.modules = {}
    end
    for moduleName in pairs(self.defaults.profile.modules or {}) do
        if imported.modules[moduleName] == nil then
            imported.modules[moduleName] = false
        end
    end

    StripRetiredProfileData(imported)
    self:MergeDefaults(imported, self.defaults.profile)

    local currentNotes = self.db
        and self.db.profile
        and self.db.profile.Notepad
        and self.db.profile.Notepad.savedNotes
    if type(currentNotes) == "table" then
        imported.Notepad = type(imported.Notepad) == "table" and imported.Notepad or {}
        imported.Notepad.savedNotes = self:DeepCopy(currentNotes)
    end
    return imported
end

local function SortedProfileNames()
    local names = {}
    local profiles = DDingUIToolkitDB and DDingUIToolkitDB.profiles
    for name in pairs(type(profiles) == "table" and profiles or {}) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

local function EnsureProfileStorage(self)
    DDingUIToolkitDB = DDingUIToolkitDB or {}

    if type(DDingUIToolkitDB.profiles) ~= "table" then
        local legacyProfile = type(DDingUIToolkitDB.profile) == "table"
            and DDingUIToolkitDB.profile
            or self:DeepCopy(self.defaults.profile)
        DDingUIToolkitDB.profiles = {
            Default = legacyProfile,
        }
    end

    if type(DDingUIToolkitDB.profileKeys) ~= "table" then
        DDingUIToolkitDB.profileKeys = {}
    end

    local charKey = CharacterKey()
    local profileName = DDingUIToolkitDB.profileKeys[charKey]
    if type(profileName) ~= "string"
        or type(DDingUIToolkitDB.profiles[profileName]) ~= "table"
    then
        profileName = DDingUIToolkitDB.profiles.Default and "Default"
            or SortedProfileNames()[1]
            or "Default"
        DDingUIToolkitDB.profileKeys[charKey] = profileName
    end

    if type(DDingUIToolkitDB.profiles[profileName]) ~= "table" then
        DDingUIToolkitDB.profiles[profileName] = self:DeepCopy(self.defaults.profile)
    end

    DDingUIToolkitDB.profile = DDingUIToolkitDB.profiles[profileName]
    self._toolkitProfileName = profileName
    self._toolkitCharacterKey = charKey
end

function ns:InitDB()
    EnsureProfileStorage(self)
    local db = originalInitDB(self)
    DDingUIToolkitDB.profiles[self._toolkitProfileName] = db.profile
    DDingUIToolkitDB.profile = db.profile
    return db
end

function ns:GetToolkitProfileName()
    return self._toolkitProfileName or "Default"
end

function ns:GetToolkitProfileNames()
    return SortedProfileNames()
end

function ns:GetToolkitProfileOptions()
    local options = {}
    for _, name in ipairs(SortedProfileNames()) do
        options[#options + 1] = {
            text = name,
            value = name,
        }
    end
    return options
end

function ns:GetToolkitProfileUsage(profileName)
    local count = 0
    local profileKeys = DDingUIToolkitDB and DDingUIToolkitDB.profileKeys
    for _, name in pairs(type(profileKeys) == "table" and profileKeys or {}) do
        if name == profileName then
            count = count + 1
        end
    end
    return count
end

function ns:UseToolkitProfile(profileName)
    profileName = Trim(profileName)
    local profiles = DDingUIToolkitDB and DDingUIToolkitDB.profiles
    if profileName == "" or type(profiles) ~= "table" or type(profiles[profileName]) ~= "table" then
        return false, "missing"
    end

    local charKey = self._toolkitCharacterKey or CharacterKey()
    DDingUIToolkitDB.profileKeys[charKey] = profileName
    DDingUIToolkitDB.profile = profiles[profileName]
    self._toolkitProfileName = profileName
    if self.db then
        self.db.profile = profiles[profileName]
    end
    return true
end

function ns:CreateToolkitProfile(profileName, copyCurrent)
    profileName = Trim(profileName)
    if profileName == "" then return false, "empty" end
    if #profileName > 48 then return false, "long" end

    local profiles = DDingUIToolkitDB and DDingUIToolkitDB.profiles
    if type(profiles) ~= "table" then return false, "storage" end
    if profiles[profileName] ~= nil then return false, "exists" end

    local source = copyCurrent and self.db and self.db.profile or self.defaults.profile
    profiles[profileName] = self:DeepCopy(source)
    self:MergeDefaults(profiles[profileName], self.defaults.profile)
    return self:UseToolkitProfile(profileName)
end

function ns:ResetToolkitProfile()
    local profileName = self:GetToolkitProfileName()
    local profiles = DDingUIToolkitDB and DDingUIToolkitDB.profiles
    if type(profiles) ~= "table" then return false, "storage" end

    profiles[profileName] = self:DeepCopy(self.defaults.profile)
    DDingUIToolkitDB.profile = profiles[profileName]
    if self.db then
        self.db.profile = profiles[profileName]
    end
    return true
end

function ns:DeleteToolkitProfile(profileName)
    profileName = Trim(profileName)
    local profiles = DDingUIToolkitDB and DDingUIToolkitDB.profiles
    if type(profiles) ~= "table" or type(profiles[profileName]) ~= "table" then
        return false, "missing"
    end

    local names = SortedProfileNames()
    if #names <= 1 then return false, "last" end

    local replacement
    for _, name in ipairs(names) do
        if name ~= profileName then
            replacement = name
            break
        end
    end

    profiles[profileName] = nil
    for charKey, name in pairs(DDingUIToolkitDB.profileKeys) do
        if name == profileName then
            DDingUIToolkitDB.profileKeys[charKey] = replacement
        end
    end

    if self:GetToolkitProfileName() == profileName then
        return self:UseToolkitProfile(replacement)
    end
    return true
end

function ns:ExportToolkitProfileCode()
    local serializer, deflate = ProfileCodeLibraries()
    if not serializer or not deflate then return nil, "library" end

    local profile, profileError = CopyTransferProfile(self.db and self.db.profile, true)
    if not profile then return nil, profileError end

    local payload = {
        addon = addonName,
        schema = PROFILE_CODE_SCHEMA,
        addonVersion = AddonVersion(),
        profileName = self:GetToolkitProfileName(),
        exportedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        notesExcluded = true,
        profile = profile,
    }

    local serializeOK, serialized = pcall(serializer.Serialize, serializer, payload)
    if not serializeOK or type(serialized) ~= "string" then
        return nil, "serialize"
    end
    if #serialized > MAX_SERIALIZED_BYTES then
        return nil, "data_size"
    end

    local compressOK, compressed = pcall(deflate.CompressDeflate, deflate, serialized)
    if not compressOK or type(compressed) ~= "string" then
        return nil, "compress"
    end
    local checksumOK, checksum = pcall(deflate.Adler32, deflate, compressed)
    if not checksumOK or type(checksum) ~= "number" then
        return nil, "checksum"
    end
    local encodeOK, encoded = pcall(deflate.EncodeForPrint, deflate, compressed)
    if not encodeOK or type(encoded) ~= "string" then
        return nil, "encode"
    end

    local code = PROFILE_CODE_PREFIX .. ":" .. tostring(checksum) .. ":" .. encoded
    if #code > MAX_PROFILE_CODE_BYTES then
        return nil, "data_size"
    end
    return code
end

function ns:DecodeToolkitProfileCode(code)
    if type(code) ~= "string" or Trim(code) == "" then
        return nil, "empty_code"
    end
    if #code > MAX_PROFILE_CODE_BYTES then
        return nil, "code_size"
    end

    local serializer, deflate = ProfileCodeLibraries()
    if not serializer or not deflate then return nil, "library" end

    local compact = code:gsub("%s+", "")
    local checksumText, encoded = compact:match("^" .. PROFILE_CODE_PREFIX .. ":(%d+):(.+)$")
    if not checksumText or not encoded then
        return nil, "format"
    end

    local decodeOK, compressed = pcall(deflate.DecodeForPrint, deflate, encoded)
    if not decodeOK or type(compressed) ~= "string" then
        return nil, "decode"
    end

    local checksumOK, checksum = pcall(deflate.Adler32, deflate, compressed)
    if not checksumOK or tostring(checksum) ~= checksumText then
        return nil, "checksum"
    end

    local decompressOK, serialized, trailingBytes = pcall(deflate.DecompressDeflate, deflate, compressed)
    if not decompressOK or type(serialized) ~= "string" or (tonumber(trailingBytes) or 0) ~= 0 then
        return nil, "decompress"
    end
    if #serialized > MAX_SERIALIZED_BYTES then
        return nil, "data_size"
    end

    local callOK, deserializeOK, payload = pcall(serializer.Deserialize, serializer, serialized)
    if not callOK or deserializeOK ~= true or type(payload) ~= "table" then
        return nil, "deserialize"
    end
    if payload.addon ~= addonName then
        return nil, "wrong_addon"
    end
    if payload.schema ~= PROFILE_CODE_SCHEMA then
        return nil, "schema"
    end

    local profile, profileError = CopyTransferProfile(payload.profile, false)
    if not profile then return nil, profileError end

    local sourceName = Trim(payload.profileName)
    if #sourceName > 48 then sourceName = "" end
    local sourceVersion = type(payload.addonVersion) == "string" and payload.addonVersion or "?"
    if #sourceVersion > 32 then sourceVersion = "?" end

    return {
        profile = profile,
        profileName = sourceName,
        addonVersion = sourceVersion,
        exportedAt = type(payload.exportedAt) == "string" and payload.exportedAt or nil,
        notesExcluded = payload.notesExcluded == true,
    }
end

function ns:GetToolkitImportProfileName(decoded, requestedName)
    if type(decoded) ~= "table" or type(decoded.profile) ~= "table" then
        return nil, "profile_missing"
    end

    local profiles = DDingUIToolkitDB and DDingUIToolkitDB.profiles
    if type(profiles) ~= "table" then return nil, "storage" end

    requestedName = Trim(requestedName)
    if requestedName ~= "" then
        if #requestedName > 48 then return nil, "long" end
        if profiles[requestedName] ~= nil then return nil, "exists" end
        return requestedName
    end

    local baseName = Trim(decoded.profileName)
    if baseName == "" or #baseName > 48 then
        baseName = "Imported"
    end
    if profiles[baseName] == nil then return baseName end

    for index = 2, 999 do
        local suffix = " " .. index
        local candidate = baseName .. suffix
        if #candidate <= 48 and profiles[candidate] == nil then
            return candidate
        end
    end

    for index = 1, 999 do
        local candidate = "Imported " .. index
        if profiles[candidate] == nil then return candidate end
    end
    return nil, "name_unavailable"
end

function ns:ImportToolkitProfileCode(decoded, profileName)
    local profiles = DDingUIToolkitDB and DDingUIToolkitDB.profiles
    if type(profiles) ~= "table" then return false, "storage" end

    profileName = Trim(profileName)
    if profileName == "" then return false, "empty" end
    if #profileName > 48 then return false, "long" end
    if profiles[profileName] ~= nil then return false, "exists" end
    if type(decoded) ~= "table" or type(decoded.profile) ~= "table" then
        return false, "profile_missing"
    end

    local imported, importError = PrepareImportedProfile(self, decoded.profile)
    if not imported then return false, importError end

    profiles[profileName] = imported
    local ok, useError = self:UseToolkitProfile(profileName)
    if not ok then
        profiles[profileName] = nil
        return false, useError
    end
    return true, profileName
end
