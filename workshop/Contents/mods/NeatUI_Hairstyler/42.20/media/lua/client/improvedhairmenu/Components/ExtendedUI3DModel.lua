--[[
	This is a UI element that extends ISUI3DModel with click detection
]]
if isServer() then return end
require("improvedhairmenu/ModCompatibility/ReorganizedInfoScreen.lua")
require("ISUI/ISUI3DModel")
local base = ISUI3DModel

ImprovedHairMenu = ImprovedHairMenu or {}
ImprovedHairMenu.UI3DModelExt = ImprovedHairMenu.UI3DModelExt or base:derive("IHM_UI3DModelExt")

local UI3D = ImprovedHairMenu.UI3DModelExt

function UI3D:new(x, y, width, height)
    local o = base.new(self, x, y, width, height)
    o.hasDragged = false
    o.onSelect = nil
    o.selectable = true
    return o
end

local texture_avatar_background = getTexture("media/ui/avatarBackground.png")
function UI3D:prerender()
    base.prerender(self)
    if texture_avatar_background then
        self:drawTextureScaled(texture_avatar_background, 0, 0, self.width, self.height, 1, 1, 1, 1)
    end
end

--[[ Drag to turn the model.

    UI3DModel only exposes setDirection(IsoDirections) - eight isometric facings.
    The engine does have a continuous AnimatedModel.setAngle(Vector2), and
    setDirection calls it internally, but UI3DModel.animatedModel is private final
    so Lua can never reach it. Genuinely smooth rotation is therefore off the table;
    what we can fix is how the eight steps feel.

    Vanilla ISUI3DModel needs 40 pixels of travel per step, which on a 64px tile
    means dragging most of the way across it for a single 45 degree turn. Here the
    step is a fraction of the tile instead, and the accumulator loops, so one
    sweep across a tile turns the character most of the way round.

    CLICK_SLOP keeps a click a click: the tile only stops counting as a selection
    once the cursor has actually travelled a few pixels.
]]
local CLICK_SLOP = 4

local function IHM_bool(key, default)
    local LC = rawget(_G, "IHM_LiveConfig")
    if LC and LC.getBool then return LC:getBool(key, default) end
    local S = ImprovedHairMenu and ImprovedHairMenu.settings
    if S and S[key] ~= nil then return S[key] and true or false end
    return default
end

local function IHM_rotateEnabled() return IHM_bool("drag_rotate", true) end
local function IHM_rotateAll()     return IHM_bool("rotate_all", false) end

-- Push our facing onto every other tile in the same grid, and remember it so
-- avatars built later (new page, rebuilt panel) come up already turned.
local function IHM_syncSiblings(self)
    local dir = self:getDirection()
    _G.ImprovedHairMenu = _G.ImprovedHairMenu or {}
    ImprovedHairMenu.sharedDir = dir

    local panel = self.parent
    if not panel or not panel.avatarList then return end
    for _, av in ipairs(panel.avatarList) do
        if av ~= self and av.setDirection and av.javaObject then
            pcall(function() av:setDirection(dir) end)
        end
    end
end

function UI3D:onMouseDown(x, y)
    self.mouseDown = true
    self.dragX = 0
    self.dragTravel = 0
    self.hasDragged = false
    self:setCapture(true)
    return true
end

function UI3D:rotateStep(dx)
    self.dragTravel = (self.dragTravel or 0) + math.abs(dx)
    if self.dragTravel > CLICK_SLOP then
        self.hasDragged = true
    end

    if not IHM_rotateEnabled() then return end

    local step = math.max(6, math.floor((self.width or 64) * 0.14))
    self.dragX = (self.dragX or 0) + dx

    -- while, not if: a fast drag can cross several steps in one event
    local turned = false
    while math.abs(self.dragX) >= step do
        local dir = self:getDirection()
        dir = IsoDirectionSet.rotate(dir, (self.dragX < 0) and -1 or 1)
        self:setDirection(dir)
        self.dragX = self.dragX + ((self.dragX < 0) and step or -step)
        turned = true
    end

    if turned and IHM_rotateAll() then IHM_syncSiblings(self) end
end

function UI3D:onMouseMove(dx, dy)
    if self.mouseDown then self:rotateStep(dx) end
end

function UI3D:onMouseMoveOutside(dx, dy)
    -- setCapture keeps events coming once the cursor leaves the tile mid-drag.
    if self.mouseDown then self:rotateStep(dx) end
end

function UI3D:endDrag()
    local wasClick = self.mouseDown and self.hasDragged == false
    self.mouseDown = false
    self.dragX = 0
    self.dragTravel = 0
    self.hasDragged = false
    self:setCapture(false)
    return wasClick
end

function UI3D:onMouseUp(x, y)
    if self:endDrag() then self:select() end
    return true
end

function UI3D:onMouseUpOutside(x, y)
    if self:endDrag() then self:select() end
    return true
end

function UI3D:select()
    if self.selectable and self.onSelect then
        self.onSelect(self)
    end
end

-- Optional legacy alias (do not overwrite if another mod already defines it)
if rawget(_G, "ISUI3DModelExt") == nil then
    ISUI3DModelExt = UI3D
end