--[[
LibSharedMedia-3.0
Shared media library for WoW addons
]]

local MAJOR, MINOR = "LibSharedMedia-3.0", 8020003
local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

local _G = getfenv(0)
local pairs = _G.pairs
local type = _G.type

lib.MediaType = lib.MediaType or {}
local MediaType = lib.MediaType

lib.MediaTable = lib.MediaTable or {}
local MediaTable = lib.MediaTable

lib.DefaultMedia = lib.DefaultMedia or {}
local DefaultMedia = lib.DefaultMedia

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

-- Constants for media types
local BACKGROUND		= "background"
local BORDER			= "border"
local FONT				= "font"
local STATUSBAR			= "statusbar"
local SOUND				= "sound"

-- Populate lib.MediaType
MediaType.BACKGROUND	= BACKGROUND
MediaType.BORDER		= BORDER
MediaType.FONT			= FONT
MediaType.STATUSBAR		= STATUSBAR
MediaType.SOUND			= SOUND

-- Create tables for each type
MediaTable[BACKGROUND]	= MediaTable[BACKGROUND] or {}
MediaTable[BORDER]		= MediaTable[BORDER] or {}
MediaTable[FONT]		= MediaTable[FONT] or {}
MediaTable[STATUSBAR]	= MediaTable[STATUSBAR] or {}
MediaTable[SOUND]		= MediaTable[SOUND] or {}

-- Default media
DefaultMedia[BACKGROUND]	= "Blizzard Dialog Background"
DefaultMedia[BORDER]		= "Blizzard Tooltip"
DefaultMedia[FONT]			= "Friz Quadrata TT"
DefaultMedia[STATUSBAR]		= "Blizzard"
DefaultMedia[SOUND]			= "None"

-- Check if game supports the locale
local locale = GetLocale()
local gameLocale = locale

-- Path constants
local SML_MT_font = {
    ["Arial Narrow"]			= [[Fonts\ARIALN.TTF]],
    ["Friz Quadrata TT"]		= [[Fonts\FRIZQT__.TTF]],
    ["Morpheus"]				= [[Fonts\MORPHEUS.TTF]],
    ["Skurri"]					= [[Fonts\SKURRI.TTF]],
}

-- Korean fonts
if gameLocale == "koKR" then
    SML_MT_font["굵은 글꼴"]		= [[Fonts\2002B.TTF]]
    SML_MT_font["기본 글꼴"]		= [[Fonts\2002.TTF]]
    SML_MT_font["데미지 글꼴"]		= [[Fonts\K_Damage.TTF]]
    SML_MT_font["퀘스트 글꼴"]		= [[Fonts\K_Pagetext.TTF]]
end

