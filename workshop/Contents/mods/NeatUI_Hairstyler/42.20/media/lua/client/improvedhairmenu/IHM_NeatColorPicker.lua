--[[
    IHM_NeatColorPicker.lua

    NeatUI-styled HSB colour picker for hair / beard colour. Drop-in replacement
    for IHM_ISColorPickerHSB (which was a restyled copy of the vanilla
    ISColorPickerHSB), keeping the exact contract CharacterCreationMain expects:

        :new(x, y, ColorInfo)   :setInitialColor(ColorInfo)
        :setPickedFunc(fn, ...) .pickedTarget / .resetFocusTo / .keepOnScreen
        pickedFunc(target, {r,g,b}, mouseUp, a1..a4)

    Every control is drawn and hit-tested by the panel itself - no child
    ISUIElements. CharacterCreationMain:showColorPicker() puts this panel under
    setCapture(true), and child mouse routing under capture is unreliable; that
    is exactly why the vanilla HSB picker (child sliders + Accept button) misbehaves
    there. Self-drawn controls sidestep it entirely.

    Styling comes from IHM_NeatStyle / IHM_NeatKit so the window is the same
    MainTitle_BG header + MainPanelBG_FlatTop body as the rest of the mod.
]]
if isServer() then return end

require "ISUI/ISPanelJoypad"
pcall(require, "improvedhairmenu/IHM_NeatStyle")
pcall(require, "improvedhairmenu/IHM_NeatKit")

-- ISPanelJoypad, not ISPanel: CharacterCreationMain:onHairColorMouseDown parks
-- characterPanel.joyfocus.focus on this panel, which only behaves on a joypad
-- panel.
IHM_NeatColorPicker = ISPanelJoypad:derive("IHM_NeatColorPicker")

local FONT_SMALL  = UIFont.Small
local FONT_MEDIUM = UIFont.Medium

local PAD     = 10
local SQUARE  = 176      -- saturation x brightness field
local RAIL_W  = 16       -- hue rail
local GAP     = 8
local SIDE_W  = 104      -- preview + hex column
local SWATCH  = 18
local SW_GAP  = 4

local function NS() return rawget(_G, "IHM_NeatStyle") end
local function KIT() return rawget(_G, "IHM_NeatKit") end

local function tr(key, fallback)
    if not getText then return fallback end
    local t = getText(key)
    if not t or t == key then return fallback end
    return t
end

local function inRect(mx, my, r)
    return r and mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

local function clamp01(v) return math.max(0, math.min(v, 1)) end

