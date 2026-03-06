--[[ $Id: CallbackHandler-1.0.lua 3 2008-09-29 16:54:20Z nevcairiel $ ]]
local MAJOR, MINOR = "CallbackHandler-1.0", 7
local CallbackHandler = LibStub:NewLibrary(MAJOR, MINOR)

if not CallbackHandler then return end

local meta = {__index = function(tbl, key) tbl[key] = {} return tbl[key] end}

local type = type
local pcall = pcall
local pairs = pairs
local assert = assert
local concat = table.concat
local loadstring = loadstring
local next = next
local select = select
local type = type
local xpcall = xpcall

local function errorhandler(err)
    return geterrorhandler()(err)
end

local function Dispatch(handlers, ...)
    local index, method = next(handlers)
    if not method then return end
    repeat
        xpcall(method, errorhandler, ...)
        index, method = next(handlers, index)
    until not method
end

function CallbackHandler:New(target, RegisterName, UnregisterName, UnregisterAllName, OnUsed, OnUnused)
    RegisterName = RegisterName or "RegisterCallback"
    UnregisterName = UnregisterName or "UnregisterCallback"
    if UnregisterAllName == nil then
        UnregisterAllName = "UnregisterAllCallbacks"
    end

    local events = setmetatable({}, meta)
    local registry = { recurse = 0, events = events }

    target[RegisterName] = function(self, eventname, method, ...)
        if type(eventname) ~= "string" then
            error("Usage: " .. RegisterName .. "(eventname, method[, arg]): 'eventname' - string expected.", 2)
        end

        method = method or eventname

        local first = not rawget(events, eventname) or not next(events[eventname])

        if type(method) ~= "string" and type(method) ~= "function" then
            error("Usage: " .. RegisterName .. "(eventname, method[, arg]): 'method' - string or function expected.", 2)
        end

        local regfunc

        if type(method) == "string" then
            if type(self) ~= "table" then
                error("Usage: " .. RegisterName .. "(\"eventname\", \"methodname\"): self was not a table?", 2)
            elseif self == target then
                error("Usage: " .. RegisterName .. "(\"eventname\", \"methodname\"): do not use Library:" .. RegisterName .. "(), use your own object as first argument.", 2)
            elseif type(self[method]) ~= "function" then
                error("Usage: " .. RegisterName .. "(\"eventname\", \"methodname\"): 'self." .. tostring(method) .. "' - method not found on self.", 2)
            end

            if select("#", ...) >= 1 then
                local arg = ...
                regfunc = function(...) self[method](self, arg, ...) end
            else
                regfunc = function(...) self[method](self, ...) end
            end
        else
            if type(self) ~= "table" and type(self) ~= "string" and type(self) ~= "thread" then
                error("Usage: " .. RegisterName .. "(self, eventname, method[, arg]): 'self' - table or string expected.", 2)
            end

            if select("#", ...) >= 1 then
                local arg = ...
                regfunc = function(...) method(arg, ...) end
            else
                regfunc = method
            end
        end

        events[eventname][self] = regfunc

        if OnUsed and first then
            OnUsed(target, eventname)
        end
    end

    target[UnregisterName] = function(self, eventname)
        if not self or self == target then
            error("Usage: " .. UnregisterName .. "(eventname): bad 'self'", 2)
        end
        if type(eventname) ~= "string" then
            error("Usage: " .. UnregisterName .. "(eventname): 'eventname' - string expected.", 2)
        end
        if rawget(events, eventname) and events[eventname][self] then
            events[eventname][self] = nil
            if OnUnused and not next(events[eventname]) then
                OnUnused(target, eventname)
            end
        end
        if registry.insertQueue and rawget(registry.insertQueue, eventname) and registry.insertQueue[eventname][self] then
            registry.insertQueue[eventname][self] = nil
        end
    end

    if UnregisterAllName then
        target[UnregisterAllName] = function(...)
            if select("#", ...) < 1 then
                error("Usage: " .. UnregisterAllName .. "(self): 'self' - Loss of self?", 2)
            end
            if select("#", ...) == 1 and ... == target then
                error("Usage: " .. UnregisterAllName .. "(self): do not use Library:" .. UnregisterAllName .. "(), use your own object as first argument.", 2)
            end

            for i = 1, select("#", ...) do
                local self = select(i, ...)
                if registry.insertQueue then
                    for eventname, callbacks in pairs(registry.insertQueue) do
                        if callbacks[self] then
                            callbacks[self] = nil
                        end
                    end
                end
                for eventname, callbacks in pairs(events) do
                    if callbacks[self] then
                        callbacks[self] = nil
                        if OnUnused and not next(callbacks) then
                            OnUnused(target, eventname)
                        end
                    end
                end
            end
        end
    end

    registry.Fire = function(self, eventname, ...)
        if not rawget(events, eventname) or not next(events[eventname]) then return end
        local oldrecurse = registry.recurse
        registry.recurse = oldrecurse + 1

        Dispatch(events[eventname], eventname, ...)

        registry.recurse = oldrecurse

        if registry.insertQueue and oldrecurse == 0 then
            for eventname, callbacks in pairs(registry.insertQueue) do
                local t = rawget(events, eventname)
                if t then
                    for self, regfunc in pairs(callbacks) do
                        t[self] = regfunc
                    end
                end
            end
            registry.insertQueue = nil
        end
    end

    target.Fire = registry.Fire

    return registry
end
