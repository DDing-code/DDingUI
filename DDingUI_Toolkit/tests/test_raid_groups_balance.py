from pathlib import Path

from lupa.lua51 import LuaRuntime


def test_auto_balance_uses_equal_group_counts_on_both_sides():
    lua = LuaRuntime()
    lua.execute('''
        ns = {L=setmetatable({}, {__index=function(_, key) return key end}),
            DDingToolKit={RegisterModule=function() end}}
        SlashCmdList = {}
        function CreateFrame()
            return {RegisterEvent=function() end, SetScript=function() end}
        end
    ''')
    source = Path(__file__).parents[1] / "Modules/RaidGroups/RaidGroups.lua"
    lua.execute(source.read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        local module = ns.RaidGroups
        module.testMode = true
        function module:Refresh() end
        function module:SetStatus() end
        local original = module.GetBalanceGroupOrder
        for _, pattern in ipairs({"CONTIGUOUS", "ODD_EVEN"}) do
            for count = 1, 40 do
                module.db = {balancePattern=pattern, currentLayout={}}
                module.roster = {}
                for index = 1, count do
                    module.roster[index] = {name="Player"..index, index=index,
                        class="WARRIOR", role="DAMAGER", damagePosition="MELEE"}
                end
                local expected = math.ceil(count / 10) * 2
                function module:GetBalanceGroupOrder(groupCount)
                    assert(groupCount == expected)
                    local order, first, second = original(self, groupCount)
                    assert(#first == #second)
                    if pattern == "CONTIGUOUS" then
                        assert(first[1] == 1 and first[#first] == expected / 2)
                        assert(second[1] == expected / 2 + 1 and second[#second] == expected)
                    end
                    return order, first, second
                end
                module:AutoBalance()
                local seen, total, sides = {}, 0, {0, 0}
                for slot, name in pairs(module.db.currentLayout) do
                    assert(slot >= 1 and slot <= expected * 5 and not seen[name])
                    seen[name] = true
                    total = total + 1
                    local group = math.floor((slot - 1) / 5) + 1
                    local side = pattern == "CONTIGUOUS" and (group <= expected / 2 and 1 or 2)
                        or (group % 2 == 1 and 1 or 2)
                    sides[side] = sides[side] + 1
                end
                assert(total == count and math.abs(sides[1] - sides[2]) <= 1)
            end
        end
    ''')
