--[[
	The pop-out hair/beard grid used by the character creation screen.

	1.4.0 changed how it is dismissed and where it sits:

	  * The full-width Close bar under the last row is gone. Closing is the red X
	    in the header corner (ReplaceCombobox's _IHM_ensureCloseButton), the same
	    control every other Neat window uses, and it costs no vertical space.

	  * The panel is draggable by its header strip, so it can be parked beside the
	    character instead of on top of them. Character creation renders the avatar
	    underneath, and the point of a preview grid is being able to compare it
	    with the real thing.

	Dragging and click-outside-to-close are the two behaviours that fight here: a
	drag that ends past the panel edge, or over the scrim, used to read as "clicked
	away" and shut the menu. _dragging / _dragMoved gate both paths.
]]
if isServer() then return end
require "ISUI/ISButton"
pcall(require, "improvedhairmenu/IHM_NeatStyle")

-- Load order can differ across platforms; ensure HairMenuPanel exists before deriving.
if not rawget(_G, "HairMenuPanel") then
    pcall(require, "improvedhairmenu/HairMenuPanel")
end

local base = rawget(_G, "HairMenuPanel")
if not base then
    print("[IHM] HairMenuPanelModal: HairMenuPanel not available (load order). Modal disabled.")
    return
end

HairMenuPanelModal = base:derive("HairMenuPanelModal")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

function HairMenuPanelModal:initialise()
    base.initialise(self)

    -- La maniglia d'angolo: trascinandola cambiano righe e colonne. Ospitata
    -- dal genitore, non da qui: ricostruire la griglia rifa' questo pannello, e
    -- una maniglia che ci stesse sopra morirebbe a meta' trascinamento.
    -- live = false: qui il bersaglio e' questo pannello, e ricostruire lo
    -- distrugge. Durante il gesto si muove la cornice; il conteggio si applica
    -- al rilascio, quando non c'e' piu' un gesto da spezzare.
    if IHM_GridResize then
        local panel = self
        IHM_GridResize.attach(self, function(cols, rows)
            if panel._ihmApplyGrid then panel._ihmApplyGrid(cols, rows) end
        end)
    end
    ImprovedHairMenu = ImprovedHairMenu or {}
    ImprovedHairMenu._activeCCModal = self

    self.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
    self._dragging  = false
    self._dragMoved = false
end

function HairMenuPanelModal:close()
    if ImprovedHairMenu and ImprovedHairMenu._activeCCModal == self then
        ImprovedHairMenu._activeCCModal = nil
    end
    if self.onClose then self.onClose() end
end

-- ---------------------------------------------------------------------------
-- Drag by the header strip
-- ---------------------------------------------------------------------------

-- Everything in the header that can be clicked (arrows, source combo, the
-- top-right cluster) is a child element and gets the event first, so the strip
-- only starts a drag on the gaps between them.
function HairMenuPanelModal:isInHeader(y)
    local hh = self.headerHeight or 0
    return y >= 0 and y < hh
end

-- Keep the panel inside its parent (the character creation panel), leaving a
-- sliver on every edge so it can always be grabbed again.
function HairMenuPanelModal:clampToParent()
    local p = self.parent
    if not p then return end

    local pw = p:getWidth()
    local ph = p:getHeight()
    local hh = self.headerHeight or 0
    local keep = math.max(24, hh)

    local x = self:getX()
    local y = self:getY()

    if x > pw - keep then x = pw - keep end
    if x + self:getWidth() < keep then x = keep - self:getWidth() end
    if y < 0 then y = 0 end
    if y > ph - keep then y = ph - keep end

    self:setX(x)
    self:setY(y)
end

function HairMenuPanelModal:onMouseDown(x, y)
    if self:isInHeader(y) then
        self._dragging  = true
        self._dragMoved = false
        -- The scrim closes the menu on any mouse-up it sees; a drag that ends
        -- over it is not a click-away.
        if self.parent then self.parent._IHM_suppressScrimClose = true end
        self:setCapture(true)
        return true
    end
    if base.onMouseDown then return base.onMouseDown(self, x, y) end
    return false
end

function HairMenuPanelModal:onMouseMove(dx, dy)
    if self._dragging then
        if dx ~= 0 or dy ~= 0 then self._dragMoved = true end
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
        self:clampToParent()
        return true
    end
    if base.onMouseMove then return base.onMouseMove(self, dx, dy) end
    return false
end

function HairMenuPanelModal:onMouseMoveOutside(dx, dy)
    if self._dragging then return self:onMouseMove(dx, dy) end
    if base.onMouseMoveOutside then return base.onMouseMoveOutside(self, dx, dy) end
    return false
end

-- Returns true when the release was the end of a drag, so the caller knows not
-- to treat it as a click.
function HairMenuPanelModal:endDrag()
    if not self._dragging then return false end
    self._dragging = false
    self:setCapture(false)
    if self.parent then self.parent._IHM_suppressScrimClose = false end
    local moved = self._dragMoved
    self._dragMoved = false
    return moved
end

function HairMenuPanelModal:onMouseUp(x, y)
	if self:endDrag() then return true end
	base.onMouseUp(self, x, y)
	-- Trascinando l'angolo verso l'esterno il rilascio cade quasi sempre fuori
	-- dal pannello, e questa riga lo chiudeva a ogni ridimensionamento.
	if IHM_GridResize and IHM_GridResize.isResizing() then return true end
	if not (0 < x and 0 < y and x < self:getWidth() and y < self:getHeight()) then self:close() end
end

function HairMenuPanelModal:onMouseUpOutside(x, y)
    if self:endDrag() then return true end
    if base.onMouseUpOutside then return base.onMouseUpOutside(self, x, y) end
    return false
end
