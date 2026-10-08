--[[
	Restores the needed functionality to ISUI3DModel.
	Reorganized Info Screen overwrites the base ISUI3DModel with an outdated version that doesn't have drag support.

	42.20: instead of re-declaring the whole class from a snapshot of the vanilla
	file, only the drag handlers are put back. The old approach silently dropped
	every method vanilla added after the snapshot was taken (in 42.20 that is
	getCharacter, setAnimSetName, getState, setVariable, getVariable,
	clearVariable and clearVariables), which broke unrelated UI that expects them.
]]
if isServer() then return end
-- NOTE: This is a function added by RIS, we're checking if the mod is enabled.
if ISUI3DModel.setCoords then

	--***********************************************************
	--**                    THE INDIE STONE                    **
	--***********************************************************
	-- The handlers below are the vanilla implementation, verbatim.

	require "ISUI/ISUIElement"

	function ISUI3DModel:onMouseDown(x, y)
		self.mouseDown = true
		self.dragX = 0
		self:setCapture(true)
		return true
	end

	function ISUI3DModel:onMouseMove(dx, dy)
		if self.mouseDown then
			self.dragX = self.dragX + dx
			if math.abs(self.dragX) > 40 then
				local dir = self:getDirection()
				dir = IsoDirectionSet.rotate(dir, (self.dragX < 0) and -1 or 1)
				self:setDirection(dir)
				self.dragX = 0
			end
		end
		return true
	end

	function ISUI3DModel:onMouseMoveOutside(dx, dy)
		if self.mouseDown then
			-- This shouldn't happen, but the way setCapture() works is broken.
			self.dragX = self.dragX + dx
			if math.abs(self.dragX) > 40 then
				local dir = self:getDirection()
				dir = IsoDirectionSet.rotate(dir, (self.dragX < 0) and -1 or 1)
				self:setDirection(dir)
				self.dragX = 0
			end
		end
	end

	function ISUI3DModel:onMouseUp(x, y)
		if self.mouseDown then
			self.mouseDown = false
			self.dragX = 0
			self:setCapture(false)
		end
		return true
	end

	function ISUI3DModel:onMouseUpOutside(x, y)
		if self.mouseDown then
			self.mouseDown = false
			self.dragX = 0
			self:setCapture(false)
		end
		return true
	end

	-- Vanilla helpers RIS' replacement class may not carry. Only fill in the
	-- gaps: never overwrite what the running build already provides.
	if not ISUI3DModel.setAnimateWhilePaused then
		function ISUI3DModel:setAnimateWhilePaused(animate)
			self.animateWhilePaused = animate
		end
	end

	if not ISUI3DModel.getCharacter then
		function ISUI3DModel:getCharacter()
			return self.javaObject:getCharacter()
		end
	end

	if not ISUI3DModel.setAnimSetName then
		function ISUI3DModel:setAnimSetName(animSet)
			self.javaObject:setAnimSetName(animSet)
		end
	end

	if not ISUI3DModel.getState then
		function ISUI3DModel:getState()
			self.javaObject:getState()
		end
	end

	if not ISUI3DModel.setVariable then
		function ISUI3DModel:setVariable(key, value)
			self.javaObject:setVariable(key, value)
		end
	end

	if not ISUI3DModel.getVariable then
		function ISUI3DModel:getVariable(key)
			return self.javaObject:getVariable(key)
		end
	end

	if not ISUI3DModel.clearVariable then
		function ISUI3DModel:clearVariable(key)
			self.javaObject:clearVariable(key)
		end
	end

	if not ISUI3DModel.clearVariables then
		function ISUI3DModel:clearVariables()
			self.javaObject:clearVariables()
		end
	end
end
