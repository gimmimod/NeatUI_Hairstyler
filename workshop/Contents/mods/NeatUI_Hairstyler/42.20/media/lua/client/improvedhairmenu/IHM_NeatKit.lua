--[[
    IHM_NeatKit.lua

    Faithful reproduction of Neat Rocco's window recipe (NR_BaseCW + NR_Header),
    self-contained inside this mod. Used to make the in-game hair window look like
    a native NeatUI / Neat Rocco panel: MainTitle_BG header with icon + title +
    framework close button, MainPanelBG_FlatTop rounded body.

    Requires NeatUI_Framework (for NI_SquareButton + the shared 9-patch textures);
    degrades to a styled ISButton if the widget is missing.
]]
if isServer() then return end
require "ISUI/ISButton"
pcall(require, "improvedhairmenu/IHM_NeatStyle")

local ok_sb, NI_SquareButton = pcall(require, "NeatUI_Framework/UI/NI_SquareButton")
if not ok_sb or not NI_SquareButton then NI_SquareButton = rawget(_G, "NI_SquareButton") end

local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local FONT_HGT_SMALL  = getTextManager():getFontHeight(UIFont.Small)

IHM_NeatKit = IHM_NeatKit or {}
IHM_NeatKit.headerHeight = math.floor(FONT_HGT_MEDIUM * 1.5)
IHM_NeatKit.padding      = math.max(3, math.floor(FONT_HGT_SMALL * 0.4))
IHM_NeatKit.buttonSize   = math.floor(FONT_HGT_MEDIUM)

local function iconFalse()
    local t = getTexture("media/ui/NeatUI/ICON/Icon_False.png")
    if t then return t end
    return getTexture("media/ui/IHMNeat/Icon/Icon_False.png")
end

-- ===========================================================================
-- IHM_NeatHeader : NeatUI header (icon + title + close), draggable.
-- Derived from ISTableLayout, mirroring Neat Rocco's NR_Header.
-- Parent-window contract: getWindowTitle(), close(); optional getWindowIcon().
-- ===========================================================================
IHM_NeatHeader = ISTableLayout:derive("IHM_NeatHeader")

function IHM_NeatHeader:new(x, y, width, height, parentWindow)
    local o = ISTableLayout:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.parentWindow = parentWindow
    o.padding      = IHM_NeatKit.padding
    o.buttonSize   = IHM_NeatKit.buttonSize
    o.iconSize     = math.floor((height * 0.8) / 4) * 4
    o.moving       = false
    o.closeIcon    = iconFalse()
    return o
end

function IHM_NeatHeader:initialise()
    ISTableLayout.initialise(self)
end

function IHM_NeatHeader:createChildren()
    self:addRowFill(nil)

    -- Column 0 : icon + title
    self._iconTitleCol = 0
    local titleStr   = self.parentWindow.getWindowTitle and self.parentWindow:getWindowTitle() or ""
    local titleWidth = getTextManager():MeasureStringX(UIFont.Medium, titleStr)
    local hasIcon    = self.parentWindow.getWindowIcon ~= nil and self.parentWindow:getWindowIcon() ~= nil
    local iconW      = hasIcon and (self.iconSize + self.padding) or 0
    local iconTitleColumn = self:addColumn(nil)
    iconTitleColumn.minimumWidth = iconW + titleWidth + self.padding * 2

    -- Columns 1-2 : fill (push the close button to the right)
    self:addColumnFill(nil)
    self:addColumnFill(nil)

    -- Column 3 : close button panel
    local rightColumn = self:addColumn(nil)
    rightColumn.minimumWidth = self.buttonSize + self.padding
    self:createRightButtonPanel()
    self:setElement(3, 0, self.rightButtonPanel)
end

function IHM_NeatHeader:createRightButtonPanel()
    local bsz = self.buttonSize
    local pad = self.padding

    self.rightButtonPanel = ISPanel:new(0, 0, bsz + pad, self.height)
    self.rightButtonPanel:noBackground()
    self.rightButtonPanel:initialise()

    local buttonY = math.floor((self.height - bsz) / 2)

    if NI_SquareButton then
        self.closeButton = NI_SquareButton:new(0, buttonY, bsz, self.closeIcon, self,
            function() self.parentWindow:close() end)
        self.closeButton:initialise()
        self.closeButton:setActive(true)
        self.closeButton:setActiveColor(0.8, 0.2, 0.2)
    else
        self.closeButton = ISButton:new(0, buttonY, bsz, bsz, "", self,
            function() self.parentWindow:close() end)
        self.closeButton:initialise()
        self.closeButton:instantiate()
        if self.closeIcon then self.closeButton:setImage(self.closeIcon) end
        local NS = rawget(_G, "IHM_NeatStyle")
        if NS and NS.styleSquareButton then NS.styleSquareButton(self.closeButton, { r = 0.8, g = 0.2, b = 0.2 }) end
    end
    self.rightButtonPanel:addChild(self.closeButton)
end

function IHM_NeatHeader:prerender()
    local NS = rawget(_G, "IHM_NeatStyle")
    if NS and NS.drawHeader then
        NS.drawHeader(self, 0, 0, self.width, self.height)
    else
        self:drawRect(0, 0, self.width, self.height, 1, 0.07, 0.07, 0.08)
        self:drawRect(0, self.height - 1, self.width, 2, 1, 0, 0, 0)
    end
