--[[
    IHM_NeatStyle.lua

    NeatUI styling helpers for the Improved Hair Menu (NeatUI fork).

    Robustness model (learned the hard way):
      * The panels ALWAYS paint an opaque dark base with plain drawRect first, so the
        UI can never end up transparent even if a texture lookup fails.
      * On top of that base we lay the NeatUI 9-patch textures for the rounded/clean
        finish. We resolve textures framework-first (media/ui/NeatUI/...) so we reuse
        the exact assets Neat Rocco / NeatUI_Framework already render, then fall back
        to the copies embedded under media/ui/IHMNeat/.
]]
if isServer() then return end

IHM_NeatStyle = IHM_NeatStyle or {}
local S = IHM_NeatStyle

-- ---------------------------------------------------------------------------
-- Palette (Neat Rocco NR_Config)
-- ---------------------------------------------------------------------------
S.color = {
    bgAlpha    = 1.0,
    -- Gli stessi valori delle tinte 9-patch qui sotto (0.08 / 0.15): il
    -- ripiego deve somigliare alla cosa vera, non essere un grigio a caso.
    headerBg   = { r = 0.08, g = 0.08, b = 0.08, a = 1.0 },
    panelBg    = { r = 0.15, g = 0.15, b = 0.15, a = 1.0 },
    accent     = { r = 0.95, g = 0.50, b = 0.10 },
    text       = { r = 0.90, g = 0.90, b = 0.90, a = 1.0 },
    -- Come Y.separator di Equipment: un grigio, non il nero pieno.
    separator  = { r = 0.40, g = 0.40, b = 0.42, a = 1.0 },
    frame      = { r = 0.30, g = 0.30, b = 0.32, a = 1.0 },
    slotBg     = { r = 0.10, g = 0.11, b = 0.12, a = 1.0 },
    slotBgSel  = { r = 0.12, g = 0.20, b = 0.14, a = 1.0 },
    selection  = { r = 0.30, g = 0.72, b = 0.38 },
    cursor     = { r = 0.95, g = 0.50, b = 0.10 },
    slotBorder = { r = 0.34, g = 0.34, b = 0.36 },
    close      = { r = 0.80, g = 0.20, b = 0.20 },
}

-- ---------------------------------------------------------------------------
-- User-configurable grid colours (Options > Mods > NeatUI Hairstyler).
--
-- Only the two the eye actually tracks in the grid are exposed:
--   selection -- the style you are wearing right now (green)
--   cursor    -- the tile the pointer / joypad cursor is on (orange)
--
-- `accent` is deliberately NOT one of them: it is the NeatUI orange the buttons
-- and the colour picker share with Neat Rocco, and repainting the whole family
-- from a hairstyle menu is not what "change the selector colour" means.
-- ---------------------------------------------------------------------------
S.DEFAULTS = {
    selection = { r = 0.30, g = 0.72, b = 0.38 },
    cursor    = { r = 0.95, g = 0.50, b = 0.10 },
}

local function clamp01(v) return math.max(0, math.min(v, 1)) end

function S.setColor(key, r, g, b)
    local c = S.color[key]
    if c == nil or S.DEFAULTS[key] == nil then return end
    c.r = clamp01(tonumber(r) or c.r)
    c.g = clamp01(tonumber(g) or c.g)
    c.b = clamp01(tonumber(b) or c.b)
end

function S.getColor(key)
    local c = S.color[key] or S.DEFAULTS[key] or { r = 1, g = 1, b = 1 }
    return c.r, c.g, c.b
end

-- tint for the 9-patch panel textures (they carry their own shading, keep neutral-dark)
local TINT_BODY   = 0.15   -- Neat Rocco NR_Config.panelBg
local TINT_HEADER = 0.08

-- ---------------------------------------------------------------------------
-- Texture resolution (framework path first, embedded copy second)
-- ---------------------------------------------------------------------------
local EMB = "media/ui/IHMNeat/"

