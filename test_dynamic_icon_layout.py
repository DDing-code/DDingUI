"""Exercise real group placement and delayed icon motion after an item is added."""
from pathlib import Path

from lupa.lua51 import LuaRuntime
from test_dashboard_workspace import STUBS

ROOT = Path(__file__).parent


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute('''
        local Frame=getmetatable(UIParent)
        function Frame:RegisterEvent()end
        function Frame:GetName()return self.name end
        function Frame:GetNumPoints()return self.point and 1 or 0 end
        function Frame:GetPoint()if self.point then return unpack(self.point)end end
        function Frame:GetSize()return self:GetWidth(),self:GetHeight()end
        function Frame:IsProtected()return false end
        function InCombatLockdown()return false end
        function IsInRaid()return false end
        function IsInGroup()return false end
        function GetCursorPosition()return 0,0 end
        updates={}; timers={}
        local create=CreateFrame
        function CreateFrame(...)
            local f=create(...); updates[#updates+1]=f; return f
        end
        C_Timer.After=function(delay,fn)timers[#timers+1]={at=clockTime+delay,fn=fn}end
        function tick(elapsed)
            clockTime=clockTime+elapsed
            for _,f in ipairs(updates)do
                if f:IsVisible() and f.scripts.OnUpdate then f.scripts.OnUpdate(f,elapsed)end
            end
            local due=timers; timers={}
            for _,t in ipairs(due)do
                if t.at<=clockTime then t.fn()else timers[#timers+1]=t end
            end
        end
        addon.CDMCompat={IsSettingsOpen=function()return false end,GetFrameCooldownID=function()end}
        addon.GroupManager={SortIconListForGroup=function()end}
        addon.db.profile={groupSystem={groups={}},dynamicIcons={iconData={}}}
        addon.CustomIcons={GetDynamicDB=function()return addon.db.profile.dynamicIcons end}
        entries={}
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    for file in ('DynamicIconBridge', 'GroupRenderer'):
        lua.execute((ROOT / f'DDingUI_CDM/Modules/GroupSystem/{file}.lua').read_text(encoding='utf-8-sig'), 'test', ns)
    lua.execute('''
        addon.DynamicIconBridge.GetActiveIconsForGroup=function()return entries end
        local renderer=addon.GroupRenderer
        local settings={enabled=true,shared=true,sourceGroupKey="items",iconSize=38,
            aspectRatioCrop=1.26,spacing=0,direction="RIGHT",iconMotion=true,borderSize=1}
        addon.db.profile.groupSystem.groups.Drink=settings
        local group=CreateFrame("Frame",nil,UIParent)
        group._managedIcons={};group._iconCount=0;group._groupName="Drink"
        group:SetSize(114,30)
        renderer.groupFrames.Drink=group
        local function add(key)
            local f=CreateFrame("Button",nil,UIParent)
            f.icon=f:CreateTexture();f.icon:SetAllPoints(f);f:SetSize(44,44)
            f._iconKey=key; f._type="item"; f._ddCustomIconReady=true
            addon.db.profile.dynamicIcons.iconData[key]={key=key,type="item",id=1,settings={}}
            entries[#entries+1]={iconKey=key,frame=f}
            return f
        end
        local function render()renderer:UpdateGroup("Drink",{},settings)end
        local function positions(label)
            local result={}
            for _,e in ipairs(entries)do
                result[#result+1]=tostring(e.frame.point and e.frame.point[4])
            end
            print(label,table.concat(result,","))
        end
        add("stone");add("health");add("stat");render();tick(1)
        positions("before")
        add("mana");render();positions("added")
        tick(0.02);render();tick(0.3);positions("settled")
        for index=2,#entries do
            local left,right=entries[index-1].frame,entries[index].frame
            assert(right.point[4]-left.point[4]>=38,"added icons remain overlapped")
        end
    ''')


if __name__ == '__main__':
    main()
