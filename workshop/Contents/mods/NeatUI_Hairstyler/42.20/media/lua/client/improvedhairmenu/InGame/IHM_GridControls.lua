--[[ ============================================================================
    IHM_GridControls - la finestra CONTROLLI.

    Contiene sempre gli interruttori dell'anteprima (nome al passaggio, gira
    trascinando, girale tutte, nascondi i vestiti) e, in creazione personaggio,
    la scelta del selettore di colore.

    I contatori Righe e Colonne invece **compaiono solo se servono**: di serie
    la griglia si ridimensiona trascinando l'angolo del menu, e in quel modo due
    contatori sarebbero un secondo padrone dello stesso numero. Chi preferisce i
    numeri li riaccende da Options > Mods > NeatUI Hairstyler togliendo la
    spunta a "Ridimensiona trascinando"; allora la maniglia d'angolo sparisce e
    i contatori tornano qui.

    I quadratini sono quelli di Rocco (Icon_Minus1 / Icon_Plus1), la spunta e'
    Icon_True. Il tasto non cambia colore quando e' acceso: la spunta da sola
    porta lo stato, e cosi' c'e' una cosa sola da leggere.
============================================================================ ]]--
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

--- Vero quando la maniglia d'angolo e' spenta e i numeri tornano qui.
local function _useSteppers()
    local MS = rawget(_G, "IHM_ModSettings")
    if MS and MS.useDragResize then
        local ok, v = pcall(MS.useDragResize)
        if ok then return not v end
    end
    return false
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
    -- Rocco stepper art (bundled copy), white silhouette. Sotto pcall come il
    -- resto delle texture: un file che manca deve far comparire un quadratino
    -- senza disegno, non impedire alla finestra CONTROLLI di aprirsi.
    local ok, t = pcall(getTexture, "media/ui/IHMNeat/Icon/" .. name .. ".png")
    if ok then return t end
    return nil
end

-- The bundled Icon folder has no tick, so resolve the framework's first and fall
-- back to the embedded copies - the same order IHM_NeatStyle uses for panels.
--
-- Icon_True is the plain white check. ICON_Check is deliberately NOT used: it is
-- a green filled disc, and on a button that also changes colour it reads as two
-- competing signals.
local function _tickIcon()
    for _, p in ipairs({
        "media/ui/NeatUI/ICON/Icon_True.png",
        "media/ui/IHMNeat/Icon/Icon_True.png",
    }) do
        local ok, t = pcall(getTexture, p)
        if ok and t then return t end
    end
    return nil
end

-- Not every toggle starts on: turning the whole grid at once is opt-in.
local TOGGLE_DEFAULT = {
    show_name_tooltip           = false,
    drag_rotate                 = true,
    rotate_all                  = false,
    hide_clothing               = true,
    cc_use_improved_hair_picker = true,
}

local function _defaultFor(key)
    local d = TOGGLE_DEFAULT[key]
    if d == nil then return true end
    return d
end

-- Read a live boolean. Written out longhand on purpose: `LC:getBool(k) or true`
-- collapses a legitimate false into true, which is what made these toggles
-- one-way - they switched off once and then never came back.
local function _readBool(key, default)
    if default == nil then default = true end
    local LC = rawget(_G, "IHM_LiveConfig")
    if LC and LC.getBool then
        local v = LC:getBool(key, default)
        if v ~= nil then return v end
    end
    return default
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

-- Preview toggles. No grid rebuild needed: the components read the live value
-- every frame, so flipping one takes effect on the next draw.
--[[ Re-apply the visual on every live avatar.

    Needed by hide_clothing only. The header name and the drag reading are re-read
    every frame, so those are live for free, but the outfit is pushed into the model
    inside VisualAvatar:applyVisual - which normally runs only when the grid is
    built. Without this the clothing toggle appeared dead until you reopened the
    menu.

    HairMenuPanel:applyVisual loops its avatars and nothing else, so this is far
    cheaper than the full opts.onChange rebuild the steppers use.
]]
function IHM_GridControlsWindow:refreshAvatars()
    local o = self.owner
    if not o then return end

    local panels = {}
    if o.hairMenu   then table.insert(panels, o.hairMenu)   end   -- character creation
    if o.beardMenu  then table.insert(panels, o.beardMenu)  end
    if o.hairPanel  then table.insert(panels, o.hairPanel)  end   -- in-game window

    for _, p in ipairs(panels) do
        if p.applyVisual then pcall(function() p:applyVisual() end) end
    end