local PATHS = {
    body   = { "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png",  EMB .. "Panel/MainPanelBG_FlatTop.png" },
    round  = { "media/ui/NeatUI/DefaultPanel/MainPanelBG_RoundTop.png", EMB .. "Panel/MainPanelBG_RoundTop.png" },
    header = { "media/ui/NeatUI/DefaultPanel/MainTitle_BG.png",         EMB .. "Panel/MainTitle_BG.png" },
    -- InnerPanel_BG, non ContentPanel_BG: e' quella che usano le altre due
    -- mod per lo stesso scopo, e sono due art diverse.
    inner  = { "media/ui/NeatUI/DefaultPanel/InnerPanel_BG.png",       EMB .. "Panel/ContentPanel_BG.png" },
}
local BTN = {
    bg     = { "media/ui/NeatUI/Button/Background.png",   EMB .. "Button/Background.png" },
    border = { "media/ui/NeatUI/Button/Boarder.png",      EMB .. "Button/Boarder.png" },
    fullL  = { "media/ui/NeatUI/Button/Button_FULL_L.png", EMB .. "Button/Button_FULL_L.png" },
    fullM  = { "media/ui/NeatUI/Button/Button_FULL_M.png", EMB .. "Button/Button_FULL_M.png" },
    fullR  = { "media/ui/NeatUI/Button/Button_FULL_R.png", EMB .. "Button/Button_FULL_R.png" },
}

local _npCache, _texCache = {}, {}

-- IMPORTANT: do NOT cache the result. NinePatchTexture.getSharedTexture may
-- return nil on the very first frames (before the texture system / framework
-- textures are ready). Neat Rocco calls it fresh every prerender, so we do too:
-- getSharedTexture is itself the shared cache, so this is cheap and never
-- "poisons" a failed early lookup for the whole session.
local function NP(list)
    if not NinePatchTexture then return nil end
    for _, path in ipairs(list) do
        local ok, res = pcall(function() return NinePatchTexture.getSharedTexture(path) end)
        if ok and res then return res end
    end
    return nil
end

local function TEX(list)
    local key = list[1]
    local c = _texCache[key]
    if c ~= nil then return c or nil end
    local found = false
    for _, p in ipairs(list) do
        local ok, res = pcall(getTexture, p)
        if ok and res and res.getWidth and res:getWidth() > 0 then found = res; break end
    end
    _texCache[key] = found or false
    return found or nil
end

-- ---------------------------------------------------------------------------
-- Panel drawing.  Each function draws an OPAQUE base first, then a rounded
-- 9-patch texture on top when available. x/y are relative to the element.
-- ---------------------------------------------------------------------------

-- Full body panel (rounded top). Used by the grid modal + in-game window body.
function S.drawBody(el, x, y, w, h)
    local t = NP(PATHS.body)
    if t then
        -- Rounded 9-patch only (it is opaque and carries its own border), like Rocco.
        t:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h, TINT_BODY, TINT_BODY, TINT_BODY, 1.0)
    else
        local c = S.color.panelBg
        el:drawRect(x, y, w, h, c.a or 1, c.r, c.g, c.b)
        local f = S.color.frame
        el:drawRectBorder(x, y, w, h, 1, f.r, f.g, f.b)
    end
end

-- Header/title bar (rounded top).
function S.drawHeader(el, x, y, w, h)
    local t = NP(PATHS.header)
    if t then
        t:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h, TINT_HEADER, TINT_HEADER, TINT_HEADER, 1.0)
    else
        local c = S.color.headerBg
        el:drawRect(x, y, w, h, c.a or 1, c.r, c.g, c.b)
    end
    -- Fuori dall'if: la riga nera sotto l'intestazione ci va in tutti e due i
    -- casi, come in Equipment. Prima c'era solo nel ripiego, quindi la
    -- finestra vera - quella con la 9-patch - ne restava senza.
    el:drawRect(x, y + h - 1, w, 1, 1, 0, 0, 0)
end

-- Recessed well for a readout sitting on the body (Rocco's InnerPanel_BG).
function S.drawInnerPanel(el, x, y, w, h)
    local t = NP(PATHS.inner)
    if t then
        -- Stessi numeri di Equipment: tinta 0.10, alfa 0.85.
        t:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h, 0.10, 0.10, 0.10, 0.85)
    else
        el:drawRect(x, y, w, h, 0.85, 0.10, 0.10, 0.10)
    end
end

-- Outer frame around a whole panel.
function S.drawFrame(el, x, y, w, h)
    local f = S.color.frame
    el:drawRectBorder(x, y, w, h, f.a or 1, f.r, f.g, f.b)
