local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

local importBuffer = ""
local newProfileNameBuffer = ""
local newProfileBuffer = ""
local copyFromBuffer = ""

-- 모듈별 불러오기 상태
local moduleImportSource = "spec"  -- "spec" or "profile"
local moduleImportSourceSpec = nil
local moduleImportSourceProfile = nil
local moduleImportSelected = {}  -- [moduleKey] = true/false

local function CreateProfileOptions()
    local options = {
        type = "group",
        name = L["Profiles"] or "Profiles",
        order = 99,
        childGroups = "tab",
        args = {
            -- Profile Management Tab
            management = {
                type = "group",
                name = L["Profile Management"] or "Profile Management",
                order = 1,
                args = {
                    desc = {
                        type = "description",
                        order = 1,
                        name = L["Manage your profiles: create, delete, copy, or switch between profiles."] or "Manage your profiles: create, delete, copy, or switch between profiles.",
                    },

                    spacer1 = {
                        type = "description",
                        order = 2,
                        name = " ",
                    },

                    currentProfile = {
                        type = "select",
                        name = L["Current Profile"] or "Current Profile",
                        desc = L["Select a profile to switch to."] or "Select a profile to switch to.",
                        order = 10,
                        width = "full",
                        values = function()
                            local profiles = {}
                            if DDingUI.db then
                                for _, name in ipairs(DDingUI.db:GetProfiles()) do
                                    profiles[name] = name
                                end
                            end
                            return profiles
                        end,
                        get = function()
                            return DDingUI.db and DDingUI.db:GetCurrentProfile() or ""
                        end,
                        set = function(_, val)
                            if DDingUI.db then
                                DDingUI.db:SetProfile(val)
                            end
                        end,
                    },

                    -- Per-Spec Snapshots (SpecProfiles)
                    specProfileEnabled = {
                        type = "toggle",
                        name = L["Enable Spec Profile Switching"] or "Enable Spec Profile Switching",
                        desc = (L["Save and restore all settings per specialization within the current profile."]
                            or "Save and restore all settings per specialization within the current profile."),
                        order = 11,
                        width = "full",
                        get = function()
                            if not DDingUI.db or not DDingUI.db.char then return true end
                            return DDingUI.db.char.specProfilesEnabled ~= false
                        end,
                        set = function(_, val)
                            if DDingUI.db and DDingUI.db.char then
                                DDingUI.db.char.specProfilesEnabled = val
                                ReloadUI()
                            end
                        end,
                        confirm = true,
                        confirmText = L["Changing this setting requires a UI reload. Continue?"]
                            or "Changing this setting requires a UI reload. Continue?",
                    },

                    spacer2 = {
                        type = "description",
                        order = 19,
                        name = " ",
                    },

                    newProfileHeader = {
                        type = "header",
                        name = L["Create New Profile"] or "Create New Profile",
                        order = 20,
                    },

                    newProfileName = {
                        type = "input",
                        name = L["New Profile Name"] or "New Profile Name",
                        order = 21,
                        width = "double",
                        get = function() return newProfileBuffer end,
                        set = function(_, val) newProfileBuffer = val or "" end,
                    },

                    createProfile = {
                        type = "execute",
                        name = L["Create"] or "Create",
                        order = 22,
                        func = function()
                            if newProfileBuffer and newProfileBuffer ~= "" and DDingUI.db then
                                DDingUI.db:SetProfile(newProfileBuffer)
                                print("|cff00ff00[DDingUI] Profile '" .. newProfileBuffer .. "' created.|r")
                                newProfileBuffer = ""
                            end
                        end,
                    },

                    spacer3 = {
                        type = "description",
                        order = 29,
                        name = " ",
                    },

                    copyHeader = {
                        type = "header",
                        name = L["Copy Profile"] or "Copy Profile",
                        order = 30,
                    },

                    copyFrom = {
                        type = "select",
                        name = L["Copy From"] or "Copy From",
                        desc = L["Copy settings from another profile to the current one."] or "Copy settings from another profile to the current one.",
                        order = 31,
                        width = "double",
                        values = function()
                            local profiles = {}
                            if DDingUI.db then
                                local current = DDingUI.db:GetCurrentProfile()
                                for _, name in ipairs(DDingUI.db:GetProfiles()) do
                                    if name ~= current then
                                        profiles[name] = name
                                    end
                                end
                            end
                            return profiles
                        end,
                        get = function() return copyFromBuffer end,
                        set = function(_, val) copyFromBuffer = val or "" end,
                    },

                    copyProfile = {
                        type = "execute",
                        name = L["Copy"] or "Copy",
                        order = 32,
                        func = function()
                            if copyFromBuffer and copyFromBuffer ~= "" and DDingUI.db then
                                DDingUI.db:CopyProfile(copyFromBuffer)
                                print("|cff00ff00[DDingUI] Profile copied from '" .. copyFromBuffer .. "'.|r")
                                copyFromBuffer = ""
                            end
                        end,
                    },

                    spacer4 = {
                        type = "description",
                        order = 39,
                        name = " ",
                    },

                    deleteHeader = {
                        type = "header",
                        name = L["Delete Profile"] or "Delete Profile",
                        order = 40,
                    },

                    deleteProfile = {
                        type = "select",
                        name = L["Delete Profile"] or "Delete Profile",
                        desc = L["Select a profile to delete."] or "Select a profile to delete.",
                        order = 41,
                        width = "double",
                        values = function()
                            local profiles = {}
                            if DDingUI.db then
                                local current = DDingUI.db:GetCurrentProfile()
                                for _, name in ipairs(DDingUI.db:GetProfiles()) do
                                    if name ~= current then
                                        profiles[name] = name
                                    end
                                end
                            end
                            return profiles
                        end,
                        get = function() return "" end,
                        set = function(_, val)
                            if val and val ~= "" and DDingUI.db then
                                DDingUI.db:DeleteProfile(val, true)
                                print("|cff00ff00[DDingUI] Profile '" .. val .. "' deleted.|r")
                            end
                        end,
                        confirm = true,
                        confirmText = L["Are you sure you want to delete this profile?"] or "Are you sure you want to delete this profile?",
                    },

                    spacer5 = {
                        type = "description",
                        order = 49,
                        name = " ",
                    },

                    resetHeader = {
                        type = "header",
                        name = L["Reset Profile"] or "Reset Profile",
                        order = 50,
                    },

                    resetProfile = {
                        type = "execute",
                        name = L["Reset Current Profile"] or "Reset Current Profile",
                        desc = L["Reset the current profile to default settings."] or "Reset the current profile to default settings.",
                        order = 51,
                        confirm = true,
                        confirmText = L["Are you sure you want to reset the current profile?"] or "Are you sure you want to reset the current profile?",
                        func = function()
                            if DDingUI.db then
                                DDingUI.db:ResetProfile()
                                print("|cff00ff00[DDingUI] Profile reset to defaults.|r")
                            end
                        end,
                    },
                },
            },

            -- Import/Export Tab
            importExport = {
                type = "group",
                name = L["Import / Export"] or "Import / Export",
                order = 2,
                args = {
                    desc = {
                        type = "description",
                        order = 1,
                        name = L["Export your current profile as text to share, or paste a string to import."] or "Export your current profile as text to share, or paste a string to import.",
                    },

                    spacer1 = {
                        type = "description",
                        order = 2,
                        name = "",
                    },

                    export = {
                        type = "input",
                        name = L["Export Current Profile"] or "Export Current Profile",
                        order = 10,
                        width = "full",
                        multiline = true,
                        get = function()
                            return DDingUI:ExportProfileToString()
                        end,
                        set = function() end,
                    },

                    spacer2 = {
                        type = "description",
                        order = 19,
                        name = " ",
                    },

                    import = {
                        type = "input",
                        name = L["Import Profile String"] or "Import Profile String",
                        order = 20,
                        width = "full",
                        multiline = true,
                        get = function()
                            return importBuffer
                        end,
                        set = function(_, val)
                            importBuffer = val or ""
                        end,
                    },

                    newProfileName = {
                        type = "input",
                        name = L["New Profile Name"] or "New Profile Name",
                        order = 25,
                        width = "full",
                        get = function()
                            return newProfileNameBuffer
                        end,
                        set = function(_, val)
                            newProfileNameBuffer = val or ""
                        end,
                    },

                    importButton = {
                        type = "execute",
                        name = L["Import"] or "Import",
                        order = 30,
                        func = function()
                            local importString = importBuffer

                            if importString then
                                importString = importString:gsub("^%s+", ""):gsub("%s+$", "")
                            end

                            if not importString or importString == "" then
                                print("|cffff0000[DDingUI] Import failed: No data found.|r")
                                return
                            end

                            local newProfileName = newProfileNameBuffer
                            if newProfileName then
                                newProfileName = newProfileName:gsub("^%s+", ""):gsub("%s+$", "")
                            end

                            if not newProfileName or newProfileName == "" then
                                print("|cffff0000[DDingUI] Please enter a profile name for the imported profile.|r")
                                return
                            end

                            local ok, err = DDingUI:ImportProfileFromString(importString, newProfileName)
                            if ok then
                                print("|cff00ff00[DDingUI] Profile imported as '" .. newProfileName .. "'. Please reload your UI.|r")
                                importBuffer = ""
                                newProfileNameBuffer = ""
                            else
                                print("|cffff0000[DDingUI] Import failed: " .. (err or "Unknown error") .. "|r")
                            end
                        end,
                    },
                },
            },

            -- 모듈별 불러오기 Tab
            moduleImport = {
                type = "group",
                name = "모듈별 불러오기",
                order = 3,
                args = {
                    desc = {
                        type = "description",
                        order = 1,
                        name = "다른 전문화 또는 프로필에서 특정 모듈 설정만 불러옵니다.\n선택한 모듈의 설정이 현재 프로필에 덮어씌워집니다.",
                    },

                    spacer1 = {
                        type = "description",
                        order = 2,
                        name = " ",
                    },

                    sourceType = {
                        type = "select",
                        name = "불러올 대상",
                        order = 10,
                        width = "normal",
                        values = {
                            spec = "다른 전문화",
                            profile = "다른 프로필",
                        },
                        get = function() return moduleImportSource end,
                        set = function(_, val)
                            moduleImportSource = val
                            moduleImportSourceSpec = nil
                            moduleImportSourceProfile = nil
                        end,
                    },

                    sourceSpec = {
                        type = "select",
                        name = "원본 전문화",
                        order = 11,
                        width = "double",
                        hidden = function() return moduleImportSource ~= "spec" end,
                        values = function()
                            local SP = DDingUI.SpecProfiles
                            if SP and SP.GetAllSavedSpecs then
                                return SP:GetAllSavedSpecs()
                            end
                            return {}
                        end,
                        get = function() return moduleImportSourceSpec end,
                        set = function(_, val) moduleImportSourceSpec = val end,
                    },

                    sourceProfile = {
                        type = "select",
                        name = "원본 프로필",
                        order = 11,
                        width = "normal",
                        hidden = function() return moduleImportSource ~= "profile" end,
                        values = function()
                            local profiles = {}
                            if DDingUI.db then
                                local current = DDingUI.db:GetCurrentProfile()
                                for _, name in ipairs(DDingUI.db:GetProfiles()) do
                                    if name ~= current then
                                        profiles[name] = name
                                    end
                                end
                            end
                            return profiles
                        end,
                        get = function() return moduleImportSourceProfile end,
                        set = function(_, val) moduleImportSourceProfile = val end,
                    },

                    spacer2 = {
                        type = "description",
                        order = 19,
                        name = " ",
                    },

                    moduleHeader = {
                        type = "header",
                        name = "불러올 모듈 선택",
                        order = 20,
                    },

                    -- 동적으로 모듈 체크박스 생성
                    selectAll = {
                        type = "execute",
                        name = "전체 선택",
                        order = 20.1,
                        width = "half",
                        func = function()
                            local SP = DDingUI.SpecProfiles
                            if SP and SP.MODULE_KEYS then
                                for _, entry in ipairs(SP.MODULE_KEYS) do
                                    moduleImportSelected[entry.key] = true
                                end
                            end
                        end,
                    },

                    deselectAll = {
                        type = "execute",
                        name = "전체 해제",
                        order = 20.2,
                        width = "half",
                        func = function()
                            wipe(moduleImportSelected)
                        end,
                    },

                    spacer3 = {
                        type = "description",
                        order = 39,
                        name = " ",
                    },

                    applyButton = {
                        type = "execute",
                        name = "|cff00ff00불러오기 적용|r",
                        order = 40,
                        width = "full",
                        confirm = true,
                        confirmText = "선택한 모듈 설정을 현재 프로필에 덮어씌웁니다. 계속하시겠습니까?",
                        func = function()
                            local SP = DDingUI.SpecProfiles
                            if not SP then
                                print("|cffff0000[DDingUI] SpecProfiles 모듈을 찾을 수 없습니다.|r")
                                return
                            end

                            -- 선택된 모듈 수집
                            local keys = {}
                            for _, entry in ipairs(SP.MODULE_KEYS) do
                                if moduleImportSelected[entry.key] then
                                    table.insert(keys, entry.key)
                                end
                            end

                            if #keys == 0 then
                                print("|cffff0000[DDingUI] 불러올 모듈을 선택해주세요.|r")
                                return
                            end

                            local ok = false
                            if moduleImportSource == "spec" and moduleImportSourceSpec then
                                -- composite key: "charKey::specID"
                                local charKey, specIDStr = moduleImportSourceSpec:match("^(.+)::(%d+)$")
                                if charKey and specIDStr then
                                    ok = SP:CopyModulesFromCharSpec(charKey, tonumber(specIDStr), keys)
                                end
                            elseif moduleImportSource == "profile" and moduleImportSourceProfile then
                                ok = SP:CopyModulesFromProfile(moduleImportSourceProfile, keys)
                            else
                                print("|cffff0000[DDingUI] 원본을 선택해주세요.|r")
                                return
                            end

                            if ok then
                                local moduleNames = {}
                                for _, entry in ipairs(SP.MODULE_KEYS) do
                                    if moduleImportSelected[entry.key] then
                                        table.insert(moduleNames, entry.name)
                                    end
                                end
                                print("|cff00ff00[DDingUI] 불러오기 완료: " .. table.concat(moduleNames, ", ") .. "|r")
                                if DDingUI.RefreshAll then
                                    DDingUI:RefreshAll()
                                end
                            else
                                print("|cffff0000[DDingUI] 불러오기 실패: 원본 데이터를 찾을 수 없습니다.|r")
                            end
                        end,
                    },
                },
            },
        },
    }

    -- 모듈 체크박스를 동적으로 추가
    local SP = DDingUI.SpecProfiles
    if SP and SP.MODULE_KEYS then
        local moduleArgs = options.args.moduleImport.args
        for i, entry in ipairs(SP.MODULE_KEYS) do
            moduleArgs["module_" .. entry.key] = {
                type = "toggle",
                name = entry.name,
                order = 20 + (i * 0.1),
                width = "normal",
                get = function() return moduleImportSelected[entry.key] or false end,
                set = function(_, val) moduleImportSelected[entry.key] = val end,
            }
        end
    end

    return options
end

ns.CreateProfileOptions = CreateProfileOptions
