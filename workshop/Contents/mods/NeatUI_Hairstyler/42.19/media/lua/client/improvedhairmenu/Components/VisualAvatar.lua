--[[
	This is a UI element that previews a HumanVisual change.
]]
if isServer() then return end
pcall(require, "improvedhairmenu/Components/ExtendedUI3DModel")

local UI3D = (ImprovedHairMenu and ImprovedHairMenu.UI3DModelExt) or rawget(_G, "ISUI3DModelExt")
if not UI3D then
    print("[IHM] VisualAvatar: UI3D base missing, avatars disabled.")
    return
end

VisualAvatar = UI3D:derive("VisualAvatar")

function VisualAvatar:new(x, y, width, height)
    local o = UI3D.new(self, x, y, width, height)
    o.visualItem = {id = "UNINITIALIZED", display = "UNINITIALIZED", selected = false}
    o.desc = nil
    o.char = nil
    o.cursor = false
    return o
end

function VisualAvatar:instantiate()
    UI3D.instantiate(self)
    self:setState("idle")
    self:setDirection(IsoDirections.S)
    self:setIsometric(false)
end

-- NeatUI slot: gradient dark background (covers the vanilla gray avatarBackground),
-- green border on the current style, orange highlight on hover.
function VisualAvatar:prerender()
    if UI3D.prerender then UI3D.prerender(self) end
    local NS = rawget(_G, "IHM_NeatStyle")
    local sel = self.visualItem and self.visualItem.selected == true
    if NS and NS.drawSlotGradient then
        NS.drawSlotGradient(self, 0, 0, self.width, self.height, sel)
    else
        self:drawRect(0, 0, self.width, self.height, 1, 0.10, 0.11, 0.12)
    end
end

function VisualAvatar:render()
    UI3D.render(self)

    local NS  = rawget(_G, "IHM_NeatStyle")
    local acc = (NS and NS.color and NS.color.accent)    or { r = 0.95, g = 0.50, b = 0.10 }
    local grn = (NS and NS.color and NS.color.selection) or { r = 0.30, g = 0.72, b = 0.38 }
    local hover = self.cursor == true
    local sel   = self.visualItem.selected == true

    -- Base slot frame.
    self:drawRectBorder(0, 0, self.width, self.height, 0.9, 0.34, 0.34, 0.36)

    -- Current style: green glass + 2px green border.
    if sel and not hover then
        self:drawRect(0, 0, self.width, self.height, 0.13, grn.r, grn.g, grn.b)
        self:drawRectBorder(0, 0, self.width,     self.height,     1.0, grn.r, grn.g, grn.b)
        self:drawRectBorder(1, 1, self.width - 2, self.height - 2, 1.0, grn.r, grn.g, grn.b)
    end

    -- Hover: orange glass + 2px orange border (takes priority over selection).
    if hover then
        self:drawRect(0, 0, self.width, self.height, 0.20, acc.r, acc.g, acc.b)
        self:drawRectBorder(0, 0, self.width,     self.height,     1.0, acc.r, acc.g, acc.b)
        self:drawRectBorder(1, 1, self.width - 2, self.height - 2, 1.0, acc.r, acc.g, acc.b)
        if sel then
            self:drawRectBorder(2, 2, self.width - 4, self.height - 4, 0.9, grn.r, grn.g, grn.b)
        end
    end
end

function VisualAvatar:setDesc(desc)
	self.desc = desc
	self.char = nil
end

function VisualAvatar:setChar(char)
	self.char = char
	self.desc = nil
end

function VisualAvatar:setVisualItem(args)
	self.visualItem = args
end

function VisualAvatar:applyVisual()
	--[[ XXX:
		The getter and setter functions will affect the visual for all other avatars. this is due
		to the visual being a table which is passed by reference in lua. this means we have to revert
		any changes made while we're in here.

		This still works because when passing the visual to the 3D element the java side makes a copy
		instead of referencing the table.
	 ]]

	--[[ XXX:
		It has to be done like this with 2 separate variables for the char/desc. we can't seem to pass
		the char/desc as a parameter because comparing the java types doesn't work everywhere.
		Possibly something to do with java environment?
	 ]]

	local visual = nil

	if self.desc then
		visual = self.desc:getHumanVisual()
	elseif self.char then
		visual = self.char:getHumanVisual()
	else
		return
	end

	local getter = visual[self.visualItem.getterName]
	local setter = visual[self.visualItem.setterName]

	-- NOTE: Unitialized items won't have getters or setters.
	if not (getter and setter) then
		return
	end

	local original_item = getter(visual)

	if self.visualItem and self.visualItem.id then
		setter(visual, self.visualItem.id)
	end
	
	-- NOTE: This appears to copy the data likely because ISUI3DModel has a java call that copies the table into an object
	-- Dentro pcall, e il ripristino subito dopo fuori da ogni condizione: in
	-- gioco `visual` e' l'HumanVisual **vero** del giocatore, prestato per un
	-- istante a questa cella dell'anteprima. Se setCharacter alza un'eccezione
	-- la riga del ripristino non veniva mai raggiunta e il personaggio restava
	-- davvero con i capelli dell'anteprima. In multiplayer e' peggio: quella
	-- pettinatura e' quella che il server puo' leggere e mandare agli altri.
	pcall(function()
		if self.desc then
			self:setSurvivorDesc(self.desc)
		elseif self.char then
			self:setCharacter(self.char)
		end
	end)

	setter(visual, original_item)
end

function VisualAvatar:setCursor(state)
	self.cursor = state
	if state == true then
		self:showTooltip()
	else
		self:hideTooltip()
	end
end

function VisualAvatar:showTooltip()
    return
end

function VisualAvatar:hideTooltip()
    if self.tooltipUI and self.tooltipUI:getIsVisible() then
        self.tooltipUI:setVisible(false)
        self.tooltipUI:removeFromUIManager()
    end
end