end

-- ---------------------------------------------------------------------------
-- 3-patch / flat button backgrounds
-- ---------------------------------------------------------------------------
local function draw3PatchH(el, x, y, w, h, a, r, g, b)
    local L, M, R = TEX(BTN.fullL), TEX(BTN.fullM), TEX(BTN.fullR)
    if not (L and M and R) then return false end
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    local lw = math.floor(L:getWidth() * (h / L:getHeight()))
    local rw = math.floor(R:getWidth() * (h / R:getHeight()))
    if w <= lw + rw then
        local lr = lw / (lw + rw)
        lw = math.floor(w * lr); rw = w - lw
        el:drawTextureScaled(L, x, y, lw, h, a, r, g, b)
        el:drawTextureScaled(R, x + lw, y, rw, h, a, r, g, b)
    else
        local mw = w - lw - rw
        el:drawTextureScaled(L, x, y, lw, h, a, r, g, b)
        el:drawTextureScaled(M, x + lw, y, mw, h, a, r, g, b)
        el:drawTextureScaled(R, x + lw + mw, y, rw, h, a, r, g, b)
    end
    return true
end

local function drawFlat(el, x, y, w, h, a, r, g, b)
    local bg, brd = TEX(BTN.bg), TEX(BTN.border)
    if bg then
        el:drawTextureScaled(bg, x, y, w, h, a, r, g, b)
    else
        el:drawRect(x, y, w, h, a, r, g, b)                    -- fallback
    end
    if brd then el:drawTextureScaled(brd, x, y, w, h, 1, 0.4, 0.4, 0.4) end
end
S.draw3PatchH = draw3PatchH
S.drawFlat    = drawFlat

-- tint is a {r,g,b} table for a coloured (active) button, or nil for neutral.
local function stateColors(btn, tint)
    if tint then
        local r, g, b = tint.r, tint.g, tint.b
        if btn.pressed then return 0.9, r * 0.8, g * 0.8, b * 0.8 end
        if btn:isMouseOver() then return 0.95, math.min(r*1.2,1), math.min(g*1.2,1), math.min(b*1.2,1) end
        return 0.95, r, g, b
    end
    if btn.pressed then return 0.95, 0.10, 0.10, 0.11 end
    if btn:isMouseOver() then return 0.95, 0.30, 0.30, 0.32 end
    return 0.95, 0.18, 0.18, 0.19
end

-- Accept legacy boolean (true = orange accent) or a {r,g,b} tint table.
local function resolveTint(v)
    if v == true then return S.color.accent end
    if type(v) == "table" then return v end
    return nil
end

-- Wide pill button (Open, Close, CONTROLS).
function S.styleFullButton(btn, tint)
    if not btn then return end
    btn:setDisplayBackground(false)
    btn._ihmTint = resolveTint(tint)
    btn.prerender = function(b)
        local a, r, g, bl = stateColors(b, b._ihmTint)
        if not draw3PatchH(b, 0, 0, b.width, b.height, a, r, g, bl) then
            drawFlat(b, 0, 0, b.width, b.height, a, r, g, bl)
        end
    end
end

-- Small square icon button (page arrows, close). Keeps the button's own image.
function S.styleSquareButton(btn, tint)
    if not btn then return end
    btn:setDisplayBackground(false)
    btn._ihmTint = resolveTint(tint)
    btn.prerender = function(b)
        local a, r, g, bl = stateColors(b, b._ihmTint)
        drawFlat(b, 0, 0, b.width, b.height, a, r, g, bl)
    end
end

-- The framework's white tick, framework path first then the embedded copy - the
-- same order the panels use. ICON_Check is deliberately skipped: it is a green
-- filled disc, which fights the box it sits in.
function S.iconTrue()
    for _, p in ipairs({ "media/ui/NeatUI/ICON/Icon_True.png", EMB .. "Icon/Icon_True.png" }) do
        local ok, t = pcall(getTexture, p)
        if ok and t then return t end
    end
    return nil
end

