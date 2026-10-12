"""실제 슬롯 갱신 경로의 강화 단계·보석 배치·옵션 해제를 검사한다."""
from pathlib import Path

from ui_runtime import runtime
from test_edit_mode import HARNESS

ROOT = Path(__file__).resolve().parents[1]


def item_runtime():
    lua = runtime()
    lua.execute(HARNESS)
    lua.execute('''
        STANDARD_TEXT_FONT="font.ttf"
        slotIDs={HeadSlot=1,NeckSlot=2,ShoulderSlot=3,BackSlot=15,ChestSlot=5,WristSlot=9,
            HandsSlot=10,WaistSlot=6,LegsSlot=7,FeetSlot=8,Finger0Slot=11,Finger1Slot=12,
            Trinket0Slot=13,Trinket1Slot=14,MainHandSlot=16,SecondaryHandSlot=17}
        function GetInventorySlotInfo(name) return slotIDs[name] end
        function UnitAffectingCombat() return combat end
        function UnitIsUnit(a,b) return a==b end
        local M=getmetatable(UIParent).__index
        function M:SetOwner() end
        function M:GetID() return self.id end
        function M:NumLines() return 0 end
        function M:SetHyperlink() end
        C_Item={GetItemInfo=function() return "Item",nil,4 end,
            GetItemUpgradeInfo=function() calls=calls+1; return upgrade end,
            GetItemNumSockets=function() return 1 end, GetItemIconByID=function() return 123 end}
        ItemLocation={CreateFromEquipmentSlot=function() return {IsValid=function() return false end} end}
        LinkUtil={ExtractLink=function(link) return "item",link:sub(6) end}
        function GetDetailedItemLevelInfo() return 320 end
        ITEM_QUALITY_COLORS={}
        for q=0,5 do ITEM_QUALITY_COLORS[q]={color={r=q/10,g=.2,b=.3}} end
        upgrade={currentLevel=4,maxLevel=8,trackString="영웅"}; calls=0
        links={player="item:100:0:101:0:0:0",target="item:100:0:101:0:0:0"}
        function GetInventoryItemLink(unit) return links[unit] end
        hooks={}; function hooksecurefunc(name,fn) hooks[name]=fn end
        function PaperDollItemSlotButton_Update() end
        function InspectPaperDollItemSlotButton_Update() end
        function ns.DDingToolKit:RegisterModule(name,mod) ns[name]=mod end
        function makeSlot(name,id)
            local b=CreateFrame("Button",name,UIParent); b.id=id; b:SetSize(40,40)
            return b
        end
        function slotData(button)
            local out={}
            for _,region in ipairs(objects) do
                if region.parent==button then out[#out+1]=region end
            end
            return out
        end
    ''')
    for rel in ("Core/Database.lua", "UI/ReadyStatus.lua", "Modules/ItemLevel/ItemLevel.lua"):
        lua.execute((ROOT / rel).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        ns.db.profile.ItemLevel=ns:DeepCopy(ns.defaults.profile.ItemLevel)
        module=ns.ItemLevel; module:OnInitialize(); module:OnEnable()
        updateSelf=hooks.PaperDollItemSlotButton_Update
        updateInspect=hooks.InspectPaperDollItemSlotButton_Update
    ''')
    return lua


def test_upgrade_slot_sides_and_gems_for_self_and_inspect():
    lua = item_runtime()
    lua.execute('''
        for _,unit in ipairs({"player","target"}) do
            for _,id in ipairs({1,10,16,17}) do
                local slot=makeSlot(nil,id)
                local update=unit=="player" and updateSelf or updateInspect
                update(slot,unit)
                local data=slotData(slot)
                local ilvl,track,gem=data[1],data[2],data[4]
                assert(track.text=="4/8" and track.shown)
                assert(track.fontSize==11 and track.fontFlags=="OUTLINE")
                assert(track.textColor[1]==ITEM_QUALITY_COLORS[4].color.r)
                local side=id==10 and "RIGHT" or "LEFT"
                assert(track.points[side][1]==ilvl and track.justify==side)
                if id==16 or id==17 then
                    assert(gem.points.TOP[1]==ilvl, "weapons keep sockets below ilvl")
                else
                    assert(gem.points[side][1]==track, "socket must follow upgrade text")
                end
                module.db.showUpgradeTrack=false; update(slot,unit)
                assert(not track.shown)
                if id==1 or id==10 then assert(gem.points[side][1]==ilvl) end
                module.db.showUpgradeTrack=true
                upgrade.currentLevel=8; update(slot,unit)
                assert(track.text=="8/8" and track.textColor[1]==ns.ReadyStatus.Token("text","dim")[1])
                upgrade.currentLevel=4
            end
        end
    ''')


def test_upgrade_unknown_uncached_secret_and_hidden_slots():
    lua = item_runtime()
    lua.execute('''
        local slot=makeSlot(nil,1); updateSelf(slot)
        local data=slotData(slot); local track=data[2]
        for _,name in ipairs({"탐험가","모험가","노련가","챔피언","영웅","신화",
            "Explorer","Adventurer","Veteran","Champion","Hero","Myth","Unknown"}) do
            upgrade={currentLevel=2,maxLevel=6,trackString=name}; updateSelf(slot)
            assert(track.text=="2/6" and track.shown)
            if name=="Unknown" then assert(track.textColor[1]==ITEM_QUALITY_COLORS[4].color.r) end
        end
        local secret={}; function issecretvalue(v) return rawequal(v,secret) end
        for _,value in ipairs({{}, {currentLevel=0,maxLevel=0}, {currentLevel=9,maxLevel=8},
            {currentLevel=secret,maxLevel=8}, {currentLevel=2,maxLevel=8,trackString=secret}, secret}) do
            upgrade=value; updateSelf(slot); assert(not track.shown)
        end
        upgrade=nil; updateSelf(slot); assert(not track.shown)
        C_Item.GetItemUpgradeInfo=function() error("not cached") end
        updateSelf(slot); assert(not track.shown)
        C_Item.GetItemUpgradeInfo=nil; updateSelf(slot); assert(not track.shown)
        C_Item.GetItemUpgradeInfo=function() return {currentLevel=4,maxLevel=8} end
        module.db.selfIlvlSize=9; updateSelf(slot); assert(track.fontSize==8)
        combat=true; links.player=nil; updateSelf(slot); assert(track.shown)
        combat=false; updateSelf(slot); assert(not track.shown)
        links.player=links.target; updateSelf(slot); module:OnDisable(); assert(not track.shown)
        module:OnEnable(); module.db.selfEnabled=false; updateSelf(slot); assert(not track.shown)
        local other=makeSlot(nil,10); updateInspect(other,"target")
        local otherTrack=slotData(other)[2]; assert(otherTrack.shown)
        module.db.inspectEnabled=false; updateInspect(other,"target"); assert(not otherTrack.shown)
        module:ResetSettings(); assert(module.db.showUpgradeTrack==true)
    ''')
