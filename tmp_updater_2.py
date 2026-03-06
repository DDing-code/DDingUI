import re

file_path = r'G:\wow2\World of Warcraft\_retail_\Interface\AddOns\DDingUI_UF\Modules\Options.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

new_category_data = """local categoryData = {
	{
		id = "general",
		text = "일반",
		children = {
			{ id = "general.global", text = "전역 설정" },
			{ id = "general.media", text = "미디어" },
			{ id = "general.colors", text = "색상" },
			{ id = "general.modules", text = "모듈" },
			{ id = "general.profiles", text = "프로필" },
		},
	},
	{
		id = "personal",
		text = "개인 프레임",
		children = {
			{ id = "personal.general", text = "기본 설정" },
			{ id = "personal.health", text = "체력바" },
			{ id = "personal.power", text = "자원바" },
			{ id = "personal.castbar", text = "시전바" },
			{ id = "personal.buffs", text = "버프" },
			{ id = "personal.debuffs", text = "디버프" },
			{ id = "personal.defensives", text = "생존기" },
			{ id = "personal.privateauras", text = "프라이빗 오라" },
			{ id = "personal.texts", text = "텍스트" },
			{ id = "personal.indicators", text = "인디케이터" },
			{ id = "personal.effects", text = "위협 상태 / 하이라이트" },
			{ id = "personal.fader", text = "페이드" },
			{ id = "personal.healprediction", text = "치유 예측" },
			{ id = "personal.customtext", text = "커스텀 텍스트" },
		},
	},
	{
		id = "group",
		text = "그룹 프레임",
		children = {
			{ id = "group.general", text = "기본 설정" },
			{ id = "group.layout", text = "레이아웃" },
			{ id = "group.health", text = "체력바" },
			{ id = "group.power", text = "자원바" },
			{ id = "group.buffs", text = "버프" },
			{ id = "group.debuffs", text = "디버프" },
			{ id = "group.defensives", text = "생존기" },
			{ id = "group.privateauras", text = "프라이빗 오라" },
			{ id = "group.indicators", text = "인디케이터" },
			{ id = "group.texts", text = "텍스트" },
			{ id = "group.debuffhighlight", text = "디버프 하이라이트" },
			{ id = "group.dispels", text = "해제" },
			{ id = "group.fader", text = "페이드" },
			{ id = "group.healprediction", text = "치유 예측" },
			{ id = "group.effects", text = "위협 상태 / 하이라이트" },
			{ id = "group.customtext", text = "커스텀 텍스트" },
		},
	},
	{
		id = "hottracker",
		text = "HoT 추적",
	},
}"""

text = re.sub(r'local categoryData = \{.*?\n\}\n\n-+\n-- Page Builders', new_category_data + '\n\n-----------------------------------------------\n-- Page Builders', text, flags=re.DOTALL)

# Also fix the pageBuilders mapping map
mapping_fix = """
-- Map personal pages
pageBuilders["personal.general"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitGeneralPage) end
pageBuilders["personal.health"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitHealthPage) end
pageBuilders["personal.power"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitPowerPage) end
pageBuilders["personal.castbar"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitCastBarPage) end
pageBuilders["personal.buffs"] = function(p) BuildSharedFeaturePage(p, "personal", function(c, u) BuildUnitAurasPage(c, u, "buffs") end) end
pageBuilders["personal.debuffs"] = function(p) BuildSharedFeaturePage(p, "personal", function(c, u) BuildUnitAurasPage(c, u, "debuffs") end) end
pageBuilders["personal.defensives"] = function(p) BuildSharedFeaturePage(p, "personal", BuildDefensivesPage) end
pageBuilders["personal.privateauras"] = function(p) BuildSharedFeaturePage(p, "personal", BuildPrivateAurasPage) end
pageBuilders["personal.texts"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitTextsPage) end
pageBuilders["personal.indicators"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitIndicatorsPage) end
pageBuilders["personal.effects"] = function(p) BuildSharedFeaturePage(p, "personal", BuildThreatHighlightPage) end
pageBuilders["personal.fader"] = function(p) BuildSharedFeaturePage(p, "personal", BuildFaderPage) end
pageBuilders["personal.healprediction"] = function(p) BuildSharedFeaturePage(p, "personal", BuildHealPredictionPage) end
pageBuilders["personal.customtext"] = function(p) BuildSharedFeaturePage(p, "personal", BuildCustomTextPage) end

-- Map group pages
pageBuilders["group.general"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitGeneralPage) end
pageBuilders["group.layout"] = function(p) BuildSharedFeaturePage(p, "group", BuildGroupLayoutPage) end
pageBuilders["group.health"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitHealthPage) end
pageBuilders["group.power"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitPowerPage) end
pageBuilders["group.buffs"] = function(p) BuildSharedFeaturePage(p, "group", function(c, u) BuildUnitAurasPage(c, u, "buffs") end) end
pageBuilders["group.debuffs"] = function(p) BuildSharedFeaturePage(p, "group", function(c, u) BuildUnitAurasPage(c, u, "debuffs") end) end
pageBuilders["group.defensives"] = function(p) BuildSharedFeaturePage(p, "group", BuildDefensivesPage) end
pageBuilders["group.privateauras"] = function(p) BuildSharedFeaturePage(p, "group", BuildPrivateAurasPage) end
pageBuilders["group.indicators"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitIndicatorsPage) end
pageBuilders["group.texts"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitTextsPage) end
pageBuilders["group.debuffhighlight"] = function(p) BuildSharedFeaturePage(p, "group", BuildDebuffHighlightPage) end
pageBuilders["group.dispels"] = function(p) BuildSharedFeaturePage(p, "group", BuildDispelsPage) end
pageBuilders["group.fader"] = function(p) BuildSharedFeaturePage(p, "group", BuildFaderPage) end
pageBuilders["group.healprediction"] = function(p) BuildSharedFeaturePage(p, "group", BuildHealPredictionPage) end
pageBuilders["group.effects"] = function(p) BuildSharedFeaturePage(p, "group", BuildThreatHighlightPage) end
pageBuilders["group.customtext"] = function(p) BuildSharedFeaturePage(p, "group", BuildCustomTextPage) end
"""

text = re.sub(r'-- Map personal pages.*?pageBuilders\["group.customtext"\].*?end', mapping_fix.strip(), text, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print('Fixed overlaps.')