--[[ Colour swatch: a rounded chip filled with the colour it stands for.

    Background.png is the piece that takes a tint. The Button_FULL 3-slice does
    not: that art is black at low alpha (its centre pixel is 0,0,0 a33), so it is
    shading meant to sit *over* something, and multiplying it by a colour just
    gives black - which is exactly what a first attempt at this looked like.
    Background.png is the opposite, white at a139, so tinting it yields the
    colour, and its own alpha edge keeps the corners round.

    One pass lands at ~55% opacity and the panel shows through, washing the
    colour out; three stack it to ~91%, which reads as solid. Boarder.png then
    supplies the rounded outline - a drawRectBorder would leave four bright
    corners hanging off a rounded chip.

    Reads btn.backgroundColor, which is where both callers already keep the
    value: character creation sets it through _IHM_setSwatchButtonColor, and
    vanilla MainOptions:addColorButton sets it on the Mod Options row.
]]
function S.drawSwatch(el, x, y, w, h, r, g, b, brd)
    local bg, border = TEX(BTN.bg), TEX(BTN.border)
    if bg then
        for _ = 1, 3 do el:drawTextureScaled(bg, x, y, w, h, 1, r, g, b) end
    else
        el:drawRect(x, y, w, h, 1, r, g, b)
    end
    if border then
        el:drawTextureScaled(border, x, y, w, h, 1, brd, brd, brd)
    else
        el:drawRectBorder(x, y, w, h, 1, brd, brd, brd)
    end
end

function S.styleSwatchButton(btn)
    if not btn then return end
    btn:setDisplayBackground(false)
    if btn._ihmNeatSwatch then return end
    btn._ihmNeatSwatch = true

    btn.prerender = function(b)
        local c = b.backgroundColor or { r = 1, g = 1, b = 1 }
        local brd = 0.45
        if b.pressed then brd = 0.30
        elseif b:isMouseOver() and b.enable ~= false then brd = 0.75 end
        S.drawSwatch(b, 0, 0, b.width, b.height, c.r, c.g, c.b, brd)
    end
end

--[[ Tick box: rounded Neat square plus the framework's white check.

    A skin, not a replacement. ISTickBox owns the state (self.selected), the hit
    testing and the joypad handling; only :render is swapped, so every caller
    keeps talking to it through addOption / isSelected / setSelected. Swapping the
    widget itself would mean re-wiring CharacterCreationMain's stubble callbacks
    for no visual gain.

    The vanilla box is a 1px rect border with a green tick from
    getGoodHighlitedColor(); this draws the framework button art and a near-white
    tick, so the state reads the same way it does on the CONTROLS toggles.
]]
function S.styleTickBox(tb)
    if not tb or tb._ihmNeatTick then return end
    tb._ihmNeatTick = true
    tb.background = false

    tb.render = function(box)
        local n = #box.options
        if n < 1 then return end

        local tick    = S.iconTrue()
        local sz      = box.boxSize or math.min(box.width, box.height)
        local spacing = 10                                    -- ISTickBox's own UI_BORDER_SPACING
        local total   = n * (box.itemHgt + spacing) - spacing
        local y       = math.floor((box.height - total) / 2)
        local boxDY   = math.floor((box.itemHgt - sz) / 2)
        local textDY  = math.floor((box.itemHgt - box.fontHgt) / 2)
        local hovered = box:isMouseOver()

        for i, label in ipairs(box.options) do
            local disabled = box.disabledOptions[label] and true or false
            local active   = (hovered and box.mouseOverOption == i and box.enable and not disabled)
                             or (box.joypadFocused and box.joypadIndex == i)

            local a = disabled and 0.45 or 1.0
            local r, g, b = 0.18, 0.18, 0.19
            if active then r, g, b = 0.30, 0.30, 0.32 end
            drawFlat(box, box.leftMargin, y + boxDY, sz, sz, a, r, g, b)

            if box.selected[i] == true then
                local isz = math.max(4, math.floor(sz * 0.66))
                local off = math.floor((sz - isz) / 2)
                if tick then
                    box:drawTextureScaled(tick, box.leftMargin + off, y + boxDY + off,
                        isz, isz, a, 0.92, 0.92, 0.92)
                else
                    box:drawRect(box.leftMargin + off, y + boxDY + off, isz, isz,
                        a, 0.92, 0.92, 0.92)
                end
            end

            if label ~= "" then
                box:drawText(label, box.leftMargin + sz + box.textGap, y + textDY,
                    0.92, 0.92, 0.92, a, box.font)
            end

            y = y + box.itemHgt + spacing
        end
    end