end

function IHM_GridControlsWindow:toggle(key)
    local LC = rawget(_G, "IHM_LiveConfig")
    if not LC then return end

    local new = not _readBool(key, _defaultFor(key))
    LC:updateAndSave(key, new)

    -- Mirror onto the settings table too: some readers reach for it directly,
    -- and a stale value there would make the change look like it did not apply.
    if ImprovedHairMenu and ImprovedHairMenu.settings then
        ImprovedHairMenu.settings[key] = new
    end

    local btn = self._toggles and self._toggles[key]
    if btn then
        if btn.setIcon then
            btn:setIcon(new and self._tickIcon or nil)
        elseif btn.setTitle then
            btn:setTitle(new and "v" or "")
        end
    end

    if key == "show_name_tooltip" then
        -- Drop a label already on screen when switching the hover name off.
        if not new then
            local TT = rawget(_G, "IHM_NeatTooltip")
            if TT and TT.hide then TT.hide() end
        end
        -- The header reserves width for the name only when it is drawn, and that
        -- is decided while the panel is built - so rebuild, or the name that just
        -- came back would be clipped to a gap sized for nothing.
        if self.opts and self.opts.onChange then
            self.opts.onChange()
        end
    end

    if key == "hide_clothing" then
        self:refreshAvatars()
    end

    -- The picker object itself has to be rebuilt: the mod keeps one instance and
    -- swaps the class between the Neat picker and the vanilla mosaic.
    if key == "cc_use_improved_hair_picker" then
        local o = self.owner
        if o and o.onHairPickerToggle then
            pcall(function() o:onHairPickerToggle(1, new) end)
        end
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

    self._keys = { rows = P.rowsKey, cols = P.colsKey }
    self._cache = {
        rows = readInitial(P.rowsKey, "modal_rows", P.defaultRows),
        cols = readInitial(P.colsKey, "modal_cols", P.defaultCols),
    }

    local bsz = math.max(24, smallH + 8)            -- square stepper button (NR_Config.buttonSize-ish)
    local rowH = bsz
    local valueW = math.max(40, tm:MeasureStringX(font, tostring(MAX_VAL)) + 24)

    -- Preview toggles (1.3.0). Global, not per-context: they describe how a
    -- preview behaves, not how many of them fit on screen.
    local toggleText = {
        show_name_tooltip = tr("UI_IHM_Opt_NameTooltip", "Show name on hover"),
        drag_rotate       = tr("UI_IHM_Opt_DragRotate", "Drag to turn"),
        rotate_all        = tr("UI_IHM_Opt_RotateAll", "Turn all together"),
        hide_clothing     = tr("UI_IHM_Opt_HideClothing", "Hide clothing"),
    }
    local toggleOrder = { "show_name_tooltip", "drag_rotate", "rotate_all", "hide_clothing" }

    -- Hair colour is only ever picked in character creation, so the picker option
    -- would be dead weight in the in-game window. The guard is now just "did the
    -- picker class load" - there is no multiplayer restriction any more.
    local pickerAllowed = rawget(_G, "IHM_IsHairPickerAllowed")
    if self.context == "charcreation" and pickerAllowed and pickerAllowed() then
        toggleText.cc_use_improved_hair_picker =
            tr("UI_IHM_UseImprovedHairPicker", "Improved Color Picker")
        table.insert(toggleOrder, "cc_use_improved_hair_picker")
    end

    -- I contatori, se l'opzione li vuole. Righe e colonne dello stesso menu:
    -- il profilo decide su quali chiavi scrivere, in gioco e in creazione
    -- personaggio sono due griglie separate.
    self._useSteppers = _useSteppers()
    local stepperOrder = {
        { key = "rows", text = tr("UI_IHM_Rows", "Rows") },
        { key = "cols", text = tr("UI_IHM_Cols", "Columns") },
    }

    local labelW = 0
    local labelSet = {}
    if self._useSteppers then
        for _, r in ipairs(stepperOrder) do table.insert(labelSet, r.text) end
    end
    for _, k in ipairs(toggleOrder) do table.insert(labelSet, toggleText[k]) end
    for _, txt in ipairs(labelSet) do
        labelW = math.max(labelW, tm:MeasureStringX(font, txt))
    end
    labelW = labelW + 12

    -- Niente tasto "Chiudi" qui sotto: lo fa gia' la X nell'intestazione, e
    -- due comandi per la stessa azione sono uno di troppo.

    -- La finestra si stringe o si allarga secondo quello che contiene davvero.
    -- Una riga con i contatori porta [-][valore][+]; una con la spunta porta un
    -- quadratino solo.
    local clusterW = self._useSteppers and (bsz * 2 + valueW) or bsz
    local totalW = math.max(200, pad * 2 + labelW + 12 + clusterW)

    local nRows = #toggleOrder + (self._useSteppers and #stepperOrder or 0)
    local totalH = self:titleBarHeight() + pad
                 + (rowH + gapY) * nRows
                 + pad
    self:setWidth(totalW)
    self:setHeight(totalH)

    local NS = rawget(_G, "IHM_NeatStyle")
    local minusIcon = _stepIcon("Icon_Minus1")
    local plusIcon  = _stepIcon("Icon_Plus1")

    self._rows = {}
    local y = self:titleBarHeight() + pad
    -- Toggle rows: label + a plain square that shows a tick when on and nothing
    -- when off. The button never goes orange - the tick alone carries the state,
    -- so there is only one thing to read.
    self._tickIcon = _tickIcon()
    self._toggles = {}
    local function addToggleRow(key)
        local lbl = ISLabel:new(pad, y, rowH, toggleText[key], 1, 1, 1, 1, font, true)
        lbl:initialise()
        lbl:instantiate()
        self:addChild(lbl)

        local on = _readBool(key, _defaultFor(key))

        local win = self
        local btn
        -- Ancorato al bordo destro. Prima si posizionava rispetto ai contatori
        -- Righe/Colonne, che non ci sono piu': stepperX e valueW erano spariti
        -- con loro e questa somma finiva su un nil, che e' l'errore che apriva
        -- il pannello a vuoto.
        -- totalW, non self:getWidth(): qui siamo dentro createChildren e
        -- l elemento puo non avere ancora la sua larghezza vera. Il tasto
        -- finiva oltre il bordo, la finestra lo ritagliava, e i comandi
        -- risultavano non cliccabili.
        local bx = totalW - pad - bsz
        if NS and NS.newSquareButton then
            btn = NS.newSquareButton(bx, y, bsz, on and self._tickIcon or nil, self,
                function() win:toggle(key) end)   -- no activeColor: stays neutral
        else
            btn = ISButton:new(bx, y, bsz, bsz, on and "v" or "", self,
                function() win:toggle(key) end)
            btn:initialise(); btn:instantiate()
        end
        self:addChild(btn)
        self._toggles[key] = btn

        y = y + rowH + gapY
    end

    -- Riga con i contatori: etichetta a sinistra, [-][valore][+] a destra.
    -- Il valore lo scrive render(), qui si segna solo dove va.
    local function addStepperRow(key, text)
        local lbl = ISLabel:new(pad, y, rowH, text, 1, 1, 1, 1, font, true)
        lbl:initialise()
        lbl:instantiate()
        self:addChild(lbl)

        local win = self
        local plusX  = totalW - pad - bsz
        local valueX = plusX - valueW
        local minusX = valueX - bsz

        local function square(x, icon, delta)
            local btn
            if NS and NS.newSquareButton then
                btn = NS.newSquareButton(x, y, bsz, icon, self,
                    function() win:step(key, delta) end)
            else
                btn = ISButton:new(x, y, bsz, bsz, delta < 0 and "-" or "+", self,
                    function() win:step(key, delta) end)
                btn:initialise(); btn:instantiate()
            end
            self:addChild(btn)
        end

        square(minusX, minusIcon, -1)
        square(plusX,  plusIcon,   1)

        table.insert(self._rows, { key = key, valueX = valueX, valueY = y })
        y = y + rowH + gapY
    end

    if self._useSteppers then
        for _, r in ipairs(stepperOrder) do addStepperRow(r.key, r.text) end
    end

    for _, key in ipairs(toggleOrder) do addToggleRow(key) end

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
