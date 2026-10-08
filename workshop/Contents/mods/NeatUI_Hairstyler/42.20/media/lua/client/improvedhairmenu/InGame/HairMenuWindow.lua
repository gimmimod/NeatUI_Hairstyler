if isServer() then return end
require "improvedhairmenu/InGame/IHM_GridControls"
pcall(require, "improvedhairmenu/IHM_NeatStyle")
pcall(require, "improvedhairmenu/IHM_NeatKit")
local _ok = pcall(require, "improvedhairmenu/ModOptions")
HairMenuPanelWindow = ISCollapsableWindowJoypad:derive("HairMenuPanelWindow")

local function _IHM_getInGameLiveValue(primaryKey, legacyKey, defaultValue, minValue, maxValue)
    local function clampInt(v, lo, hi)
        v = tonumber(v)
        if not v then return nil end
        v = math.floor(v + 0.5)
        if v < lo then v = lo end
        if v > hi then v = hi end
        return v
    end

    local LC = rawget(_G, "IHM_LiveConfig")
    if LC and LC.load then
        pcall(function() LC:load() end)
    end

    if LC and LC.cache then
        local v = LC.cache[primaryKey]
        if v == nil and legacyKey then
            v = LC.cache[legacyKey]
        end
        v = clampInt(v, minValue, maxValue)
        if v ~= nil then
            return v
        end
    end

    local S = ImprovedHairMenu and ImprovedHairMenu.settings
    if S then
        local v = S[primaryKey]
        if v == nil and legacyKey then
            v = S[legacyKey]
        end
        v = clampInt(v, minValue, maxValue)
        if v ~= nil then
            return v
        end
    end

    return defaultValue
end

function HairMenuPanelWindow:new(x, y, width, height, playerNum, char, hairlist, isbeard)
	local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
	o.char = char
	o.hairList = hairlist
	o.onSelect = nil
	o.isbeard = isbeard
	o.playerNum = playerNum
	o.background = false
	o.drawFrame = false
	return o
end

function HairMenuPanelWindow:titleBarHeight()
	return (IHM_NeatKit and IHM_NeatKit.headerHeight) or ISCollapsableWindowJoypad.titleBarHeight(self)
end

function HairMenuPanelWindow:getWindowTitle()
	return self.title or ""
end

function HairMenuPanelWindow:getWindowIcon()
	local path = self.isbeard
		and "media/ui/IHMNeat/Icon/Icon_Razor.png"
		or  "media/ui/IHMNeat/Icon/Icon_Scissors.png"
	return getTexture(path)
end

-- NeatUI body (the NeatUI header child paints the MainTitle_BG title bar).
function HairMenuPanelWindow:prerender()
	if IHM_NeatKit and IHM_NeatKit.prerenderBody then
		IHM_NeatKit.prerenderBody(self)
	else
		local NS = rawget(_G, "IHM_NeatStyle")
		local th = self:titleBarHeight()
		if NS and NS.drawBody then
			NS.drawBody(self, 0, th, self.width, self.height - th)
		else
			self:drawRect(0, th, self.width, self.height - th, 1, 0.13, 0.13, 0.14)
		end
	end
end

function HairMenuPanelWindow:render()
	-- Neat Rocco pattern: render via ISPanelJoypad (children + joypad), NOT
	-- ISCollapsableWindowJoypad.render, whose vanilla titlebar/square background
	-- kept the corners square. The NeatUI header child + body 9-patch own the look.
	ISPanelJoypad.render(self)

	if JoypadState.players[self.playerNum+1] then
		if JoypadState.players[self.playerNum+1].focus == self then
			self:drawRectBorder(0, 0, self:getWidth(), self:getHeight(), 0.4, 0.2, 1.0, 1.0);
			self:drawRectBorder(1, 1, self:getWidth()-2, self:getHeight()-2, 0.4, 0.2, 1.0, 1.0);
		end
	end
end

