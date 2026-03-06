-- Parse ElvUI SavedVariables to extract unitframe structure
-- This extracts all keys and their types from the unitframe configuration

local function getType(value)
    local t = type(value)
    if t == "table" then
        -- Check if it's an array or dict
        local hasNumeric = false
        local hasString = false
        for k, v in pairs(value) do
            if type(k) == "number" then hasNumeric = true end
            if type(k) == "string" then hasString = true end
        end
        if hasNumeric and not hasString then
            return "array"
        else
            return "table"
        end
    end
    return t
end

local function printKeys(tbl, prefix, depth, seen)
    if depth > 10 then return end -- Prevent infinite recursion
    seen = seen or {}
    if seen[tbl] then return end
    seen[tbl] = true

    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
        local v = tbl[k]
        local vtype = getType(v)
        local fullKey = prefix and (prefix .. "." .. tostring(k)) or tostring(k)

        if vtype == "table" then
            print(fullKey .. " = table {")
            printKeys(v, fullKey, depth + 1, seen)
            print(string.rep("  ", depth) .. "}")
        else
            print(fullKey .. " = " .. vtype)
        end
    end
end

-- Load the SavedVariables file
dofile([[G:\wow2\World of Warcraft\_retail_\WTF\Account\19178509#5\SavedVariables\ElvUI.lua]])

-- Get the first profile's unitframe settings
local profile = nil
local profileName = nil
if ElvDB and ElvDB.profiles then
    for name, data in pairs(ElvDB.profiles) do
        profile = data
        profileName = name
        break
    end
end

if not profile or not profile.unitframe then
    print("ERROR: No unitframe data found")
    return
end

print("=== PROFILE: " .. tostring(profileName) .. " ===\n")

-- Print global unitframe settings (not under units)
print("=== GLOBAL UNITFRAME SETTINGS ===")
for k, v in pairs(profile.unitframe) do
    if k ~= "units" then
        local vtype = getType(v)
        if vtype == "table" then
            print("unitframe." .. k .. " = table {")
            printKeys(v, "unitframe." .. k, 1)
            print("}")
        else
            print("unitframe." .. k .. " = " .. vtype)
        end
    end
end

print("\n=== UNIT: player ===")
if profile.unitframe.units and profile.unitframe.units.player then
    printKeys(profile.unitframe.units.player, "player", 0)
end

print("\n=== UNIT: target ===")
if profile.unitframe.units and profile.unitframe.units.target then
    printKeys(profile.unitframe.units.target, "target", 0)
end

print("\n=== UNIT: raid1 ===")
if profile.unitframe.units and profile.unitframe.units.raid1 then
    printKeys(profile.unitframe.units.raid1, "raid1", 0)
end

print("\n=== UNIT: party ===")
if profile.unitframe.units and profile.unitframe.units.party then
    printKeys(profile.unitframe.units.party, "party", 0)
end

print("\n=== ALL AVAILABLE UNITS ===")
if profile.unitframe.units then
    for unitName in pairs(profile.unitframe.units) do
        print(unitName)
    end
end
