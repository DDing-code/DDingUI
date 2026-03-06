local _, ns = ...
ns.oUF = {}
ns.oUF.Private = {}

-----------------------------------------------
-- Secret Value API (ElvUI oUF 패턴 by Simpy)
-- WoW 12.x: UnitHealth 등 반환값이 secret value일 수 있음
-- issecretvalue/issecrettable/canaccessvalue 래퍼
-----------------------------------------------

local oUF = ns.oUF

do
	function oUF:IsSecretValue(value)
		return issecretvalue and issecretvalue(value)
	end

	function oUF:IsSecretTable(object)
		return issecrettable and issecrettable(object)
	end

	function oUF:NotSecretValue(value)
		return not issecretvalue or not issecretvalue(value)
	end

	function oUF:NotSecretTable(object)
		return not issecrettable or not issecrettable(object)
	end

	function oUF:CanAccessValue(value)
		return not canaccessvalue or canaccessvalue(value)
	end

	function oUF:CanNotAccessValue(value)
		return canaccessvalue and not canaccessvalue(value)
	end
end
