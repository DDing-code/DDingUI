--[[
# Element: Range Fader

Changes the opacity of a unit frame based on whether the frame's unit is in the player's range.

## Widget

Range - A table containing opacity values.

## Notes

Offline units are handled as if they are in range.

## Options

.outsideAlpha - Opacity when the unit is out of range. Defaults to 0.55 (number)[0-1].
.insideAlpha  - Opacity when the unit is within range. Defaults to 1 (number)[0-1].

## Examples

    -- Register with oUF
    self.Range = {
        insideAlpha = 1,
        outsideAlpha = 1/2,
    }
--]]

local _, ns = ...
local oUF = ns.oUF

local function Update(self, event)
	local element = self.Range
	local unit = self.unit

	--[[ Callback: Range:PreUpdate()
	Called before the element has been updated.

	* self - the Range element
	--]]
	if(element.PreUpdate) then
		element:PreUpdate()
	end

	local inRange
	-- [12.0.1] UnitIsConnected can return secret boolean
	local isConnected = not (issecretvalue and issecretvalue(UnitIsConnected(unit))) and UnitIsConnected(unit) or false
	local isEligible = isConnected and UnitInParty(unit)

	-- [FLIGHTHIDE] FlightHide 활성 시 알파 덮어쓰기 방지
	local FH = ns.FlightHide
	local fhActive = FH and (FH._hiding or FH.isActive)

	if(isEligible) then
		inRange = UnitInRange(unit)
		if not fhActive then
			self:SetAlphaFromBoolean(inRange, element.insideAlpha, element.outsideAlpha)
		end
	else
		if not fhActive then
			self:SetAlpha(element.insideAlpha)
		end
	end

	--[[ Callback: Range:PostUpdate(object, inRange, isEligible)
	Called after the element has been updated.

	* self       - the Range element
	* object     - the parent object
	* inRange    - indicates if the unit is within 40 yards of the player (boolean)
	* isEligible - indicates if the unit is eligible for the range check (boolean)
	--]]
	if(element.PostUpdate) then
		return element:PostUpdate(self, inRange, isEligible)
	end
end

local function Path(self, ...)
	--[[ Override: Range.Override(self, event)
	Used to completely override the internal update function.

	* self  - the parent object
	* event - the event triggering the update (string)
	--]]
	return (self.Range.Override or Update) (self, ...)
end

local function Enable(self)
	local element = self.Range
	if(element) then
		element.__owner = self
		element.insideAlpha = element.insideAlpha or 1
		element.outsideAlpha = element.outsideAlpha or 0.55

		self:RegisterEvent('UNIT_IN_RANGE_UPDATE', Path)

		return true
	end
end

local function Disable(self)
	local element = self.Range
	if(element) then
		self:SetAlpha(element.insideAlpha)

		self:UnregisterEvent('UNIT_IN_RANGE_UPDATE', Path)
	end
end

oUF:AddElement('Range', Path, Enable, Disable)