function HairMenuPanelWindow:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.resizable = false

    if IHM_NeatKit and IHM_NeatKit.attachHeader then
        IHM_NeatKit.attachHeader(self)
    end

    self:rebuildPanel()

    function self:installControlsButton()
        if self._controlsBtn then
            self:removeChild(self._controlsBtn)
            self._controlsBtn = nil
        end

        local th = self:titleBarHeight()
        local smallH = getTextManager():getFontHeight(UIFont.Small)
        local btnH = math.max(22, smallH + 6)
        local title = (getText and getText("UI_IHM_Controls")) or "Controls"
        local btnW = math.max(96, getTextManager():MeasureStringX(UIFont.Small, title) + 24)
        local y = th + math.max(4, math.floor(smallH * 0.25))
        local x = self:getWidth() - btnW - 8
        if x < 8 then x = 8 end

        local b = ISButton:new(x, y, btnW, btnH, title, self, function()
            -- toggleWindow apre se e' chiusa e chiude se e' aperta, e restituisce
            -- nil nel secondo caso. Qui sopra c'era una chiusura esplicita prima
            -- della chiamata: siccome close() azzera il singleton, la toggleWindow
            -- che seguiva trovava sempre campo libero e riapriva. Il tasto apriva
            -- e basta - premuto due volte non chiudeva niente, e in creazione
            -- personaggio invece funzionava, perche' li' la chiamata era diretta.
            self._controlsWin = IHM_GridControlsWindow.toggleWindow(self, {
                context = "ingame",
                onChange = function()
                    self:rebuildPanel()
                end,
            })
        end)
        b:initialise()
        b:instantiate()
        if b.setBorderRGBA then b:setBorderRGBA(0.3, 0.3, 0.3, 0.9) end
        b:setDisplayBackground(true)
        b:setBackgroundRGBA(0, 0, 0, 0.15)
        do local NS = rawget(_G, "IHM_NeatStyle"); if NS and NS.styleFullButton then NS.styleFullButton(b, false) end end

        self:addChild(b)
        self._controlsBtn = b
    end

    self:installControlsButton()

    if not self._setVisibleWrapped then
        local _setVisible = self.setVisible
        -- collide-ok: sovrascrittura voluta di ISUIElement:setVisible.
        -- L'originale e' salvato qui sopra e richiamato qui sotto; il
        -- flag _setVisibleWrapped impedisce di avvolgerlo due volte.
        self.setVisible = function(s, visible, ...)
            local result = _setVisible(s, visible, ...)
            if visible == false and s._controlsWin and s._controlsWin.close then
                pcall(function() s._controlsWin:close() end)
                s._controlsWin = nil
            end
            return result
        end
        self._setVisibleWrapped = true
    end
end

