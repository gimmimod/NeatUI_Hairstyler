--[[
	This is the actual menu element.

	By being a separate UI element it can be implemented in both the character creation menu and in-game hair options.
]]
if isServer() then return end
require "ISUI/ISComboBox"
pcall(require, "improvedhairmenu/IHM_HairSourceFilter")
pcall(require, "improvedhairmenu/IHM_NeatStyle")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local function _IHM_clipToWidth(font, s, maxw)
    if not s or s == "" then return "" end
    local tm = getTextManager()
    if tm:MeasureStringX(font, s) <= maxw then return s end
    local ell  = "..."
    local ellW = tm:MeasureStringX(font, ell)
    local res  = s
    while #res > 0 and (tm:MeasureStringX(font, res) + ellW) > maxw do
        res = string.sub(res, 1, #res - 1)
    end
    return res .. ell
end

local header_height = FONT_HGT_SMALL + 14

local function predicateAvatarIsSelectable(avatar)
	return avatar and avatar.selectable == true
end

local base = ISPanelJoypad
HairMenuPanel = base:derive("HairMenuPanel")

local function IHM_HMP_smallFontHgt()
    return getTextManager():getFontHeight(UIFont.Small)
end

local function IHM_HMP_headerHeight()
    local smallH = IHM_HMP_smallFontHgt()
    return math.max(smallH + 14, 28)
end

local function IHM_HMP_navButtonSize()
    local smallH = IHM_HMP_smallFontHgt()
    return math.max(18, smallH + 4)
end

local function IHM_HMP_headerPad()
    local smallH = IHM_HMP_smallFontHgt()
    return math.max(5, math.floor(smallH * 0.4))
end

local function IHM_HMP_getSourceFilter()
    return rawget(_G, "IHM_HairSourceFilter")
end

local function IHM_HMP_rightControlWidth(panel)
    if not panel then return 0 end

    local smallH = IHM_HMP_smallFontHgt()
    local gap = math.max(6, math.floor(smallH * 0.35))
    local width = 0

    local ctrl = panel.hairControlsBtn or panel.beardControlsBtn

    if panel.hairColorBtn then
        width = width + panel.hairColorBtn:getWidth() + gap
    end

    if panel.stubbleTickBox then
        width = width + panel.stubbleTickBox:getWidth() + gap
    end

    if ctrl then
        width = width + ctrl:getWidth() + gap
    end

    return width
end

local function IHM_HMP_getHeaderRightLimit(panel)
    if not panel then return 0 end

    local smallH = IHM_HMP_smallFontHgt()
    local pad = IHM_HMP_headerPad()
    local gap = math.max(6, math.floor(smallH * 0.35))
    local panelW = panel:getWidth()
    local minControlX = nil

    local function considerControl(ctrl, parentRelative)
        if not ctrl then return end
        if ctrl.getIsVisible and not ctrl:getIsVisible() then return end
        if not ctrl.getX or not ctrl.getWidth then return end

        local x = ctrl:getX()

        -- In-game Controls button lives on the parent window, not inside HairMenuPanel.
        if parentRelative then
            x = x - panel:getX()
        end

        if x and x > pad and x < panelW then
            if not minControlX or x < minControlX then
                minControlX = x
            end
        end
    end

    -- Character creation controls are inside the panel.
    considerControl(panel.hairColorBtn, false)
    considerControl(panel.stubbleTickBox, false)
    considerControl(panel.hairControlsBtn or panel.beardControlsBtn, false)

    -- In-game Controls button is outside the panel, on the parent window.
    if panel.parent then
        considerControl(panel.parent._controlsBtn, true)
    end

    if minControlX then
        return math.max(pad, minControlX - gap)
    end

    -- Fallback for early layout before the controls have valid positions.
    local rightW = IHM_HMP_rightControlWidth(panel)
    if rightW > 0 then
        return math.max(pad, panelW - pad - rightW)
    end

    return panelW - pad
end

-- NeatUI-styled background: rounded header bar + flat-top body panel.
-- NeatUI-styled background: rounded header bar + flat-top body panel.
-- The grid is skinned in both character creation and in-game; only the
-- character-creation launcher buttons stay vanilla.
function HairMenuPanel:prerender()
    if self.ihmEmbedded then return end
    local NS = rawget(_G, "IHM_NeatStyle")
    local hh = self.headerHeight or IHM_HMP_headerHeight()
    if NS and NS.drawBody then
        NS.drawBody(self, 0, hh, self.width, self.height - hh)
        NS.drawHeader(self, 0, 0, self.width, hh)
    else
        self:drawRect(0, hh, self.width, self.height - hh, 1, 0.13, 0.13, 0.14)
        self:drawRect(0, 0, self.width, hh, 1, 0.07, 0.07, 0.08)
        self:drawRect(0, hh - 1, self.width, 2, 1, 0, 0, 0)
        self:drawRectBorder(0, 0, self.width, self.height, 1, 0.30, 0.30, 0.32)
    end
end

function HairMenuPanel:render()
    ISPanelJoypad.render(self)

    if self.layoutSourceFilterCombo then
        self:layoutSourceFilterCombo()
    end

    if not self.pageLeftButton or not self.pageRightButton then
        return
    end

    local tm = getTextManager()
    local font = UIFont.Small
    local smallH = tm:getFontHeight(font)
    local textY = self.pageLeftButton:getY() + math.floor((self.pageLeftButton:getHeight() - smallH) / 2)
    local xLeft = self.pageRightButton:getRight() + math.max(6, math.floor(self.pageRightButton:getWidth() / 3))

    local pages = tostring(self.pageCurrent) .. "/" .. tostring(self:getNumberOfPages())
    self:drawText(pages, xLeft, textY, 0.9, 0.9, 0.9, 0.9, font)
    xLeft = xLeft + tm:MeasureStringX(font, pages) + math.max(10, math.floor(smallH * 0.75))

    local gap = math.max(6, math.floor(smallH * 0.35))
	local xRightLimit = IHM_HMP_getHeaderRightLimit(self)

    if self.sourceFilterCombo and self.sourceFilterCombo:getIsVisible() then
        xRightLimit = math.min(xRightLimit, self.sourceFilterCombo:getX() - gap)
    end

    local maxTitleW = math.max(0, xRightLimit - xLeft)

    local titleInfo = self.selectedHairInfo

    if self.joypadCursor and self.avatarList and self.avatarList[self.joypadCursor] and self.avatarList[self.joypadCursor].selectable then
        local hoveredInfo = self.avatarList[self.joypadCursor].visualItem
        if type(hoveredInfo) == "table" and hoveredInfo.display then
            titleInfo = hoveredInfo
        end
    end

    if self.showSelectedName and titleInfo and type(titleInfo) == "table" then
        local title = _IHM_clipToWidth(font, titleInfo.display or "", maxTitleW)
        self:drawText(title, xLeft, textY, 0.9, 0.9, 0.9, 0.9, font)
    end
end

function HairMenuPanel:new(x, y, size_x, size_y, rows, cols, gap, isBeard)
    size_x = size_x or 96
    size_y = size_y or 96
    rows   = rows or 2
    cols   = cols or 4
    gap    = gap or 3

    local headerH = IHM_HMP_headerHeight()
    local o = base.new(self, x, y, (size_x * cols) + (gap * (cols - 1)), (size_y * rows) + (gap * (rows - 1)) + headerH)

    o.isHairMenu = true
    o.gridSizeX = size_x
    o.gridSizeY = size_y
    o.gridRows = rows
    o.gridCols = cols
    o.pageSize = rows * cols
    o.gap = gap
    o.avatarList = {}
    o.info = {}
    o.allInfo = {}
    o.pageCurrent = 1
    o.onSelect = nil
    o.isBeard = isBeard
    o.showSelectedName = true
    o.joypadCursor = 1
    o.selectedHairInfo = { id = "", display = "" }
    o.headerHeight = headerH

    o.sourceFilterCombo = nil
    o.sourceFilterId = nil
    o.sourceFilterOptions = {}
    o.ihmEmbedded = false

    return o
end

function HairMenuPanel:initialise()
    local pageBtnSize = IHM_HMP_navButtonSize()
    local headerPad = IHM_HMP_headerPad()
    local headerH = math.max(IHM_HMP_headerHeight(), pageBtnSize + headerPad * 2)
    local arrowGap = math.max(5, math.floor(pageBtnSize / 3))

    self.headerHeight = headerH
    self.offset_x = 0
    self.offset_y = headerH

    self.pageLeftButton = ISButton:new(5, headerPad, pageBtnSize, pageBtnSize, "", self, self.onChangePageButton)
    self.pageLeftButton.internal = "PREV"
    self.pageLeftButton:initialise()
    self.pageLeftButton:instantiate()
    self.pageLeftButton:setImage(getTexture("media/ui/IHMNeat/Icon/Icon_Arrow_L.png") or getTexture("media/ui/ArrowLeft.png"))
    self.pageLeftButton.forcedWidthImage = math.floor(pageBtnSize * 0.65)
    self.pageLeftButton.forcedHeightImage = math.floor(pageBtnSize * 0.65)
    self:addChild(self.pageLeftButton)

    self.pageRightButton = ISButton:new(self.pageLeftButton:getRight() + arrowGap, headerPad, pageBtnSize, pageBtnSize, "", self, self.onChangePageButton)
    self.pageRightButton.internal = "NEXT"
    self.pageRightButton:initialise()
    self.pageRightButton:instantiate()
    self.pageRightButton:setImage(getTexture("media/ui/IHMNeat/Icon/Icon_Arrow_R.png") or getTexture("media/ui/ArrowRight.png"))
    self.pageRightButton.forcedWidthImage = math.floor(pageBtnSize * 0.65)
    self.pageRightButton.forcedHeightImage = math.floor(pageBtnSize * 0.65)
    self:addChild(self.pageRightButton)

    do
        local NS = rawget(_G, "IHM_NeatStyle")
        if NS and NS.styleSquareButton then
            NS.styleSquareButton(self.pageLeftButton)
            NS.styleSquareButton(self.pageRightButton)
        end
    end

	self.sourceFilterCombo = ISComboBox:new(0, 0, 140, math.max(22, pageBtnSize), self, self.onSourceFilterChanged)
    self.sourceFilterCombo:initialise()
    self.sourceFilterCombo:instantiate()
    do local NS = rawget(_G, "IHM_NeatStyle"); if NS and NS.styleComboBox then NS.styleComboBox(self.sourceFilterCombo) end end
    self.sourceFilterCombo.font = UIFont.Small
    self.sourceFilterCombo:setVisible(false)
    self:addChild(self.sourceFilterCombo)

    for h = 1, self.gridRows do
        for v = 1, self.gridCols do
            local idx = ((h - 1) * self.gridCols) + v
            local x = ((v - 1) * self.gridSizeX) + (self.gap * (v - 1))
            local y = self.offset_y + ((h - 1) * self.gridSizeY) + (self.gap * (h - 1))
            local hairAvatar = HairAvatar:new(x, y, self.gridSizeX, self.gridSizeY)
            hairAvatar:initialise()
            hairAvatar:instantiate()
            hairAvatar:setVisible(true)
            hairAvatar.panelIndex = idx
            hairAvatar.onSelect = function(avatar)
                self:onAvatarSelect(avatar)
            end

            hairAvatar.onMouseMove = function(avatar, mx, my)
                HairAvatar.onMouseMove(avatar, mx, my)
                self:setCursor(avatar.panelIndex)
            end

            hairAvatar.onMouseMoveOutside = function(avatar, mx, my)
                HairAvatar.onMouseMoveOutside(avatar, mx, my)
                if self.joypadFocus then return end
                if self.joypadCursor == avatar.panelIndex then
                    self:setCursor(nil)
                end
            end

            self:addChild(hairAvatar)
            self.avatarList[idx] = hairAvatar
        end
    end

    self.offset_y = self.offset_y + (self.gridRows * self.gridSizeY) + (self.gap * (self.gridRows - 1))
    self:setHeight(self.offset_y)
end

function HairMenuPanel:layoutSourceFilterCombo()
    local combo = self.sourceFilterCombo
    if not combo or not combo:getIsVisible() then return end

    local smallH = IHM_HMP_smallFontHgt()
    local pad = IHM_HMP_headerPad()
    local gap = math.max(6, math.floor(smallH * 0.35))

    local rowY = pad
    local rowH = IHM_HMP_navButtonSize()

    if self.pageLeftButton then
        rowY = self.pageLeftButton:getY()
        rowH = self.pageLeftButton:getHeight()
    end

    local leftLimit = pad
    if self.pageRightButton then
        leftLimit = self.pageRightButton:getRight() + gap
    end

    local rightLimit = IHM_HMP_getHeaderRightLimit(self)
    local available = rightLimit - leftLimit

    -- Not enough clean header space. Better hide it than cover the Controls button.
    if available < 96 then
        combo:setVisible(false)
        return
    end

    local comboW = math.min(168, math.max(96, available))
    local comboH = math.max(22, rowH)

    combo:setWidth(math.floor(comboW))
    combo:setHeight(comboH)
    combo:setX(math.floor(rightLimit - comboW))
    combo:setY(rowY + math.floor((rowH - comboH) / 2))
end

function HairMenuPanel:setSourceFilterOptions(options, selectedFilterId)
    local combo = self.sourceFilterCombo
    if not combo then return end

    combo.options = {}
    combo.optionData = {}
    combo.selected = 0

    local optionCount = 0
    for _, option in ipairs(options or {}) do
        combo:addOptionWithData(option.display, option.id)
        optionCount = optionCount + 1
    end

    if optionCount <= 1 then
		combo:setVisible(false)
		return
	end

    combo:setVisible(true)

    if selectedFilterId then
        combo:selectData(selectedFilterId)
    end

    if combo.selected == 0 then
        combo.selected = 1
    end

    self:layoutSourceFilterCombo()
end

function HairMenuPanel:onSourceFilterChanged(combo)
    local sourceFilter = IHM_HMP_getSourceFilter()
    if not sourceFilter then return end

    local selectedId = nil
    if combo and combo.getOptionData then
        selectedId = combo:getOptionData(combo.selected)
    end

    self.sourceFilterId = selectedId or sourceFilter.getDefaultSourceFilterId()
    self.info = sourceFilter.filterEntriesBySource(self.allInfo or {}, self.sourceFilterId)

    if self.syncSelectedInfoFromVisual then
        self:syncSelectedInfoFromVisual()
    end

    self:showPage(1)
end

function HairMenuPanel:syncSelectedInfoFromVisual()
    local visual = nil

    if self.desc and self.desc.getHumanVisual then
        visual = self.desc:getHumanVisual()
    elseif self.char and self.char.getHumanVisual then
        visual = self.char:getHumanVisual()
    end

    if not visual then return end

    local getterName = self.isBeard and "getBeardModel" or "getHairModel"
    local getter = visual[getterName]
    if not getter then return end

    local ok, currentId = pcall(getter, visual)
    if not ok then return end

    local searchList = self.allInfo or self.info or {}
    for _, info in ipairs(searchList) do
        if info.id == currentId then
            self:setSelectedInfo(info)
            return
        end
    end
end

function HairMenuPanel:onAvatarSelect(hairAvatar)
	self:selectInfo(hairAvatar.visualItem)
end

-- Silently updates the hair info selection, avoiding triggering the `onSelect` callback which can cause infinite loops.
function HairMenuPanel:setSelectedInfo(hairInfo)
	-- XXX: This function has to allow for nil as beard menus might be initialized to nil if starting with a female character.
	if self.selectedHairInfo then self.selectedHairInfo.selected = false end
	self.selectedHairInfo = hairInfo
	if self.selectedHairInfo then self.selectedHairInfo.selected = true end
end

function HairMenuPanel:selectInfo(hairInfo)
	if type(hairInfo) == "number" then hairInfo = self.info[hairInfo] end
	if not hairInfo then print("HairMenuPanel:selectInfo(): info shouldn't be nil") return end
	self:setSelectedInfo(hairInfo)
	if self.onSelect then self.onSelect(hairInfo) end
end

function HairMenuPanel:setDesc(desc)
	for i=1,#self.avatarList do
		self.avatarList[i]:setDesc(desc)
	end
end

function HairMenuPanel:setChar(desc)
	for i=1,#self.avatarList do
		self.avatarList[i]:setChar(desc)
	end
end

function HairMenuPanel:applyVisual(desc)
	for i=1,#self.avatarList do
		self.avatarList[i]:applyVisual()
	end
end

function HairMenuPanel:setHairList(list)
    if type(list) ~= "table" then
        print("HairMenuPanel:setHairList() given a non-table value, ignoring and setting to blank table.")
        list = {}
    end

    local sourceFilter = IHM_HMP_getSourceFilter()

    if sourceFilter then
        sourceFilter.decorateEntries(list, self.isBeard)

        self.allInfo = list
        self.sourceFilterOptions = sourceFilter.getSourceFilterOptions(list)

        if not sourceFilter.hasSourceFilterOption(self.sourceFilterOptions, self.sourceFilterId) then
            self.sourceFilterId = sourceFilter.getDefaultSourceFilterId()
        end

        self.info = sourceFilter.filterEntriesBySource(self.allInfo, self.sourceFilterId)

        if self.setSourceFilterOptions then
            self:setSourceFilterOptions(self.sourceFilterOptions, self.sourceFilterId)
        end
    else
        self.allInfo = list
        self.info = list

        if self.sourceFilterCombo then
            self.sourceFilterCombo:setVisible(false)
        end
    end

    if self.syncSelectedInfoFromVisual then
        self:syncSelectedInfoFromVisual()
    end

    self:showPage(1)
end

-- #########
-- # Pages #
-- #########

function HairMenuPanel:onChangePageButton(button,x,y)
	if button.internal == "NEXT" then 
		self:changePage(1)
	elseif button.internal == "PREV" then 
		self:changePage(-1)
	end
end

function HairMenuPanel:getNumberOfPages()
    return math.max(1, math.ceil(#self.info / self.pageSize))
end

function HairMenuPanel:getCurrentPageSize()
	-- HACK: Only the last page has less than pageSize elements
	if self:getNumberOfPages() ~= self.pageCurrent then
		return self.pageSize
	else
		return #self.info % self.pageSize
	end
end

function HairMenuPanel:changePage(step)
	self:showPage(ImprovedHairMenu.math.wrap(self.pageCurrent + step, 1, self:getNumberOfPages()))
end

function HairMenuPanel:showPage(page_number)
	self.pageCurrent = page_number
	for i=1,self.pageSize do
		local info = self.info[((page_number-1) * self.pageSize) + i]
		if info then 
			self.avatarList[i].selectable = true
			self.avatarList[i]:setVisualItem(info)
			self.avatarList[i]:applyVisual()
			self.avatarList[i]:setVisible(true)
		else
			self.avatarList[i].selectable = false
			self.avatarList[i]:setVisible(false)
		end
	end

	if self.joypadFocus then
		self:makeCursorValid()
	else
		self:setCursor(nil)
	end
end

-- ##########
-- # Cursor #
-- ##########

function HairMenuPanel:getValidCursor(index)
	-- NOTE: index 1 will always be valid as the page wouldn't exist if there wasn't at least 1 element.
	local cursor = ImprovedHairMenu.math.clamp(index, 1, self.pageSize)
	if not self.avatarList[cursor].selectable == true then 
		for i=0,self.pageSize do
			local new_cursor = ImprovedHairMenu.math.wrap(cursor - i, 1, self.pageSize) -- NOTE: Move downwards as avatars are seqential.
			if self.avatarList[new_cursor].selectable == true then 
				cursor = new_cursor
				break
			end
		end
	end
	return cursor
end

function HairMenuPanel:setCursor(index)
	if self.joypadCursor then
		-- NOTE: Clear old cursor. this should avoid a double cursor as long as everyone uses this function.
		self.avatarList[self.joypadCursor]:setCursor(false)
	end

	if not index then
		self.joypadCursor = nil
		return
	end

	self.joypadCursor = self:getValidCursor(index)
	self.avatarList[self.joypadCursor]:setCursor(true)
end

function HairMenuPanel:makeCursorValid()
	self:setCursor(self:getValidCursor(self.joypadCursor))
end

--##################
--Controller Support
--##################

--[[ NOTE:
	We never actually get the joypad focus onto this element.
	Similar to how vanilla handles this (see `ISPanelJoypad`) we forward events from the panel to the element.
 ]]

function HairMenuPanel:ensureCursor()
	if not self.joypadCursor then
		self:setCursor(1)
	end
end

function HairMenuPanel:stepCursor(direction)
	self:ensureCursor()

	local direction = ImprovedHairMenu.math.sign(direction)

	-- NOTE: `stepCursor` is only called by joypad events we don't need any flags for joypad usage
	if direction ~= 0 then
		if self.joypadCursor + direction > self:getCurrentPageSize() then
			self:changePage(1)
			self:setCursor(1)
			return
		elseif self.joypadCursor + direction < 1 then
			self:changePage(-1)
			self:setCursor(self.pageSize)
			return
		end
	end

	self:setCursor(self.joypadCursor + direction)
end

-- Determines if the next joypad press should move outside the menu
function HairMenuPanel:isNextDownOutside()
	if not self.joypadCursor then
		return true
	end
	return not predicateAvatarIsSelectable(self.avatarList[self.joypadCursor + self.gridCols])
end

-- Determines if the next joypad press should move outside the menu
function HairMenuPanel:isNextUpOutside()
	if not self.joypadCursor then
		return true
	end
	return not predicateAvatarIsSelectable(self.avatarList[self.joypadCursor - self.gridCols])
end

function HairMenuPanel:setJoypadFocused(focused, joypadData)
	-- XXX: This function has to at least exist as vanilla calls it on any element that doesn't directly recieve focus
	self.joypadFocus = focused
	if focused then
		self:setCursor(1)
	else
		self:setCursor(nil)
	end
end

function HairMenuPanel:onJoypadDown(button, joypadData)
	if button == Joypad.RBumper then self:changePage(1) end
	if button == Joypad.LBumper then self:changePage(-1) end
	if button == Joypad.AButton then
		self:ensureCursor()
		if self.avatarList[self.joypadCursor] then self.avatarList[self.joypadCursor]:select() end
	end
	if button == Joypad.XButton then
		if self.stubbleTickBox then self.stubbleTickBox:forceClick() end
	end
	if button == Joypad.YButton then
		if self.hairColorBtn then self.hairColorBtn:forceClick() end
	end
end

function HairMenuPanel:onJoypadDirLeft(joypadData)  self:stepCursor(-1) end
function HairMenuPanel:onJoypadDirRight(joypadData) self:stepCursor(1)  end

function HairMenuPanel:onJoypadDirDown(joypadData)
	self:ensureCursor()
	local i = self.joypadCursor + self.gridCols
	if predicateAvatarIsSelectable(self.avatarList[i]) then
		self:setCursor(i)
	end
end

function HairMenuPanel:onJoypadDirUp(joypadData)
	self:ensureCursor()
	local i = self.joypadCursor - self.gridCols
	if predicateAvatarIsSelectable(self.avatarList[i]) then
		self:setCursor(i)
	end
end