-- ---------------------------------------------------------------------------
-- Colour maths (kept local so the picker has no dependency on Color.HSBtoRGB)
-- ---------------------------------------------------------------------------
local function hsbToRgb(h, s, v)
    s, v = clamp01(s or 0), clamp01(v or 0)
    if s <= 0 then return v, v, v end
    h = ((h or 0) % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

local function rgbToHsb(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = ((b - r) / d) + 2
        else h = ((r - g) / d) + 4 end
        h = h / 6
    end
    return h % 1, (mx > 0) and (d / mx) or 0, mx
end

local function toHex(r, g, b)
    return string.format("#%02X%02X%02X",
        math.floor(clamp01(r) * 255 + 0.5),
        math.floor(clamp01(g) * 255 + 0.5),
        math.floor(clamp01(b) * 255 + 0.5))
end

-- ColorInfo / Color / plain table -> r,g,b floats
local function readColor(c)
    if not c then return 1, 1, 1 end
    if c.r ~= nil and c.g ~= nil and c.b ~= nil then return c.r, c.g, c.b end
    local ok, r, g, b = pcall(function() return c:getR(), c:getG(), c:getB() end)
    if ok and r then return r, g, b end
    ok, r, g, b = pcall(function() return c:getRedFloat(), c:getGreenFloat(), c:getBlueFloat() end)
    if ok and r then return r, g, b end
    return 1, 1, 1
end

-- ===========================================================================
-- Construction
-- ===========================================================================

function IHM_NeatColorPicker:new(x, y, initial)
    local kit = KIT()
    local headerH = (kit and kit.headerHeight) or math.floor(getTextManager():getFontHeight(FONT_MEDIUM) * 1.5)
    local fhSml   = getTextManager():getFontHeight(FONT_SMALL)
    local btnH    = fhSml + 12

    local w = PAD + SQUARE + GAP + RAIL_W + GAP + SIDE_W + PAD
    local paletteCols = math.max(1, math.floor((w - PAD * 2 + SW_GAP) / (SWATCH + SW_GAP)))

    -- .new(self, ...) so the metatable lands on the derived class, the pattern
    -- the rest of this mod's panels use.
    local o = ISPanelJoypad.new(self, x, y, w, 10)   -- height set once the palette is known

    o.background   = false
    o.headerH      = headerH
    o.btnH         = btnH
    o.paletteCols  = paletteCols
    o.paletteRows  = 0
    o.palette      = {}
    o.swatches     = {}

    o.h, o.s, o.b = 0, 0, 1
    o.initial     = { r = 1, g = 1, b = 1 }
    o.pickedRGB   = { r = 1, g = 1, b = 1 }
    o.pickedArgs  = {}
    -- Set by callers that have a factory value to go back to (Mod Options does,
    -- character creation does not). The footer button appears only when it is.
    o.defaultColor = nil

    o.rSquare = { x = PAD,                y = headerH + PAD, w = SQUARE, h = SQUARE }
    o.rRail   = { x = PAD + SQUARE + GAP, y = headerH + PAD, w = RAIL_W, h = SQUARE }

    local sideX = PAD + SQUARE + GAP + RAIL_W + GAP
    o.rPreview = { x = sideX, y = headerH + PAD,      w = SIDE_W, h = 52 }
    o.rHex     = { x = sideX, y = headerH + PAD + 60, w = SIDE_W, h = fhSml + 4 }

    local bsz = (kit and kit.buttonSize) or math.floor(getTextManager():getFontHeight(FONT_MEDIUM))
    o.closeSize = bsz
    o.rClose = { x = w - PAD - bsz, y = math.floor((headerH - bsz) / 2), w = bsz, h = bsz }

    o.labelOk      = tr("UI_Ok", "Ok")
    o.labelCancel  = tr("UI_Cancel", "Cancel")
    o.labelDefault = tr("UI_IHM_Opt_Default", "Default")
    o.title        = tr("UI_characreation_hair", "Hair")

    if initial then o:setInitialColor(initial) end
    o:setPalette(nil)
    return o
end

function IHM_NeatColorPicker:initialise() ISPanelJoypad.initialise(self) end

-- No child widgets to walk, so focus handling is just bookkeeping; without these
-- the joypad path would call into an empty joypadButtons table.
function IHM_NeatColorPicker:onGainJoypadFocus(joypadData)
    ISPanelJoypad.onGainJoypadFocus(self, joypadData)
    self.joypadButtons, self.joypadButtonsY = {}, {}
    self.joypadIndex, self.joypadIndexY = 1, 1
end

function IHM_NeatColorPicker:onLoseJoypadFocus(joypadData)
    ISPanelJoypad.onLoseJoypadFocus(self, joypadData)
    self:clearJoypadFocus(joypadData)
end

-- The mod already builds the game's common hair colours for the vanilla mosaic;
-- reusing them here keeps the natural shades one click away.
function IHM_NeatColorPicker:setPalette(colors)
    self.palette = {}
    if type(colors) == "table" then
        for _, c in ipairs(colors) do
            if c and c.r and c.g and c.b then
                table.insert(self.palette, { r = c.r, g = c.g, b = c.b })
            end
        end
    end

    local cols = self.paletteCols
    self.paletteRows = math.ceil(#self.palette / cols)

    local pY = self.headerH + PAD + SQUARE + GAP
    self.swatches = {}
    for i, c in ipairs(self.palette) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        table.insert(self.swatches, {
            x = PAD + col * (SWATCH + SW_GAP),
            y = pY + row * (SWATCH + SW_GAP),
            w = SWATCH, h = SWATCH,
            r = c.r, g = c.g, b = c.b,
        })
    end

    local paletteH = 0
    if self.paletteRows > 0 then
        paletteH = self.paletteRows * (SWATCH + SW_GAP) - SW_GAP + GAP
    end

    local h = self.headerH + PAD + SQUARE + GAP + paletteH + self.btnH + PAD
    self:setHeight(h)

    local tm = getTextManager()
    local bw = math.max(78, 28 + math.max(
        tm:MeasureStringX(FONT_SMALL, self.labelOk),
        tm:MeasureStringX(FONT_SMALL, self.labelCancel),
        tm:MeasureStringX(FONT_SMALL, self.labelDefault)))
    local by = h - PAD - self.btnH
    self.btnOk      = { x = self.width - PAD - bw,         y = by, w = bw, h = self.btnH, label = self.labelOk }
    self.btnCancel  = { x = self.width - PAD - bw * 2 - 8, y = by, w = bw, h = self.btnH, label = self.labelCancel }
    -- Laid out unconditionally, drawn and hit-tested only when a default is set,
    -- so setPalette and setDefaultColor can be called in either order.
    self.btnDefault = { x = PAD,                           y = by, w = bw, h = self.btnH, label = self.labelDefault }
end

-- ===========================================================================
-- Colour state
-- ===========================================================================

function IHM_NeatColorPicker:getRGB() return hsbToRgb(self.h, self.s, self.b) end

function IHM_NeatColorPicker:setRGB(r, g, b)
    self.h, self.s, self.b = rgbToHsb(r, g, b)
    self.pickedRGB.r, self.pickedRGB.g, self.pickedRGB.b = r, g, b
end

function IHM_NeatColorPicker:syncPicked()
    local r, g, b = self:getRGB()
    self.pickedRGB.r, self.pickedRGB.g, self.pickedRGB.b = r, g, b
end

function IHM_NeatColorPicker:setInitialColor(initial)
    local r, g, b = readColor(initial)
    self.initial = { r = r, g = g, b = b }
    self:setRGB(r, g, b)
end

-- Enables the Default footer button. Mod Options passes the value the option
-- was registered with; character creation has no such thing and skips it.
function IHM_NeatColorPicker:setDefaultColor(r, g, b)
    self.defaultColor = { r = r, g = g, b = b }
end

function IHM_NeatColorPicker:setCurrentColor(h, s, b)
    self.h, self.s, self.b = h, s, b
    self:syncPicked()
end

function IHM_NeatColorPicker:setPickedFunc(func, arg1, arg2, arg3, arg4)
    self.pickedFunc = func
    self.pickedArgs = { arg1, arg2, arg3, arg4 }
end

-- Live apply: the avatar updates while dragging, same as the old HSB picker.
function IHM_NeatColorPicker:applyLive(mouseUp)
    self:syncPicked()
    if not self.pickedFunc then return end
    self.pickedFunc(self.pickedTarget, self.pickedRGB, mouseUp and true or false,
        self.pickedArgs[1], self.pickedArgs[2], self.pickedArgs[3], self.pickedArgs[4])
end

-- API parity with ISColorPicker (the mod wraps these on the vanilla mosaic).
function IHM_NeatColorPicker:picked(hide)
    if hide then self:removeSelf() end
    self:applyLive(true)
end

function IHM_NeatColorPicker:picked2(hide) self:applyLive(false) end

-- ===========================================================================
-- Render
-- ===========================================================================

function IHM_NeatColorPicker:prerender()
    local w, h = self.width, self.height
    local S = NS()

    if S and S.drawHeader then
        S.drawBody(self, 0, self.headerH, w, h - self.headerH)
        S.drawHeader(self, 0, 0, w, self.headerH)
    else
        self:drawRect(0, 0, w, h, 1, 0.13, 0.13, 0.14)
        self:drawRect(0, 0, w, self.headerH, 1, 0.07, 0.07, 0.08)
    end

    local fhMed = getTextManager():getFontHeight(FONT_MEDIUM)
    self:drawText(self.title, PAD, math.floor((self.headerH - fhMed) / 2), 1, 1, 1, 1, FONT_MEDIUM)

    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()

    self:drawCloseButton(over and inRect(mx, my, self.rClose))
    self:drawField()
    self:drawRail()
    self:drawSide()
    self:drawPalette(over, mx, my)

    -- footer
    local fhSml = getTextManager():getFontHeight(FONT_SMALL)
    local footer = { self.btnCancel, self.btnOk }
    if self.defaultColor then table.insert(footer, 1, self.btnDefault) end
    for _, btn in ipairs(footer) do
        local hovered = over and inRect(mx, my, btn)
        local tint = (btn == self.btnOk) and (S and S.color.accent) or nil
        self:drawNeatButton(btn.x, btn.y, btn.w, btn.h, hovered, tint)
        self:drawTextCentre(btn.label, btn.x + math.floor(btn.w / 2),
            btn.y + math.floor((btn.h - fhSml) / 2), 1, 1, 1, 1, FONT_SMALL)
    end
end

function IHM_NeatColorPicker:drawNeatButton(x, y, w, h, hovered, tint)
    local S = NS()
    local a, r, g, b = 0.95, 0.18, 0.18, 0.19
    if tint then
        r, g, b = tint.r, tint.g, tint.b
        if hovered then r, g, b = math.min(r * 1.2, 1), math.min(g * 1.2, 1), math.min(b * 1.2, 1) end
    elseif hovered then
        r, g, b = 0.30, 0.30, 0.32
    end
    if S and S.draw3PatchH and S.draw3PatchH(self, x, y, w, h, a, r, g, b) then return end
    if S and S.drawFlat then S.drawFlat(self, x, y, w, h, a, r, g, b) return end
    self:drawRect(x, y, w, h, a, r, g, b)
end

function IHM_NeatColorPicker:drawCloseButton(hovered)
    local S = NS()
    local c = self.rClose
    local cr, cg, cb = 0.80, 0.20, 0.20
    if hovered then cr, cg, cb = 0.96, 0.24, 0.24 end
    if S and S.drawFlat then
        S.drawFlat(self, c.x, c.y, c.w, c.h, 0.95, cr, cg, cb)
    else
        self:drawRect(c.x, c.y, c.w, c.h, 0.95, cr, cg, cb)
    end
    local icon = S and S.iconFalse and S.iconFalse()
    if icon then
        local isz = math.floor(c.w * 0.8)
        local off = math.floor((c.w - isz) / 2)
        self:drawTextureScaled(icon, c.x + off, c.y + off, isz, isz, 1, 1, 1, 1)
    end
end

-- Saturation (x) by brightness (y) for the current hue, using the vanilla
-- ColorPicker gradients; falls back to a computed cell grid.
function IHM_NeatColorPicker:drawField()
    local r = self.rSquare
    local hr, hg, hb = hsbToRgb(self.h, 1, 1)
    local hueTex = getTexture("media/ui/ColorPicker/ColorPicker_Hue.png")
    local satTex = getTexture("media/ui/ColorPicker/ColorPicker_Sat.png")

    if hueTex and satTex then
        self:drawTextureScaled(hueTex, r.x, r.y, r.w, r.h, 1, hr, hg, hb)
        self:drawTextureScaled(satTex, r.x, r.y, r.w, r.h, 1, 1, 1, 1)
    else
        local cells = 24
        local cw, ch = r.w / cells, r.h / cells
        for ix = 0, cells - 1 do
            for iy = 0, cells - 1 do
                local cr, cg, cb = hsbToRgb(self.h, ix / (cells - 1), 1 - iy / (cells - 1))
                self:drawRect(r.x + math.floor(ix * cw), r.y + math.floor(iy * ch),
                    math.ceil(cw), math.ceil(ch), 1, cr, cg, cb)
            end
        end
    end
    self:drawRectBorder(r.x, r.y, r.w, r.h, 0.85, 0.34, 0.34, 0.36)

    local cx = r.x + math.floor(r.w * self.s)
    local cy = r.y + math.floor(r.h * (1 - self.b))
    local cr, cg, cb = self:getRGB()
    self:drawRectBorder(cx - 6, cy - 6, 13, 13, 1, 1, 1, 1)
    self:drawRectBorder(cx - 5, cy - 5, 11, 11, 1, 0, 0, 0)
    self:drawRect(cx - 4, cy - 4, 9, 9, 1, cr, cg, cb)
end

-- No vertical hue strip ships with the game, so it is drawn as 1px bands.
function IHM_NeatColorPicker:drawRail()
    local r = self.rRail
    for i = 0, r.h - 1 do
        local hr, hg, hb = hsbToRgb(i / r.h, 1, 1)
        self:drawRect(r.x, r.y + i, r.w, 1, 1, hr, hg, hb)
    end
    self:drawRectBorder(r.x, r.y, r.w, r.h, 0.85, 0.34, 0.34, 0.36)

    local cy = r.y + math.floor(r.h * self.h)
    self:drawRect(r.x - 2, cy - 1, r.w + 4, 3, 1, 0, 0, 0)
    self:drawRect(r.x - 1, cy - 1, r.w + 2, 1, 1, 1, 1, 1)
    self:drawRect(r.x - 1, cy + 1, r.w + 2, 1, 1, 1, 1, 1)
end

function IHM_NeatColorPicker:drawSide()
    local p = self.rPreview
    local half = math.floor(p.w / 2)
    local ini = self.initial
    local cr, cg, cb = self:getRGB()

    local S = NS()

    -- Inner-panel well behind the split, the way Rocco seats a readout.
    if S and S.drawInnerPanel then
        S.drawInnerPanel(self, p.x - 3, p.y - 3, p.w + 6, p.h + 6)
    end

    self:drawRect(p.x, p.y, half, p.h, 1, ini.r, ini.g, ini.b)
    self:drawRect(p.x + half, p.y, p.w - half, p.h, 1, cr, cg, cb)
    self:drawRectBorder(p.x, p.y, p.w, p.h, 0.85, 0.34, 0.34, 0.36)
    self:drawRect(p.x + half, p.y, 1, p.h, 0.8, 0.08, 0.08, 0.08)

    local acc = (S and S.color.accent) or { r = 0.95, g = 0.50, b = 0.10 }
    self:drawTextCentre(toHex(cr, cg, cb), self.rHex.x + math.floor(self.rHex.w / 2),
        self.rHex.y, acc.r, acc.g, acc.b, 1, FONT_SMALL)
end

function IHM_NeatColorPicker:drawPalette(over, mx, my)
    for _, sw in ipairs(self.swatches) do
        self:drawRect(sw.x, sw.y, sw.w, sw.h, 1, sw.r, sw.g, sw.b)
        if over and inRect(mx, my, sw) then
            self:drawRectBorder(sw.x - 1, sw.y - 1, sw.w + 2, sw.h + 2, 1, 1, 1, 1)
        else
            self:drawRectBorder(sw.x, sw.y, sw.w, sw.h, 0.6, 0, 0, 0)
        end
    end
end

-- ===========================================================================
-- Input
-- ===========================================================================

function IHM_NeatColorPicker:onMouseDown(x, y)
    if self:isCapture() and not self:isMouseOver() then
        return self:onMouseDownOutside(x, y)
    end

    if inRect(x, y, self.rClose) or inRect(x, y, self.btnCancel) then self:cancel(); return true end
    if inRect(x, y, self.btnOk) then self:confirm(); return true end
    if self.defaultColor and inRect(x, y, self.btnDefault) then
        local d = self.defaultColor
        self:setRGB(d.r, d.g, d.b)
        self:applyLive(true)
        return true
    end

    for _, sw in ipairs(self.swatches) do
        if inRect(x, y, sw) then
            self:setRGB(sw.r, sw.g, sw.b)
            self:applyLive(true)
            return true
        end
    end

    if inRect(x, y, self.rSquare) then
        self.dragField = true
        self:applyField(x, y)
        return true
    end
    if inRect(x, y, self.rRail) then
        self.dragRail = true
        self:applyRail(y)
        return true
    end

    -- header drag: move the picker instead of doing nothing
    if y >= 0 and y < self.headerH then
        self.moving = true
        self.moveDX, self.moveDY = x, y
    end
    return true
end

-- Clicking away keeps the live-applied colour, matching how the vanilla mosaic
-- behaves in character creation.
function IHM_NeatColorPicker:onMouseDownOutside(x, y)
    self:confirm()
    return true
end

function IHM_NeatColorPicker:applyField(x, y)
    local r = self.rSquare
    self.s = clamp01((x - r.x) / r.w)
    self.b = clamp01(1 - (y - r.y) / r.h)
    self:applyLive(false)
end

function IHM_NeatColorPicker:applyRail(y)
    local r = self.rRail
    self.h = math.max(0, math.min((y - r.y) / r.h, 0.9999))
    self:applyLive(false)
end

function IHM_NeatColorPicker:onMouseMove(dx, dy)
    if self.dragField then self:applyField(self:getMouseX(), self:getMouseY())
    elseif self.dragRail then self:applyRail(self:getMouseY())
    elseif self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
end

function IHM_NeatColorPicker:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function IHM_NeatColorPicker:onMouseUp(x, y)
    if self.dragField or self.dragRail then self:applyLive(true) end
    self.dragField, self.dragRail, self.moving = false, false, false
    return true
end

function IHM_NeatColorPicker:onMouseUpOutside(x, y) return self:onMouseUp(x, y) end

function IHM_NeatColorPicker:onJoypadDown(button)
    if button == Joypad.AButton then self:confirm()
    elseif button == Joypad.BButton then self:cancel() end
end

-- ===========================================================================
-- Close
-- ===========================================================================

function IHM_NeatColorPicker:confirm()
    self:applyLive(true)
    self:removeSelf()
end

function IHM_NeatColorPicker:cancel()
    self:setRGB(self.initial.r, self.initial.g, self.initial.b)
    self:applyLive(true)
    self:removeSelf()
end

function IHM_NeatColorPicker:removeSelf()
    self:setCapture(false)
    if self.parent then
        self.parent:removeChild(self)
    else
        self:removeFromUIManager()
    end
    if self.joyfocus then
        self.joyfocus.focus = self.resetFocusTo
    end
end

return IHM_NeatColorPicker
