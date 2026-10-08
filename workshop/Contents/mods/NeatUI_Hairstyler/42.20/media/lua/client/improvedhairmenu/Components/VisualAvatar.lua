--[[
	This is a UI element that previews a HumanVisual change.
]]
if isServer() then return end
pcall(require, "improvedhairmenu/Components/ExtendedUI3DModel")
pcall(require, "improvedhairmenu/Components/IHM_NeatTooltip")

-- Live preview toggles. Read through IHM_LiveConfig so the CONTROLS window can
-- flip them without a reload. show_name_tooltip is the opt-in: off, the style
-- name is drawn in the panel header instead.
local IHM_DEFAULT = {
    show_name_tooltip = false,
    drag_rotate       = true,
    hide_clothing     = true,
    rotate_all        = false,
}

local function IHM_opt(key)
    local default = IHM_DEFAULT[key]
    if default == nil then default = true end
    local LC = rawget(_G, "IHM_LiveConfig")
    if LC and LC.getBool then return LC:getBool(key, default) end
    local S = ImprovedHairMenu and ImprovedHairMenu.settings
    if S and S[key] ~= nil then return S[key] and true or false end
    return default
end

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
-- selection border on the current style, cursor highlight on hover. Both colours
-- come from IHM_NeatStyle and are user-settable in Mod Options.
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

    -- Renew the tooltip lease every frame we are the hovered tile: that is what
    -- lets IHM_NeatTooltip retire itself when the grid goes away mid-hover.
    if self.cursor == true then self:showTooltip() end

    local NS  = rawget(_G, "IHM_NeatStyle")
    local cur = (NS and NS.color and NS.color.cursor)    or { r = 0.95, g = 0.50, b = 0.10 }
    local sc  = (NS and NS.color and NS.color.selection) or { r = 0.30, g = 0.72, b = 0.38 }
    local hover = self.cursor == true
    local sel   = self.visualItem.selected == true

    -- Base slot frame.
    self:drawRectBorder(0, 0, self.width, self.height, 0.9, 0.34, 0.34, 0.36)

    -- Current style: selection glass + 2px selection border.
    if sel and not hover then
        self:drawRect(0, 0, self.width, self.height, 0.13, sc.r, sc.g, sc.b)
        self:drawRectBorder(0, 0, self.width,     self.height,     1.0, sc.r, sc.g, sc.b)
        self:drawRectBorder(1, 1, self.width - 2, self.height - 2, 1.0, sc.r, sc.g, sc.b)
    end

    -- Cursor: selector glass + 2px selector border (takes priority over selection).
    if hover then
        self:drawRect(0, 0, self.width, self.height, 0.20, cur.r, cur.g, cur.b)
        self:drawRectBorder(0, 0, self.width,     self.height,     1.0, cur.r, cur.g, cur.b)
        self:drawRectBorder(1, 1, self.width - 2, self.height - 2, 1.0, cur.r, cur.g, cur.b)
        if sel then
            self:drawRectBorder(2, 2, self.width - 4, self.height - 4, 0.9, sc.r, sc.g, sc.b)
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
	--
	-- Dentro pcall, e il ripristino subito dopo fuori da ogni condizione: in
	-- gioco `visual` e' l'HumanVisual **vero** del giocatore, prestato per un
	-- istante a questa cella dell'anteprima. Se setCharacter alza un'eccezione
	-- - un modello che manca, uno stile di un'altra mod, un compagno che
	-- interferisce - la riga del ripristino non veniva mai raggiunta e il
	-- personaggio restava davvero con i capelli dell'anteprima, fino al
	-- prossimo riavvio. In multiplayer e' peggio: quella pettinatura e' quella
	-- che il server puo' leggere e mandare agli altri.
	pcall(function()
		if self.desc then
			self:setSurvivorDesc(self.desc)
		elseif self.char then
			self:setCharacter(self.char)
		end
	end)

	setter(visual, original_item)

	self:applyBareBody()
	self:applySharedDirection()
end

-- With rotate_all on, a freshly built or re-paged avatar adopts the angle the
-- others are already facing, instead of snapping back to front.
function VisualAvatar:applySharedDirection()
	if not IHM_opt("rotate_all") then return end
	local dir = ImprovedHairMenu and ImprovedHairMenu.sharedDir
	if not dir then return end
	pcall(function() self:setDirection(dir) end)
end

--[[ Strip the clothing from the preview so a hat never hides the hair.

	setSurvivorDesc / setCharacter both fill the model's itemVisuals from the
	source's worn items (SurvivorDesc.getWornItems and IsoGameCharacter.getItemVisuals
	respectively) - that is why headwear shows up at all. "Naked" is a real outfit
	in media/clothing/clothing.xml with zero items, so pointing the model at it
	after the visual has been applied leaves the bare body plus the hair.

	Order matters: this has to run after setSurvivorDesc/setCharacter, which reset
	the model's outfit name themselves.
]]
function VisualAvatar:applyBareBody()
	if not IHM_opt("hide_clothing") then return end

	local female = false
	local ok = pcall(function()
		if self.desc then female = self.desc:isFemale()
		elseif self.char then female = self.char:isFemale() end
	end)
	if not ok then female = false end

	pcall(function() self:setOutfitName("Naked", female, false) end)
end

function VisualAvatar:setCursor(state)
	self.cursor = state
	if state == true then
		self:showTooltip()
	else
		self:hideTooltip()
	end
end

--[[ Two presentations of the same fact, and they are mutually exclusive.

    Off (the default), the name is drawn in the panel header by
    HairMenuPanel:render - it tracks the hovered tile and falls back to the
    selected style, and it always sits in the same place.

    On, it follows the pointer instead, which is what the menu did in 1.3.x.
    IHM_ShowHeaderName() reads the same key inverted, so exactly one of the two
    is ever on screen.
]]
function VisualAvatar:showTooltip()
    local TT = rawget(_G, "IHM_NeatTooltip")
    if not TT or not IHM_opt("show_name_tooltip") then return end

    local name = self.visualItem and self.visualItem.display
    if not name or name == "" then return end

    TT.show(name, self:getAbsoluteX(), self:getAbsoluteY(), self.width, self.height)
end

function VisualAvatar:hideTooltip()
    local TT = rawget(_G, "IHM_NeatTooltip")
    if TT and TT.hide then TT.hide() end

    if self.tooltipUI and self.tooltipUI:getIsVisible() then
        self.tooltipUI:setVisible(false)
        self.tooltipUI:removeFromUIManager()
    end
end