end

-- ---------------------------------------------------------------------------
-- Avatar-tile slot background: subtle vertical gradient (replaces the flat
-- gray avatarBackground). Drawn AFTER ExtendedUI3DModel:prerender so it covers
-- the vanilla gray, then the 3D model renders on top.
-- ---------------------------------------------------------------------------
function S.drawSlotBG(el, x, y, w, h)
    local tr, tg, tb = 0.15, 0.16, 0.18   -- top
    local br, bg, bb = 0.06, 0.07, 0.08   -- bottom
    local n = 7
    for i = 0, n - 1 do
        local t  = i / (n - 1)
        local by = y + math.floor(h * i / n)
        local bh = math.ceil(h / n) + 1
        el:drawRect(x, by, w, bh, 1,
            tr + (br - tr) * t,
            tg + (bg - tg) * t,
            tb + (bb - tb) * t)
    end
end

-- ---------------------------------------------------------------------------
-- Framework components. Reuse the real NeatUI_Framework widgets/icons when
-- present (identical look to Neat Rocco); degrade gracefully otherwise.
-- ---------------------------------------------------------------------------

--[[ Le due icone da barbiere di Neat Rocco.

    Sono quelle che Rocco mette al posto dei tasti vanilla capelli/barba nella
    schermata del personaggio: usare le stesse anche in creazione personaggio e'
    quello che fa sembrare le due schermate la stessa interfaccia.

    Si prova prima il percorso di Rocco, cosi' chi ha quella mod installata vede
    esattamente la sua art; la copia qui dentro serve a chi non ce l'ha.
]]
local function iconFrom(list)
    for _, p in ipairs(list) do
        local ok, t = pcall(getTexture, p)
        if ok and t then return t end
    end
    return nil
end

function S.iconScissors()
    return iconFrom({ "media/ui/NeatRocco/ICON/Icon_Scissors.png", EMB .. "Icon/Icon_Scissors.png" })
end

function S.iconRazor()
    return iconFrom({ "media/ui/NeatRocco/ICON/Icon_Razor.png", EMB .. "Icon/Icon_Razor.png" })
end

-- The NeatUI "X" close icon (framework path first, embedded fallback).
function S.iconFalse()
    local ok, t = pcall(getTexture, "media/ui/NeatUI/ICON/Icon_False.png")
    if ok and t then return t end
    ok, t = pcall(getTexture, EMB .. "Icon/Icon_False.png")
    return ok and t or nil
end

-- Create a real NI_SquareButton (framework) when available; else a styled ISButton.
-- activeColor is an optional {r,g,b} table.
function S.newSquareButton(x, y, size, icon, target, onclick, activeColor)
    local SB = rawget(_G, "NI_SquareButton")
    if SB then
        local b = SB:new(x, y, size, icon, target, onclick)
        b:initialise()
        if activeColor then
            b:setActive(true)
            b:setActiveColor(activeColor.r, activeColor.g, activeColor.b)
        else
            b:setActive(false)
        end
        return b
    end
    local b = ISButton:new(x, y, size, size, "", target, onclick)
    b:initialise(); b:instantiate()
    if icon and b.setImage then b:setImage(icon) end
    S.styleSquareButton(b, activeColor)
    return b
end

--[[ Tint the selected tile's gradient with the selection colour.

    The texture is a dark gradient and the tint multiplies it, so feeding the
    selection colour in raw would just darken the slot. Normalise it to full
    brightness first, then lift it a little towards white - with the default
    green (0.30, 0.72, 0.38) that lands on (0.50, 1.00, 0.60), which is the
    hand-tuned tint this used to carry as a literal.
]]
local function slotTint(c)
    local mx = math.max(c.r, c.g, c.b)
    if mx <= 0 then return 0.5, 0.5, 0.5 end
    local k = 0.14
    return c.r / mx + (1 - c.r / mx) * k,
           c.g / mx + (1 - c.g / mx) * k,
           c.b / mx + (1 - c.b / mx) * k
end

