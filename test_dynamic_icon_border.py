"""Keep group-owned borders in charge across dynamic icon style refreshes."""
from pathlib import Path

from lupa.lua51 import LuaRuntime
from test_dashboard_workspace import STUBS


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute('''
        LibStub=function()return nil end
        function addon:GetGlobalFont()return "font.ttf"end
        function addon.CreateTextureBorder(frame, size, r, g, b, a)
            frame.__dduiBorders={}; frame.edgeSize=size
        end
        function addon.UpdateTextureBorderSize(frame, size)frame.edgeSize=size end
        function addon.UpdateTextureBorderColor()end
        function addon.ShowTextureBorder(frame, shown)frame.edgesShown=shown end
        local frameType=getmetatable(UIParent)
        frameType.SetShadowOffset=function()end
        icon=CreateFrame("Frame",nil,UIParent)
        icon.icon=icon:CreateTexture()
        icon.border=CreateFrame("Frame",nil,icon)
        icon.count=icon:CreateFontString()
        icon.cooldown=CreateFrame("Cooldown",nil,icon)
        data={type="item",id=245898,settings={borderSize=1}}
        group={iconSize=38,borderSize=2}
    ''')
    path = Path(__file__).parent / 'DDingUI_CDM/Modules/CustomIcons/IconStyle.lua'
    lua.execute(path.read_text(encoding='utf-8-sig'), 'test', lua.table(Addon=lua.globals().addon))
    lua.execute('''
        local style=addon.CustomIconStyle
        style.ApplyIconSettings(icon,data,group)
        assert(icon.border:IsShown() and icon.border.edgesShown,
            "standalone icons must retain their own border")

        -- GroupRenderer hides the standalone border when taking ownership.
        icon._ddIsManaged=true
        icon.border:Hide()
        icon:SetSize(38,30)
        local groupBorder=icon:CreateTexture()
        groupBorder:Show()
        icon._ddBorders={groupBorder}
        for _,size in ipairs({1,3,0,2}) do
            data.settings.borderSize=size
            style.ApplyIconSettings(icon,data,group)
            assert(not icon.border:IsShown() and not icon.border.edgesShown,
                "style refresh revived a duplicate border above the glow")
            assert(groupBorder:IsShown(), "group border must remain visible")
            assert(icon:GetWidth()==38 and icon:GetHeight()==30)
        end

        -- Direct option calls must obey the same ownership rule.
        icon.border:Show()
        style.ApplyIconBorder(icon,{borderSize=2})
        assert(not icon.border:IsShown())

        icon._ddIsManaged=nil
        style.ApplyIconSettings(icon,data,group)
        assert(icon.border:IsShown() and icon.border.edgeSize==2,
            "releasing group ownership must restore the standalone border")
        data.settings.borderSize=0
        style.ApplyIconSettings(icon,data,group)
        assert(not icon.border:IsShown() and not icon.border.edgesShown)
    ''')
    print('dynamic icon border ownership: OK')


if __name__ == '__main__':
    main()
