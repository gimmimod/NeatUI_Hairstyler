-- IHM_GridControls.lua — simple NeatUI window for grid controls: Rows / Columns.
-- Reworked: no sliders, no avatar-size row. Two steppers built from the same
-- square buttons Rocco uses for his numeric steppers (Icon_Minus1 / Icon_Plus1).
-- Place at: media/lua/client/improvedhairmenu/InGame/IHM_GridControls.lua
if isServer() then return end
require "ISUI/ISCollapsableWindow"
require "ISUI/ISLabel"
require "ISUI/ISButton"
pcall(require, "improvedhairmenu/IHM_NeatStyle")
pcall(require, "improvedhairmenu/IHM_NeatKit")
local _ok = pcall(require, "improvedhairmenu/ModOptions")
IHM_GridControlsWindow = ISCollapsableWindow:derive("IHM_GridControlsWindow")

local MIN_VAL, MAX_VAL = 1, 10

-- getText returns the raw key when a translation is missing: never show that.
local function tr(key, fallback)
    if not getText then return fallback end
    local t = getText(key)
    if not t or t == key then return fallback end
    return t
end

local function _clampInt(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return math.floor(v + 0.5)
end

local function _IHM_getGridProfile(context)
    if context == "charcreation" then
        return {
            rowsKey = "cc_modal_rows",
            colsKey = "cc_modal_cols",
            defaultRows = 4,
            defaultCols = 6,
        }
    end
    return {
        rowsKey = "ig_modal_rows",
        colsKey = "ig_modal_cols",
        defaultRows = 2,
        defaultCols = 3,
    }
end

local function _stepIcon(name)
    -- Rocco stepper art (bundled copy), white silhouette.
    return getTexture("media/ui/IHMNeat/Icon/" .. name .. ".png")
end

function IHM_GridControlsWindow:new(x, y, w, h, owner, opts)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.owner = owner
    o.opts = opts or {}
    o.context = o.opts.context or "ingame"
    o.profile = _IHM_getGridProfile(o.context)
    o.resizable = false
    o.moveWithMouse = true
    o:setWantKeyEvents(true)
    o.background = false
    o.drawFrame = false
    return o
end

function IHM_GridControlsWindow:titleBarHeight()
    return (IHM_NeatKit and IHM_NeatKit.headerHeight) or ISCollapsableWindow.titleBarHeight(self)
end

function IHM_GridControlsWindow:getWindowTitle()
    return self.title or ""
end

function IHM_GridControlsWindow:getWindowIcon()
    return nil
end

-- Change a value by delta, persist it, refresh the grid.
function IHM_GridControlsWindow:step(logicalKey, delta)
    local cur = self._cache[logicalKey] or MIN_VAL
    local v = _clampInt(cur + delta, MIN_VAL, MAX_VAL)
    if v == cur then return end
    self._cache[logicalKey] = v

    local storeKey = self._keys[logicalKey] or logicalKey
    if IHM_LiveConfig then
        IHM_LiveConfig:updateAndSave(storeKey, v)
    end
    if self.opts and self.opts.onChange then
        self.opts.onChange()
    end
end

function IHM_GridControlsWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    if IHM_LiveConfig and ImprovedHairMenu and ImprovedHairMenu.settings then
        pcall(function()
            IHM_LiveConfig:load()
            IHM_LiveConfig:applyToSettings(ImprovedHairMenu.settings)
        end)
    end

    local P = self.profile or _IHM_getGridProfile(self.context)
    self.profile = P

    local function readInitial(primaryKey, legacyKey, defaultValue)
        local v = nil
        if IHM_LiveConfig and IHM_LiveConfig.cache then
            v = IHM_LiveConfig.cache[primaryKey]
            if v == nil and legacyKey then v = IHM_LiveConfig.cache[legacyKey] end
        end
        if v == nil and ImprovedHairMenu and ImprovedHairMenu.settings then
            v = ImprovedHairMenu.settings[primaryKey]
            if v == nil and legacyKey then v = ImprovedHairMenu.settings[legacyKey] end
        end
        return _clampInt(v or defaultValue, MIN_VAL, MAX_VAL)
    end

    local tm = getTextManager()
    local font = UIFont.Small
    local smallH = tm:getFontHeight(font)
    local pad = math.max(10, math.floor(smallH * 0.6))
    local gapY = math.max(8, math.floor(smallH * 0.5))

    local title = tr("UI_IHM_Controls", "Controls")
    self:setTitle(title)

    local rowsText = tr("IGUI_IHM_modal_rows", "Rows")
    local colsText = tr("IGUI_IHM_modal_cols", "Columns")

    self._keys = { rows = P.rowsKey, cols = P.colsKey }
    self._cache = {
        rows = readInitial(P.rowsKey, "modal_rows", P.defaultRows),
        cols = readInitial(P.colsKey, "modal_cols", P.defaultCols),
    }

    local bsz = math.max(24, smallH + 8)            -- square stepper button (NR_Config.buttonSize-ish)
    local rowH = bsz
    local valueW = math.max(40, tm:MeasureStringX(font, tostring(MAX_VAL)) + 24)

    local labelW = 0
    for _, txt in ipairs({ rowsText, colsText }) do
        labelW = math.max(labelW, tm:MeasureStringX(font, txt))
    end
    labelW = labelW + 12

    local stepperW = bsz + valueW + bsz
    -- Niente tasto "Chiudi" qui sotto: lo fa gia' la X nell'intestazione, e
    -- due comandi per la stessa azione sono uno di troppo.

    local totalW = math.max(230, pad * 2 + labelW + 12 + stepperW)
    local totalH = self:titleBarHeight() + pad + (rowH + gapY) * 2 - gapY + pad
    self:setWidth(totalW)
    self:setHeight(totalH)

    local NS = rawget(_G, "IHM_NeatStyle")
    local minusIcon = _stepIcon("Icon_Minus1")
    local plusIcon  = _stepIcon("Icon_Plus1")

    self._rows = {}
    local y = self:titleBarHeight() + pad
    local stepperX = totalW - pad - stepperW

    local function addStepperRow(labelText, logicalKey)
        local lbl = ISLabel:new(pad, y, rowH, labelText, 1, 1, 1, 1, font, true)
        lbl:initialise()
        lbl:instantiate()
        self:addChild(lbl)

        local win = self
        local btnMinus, btnPlus
        if NS and NS.newSquareButton then
            btnMinus = NS.newSquareButton(stepperX, y, bsz, minusIcon, self,
                function() win:step(logicalKey, -1) end)
            btnPlus = NS.newSquareButton(stepperX + bsz + valueW, y, bsz, plusIcon, self,
                function() win:step(logicalKey, 1) end)
        else
            btnMinus = ISButton:new(stepperX, y, bsz, bsz, "-", self,
                function() win:step(logicalKey, -1) end)
            btnMinus:initialise(); btnMinus:instantiate()
            btnPlus = ISButton:new(stepperX + bsz + valueW, y, bsz, bsz, "+", self,
                function() win:step(logicalKey, 1) end)
            btnPlus:initialise(); btnPlus:instantiate()
        end
        self:addChild(btnMinus)
        self:addChild(btnPlus)

        table.insert(self._rows, {
            key = logicalKey,
            valueX = stepperX + bsz,
            valueY = y,
        })

        y = y + rowH + gapY
    end

    addStepperRow(rowsText, "rows")
    addStepperRow(colsText, "cols")

    self._valueW = valueW
    self._rowH = rowH
    self._font = font

    if IHM_NeatKit and IHM_NeatKit.attachHeader then
        IHM_NeatKit.attachHeader(self)
    end
end

-- Neat Rocco render pattern: skip the vanilla titlebar (square), the NeatUI
-- header child + body 9-patch own the look.
function IHM_GridControlsWindow:render()
    ISPanelJoypad.render(self)

    -- current values, centred between the stepper buttons
    if self._rows and self._cache then
        local tm = getTextManager()
        local fh = tm:getFontHeight(self._font or UIFont.Small)
        for _, row in ipairs(self._rows) do
            local v = tostring(self._cache[row.key] or "")
            self:drawTextCentre(v,
                row.valueX + math.floor((self._valueW or 40) / 2),
                row.valueY + math.floor(((self._rowH or 24) - fh) / 2),
                0.9, 0.9, 0.9, 1, self._font or UIFont.Small)
        end
    end
end

function IHM_GridControlsWindow:prerender()
    if not self.owner
        or (self.owner.getIsVisible and not self.owner:getIsVisible())
        or (self.owner.isVisible and not self.owner:isVisible())
    then
        self:close()
        return
    end

    if IHM_NeatKit and IHM_NeatKit.prerenderBody then
        IHM_NeatKit.prerenderBody(self)
    else
        ISCollapsableWindow.prerender(self)
    end
end

function IHM_GridControlsWindow:close()
    if self.owner and self.owner._controlsWin == self then
        self.owner._controlsWin = nil
    end
    if IHM_GridControlsWindow.instance == self then
        IHM_GridControlsWindow.instance = nil
    end
    self:setVisible(false)
    self:removeFromUIManager()
end

--- L'unica finestra controlli in giro, se c'e'.
---
--- Ce n'e' una sola per costruzione: prima ogni pressione del tasto ne creava
--- un'altra, si impilavano una sull'altra e l'unico modo di liberarsene era
--- chiuderle a una a una con la X.
IHM_GridControlsWindow.instance = nil

function IHM_GridControlsWindow.isOpen()
    local w = IHM_GridControlsWindow.instance
    return w ~= nil and w:isVisible()
end

-- Static opener
function IHM_GridControlsWindow.open(owner, opts)
    -- Gia' aperta: la si porta davanti invece di clonarla.
    local existing = IHM_GridControlsWindow.instance
    if existing and existing:isVisible() then
        existing.owner = owner
        existing.opts = opts or existing.opts
        existing:bringToTop()
        return existing
    end

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = IHM_GridControlsWindow:new(0, 0, 230, 140, owner, opts)
    win:initialise()
    win:setX(math.floor((sw - win:getWidth()) / 2))
    win:setY(math.floor((sh - win:getHeight()) / 2))
    win:addToUIManager()
    win:setVisible(true)
    if win.setAlwaysOnTop then win:setAlwaysOnTop(true) else win:bringToTop() end
    IHM_GridControlsWindow.instance = win
    return win
end

--- Il tasto Controlli apre e chiude la stessa finestra.
---
--- Un tasto che apre e non richiude e' meta' comando: si preme due volte e non
--- succede niente di visibile, mentre in realta' si sta impilando roba.
---@return table|nil la finestra se e' stata aperta, nil se e' stata chiusa
--- NON `toggle`: quel nome e gia occupato da :toggle(key), il metodo che
--- ribalta una spunta. Sono la stessa voce della stessa tabella, e questa
--- essendo definita dopo se lo mangiava: ogni clic su una spunta apriva o
--- chiudeva la finestra invece di cambiare l impostazione.
function IHM_GridControlsWindow.toggleWindow(owner, opts)
    if IHM_GridControlsWindow.isOpen() then
        IHM_GridControlsWindow.instance:close()
        return nil
    end
    return IHM_GridControlsWindow.open(owner, opts)
end