-- Smooth gradient slot background for avatar tiles (replaces the banded look).
local GRAD = { EMB .. "Panel/SlotGradient.png" }
function S.drawSlotGradient(el, x, y, w, h, selected)
    local t = TEX(GRAD)
    if t then
        if selected then
            local r, g, b = slotTint(S.color.selection)
            el:drawTextureScaled(t, x, y, w, h, 1, r, g, b)
        else
            el:drawTextureScaled(t, x, y, w, h, 1, 1, 1, 1)
        end
    else
        if selected then
            local c = S.color.selection
            el:drawRect(x, y, w, h, 1, 0.10 + c.r * 0.10, 0.11 + c.g * 0.13, 0.12 + c.b * 0.06)
        else
            el:drawRect(x, y, w, h, 1, 0.10, 0.11, 0.12)
        end
    end
end

--[[ Style a vanilla ISComboBox to match NeatUI: rounded 3-patch pill body,
    accent arrow, accent row highlight in the drop-down.

    The earlier version drew a pill *underneath* the vanilla combo with its
    colours zeroed out. That worked for the closed state but cost the drop-down:
    ISComboBoxPopup colours its selected row from parentCombo.backgroundColorMouseOver,
    so zeroing that field to hide the closed-state hover fill also flattened the
    highlight in the list. Owning prerender outright frees that field to be the
    accent, which is where it belongs.

    What is NOT touched: the popup itself. ISComboBox.SharedPopup is one instance
    shared by every combo box in the game, so restyling it would follow the player
    into other mods' menus. The per-combo fields below reach it safely; its
    background stays vanilla.
]]
function S.styleComboBox(combo)
    if not combo then return end

    -- Read by ISComboBoxPopup for the highlighted row and its text.
    combo.backgroundColorMouseOver = { r = S.color.accent.r, g = S.color.accent.g,
                                       b = S.color.accent.b, a = 0.85 }
    combo.textColor                = { r = 0.92, g = 0.92, b = 0.92, a = 1.0 }
    combo.backgroundColor          = { r = 0.16, g = 0.16, b = 0.17, a = 0.0 }
    combo.borderColor              = { r = 0.42, g = 0.42, b = 0.44, a = 0.0 }

    if combo._ihmNeatPill then return end
    combo._ihmNeatPill = true

    combo.prerender = function(c)
        if not c.disabled then
            c.fade:setFadeIn(c.joypadFocused or c:isMouseOver())
            c.fade:update()
        end

        local lit = c.expanded or c.joypadFocused or c:isMouseOver()
        local r, g, b = 0.16, 0.16, 0.17
        if lit then r, g, b = 0.26, 0.26, 0.28 end
        if c.disabled then r, g, b = 0.13, 0.13, 0.14 end

        if not draw3PatchH(c, 0, 0, c.width, c.height, 0.95, r, g, b) then
            c:drawRect(0, 0, c.width, c.height, 0.95, r, g, b)
        end

        local arrowW = c.image and c.image:getWidthOrig() or 0
        local textW  = c.width - arrowW - 16

        local text = nil
        if c.options[c.selected] then text = c:getOptionText(c.selected)
        elseif c.noSelectionText then text = c.noSelectionText end

        if text and textW > 0 then
            local fh = getTextManager():getFontHeight(c.font)
            local ty = math.floor((c.height - fh) / 2)
            local tr, tg, tb = 0.92, 0.92, 0.92
            if c.disabled then tr, tg, tb = 0.55, 0.55, 0.55 end
            local sx, sy, sw, sh = c:clampStencilRectToParent(0, 0, textW, c.height)
            c:drawText(text, 10, ty, tr, tg, tb, 1, c.font)
            c:clearStencilRect()
            if c.doRepaintStencil then c:repaintStencilRect(sx, sy, sw, sh) end
        end

        -- The arrow is the one place the accent belongs on a closed combo: it is
        -- the affordance, and it lines the widget up with the Neat buttons.
        if c.image then
            local ar, ag, ab = 0.72, 0.72, 0.74
            if c.disabled then ar, ag, ab = 0.45, 0.45, 0.45
            elseif lit then ar, ag, ab = S.color.accent.r, S.color.accent.g, S.color.accent.b end
            c:drawTexture(c.image, c.width - arrowW - 6,
                math.floor((c.height - c.image:getHeight()) / 2), 1, ar, ag, ab)
        end
    end
end
return S
