--[[ ============================================================================
    IHM_ModSettings - Options > Mods > "NeatUI Hairstyler".

    Quello che si sceglie una volta e poi non si tocca piu'.

      * Ridimensiona trascinando - la maniglia all'angolo del menu, accesa di
        serie. Spegnendola tornano i contatori Righe e Colonne dentro CONTROLLI.
      * Stile selezionato        - il riquadro che indossi adesso      (verde)
      * Selettore di stile       - il riquadro sotto il cursore     (arancione)

    Stanno qui e non in CONTROLLI apposta: CONTROLLI e' l'arredamento del menu
    aperto (cosa fa un'anteprima, quante ne stanno), mentre queste sono
    decisioni di impostazione. Options > Mods si raggiunge anche dal menu
    principale, quindi valgono gia' la prima volta che si apre la creazione
    personaggio - e l'opzione del trascinamento decide *cosa contiene* la
    finestra CONTROLLI, che e' un motivo in piu' per non metterla dentro di
    essa.

    Colour rows are the stock PZAPI "colorpicker" option, but the swatch button
    opens IHM_NeatColorPicker instead of the 84-square vanilla mosaic - the same
    trade NeatXPSettings makes, and for the same reason: the mosaic does not look
    like a Neat window. MainOptions.onModColorPick is wrapped rather than
    replaced, so every other mod's colour options keep the vanilla picker.

    Everything ImprovedHairMenu keeps per-menu still lives in IHM_live.ini via
    IHM_LiveConfig (see ModOptions.lua); nothing here touches that file.
============================================================================ ]]--
if isServer() then return end

pcall(require, "improvedhairmenu/IHM_NeatStyle")
pcall(require, "improvedhairmenu/IHM_NeatColorPicker")

IHM_ModSettings = IHM_ModSettings or {}

IHM_ModSettings.MOD_ID    = "NeatUI_Hairstyler"
IHM_ModSettings.MOD_TITLE = "NeatUI Hairstyler"

local PREFIX = IHM_ModSettings.MOD_ID .. "."

-- getText returns the raw key when a translation is missing: never show that.
local function tr(key, fallback)
    if not getText then return fallback end
    local t = getText(key)
    if not t or t == key then return fallback end
    return t
end

-- optionId -> { style colour key, picker window title }
local COLOR_OPTIONS = {
    selectedColor = { key = "selection", title = { "UI_IHM_Opt_SelectedColor", "Selected style" } },
    cursorColor   = { key = "cursor",    title = { "UI_IHM_Opt_CursorColor",   "Style selector" } },
}

-- Offered as one-click swatches under the field. The option's own default is
-- prepended per picker, so "put it back" is always the first square.
local PRESETS = {
    { r = 0.30, g = 0.72, b = 0.38 },   -- Neat green (selection default)
    { r = 0.95, g = 0.50, b = 0.10 },   -- Neat orange (cursor default)
    { r = 1.00, g = 1.00, b = 1.00 },
    { r = 0.72, g = 0.72, b = 0.72 },
    { r = 0.95, g = 0.78, b = 0.20 },
    { r = 0.30, g = 0.72, b = 0.68 },
    { r = 0.35, g = 0.60, b = 0.95 },
    { r = 0.62, g = 0.45, b = 0.90 },
    { r = 0.90, g = 0.30, b = 0.35 },
}

local function NS() return rawget(_G, "IHM_NeatStyle") end

local function getOptions()
    return PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions(IHM_ModSettings.MOD_ID)
end

-- =============================================================================
-- Come si sceglie quante anteprime stanno nel menu
-- =============================================================================

--- Acceso di serie: si trascina l'angolo del menu e la griglia segue.
---
--- Spento, torna il modo di prima: niente maniglia d'angolo, e due contatori
--- Righe e Colonne nella finestra CONTROLLI. Sono due modi di dire la stessa
--- cosa, quindi non convivono - averli tutti e due vorrebbe dire due padroni
--- per lo stesso numero, ed e' esattamente il difetto da cui e' nato
--- IHM_GridResize.
---
--- Sta qui e non in CONTROLLI perche' e' una scelta che si fa una volta, come i
--- colori: decide *cosa contiene* la finestra CONTROLLI, e un'opzione che
--- cambia il pannello in cui si trova e' un pannello che si riscrive sotto le
--- dita.
IHM_ModSettings.DRAG_RESIZE_DEFAULT = true

---@return boolean vero se vale il trascinamento, falso se valgono i contatori
function IHM_ModSettings.useDragResize()
    local page = getOptions()
    local opt = page and page.getOption and page:getOption("dragResize")
    if opt and opt.getValue then
        local v = opt:getValue()
        if v ~= nil then return v and true or false end
    end
    return IHM_ModSettings.DRAG_RESIZE_DEFAULT
end

--- La finestra CONTROLLI cambia forma con l'opzione, quindi si richiude.
---
--- Non si puo' rifarla sul posto: i contatori entrano ed escono, e con loro
--- l'altezza. Chiuderla e' onesto - la si riapre e c'e' quello che serve.
local function closeControlsWindow()
    local W = rawget(_G, "IHM_GridControlsWindow")
    if W and W.instance and W.instance.close then
        pcall(function() W.instance:close() end)
    end
end

-- =============================================================================
-- Colour plumbing
-- =============================================================================

local function applyColor(styleKey, value)
    if type(value) ~= "table" then return end
    local S = NS()
    if not (S and S.setColor) then return end
    S.setColor(styleKey, value.r or value[1], value.g or value[2], value.b or value[3])
end

-- Vanilla positioning logic from MainOptions:onModColorPick, kept identical so
-- the panel lands under its swatch button on every resolution.
local function anchorPicker(mainOptions, button, picker)
    local x = button.parent.parent.x + button.parent.x + button.parent:getXScroll() + button.x
    local y = button.parent.parent.y + button.parent.y + button.parent:getYScroll() + button.y + button.height + 1
    if y + picker.height > mainOptions.height then
        y = y - button.height - picker.height - 1
    end
    if y < 0 then y = 0 end
    x = math.min(x, mainOptions.width - picker.width - 4)
    if x < 0 then x = 0 end
    picker:setX(x)
    picker:setY(y)
end

function IHM_ModSettings.openNeatPicker(mainOptions, button)
    local Picker = rawget(_G, "IHM_NeatColorPicker")
    if not Picker then return false end

    local optionId = string.sub(button.optionID or "", #PREFIX + 1)
    local meta = COLOR_OPTIONS[optionId]

    -- A plain table, not a ColorInfo: the picker's readColor takes either, and
    -- the swatch button already stores the colour in exactly this shape.
    local c = button.backgroundColor or { r = 1, g = 1, b = 1 }
    local picker = Picker:new(0, 0, { r = c.r, g = c.g, b = c.b })
    picker:initialise()

    if meta then
        picker.title = tr(meta.title[1], meta.title[2])

        -- Default first, then the shared row, skipping a duplicate of it.
        local S = NS()
        local def = S and S.DEFAULTS and S.DEFAULTS[meta.key]
        if def and picker.setDefaultColor then
            picker:setDefaultColor(def.r, def.g, def.b)
        end
        local palette = {}
        if def then table.insert(palette, { r = def.r, g = def.g, b = def.b }) end
        for _, p in ipairs(PRESETS) do
            if not (def and p.r == def.r and p.g == def.g and p.b == def.b) then
                table.insert(palette, p)
            end
        end
        -- setPalette re-measures the panel, so it has to run before anchoring.
        picker:setPalette(palette)
    end

    picker.pickedFunc   = MainOptions.pickedModColor
    picker.pickedTarget = button
    picker.pickedArgs   = {}

    anchorPicker(mainOptions, button, picker)
    mainOptions:addChild(picker)
    picker:setCapture(true)
    picker:setVisible(true)
    picker:bringToTop()
    return true
end

--[[ Round off our two swatch buttons on the options screen.

    MainOptions:addColorButton hands back a plain square ISButton and PZAPI keeps
    it on `option.element`, so the handle is there - it just does not exist until
    the screen is built. addModOptionsPanel is the moment it does, hence the
    wrapper rather than a one-shot call at boot. Re-styling is idempotent
    (styleSwatchButton latches), so re-opening Options costs nothing.
]]
--[[ ----------------------------------------------------------------------
    Lo scudo sul '%'.

    MainOptions:addModOptionsPanel scorre le opzioni di **tutte** le mod
    installate e per ognuna chiama getText (MainOptions.lua:2815-2817). Se il
    testo che ne esce contiene un '%' che non sia '%%', Translator lo passa a
    String.format per avvisare che mancano gli argomenti, Formatter alza
    UnknownFormatConversionException, e la pagina Options > Mods si ferma li':
    le mod che venivano dopo non compaiono piu'. (METODO/03, lezione 28.)

    Il guasto non e' mai nostro - nessuna nostra stringa ha un '%' isolato - ma
    la traccia porta il nostro nome, perche' e' questo wrapper a chiamare il
    vanilla. Una segnalazione vera, con "Keeps headlight condition at 100%" e
    "+50%)" come tooltip di caselle di altre mod, e' quello che si vede.

    Rimedio: per la durata della chiamata al vanilla, getText passa di qui.
    getTextOrNull da' lo **stesso** testo che darebbe getText - la traduzione,
    o nil se la chiave non esiste - senza passare dal formattatore. Se quel
    testo e' innocuo chiamiamo il getText vero, e non cambia niente per
    nessuno; se e' uno di quelli che farebbero saltare tutto restituiamo il
    testo cosi' com'e' e scriviamo nel log di chi e'.

    Non copre chi salta getText per conto suo, e non copre le opzioni sandbox:
    e' solo questa pagina, che e' quella che si rompeva.
------------------------------------------------------------------------- ]]--

--- Un '%' che Java Formatter non sa digerire: tutto tranne '%%'.
--- Vale anche per '%1', che e' la convenzione del gioco ma non di Formatter -
--- ed e' esattamente il caso che Translator segnala come "argomenti mancanti".
local function hasLoosePercent(text)
    local i = 1
    while true do
        -- plain = true: '%' cercato come carattere, non come pattern.
        local at = string.find(text, "%", i, true)
        if not at then return false end
        if string.sub(text, at + 1, at + 1) ~= "%" then return true end
        i = at + 2
    end
end

-- Una riga di log per stringa, non una per fotogramma.
local _reported = {}

--- Il getText di prima, da rimettere. Fuori dalla costruzione del pannello e'
--- nil, e getText e' quello di sempre: lo scudo non deve costare niente al
--- resto del gioco, dove getText viene chiamato a ogni disegno di tooltip.
local _getTextToRestore = nil

--- Sostituto di getText per la durata della costruzione del pannello.
---@param realGetText fun(key:string, ...):string
---@param realGetTextOrNull fun(key:string):string|nil
local function makeShield(realGetText, realGetTextOrNull)
    return function(key, ...)
        if select("#", ...) > 0 or type(key) ~= "string" then
            return realGetText(key, ...)
        end

        -- getTextOrNull da' la traduzione senza formattarla; niente chiave,
        -- niente traduzione, e allora il testo e' la stringa stessa - che e'
        -- anche quello che restituirebbe getText.
        local ok, resolved = pcall(realGetTextOrNull, key)
        if not ok or type(resolved) ~= "string" then resolved = key end

        -- Innocuo: passa dal getText vero, e per il gioco non e' cambiato
        -- niente. E' il caso di quasi tutte le stringhe di quasi tutte le mod.
        if not hasLoosePercent(resolved) then return realGetText(key) end

        if not _reported[key] then
            _reported[key] = true
            print("NeatUI Hairstyler: Options > Mods - \"" .. key ..
                  "\" contiene un '%' che il gioco non sa formattare (" ..
                  string.sub(resolved, 1, 120) ..
                  "). Senza questo scudo la pagina si fermava qui.")
        end
        return resolved
    end
end

--- Mette lo scudo e restituisce cosa c'era prima, o nil se non si puo' fare.
--- Senza getTextOrNull non c'e' modo di leggere una traduzione senza rischiare
--- il guasto stesso che si vuole evitare: in quel caso, meglio niente scudo.
local function raisePercentShield()
    local realGetText = rawget(_G, "getText")
    local realGetTextOrNull = rawget(_G, "getTextOrNull")
    if type(realGetText) ~= "function" or type(realGetTextOrNull) ~= "function" then
        return nil
    end

    _getTextToRestore = realGetText
    _G.getText = makeShield(realGetText, realGetTextOrNull)
    return realGetText
end

local function lowerPercentShield()
    if _getTextToRestore then
        _G.getText = _getTextToRestore
        _getTextToRestore = nil
    end
end

-- Rete: lo scudo vale per una chiamata sola, e una chiamata sta dentro un
-- fotogramma. Se il vanilla si pianta a meta' nessuno arriva a toglierlo, e da
-- li' in poi ogni getText del gioco passerebbe di qui; il primo tick lo rimette
-- a posto. Lua qui e' a un filo solo, quindi un tick non puo' cadere dentro la
-- costruzione del pannello.
if Events and Events.OnTick then
    Events.OnTick.Add(lowerPercentShield)
end

local _panelHooked = false
local function hookOptionsPanel()
    if _panelHooked then return end
    if not (MainOptions and MainOptions.addModOptionsPanel) then return end
    _panelHooked = true

    local vanilla = MainOptions.addModOptionsPanel
    MainOptions.addModOptionsPanel = function(self, ...)
        raisePercentShield()
        local result = { vanilla(self, ...) }
        lowerPercentShield()

        local S = NS()
        local options = getOptions()
        if S and S.styleSwatchButton and options then
            for optionId in pairs(COLOR_OPTIONS) do
                local opt = options:getOption(optionId)
                if opt and opt.element then
                    pcall(function() S.styleSwatchButton(opt.element) end)
                end
            end
        end
        return unpack(result)
    end
end

local _hooked = false
local function hookColorPicker()
    if _hooked then return end
    if not (MainOptions and MainOptions.onModColorPick) then return end
    _hooked = true

    local vanilla = MainOptions.onModColorPick
    MainOptions.onModColorPick = function(self, button, ...)
        local id = button and button.optionID
        if type(id) == "string" and string.sub(id, 1, #PREFIX) == PREFIX then
            if IHM_ModSettings.openNeatPicker(self, button) then return end
        end
        return vanilla(self, button, ...)
    end
end

-- =============================================================================
-- Registration
-- =============================================================================

local function register()
    if not (PZAPI and PZAPI.ModOptions) then return end

    local S = NS()
    local D = (S and S.DEFAULTS) or {
        selection = { r = 0.30, g = 0.72, b = 0.38 },
        cursor    = { r = 0.95, g = 0.50, b = 0.10 },
    }

    local options = PZAPI.ModOptions:create(IHM_ModSettings.MOD_ID, IHM_ModSettings.MOD_TITLE)

    -- The mod name is already drawn as the section header by
    -- MainOptions:addModOptionsPanel, so these titles only carry the subsection.
    options:addTitle("UI_IHM_Opt_Section_Grid")
    options:addTickBox("dragResize", "UI_IHM_Opt_DragResize",
        IHM_ModSettings.DRAG_RESIZE_DEFAULT, "UI_IHM_Opt_DragResize_Tooltip")

    options:addTitle("UI_IHM_Opt_Section_Colors")

    options:addColorPicker("selectedColor", "UI_IHM_Opt_SelectedColor",
        D.selection.r, D.selection.g, D.selection.b, 1, "UI_IHM_Opt_SelectedColor_Tooltip")
    options:addColorPicker("cursorColor", "UI_IHM_Opt_CursorColor",
        D.cursor.r, D.cursor.g, D.cursor.b, 1, "UI_IHM_Opt_CursorColor_Tooltip")

    if type(PZAPI.ModOptions.load) == "function" then
        pcall(function() PZAPI.ModOptions:load() end)
    end

    -- Apply the stored value now, then on every live change.
    for optionId, meta in pairs(COLOR_OPTIONS) do
        local opt = options:getOption(optionId)
        if opt then
            opt.onChange      = function(_, v) applyColor(meta.key, v) end
            opt.onChangeApply = function(_, v) applyColor(meta.key, v) end
            applyColor(meta.key, opt:getValue())
        end
    end

    local dragOpt = options:getOption("dragResize")
    if dragOpt then
        dragOpt.onChange      = function() closeControlsWindow() end
        dragOpt.onChangeApply = function() closeControlsWindow() end
    end

    hookColorPicker()
    hookOptionsPanel()
end

-- MainOptions:create() bakes the swatch button's click handler in as a function
-- *value*, so the wrapper has to be in place before the options screen is built.
-- Mod Lua loads after the base game's, so this normally lands right here; the
-- call in register() is the retry for load orders where it does not.
hookColorPicker()
hookOptionsPanel()

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(register)
end
