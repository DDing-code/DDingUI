local addonName, ns = ...

local originalInitDB = ns.InitDB

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