local SML_MT_background = {
    ["Blizzard Dialog Background"]		= [[Interface\DialogFrame\UI-DialogBox-Background]],
    ["Blizzard Dialog Background Dark"]	= [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
    ["Blizzard Dialog Background Gold"]	= [[Interface\DialogFrame\UI-DialogBox-Gold-Background]],
    ["Blizzard Low Health"]				= [[Interface\FullScreenTextures\LowHealth]],
    ["Blizzard Marble"]					= [[Interface\FrameGeneral\UI-Background-Marble]],
    ["Blizzard Out of Control"]			= [[Interface\FullScreenTextures\OutOfControl]],
    ["Blizzard Parchment"]				= [[Interface\AchievementFrame\UI-Achievement-Parchment-Horizontal]],
    ["Blizzard Parchment 2"]			= [[Interface\AchievementFrame\UI-GuildAchievement-Parchment-Horizontal]],
    ["Blizzard Rock"]					= [[Interface\FrameGeneral\UI-Background-Rock]],
    ["Blizzard Tabard Background"]		= [[Interface\TabardFrame\TabardFrameBackground]],
    ["Blizzard Tooltip"]				= [[Interface\Tooltips\UI-Tooltip-Background]],
    ["Solid"]							= [[Interface\Buttons\WHITE8X8]],
}

local SML_MT_border = {
    ["Blizzard Achievement Wood"]		= [[Interface\AchievementFrame\UI-Achievement-WoodBorder]],
    ["Blizzard Chat Bubble"]			= [[Interface\Tooltips\ChatBubble-Backdrop]],
    ["Blizzard Dialog"]					= [[Interface\DialogFrame\UI-DialogBox-Border]],
    ["Blizzard Dialog Gold"]			= [[Interface\DialogFrame\UI-DialogBox-Gold-Border]],
    ["Blizzard Party"]					= [[Interface\CHARACTERFRAME\UI-Party-Border]],
    ["Blizzard Tooltip"]				= [[Interface\Tooltips\UI-Tooltip-Border]],
    ["None"]							= [[Interface\None]],
}

local SML_MT_statusbar = {
    ["Blizzard"]						= [[Interface\TargetingFrame\UI-StatusBar]],
    ["Blizzard Character Skills Bar"]	= [[Interface\PaperDollInfoFrame\UI-Character-Skills-Bar]],
    ["Blizzard Raid Bar"]				= [[Interface\RaidFrame\Raid-Bar-Hp-Fill]],
}

local SML_MT_sound = {
    ["None"]							= [[Interface\Quiet.ogg]],
}

-- Register default media
for name, path in pairs(SML_MT_font) do
    MediaTable[FONT][name] = path
end
for name, path in pairs(SML_MT_background) do
    MediaTable[BACKGROUND][name] = path
end
for name, path in pairs(SML_MT_border) do
    MediaTable[BORDER][name] = path
end
for name, path in pairs(SML_MT_statusbar) do
    MediaTable[STATUSBAR][name] = path
end
for name, path in pairs(SML_MT_sound) do
    MediaTable[SOUND][name] = path
end

-- API

function lib:Register(mediatype, key, data, langmask)
    if type(mediatype) ~= "string" then
        error(MAJOR..":Register(mediatype, key, data, langmask) - mediatype must be string, got "..type(mediatype))
    end
    if type(key) ~= "string" then
        error(MAJOR..":Register(mediatype, key, data, langmask) - key must be string, got "..type(key))
    end

    mediatype = mediatype:lower()

    if not MediaTable[mediatype] then
        MediaTable[mediatype] = {}
    end

    MediaTable[mediatype][key] = data

    self.callbacks:Fire("LibSharedMedia_Registered", mediatype, key)
    return true
end

function lib:Fetch(mediatype, key, noDefault)
    if type(mediatype) ~= "string" then
        error(MAJOR..":Fetch(mediatype, key, noDefault) - mediatype must be string, got "..type(mediatype))
    end

    mediatype = mediatype:lower()
    local mtt = MediaTable[mediatype]

    if not mtt then
        return nil
    end

    if key then
        return mtt[key] or (not noDefault and mtt[DefaultMedia[mediatype]] or nil)
    else
        return mtt[DefaultMedia[mediatype]]
    end
end

function lib:IsValid(mediatype, key)
    if type(mediatype) ~= "string" then
        error(MAJOR..":IsValid(mediatype, key) - mediatype must be string, got "..type(mediatype))
    end

    mediatype = mediatype:lower()

    if not MediaTable[mediatype] then
        return false
    end

    return MediaTable[mediatype][key] and true or false
end

function lib:HashTable(mediatype)
    if type(mediatype) ~= "string" then
        error(MAJOR..":HashTable(mediatype) - mediatype must be string, got "..type(mediatype))
    end

    mediatype = mediatype:lower()
    return MediaTable[mediatype]
end

function lib:List(mediatype)
    if type(mediatype) ~= "string" then
        error(MAJOR..":List(mediatype) - mediatype must be string, got "..type(mediatype))
    end

    mediatype = mediatype:lower()

    if not MediaTable[mediatype] then
        return nil
    end

    local t = {}
    for k in pairs(MediaTable[mediatype]) do
        t[#t + 1] = k
    end
    table.sort(t)
    return t
end

function lib:GetGlobal(mediatype)
    if type(mediatype) ~= "string" then
        error(MAJOR..":GetGlobal(mediatype) - mediatype must be string, got "..type(mediatype))
    end

    mediatype = mediatype:lower()
    return DefaultMedia[mediatype]
end

function lib:SetGlobal(mediatype, key)
    if type(mediatype) ~= "string" then
        error(MAJOR..":SetGlobal(mediatype, key) - mediatype must be string, got "..type(mediatype))
    end
    if type(key) ~= "string" then
        error(MAJOR..":SetGlobal(mediatype, key) - key must be string, got "..type(key))
    end

    mediatype = mediatype:lower()

    if MediaTable[mediatype] and MediaTable[mediatype][key] then
        DefaultMedia[mediatype] = key
        self.callbacks:Fire("LibSharedMedia_SetGlobal", mediatype, key)
        return true
    end
    return false
end

function lib:GetDefault(mediatype)
    return DefaultMedia[mediatype]
end
