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

function UI3D:onMouseMove(dx, dy)
    if self.mouseDown and math.abs(self.dragX + dx) > 40 then
        self.hasDragged = true
    end
    base.onMouseMove(self, dx, dy)
end

function UI3D:onMouseUp(x, y)
    if self.mouseDown and self.hasDragged == false then
        self:select()
    end
    self.hasDragged = false
    base.onMouseUp(self, x, y)
end

function UI3D:onMouseUpOutside(x, y)
    if self.mouseDown and self.hasDragged == false then
        self:select()
    end
    self.hasDragged = false
    base.onMouseUpOutside(self, x, y)
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