function HairMenuPanelWindow:rebuildPanel()
    local th = self:titleBarHeight()

    local function clampInt(v, lo, hi)
        v = tonumber(v)
        if not v then return nil end
        v = math.floor(v + 0.5)
        if v < lo then v = lo end
        if v > hi then v = hi end
        return v
    end

    local function pxFromStep(step)
        step = clampInt(step, 1, 7) or 5
        return 32 + ((step - 1) * 16)
    end

    local rows = _IHM_getInGameLiveValue("ig_modal_rows", "modal_rows", 2, 1, 10)
    local cols = _IHM_getInGameLiveValue("ig_modal_cols", "modal_cols", 3, 1, 10)
    local avatarStep = _IHM_getInGameLiveValue("ig_avatar_size", "avatar_size", 5, 1, 7)
    local avatar_px = pxFromStep(avatarStep)

    if self.hairPanel then
        self:removeChild(self.hairPanel)
    end

    self.hairPanel = HairMenuPanel:new(0, th, avatar_px, avatar_px, rows, cols, 3, self.isbeard)

    local win = self
    self.hairPanel._ihmApplyGrid = function(newCols, newRows)
        if IHM_LiveConfig then
            IHM_LiveConfig:updateAndSave("ig_modal_cols", newCols)
            IHM_LiveConfig:updateAndSave("ig_modal_rows", newRows)
        end
        win:rebuildPanel()
    end

    self.hairPanel:initialise()
    self.hairPanel.ihmEmbedded = true
    self.hairPanel:setChar(self.char)
    self.hairPanel.onSelect = function(selection)
        if self.onSelect then
            self.onSelect(selection)
        end
    end
    self.hairPanel:setHairList(self.hairList)
    self:addChild(self.hairPanel)

    -- live = false, come in creazione personaggio: anche qui rebuildPanel
    -- **ricrea** self.hairPanel, quindi il bersaglio non sopravvive alla
    -- ricostruzione e con lui morirebbe la maniglia che ne e' figlia. Durante
    -- il gesto si muove la cornice; il conteggio si applica al rilascio.
    if IHM_GridResize then
        local p = self.hairPanel
        IHM_GridResize.attach(p, function(c, r) if p._ihmApplyGrid then p._ihmApplyGrid(c, r) end end)
    end

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local title = (getText and getText("UI_IHM_Controls")) or "Controls"
    local ctrlW = math.max(96, getTextManager():MeasureStringX(UIFont.Small, title) + 24)
    -- Zero, non quattro.
    --
    -- Il pannello ha gia' il suo margine intorno alle caselle
    -- (HairMenuPanel.gridPad, sei-otto pixel per lato), e questi quattro erano
    -- un secondo bordo sopra il primo. Si notavano su un dettaglio solo, ma
    -- preciso: la maniglia di ridimensionamento sta nell'angolo del **pannello**,
    -- e con il doppio bordo l'angolo del pannello non era l'angolo della
    -- finestra - la freccia restava quattro pixel dentro invece di appoggiarsi
    -- allo spigolo, come fa nelle altre due mod.
    local ihmPad = 0
    local targetW = math.max(self.hairPanel:getWidth() + ihmPad * 2, ctrlW + 16)
    local desiredH = th + self.hairPanel:getHeight() + ihmPad
    local maxH = math.floor(sh * 0.90)

    self:setWidth(targetW)
    self:setHeight(math.min(desiredH, maxH))
    self.hairPanel:setX(math.floor((targetW - self.hairPanel:getWidth()) / 2))
    self.hairPanel:setY(th)

    -- Al centro la prima volta, e poi mai piu'.
    --
    -- Queste due righe giravano a ogni rebuildPanel, cioe' a ogni rilascio della
    -- maniglia: la finestra tornava al centro dello schermo proprio mentre la si
    -- stava ridimensionando, e da fuori sembrava che scappasse da sola da sotto
    -- il cursore. Ora la posizione la decide chi la trascina; qui si controlla
    -- soltanto che, dopo essere cresciuta, non sia finita fuori dallo schermo.
    if self._ihmPlaced then
        self:setX(math.max(0, math.min(self:getX(), sw - self:getWidth())))
        self:setY(math.max(0, math.min(self:getY(), sh - self:getHeight())))
    else
        self:setX((sw - self:getWidth()) / 2)
        self:setY((sh - self:getHeight()) / 2)
        self._ihmPlaced = true
    end

    if self.neatHeader then
        self.neatHeader:setY(0)
        self.neatHeader:setWidth(self:getWidth())
        if self.neatHeader.calculateLayout then
            self.neatHeader:calculateLayout(self:getWidth(), self:titleBarHeight())
        end
    end

    if self.installControlsButton then
        self:installControlsButton()
    end
end

function HairMenuPanelWindow:close()
    -- Close the Controls popup first (if present)
    if self._controlsWin and self._controlsWin.close then
        pcall(function() self._controlsWin:close() end)
        self._controlsWin = nil
    end

    self:setVisible(false)
    self:removeFromUIManager()
    if JoypadState.players[self.playerNum+1] then
        setJoypadFocus(self.playerNum, self.returnFocus)
    end
end

function HairMenuPanelWindow:onLoseJoypadFocus(joypadData)
	ISCollapsableWindowJoypad.onLoseJoypadFocus(self, joypadData)
	self.hairPanel:setJoypadFocused(false)
end

function HairMenuPanelWindow:onGainJoypadFocus(joypadData)
	ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
	self.hairPanel:setJoypadFocused(true)
end

function HairMenuPanelWindow:onJoypadDown(button, joypadData)
	if button == Joypad.BButton then
		self:close()
	end
	self.hairPanel:onJoypadDown(button, joypadData)
	ISCollapsableWindowJoypad.onJoypadDown(self, joypadData)
end

function HairMenuPanelWindow:onJoypadDirLeft(joypadData)
	self.hairPanel:onJoypadDirLeft(joypadData)
	ISCollapsableWindowJoypad.onJoypadDirLeft(self, joypadData)
end

function HairMenuPanelWindow:onJoypadDirRight(joypadData)
	self.hairPanel:onJoypadDirRight(joypadData)
	ISCollapsableWindowJoypad.onJoypadDirRight(self, joypadData)
end

function HairMenuPanelWindow:onJoypadDirUp(joypadData)
	self.hairPanel:onJoypadDirUp(joypadData)
	ISCollapsableWindowJoypad.onJoypadDirUp(self, joypadData)
end

function HairMenuPanelWindow:onJoypadDirDown(joypadData)
	self.hairPanel:onJoypadDirDown(joypadData)
	ISCollapsableWindowJoypad.onJoypadDirDown(self, joypadData)
end