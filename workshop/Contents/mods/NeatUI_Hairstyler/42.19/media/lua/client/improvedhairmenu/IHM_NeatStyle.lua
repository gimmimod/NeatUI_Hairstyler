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
    -- Gli stessi valori delle tinte 9-patch (0.08 / 0.15).
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
    slotBorder = { r = 0.34, g = 0.34, b = 0.36 },
    close      = { r = 0.80, g = 0.20, b = 0.20 },
}

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
    -- La riga nera sotto l intestazione, come in Equipment: prima c era solo
    -- nel ripiego, quindi la finestra vera ne restava senza.
    el:drawRect(x, y + h - 1, w, 1, 1, 0, 0, 0)
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

function S.styleSwatchButton(btn)
    if not btn then return end
    if btn.setBorderRGBA then btn:setBorderRGBA(0.4, 0.4, 0.4, 0.9) end
    btn:setDisplayBackground(true)
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

-- Smooth gradient slot background for avatar tiles (replaces the banded look).
local GRAD = { EMB .. "Panel/SlotGradient.png" }
function S.drawSlotGradient(el, x, y, w, h, selected)
    local t = TEX(GRAD)
    if t then
        if selected then
            el:drawTextureScaled(t, x, y, w, h, 1, 0.50, 1.0, 0.62)   -- green-tinted
        else
            el:drawTextureScaled(t, x, y, w, h, 1, 1, 1, 1)
        end
    else
        if selected then el:drawRect(x, y, w, h, 1, 0.12, 0.20, 0.14)
        else             el:drawRect(x, y, w, h, 1, 0.10, 0.11, 0.12) end
    end
end

-- Style a vanilla ISComboBox to match NeatUI: rounded 3-patch pill body.
-- Zero-risk approach: the vanilla rect+border are made invisible (alpha 0) and
-- the pill is drawn underneath by chaining prerender, so the combo's own
-- text/arrow/popup keep working untouched.
function S.styleComboBox(combo)
    if not combo then return end
    combo.backgroundColor          = { r = 0.16, g = 0.16, b = 0.17, a = 0.0 }
    combo.backgroundColorMouseOver = { r = 0.22, g = 0.22, b = 0.23, a = 0.0 }
    combo.borderColor              = { r = 0.42, g = 0.42, b = 0.44, a = 0.0 }
    if combo._ihmNeatPill then return end
    combo._ihmNeatPill = true
    local basePrerender = combo.prerender
    combo.prerender = function(c)
        local r, g, b = 0.16, 0.16, 0.17
        if c:isMouseOver() then r, g, b = 0.22, 0.22, 0.23 end
        if not draw3PatchH(c, 0, 0, c.width, c.height, 0.95, r, g, b) then
            c:drawRect(0, 0, c.width, c.height, 0.95, r, g, b)
        end
        if basePrerender then basePrerender(c) end
    end
end
return S