end

function IHM_NeatHeader:render()
    local cell = self:cell(self._iconTitleCol or 0, 0)
    if not cell then return end
    local pad   = self.padding
    local icon  = self.parentWindow.getWindowIcon and self.parentWindow:getWindowIcon() or nil
    local title = self.parentWindow.getWindowTitle and self.parentWindow:getWindowTitle() or ""
    local textY = cell.y + (cell.height - FONT_HGT_MEDIUM) / 2
    if icon then
        local iconY = cell.y + (cell.height - self.iconSize) / 2
        self:drawTextureScaled(icon, cell.x + pad, iconY, self.iconSize, self.iconSize, 1, 1, 1, 1)
        self:drawText(title, cell.x + pad + self.iconSize + pad, textY, 1, 1, 1, 1, UIFont.Medium)
    else
        self:drawText(title, cell.x + pad, textY, 1, 1, 1, 1, UIFont.Medium)
    end
end

-- Size/position clamp, same pattern as NR_Header / NC_CraftHeader.
local function clampWindowSizeAndPos(win, factor)
    if not win or not getCore then return end
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    if not sw or not sh then return end

    local w = win.width or (win.getWidth and win:getWidth()) or 0
    local h = win.height or (win.getHeight and win:getHeight()) or 0

    local changed = false
    local targetW, targetH = w, h
    if w > sw then targetW = math.floor(sw * factor); changed = true end
    if h > sh then targetH = math.floor(sh * factor); changed = true end
    if changed then
        if win.calculateLayout then
            win:calculateLayout(targetW, targetH)
        else
            if win.setWidth  then win:setWidth(targetW)  end
            if win.setHeight then win:setHeight(targetH) end
        end
    end

    local curW = win.width or targetW
    local curH = win.height or targetH
    local newX = win.x or 0
    local newY = win.y or 0
    if newX < 0 then newX = 0 end
    if newY < 0 then newY = 0 end
    if (newX + curW) > sw then newX = math.max(0, sw - curW) end
    if (newY + curH) > sh then newY = math.max(0, sh - curH) end
    if newX ~= (win.x or 0) then
        if win.setX then win:setX(newX) else win.x = newX end
    end
    if newY ~= (win.y or 0) then
        if win.setY then win:setY(newY) else win.y = newY end
    end
end

-- Drag the parent window by the header (like NR_Header).
function IHM_NeatHeader:onMouseDown(x, y)
    self.moving = true
    self:setCapture(true)
    return true
end

function IHM_NeatHeader:onMouseMove(dx, dy)
    if self.moving and self.parentWindow then
        self.parentWindow:setX(self.parentWindow.x + dx)
        self.parentWindow:setY(self.parentWindow.y + dy)
        clampWindowSizeAndPos(self.parentWindow, 0.90)
        return true
    end
    return false
end

function IHM_NeatHeader:onMouseMoveOutside(dx, dy)
    if self.moving and self.parentWindow then
        self.parentWindow:setX(self.parentWindow.x + dx)
        self.parentWindow:setY(self.parentWindow.y + dy)
        clampWindowSizeAndPos(self.parentWindow, 0.90)
        return true
    end
    return false
end

function IHM_NeatHeader:onMouseUp(x, y)
    if self.moving then self.moving = false; self:setCapture(false); return true end
    return false
end

function IHM_NeatHeader:onMouseUpOutside(x, y)
    if self.moving then self.moving = false; self:setCapture(false); return true end
    return false
end

-- ===========================================================================
-- Window helpers (mirror NR_BaseCW)
-- ===========================================================================

-- Hide vanilla title-bar buttons and attach a NeatUI header. Stored on panel.neatHeader.
function IHM_NeatKit.attachHeader(panel)
    local hh = IHM_NeatKit.headerHeight
    if panel.closeButton    and panel.closeButton.setVisible    then panel.closeButton:setVisible(false)    end
    if panel.collapseButton and panel.collapseButton.setVisible then panel.collapseButton:setVisible(false) end
    if panel.infoButton     and panel.infoButton.setVisible     then panel.infoButton:setVisible(false)     end
    if panel.resizeWidget   and panel.resizeWidget.setVisible   then panel.resizeWidget:setVisible(false)   end

    panel.neatHeader = IHM_NeatHeader:new(0, 0, panel.width, hh, panel)
    panel.neatHeader:initialise()
    panel:addChild(panel.neatHeader)
    if panel.neatHeader.calculateLayout then
        panel.neatHeader:calculateLayout(panel.width, hh)
    end
    return panel.neatHeader
end

-- Draw the NeatUI rounded body below the header.
function IHM_NeatKit.prerenderBody(panel)
    local NS = rawget(_G, "IHM_NeatStyle")
    local hh = IHM_NeatKit.headerHeight
    if NS and NS.drawBody then
        NS.drawBody(panel, 0, hh, panel.width, panel.height - hh)
    else
        panel:drawRect(0, hh, panel.width, panel.height - hh, 1, 0.13, 0.13, 0.14)
    end
end

return IHM_NeatKit
