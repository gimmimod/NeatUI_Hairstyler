--[[
    IHM_NeatTooltip.lua

    The floating style-name label, shown while the pointer sits on a preview.
    Off by default: the name lives in the panel header, and this is the opt-in
    alternative behind CONTROLS > "Show name on hover".

    One shared panel rather than one per avatar - a grid can hold sixty tiles and
    only ever one of them is hovered.

    Lifetime is a lease, not a pairing. VisualAvatar:render re-asserts show() on
    every frame it is the hovered tile, and the panel retires itself when nobody
    has renewed for a couple of frames. That is what keeps it from surviving the
    thing it belongs to: picking a hairstyle tears the whole grid down mid-hover,
    so there is no hideTooltip() call left to make - which is exactly how 1.3.0
    ended up leaving a name stranded on screen.
]]
if isServer() then return end
require "ISUI/ISPanel"
pcall(require, "improvedhairmenu/IHM_NeatStyle")

IHM_NeatTooltip = IHM_NeatTooltip or {}

local FONT      = UIFont.Small
local PAD_X     = 8
local PAD_Y     = 4
local GAP       = 6      -- distance from the tile edge
local LEASE     = 2      -- frames a show() is good for

local function NS() return rawget(_G, "IHM_NeatStyle") end

local Panel = ISPanel:derive("IHM_NeatTooltipPanel")

function Panel:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.text = ""
    o.lease = 0
    return o
end

function Panel:prerender()
    -- Nobody renewed the lease: the grid is gone, or the cursor left it.
    self.lease = self.lease - 1
    if self.lease <= 0 then
        IHM_NeatTooltip.hide()
        return
    end

    local S = NS()
    if S and S.drawBody then
        S.drawBody(self, 0, 0, self.width, self.height)
    else
        self:drawRect(0, 0, self.width, self.height, 0.95, 0.13, 0.13, 0.14)
        self:drawRectBorder(0, 0, self.width, self.height, 1, 0.30, 0.30, 0.32)
    end

    local fh = getTextManager():getFontHeight(FONT)
    self:drawTextCentre(self.text, math.floor(self.width / 2),
        math.floor((self.height - fh) / 2), 0.92, 0.92, 0.92, 1, FONT)
end

function Panel:render() end

local _panel = nil

--[[ absX/absY/tileW/tileH describe the hovered tile in screen space.

    The label is centred under the tile and flips above it near the bottom edge,
    then is clamped horizontally - a tile in the last column would otherwise push
    half the name off screen.
]]
function IHM_NeatTooltip.show(text, absX, absY, tileW, tileH)
    text = tostring(text or "")
    if text == "" then return IHM_NeatTooltip.hide() end

    local tm = getTextManager()
    local fh = tm:getFontHeight(FONT)
    local w  = tm:MeasureStringX(FONT, text) + PAD_X * 2
    local h  = fh + PAD_Y * 2

    if not _panel then
        _panel = Panel:new(0, 0, w, h)
        _panel:initialise()
        _panel:instantiate()
    end

    _panel.text  = text
    _panel.lease = LEASE
    _panel:setWidth(w)
    _panel:setHeight(h)

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()

    local x = absX + math.floor((tileW - w) / 2)
    if x < 2 then x = 2 end
    if x + w > sw - 2 then x = sw - 2 - w end

    local y = absY + tileH + GAP
    if y + h > sh - 2 then y = absY - h - GAP end
    if y < 2 then y = 2 end

    _panel:setX(x)
    _panel:setY(y)

    if not _panel:getIsVisible() then
        _panel:setVisible(true)
        _panel:addToUIManager()
    end
    _panel:setAlwaysOnTop(true)
    _panel:bringToTop()
end

function IHM_NeatTooltip.hide()
    if not _panel then return end
    _panel.lease = 0
    if _panel:getIsVisible() then
        _panel:setVisible(false)
        _panel:removeFromUIManager()
    end
end

return IHM_NeatTooltip
