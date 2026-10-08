--[[
	Replace the original hair/beard combos with our modal grid menus.

	Highlights:
	- Modal-only hair/beard panels.
	- Top-right cluster inside each panel: [CONTROLS] [Stubble] [Color].
	- Live slider changes (rows/cols/avatar size) via IHM_LiveConfig.
	- Robust rebuild: no nil-calls, modal remains open & focused.
	- Color picker capture to avoid click-through.

	All comments are in English.
]]
if isServer() then return end

--- L'intestazione della creazione personaggio, o nil.
---
--- In B42.20 questa classe non esiste piu': al suo posto ci sono
--- CharacterCreationMain, CharacterCreationAvatar e CharacterCreationProfession.
--- Si chiede con rawget e non la si nomina e basta, perche' e' esattamente il
--- caso in cui un nome puo' non esserci: nominarla direttamente farebbe sembrare
--- che ci sia sempre, e nasconderebbe il fatto che su questa build il ramo
--- buono e' l'altro, quello di CharacterCreationMain.
local function _IHM_ccHeader()
    return rawget(_G, "CharacterCreationHeader")
end

pcall(require, "IHM_ISColorPickerHSB")
require "improvedhairmenu/InGame/IHM_GridControls"
pcall(require, "improvedhairmenu/IHM_NeatStyle")
pcall(require, "improvedhairmenu/IHM_NeatColorPicker")
do
    local LC = rawget(_G, "IHM_LiveConfig")
    if LC and (LC.cache.use_modal == nil or LC.cache.use_modal == false) then
        pcall(function() LC:updateAndSave("use_modal", true) end)
    end
end
local _ok = pcall(require, "improvedhairmenu/ModOptions")
local FONT_HGT_SMALL  = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local function is_low_res()
	-- Vanilla convention; ensure menus stay modal on small screens.
	return (getCore():getScreenHeight() <= 900)
end

-- ======== SMALL UTILITIES =====================================================
local function _clampInt(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return math.floor(v + 0.5)
end

local function _avatarPxFromStep(n, maxStep)
    maxStep = maxStep or 7
    n = _clampInt(n or 5, 1, maxStep)
    return 32 + ((n - 1) * 16)
end

local function _IHM_resolutionScale()
    local h = getCore():getScreenHeight()
    return math.max(1.0, math.min(2.0, h / 1080))
end

local function _IHM_maxAvatarPxForBounds(rows, cols, boundsW, boundsH)
    local screenW = boundsW or getCore():getScreenWidth()
    local screenH = boundsH or getCore():getScreenHeight()

    local maxW = math.max(320, screenW - 80)
    local maxH = math.max(240, screenH - 120)

    local gap = 3
    local reserveW = 40
    local reserveH = 64

    local byW = math.floor((maxW - reserveW - (gap * math.max(0, cols - 1))) / math.max(1, cols))
    local byH = math.floor((maxH - reserveH - (gap * math.max(0, rows - 1))) / math.max(1, rows))

    return math.max(32, math.min(byW, byH))
end

-- Read a live value (IHM_LiveConfig first, then ImprovedHairMenu.settings)
local function _getLive(key, default, legacyKey)
    local LC = rawget(_G, "IHM_LiveConfig")
    if LC and LC.cache then
        if LC.cache[key] ~= nil then
            return LC.cache[key]
        end
        if legacyKey and LC.cache[legacyKey] ~= nil then
            return LC.cache[legacyKey]
        end
    end

    local S = ImprovedHairMenu and ImprovedHairMenu.settings
    if S then
        if S[key] ~= nil then
            return S[key]
        end
        if legacyKey and S[legacyKey] ~= nil then
            return S[legacyKey]
        end
    end

    return default
end

-- Live settings resolver (NO refreshFromPZAPI; trust the live values)
local function _resolveSettings(isBeard)
    local use_modal = true

    local rows = _clampInt(_getLive("cc_modal_rows", 4, "modal_rows"), 1, 10)
    local cols = _clampInt(_getLive("cc_modal_cols", 6, "modal_cols"), 1, 10)
    local avatar_step = _clampInt(_getLive("cc_avatar_size", 6, "avatar_size"), 1, 9)

    local base_avatar_px = _avatarPxFromStep(avatar_step, 9)
    local scaled_avatar_px = math.floor((base_avatar_px * _IHM_resolutionScale()) + 0.5)

    local max_avatar_px = _IHM_maxAvatarPxForBounds(rows, cols)
    local avatar_px = math.max(32, math.min(scaled_avatar_px, max_avatar_px))

    return use_modal, avatar_px, { rows = rows, cols = cols }
end

local function _IHM_getTextOrFallback(key, fallback)
    local txt = getText(key)
    if txt == key then return fallback end
    return txt
end

-- The NeatUI picker is the one we ship; IHM_ISColorPickerHSB stays as a fallback
-- so a failed load of the new file still leaves the toggle working.
local function _IHM_improvedPickerClass()
    return rawget(_G, "IHM_NeatColorPicker") or rawget(_G, "IHM_ISColorPickerHSB")
end

local function _IHM_hasImprovedHairPicker()
    return _IHM_improvedPickerClass() ~= nil
end

-- The picker used to be gated in multiplayer behind a separate empty "ihm_picker"
-- mod, inherited from Improved Hair Menu: the idea was that a server operator
-- opted in before players could pick arbitrary hair colours. That companion mod
-- is not ours and most players never had it, so on a server the option was simply
-- unreachable. Hair colour is cosmetic and lives in the character's HumanVisual,
-- so the picker is now available everywhere.
local function _IHM_isImprovedHairPickerAllowed()
    return true
end

local function _IHM_isImprovedHairPickerEnabled(self)
    if not _IHM_isImprovedHairPickerAllowed() then
        return false
    end

    -- The tick box used to live in character creation; the option moved to the
    -- CONTROLS panel, so the persisted value is now the only source of truth.
    return _getLive("cc_use_improved_hair_picker", true) and true or false
end

local function _IHM_setImprovedHairPickerEnabled(enabled)
    enabled = enabled and true or false

    if enabled and not _IHM_isImprovedHairPickerAllowed() then
        enabled = false
    end

    _G.ImprovedHairMenu = _G.ImprovedHairMenu or {}
    _G.ImprovedHairMenu.settings = _G.ImprovedHairMenu.settings or {}
    _G.ImprovedHairMenu.settings.cc_use_improved_hair_picker = enabled

    local LC = rawget(_G, "IHM_LiveConfig")
    if LC and LC.updateAndSave then
        pcall(function() LC:updateAndSave("cc_use_improved_hair_picker", enabled) end)
    end
end

-- Exposed for the CONTROLS panel, which owns the toggle now.
function IHM_IsHairPickerAllowed()
    return _IHM_hasImprovedHairPicker() and _IHM_isImprovedHairPickerAllowed()
end

local function _IHM_removeHairColorPicker(self)
    if not self or not self.colorPickerHair then return end

    local picker = self.colorPickerHair
    if picker.parent then
        picker.parent:removeChild(picker)
    elseif picker.removeFromUIManager then
        picker:removeFromUIManager()
    end

    self.colorPickerHair = nil
    self._ihmHairPickerImproved = nil
end

local function _IHM_buildHairColorPicker(self, hairColors)
    hairColors = hairColors or self._ihmHairColors or {}
    self._ihmHairColors = hairColors

    _IHM_removeHairColorPicker(self)

    local useImproved = _IHM_hasImprovedHairPicker() and _IHM_isImprovedHairPickerEnabled(self)

    if useImproved then
        local PickerClass = _IHM_improvedPickerClass()
        self.colorPickerHair = PickerClass:new(0, 0, ColorInfo.new())
        self.colorPickerHair:initialise()
        self.colorPickerHair.keepOnScreen = true
        self.colorPickerHair.pickedTarget = self
        self.colorPickerHair.resetFocusTo = self.characterPanel
        -- Hand the game's natural hair shades to the Neat picker so its swatch
        -- row is the vanilla palette rather than an invented one.
        if self.colorPickerHair.setPalette then
            self.colorPickerHair:setPalette(hairColors)
        end
    else
        self.colorPickerHair = ISColorPicker:new(0, 0, nil)
        self.colorPickerHair:initialise()
        self.colorPickerHair.keepOnScreen = true
        self.colorPickerHair.pickedTarget = self
        self.colorPickerHair.resetFocusTo = self.characterPanel
        self.colorPickerHair:setColors(hairColors, math.min(#hairColors, 10), math.ceil(#hairColors / 10))

        local _picked = self.colorPickerHair.picked
        function self.colorPickerHair:picked(hide) _picked(self, hide) end

        local _picked2 = self.colorPickerHair.picked2
        function self.colorPickerHair:picked2(hide) _picked2(self, hide) end
    end

    self._ihmHairPickerImproved = useImproved

    if self.colorPickerHair and self.colorPickerHair.setCapture then
        self.colorPickerHair:setCapture(true)
    end

    return self.colorPickerHair
end

-- Kept as the entry point the CONTROLS panel calls after flipping the option.
function CharacterCreationMain:onHairPickerToggle(index, selected)
    local enabled = selected
        and _IHM_hasImprovedHairPicker()
        and _IHM_isImprovedHairPickerAllowed()

    _IHM_setImprovedHairPickerEnabled(enabled)
    _IHM_buildHairColorPicker(self, self._ihmHairColors or {})
end

-- Bridge: make sure live writes also touch ImprovedHairMenu.settings (if present)
do
	local LC = rawget(_G, "IHM_LiveConfig")
	if LC and not LC._ihm_bridge_patched then
		local orig = LC.updateAndSave
		LC.updateAndSave = function(self, key, val)
			if ImprovedHairMenu and ImprovedHairMenu.settings then
				ImprovedHairMenu.settings[key] = val
			end
			if orig then return orig(self, key, val) end
		end
		LC._ihm_bridge_patched = true
	end
end

-- Returns the *equipped* display name for hair/beard (never nil)
local function _IHM_getEquippedDisplayName(isBeard)
    local desc = MainScreen.instance and MainScreen.instance.desc
    if not desc then return "" end
    local hv  = desc:getHumanVisual()
    local id  = isBeard and hv:getBeardModel() or hv:getHairModel()
    if not id or id == "" then
        return isBeard and getText("IGUI_Beard_None") or getText("IGUI_Hair_None")
    end
    local key = (isBeard and "IGUI_Beard_" or "IGUI_Hair_") .. id
    local txt = getText(key)
    -- getText returns the key itself if missing – guard that:
    if txt == key then
        return (isBeard and "Beard " or "Hair ") .. tostring(id)
    end
    return txt or ""
end

-- ======== LIST BUILDING + POST INIT ==========================================
-- Build the display list (Hair/Beard) with getter/setter names so VisualAvatar can apply models.
local function _IHM_buildListFromGame(desc, isBeard)
    local out = {}
    if not desc then return out end

    local function push(id, disp, getter, setter)
        out[#out+1] = { id = id, display = disp or id, selected = false, getterName = getter, setterName = setter }
    end

    if isBeard then
        local styles = getAllBeardStyles()
        if styles and styles.size then
            for i = 1, styles:size() do
                local id   = styles:get(i-1)
                local disp = (id == "" and getText("IGUI_Beard_None")) or getText("IGUI_Beard_" .. id) or id
                push(id, disp, "getBeardModel", "setBeardModel")
            end
        end
    else
        local female = desc:isFemale()
        local styles = getAllHairStyles(female)
        if styles and styles.size then
            for i = 1, styles:size() do
                local id = styles:get(i-1)
                local label
                if id == "" then label = getText("IGUI_Hair_Bald")
                else label = getText("IGUI_Hair_" .. id) or id end
                local hs = female and getHairStylesInstance():FindFemaleStyle(id) or getHairStylesInstance():FindMaleStyle(id)
                if not hs or not hs:isNoChoose() then
                    push(id, label, "getHairModel", "setHairModel")
                end
            end
        end
    end
    return out
end

-- Desc -> list -> select current -> visuals
local function _IHM_postInitPanel(self, panel, isBeard)
    if not panel then return end
    local desc = MainScreen.instance and MainScreen.instance.desc
    if panel.setDesc then panel:setDesc(desc) end

    local list = _IHM_buildListFromGame(desc, isBeard)
    if panel.setHairList then panel:setHairList(list) end

    -- Mark current selection
    if desc and #list > 0 and panel.setSelectedInfo then
        local hv = desc:getHumanVisual()
        local current = isBeard and hv:getBeardModel() or hv:getHairModel()
        local idx = 1
        for i = 1, #list do if list[i].id == current then idx = i break end end
        panel:setSelectedInfo(list[idx])
    end

    if panel.applyVisual then panel:applyVisual(desc) end
	 if not panel.onSelect then
        panel.onSelect = function(info)
            local desc = MainScreen.instance and MainScreen.instance.desc
            if not desc then return end
            if info and info.id then
                local hv = desc:getHumanVisual()
                if isBeard then hv:setBeardModel(info.id) else hv:setHairModel(info.id) end
            end

            -- Header- oder Main-Avatar aktualisieren
            -- La prima delle due non esiste piu' in B42.20: si chiede con
            -- rawget e, quando manca, si passa alla seconda - che e' quella
            -- vera su questa build.
            local CCH = _IHM_ccHeader()
            local avatarPanel =
                (CCH and CCH.instance and CCH.instance.avatarPanel)
                or
                (CharacterCreationMain and CharacterCreationMain.instance and CharacterCreationMain.instance.avatarPanel)

            if avatarPanel and avatarPanel.setSurvivorDesc then
                avatarPanel:setSurvivorDesc(desc)
            end
            if self.disableBtn then self:disableBtn() end
        end
    end
end

local function _IHM_smallFontHgt()
    return getTextManager():getFontHeight(UIFont.Small)
end

local function _IHM_mediumFontHgt()
    return getTextManager():getFontHeight(UIFont.Medium)
end

local function _IHM_compactButtonH()
    return math.max(20, _IHM_smallFontHgt() + 6)
end

local function _IHM_modalLauncherH()
    local smallH = _IHM_smallFontHgt()
    return math.max(smallH * 2, smallH + 10)
end

--[[ Il tasto che apre il menu capelli o barba.

    E' la ricetta di Neat Rocco, la stessa con cui sostituisce i tasti vanilla
    nella schermata del personaggio: un NI_SquareButton con l'icona da barbiere,
    acceso, con l'arancione NeatUI come colore attivo. Le forbici per i capelli,
    il rasoio per la barba.

    Il testo non si perde: passa nel tooltip, dove non occupa spazio.
]]
local function _IHM_newLauncher(x, y, size, target, onclick, isBeard)
    local NS = rawget(_G, "IHM_NeatStyle")
    local icon = NS and (isBeard and NS.iconRazor() or NS.iconScissors()) or nil
    local accent = NS and NS.color and NS.color.accent or { r = 0.95, g = 0.50, b = 0.10 }

    local btn
    if NS and NS.newSquareButton then
        btn = NS.newSquareButton(x, y, size, icon, target, onclick, accent)
    else
        btn = ISButton:new(x, y, size, size, icon and "" or getText("IGUI_Open"), target, onclick)
        btn:initialise()
        btn:instantiate()
        if icon and btn.setImage then btn:setImage(icon) end
    end

    -- NI_SquareButton legge tabName come tooltip; ISButton lo ignora e non fa
    -- danni, quindi si imposta comunque.
    btn.tabName = getText("IGUI_PlayerStats_Change")
    return btn
end

--- Il lanciatore del menu e' un tasto quadrato con un'icona, non piu' un
--- rettangolo con scritto "Open": e' la stessa forma che ha in gioco nella
--- schermata del personaggio, e usarla anche qui fa leggere le due schermate
--- come la stessa interfaccia.
---
--- Quadrato vuol dire largo quanto e' alto, e tutto cio' che segue nella riga
--- si posiziona leggendo questa misura: cambiare qui basta.
--- Attacca un tooltip Neat a un elemento, al posto di quello vanilla.
---
--- Il tooltip di serie e' un riquadro squadrato con il suo font e i suoi
--- colori: in mezzo a un pannello Neat si vede che viene da un'altra parte.
--- Questo usa la stessa pastiglia dei nomi delle acconciature.
local function _IHM_neatTooltip(el, text)
    if not el or not text or text == "" then return end

    -- Via quello vanilla, altrimenti compaiono tutti e due.
    el.tooltip = nil

    local og = el.prerender
    el.prerender = function(self, ...)
        if og then og(self, ...) end
        if not IHM_NeatTooltip then return end
        if self:isMouseOver() then
            IHM_NeatTooltip.show(text, self:getAbsoluteX(), self:getAbsoluteY(),
                self:getWidth(), self:getHeight())
            self._ihmTipShown = true
        elseif self._ihmTipShown then
            self._ihmTipShown = false
            IHM_NeatTooltip.hide()
        end
    end
end

local function _IHM_openButtonWidth()
    return _IHM_modalLauncherH()
end

local function _IHM_controlsButtonWidth()
    local ctrlLbl = (getText and getText("UI_IHM_Controls")) or "Controls"
    return math.max(60, getTextManager():MeasureStringX(UIFont.Small, ctrlLbl) + 18)
end

local function _IHM_colorSwatchSize()
    return math.max(_IHM_compactButtonH(), _IHM_smallFontHgt() + 4)
end

local function _IHM_colorToRGBA(color)
    if not color then return nil end

    if color.r ~= nil and color.g ~= nil and color.b ~= nil then
        return color.r, color.g, color.b, color.a or 1
    end

    if color.getR and color.getG and color.getB then
        return color:getR(), color:getG(), color:getB(), (color.getA and color:getA()) or 1
    end

    if color.getRedFloat and color.getGreenFloat and color.getBlueFloat then
        return color:getRedFloat(), color:getGreenFloat(), color:getBlueFloat(), 1
    end

    return nil
end

local function _IHM_setSwatchButtonColor(btn, r, g, b, a)
    if not btn then return end
    a = a or 1

    btn.backgroundColor = { r = r, g = g, b = b, a = a }
    btn.backgroundColorMouseOver = {
        r = math.min(1, r + 0.15),
        g = math.min(1, g + 0.15),
        b = math.min(1, b + 0.15),
        a = 1
    }

    if btn.setBorderRGBA then
        btn:setBorderRGBA(0.85, 0.85, 0.85, 0.9)
    end
end

local function _IHM_getCurrentHairRGBA(self)
    local desc = MainScreen.instance and MainScreen.instance.desc
    if desc and desc.getHumanVisual then
        local hv = desc:getHumanVisual()
        if hv and hv.getHairColor then
            local r, g, b, a = _IHM_colorToRGBA(hv:getHairColor())
            if r ~= nil then
                return r, g, b, a
            end
        end
    end

    local btn = self and (self.hairColorMainButton or self.hairColorPreviewButton or self.hairColorButton)
    if btn and btn.backgroundColor then
        return btn.backgroundColor.r, btn.backgroundColor.g, btn.backgroundColor.b, btn.backgroundColor.a or 1
    end

    return 1, 1, 1, 1
end

local function _IHM_syncHairColorButtons(self, color)
    local r, g, b, a = _IHM_colorToRGBA(color)
    if r == nil then
        r, g, b, a = _IHM_getCurrentHairRGBA(self)
    end

    _IHM_setSwatchButtonColor(self.hairColorMainButton, r, g, b, a)
    _IHM_setSwatchButtonColor(self.hairColorPreviewButton or (self.hairMenu and self.hairMenu.hairColorBtn), r, g, b, a)
end

-- ======== TOP-RIGHT CLUSTER (CONTROLS / STUBBLE / COLOR) =====================
function _IHM_layoutTopRightControls(panel)
    if not panel then return end

    local smallH = _IHM_smallFontHgt()
    local pad = math.max(8, math.floor(smallH * 0.5))
    local gap = math.max(6, math.floor(smallH * 0.35))
    local right = panel:getWidth() - pad

    local rowY = pad
    local rowH = _IHM_compactButtonH()
    if panel.pageLeftButton then
        rowY = panel.pageLeftButton:getY()
        rowH = panel.pageLeftButton:getHeight()
    end

    local function place(ctrl)
        if not ctrl then return end
        local cw = ctrl:getWidth()
        local ch = ctrl:getHeight()
        ctrl:setX(right - cw)
        ctrl:setY(rowY + math.floor((rowH - ch) / 2))
        right = right - cw - gap
    end

    -- Placed first, so it ends up furthest right: a close X belongs in the corner.
    place(panel.closeXBtn)
    place(panel.hairColorBtn)
    place(panel.stubbleTickBox)
    place(panel.hairControlsBtn or panel.beardControlsBtn)
end

-- Close the grid controls window if it's open (supports several patterns).
local function _IHM_closeControls(self)
    local W = rawget(_G, "IHM_GridControlsWindow")
    -- 1) Known singleton instance
    if W and W.instance and W.instance.close then
        pcall(function() W.instance:close() end)
    end
    -- 2) getInstance() pattern
    if W and W.getInstance then
        local inst = nil
        pcall(function() inst = W:getInstance() end)
        if inst and inst.close then pcall(function() inst:close() end) end
    end
    -- 3) stored on 'self' when we opened it
    if self and self._ihmControlsWindow and self._ihmControlsWindow.close then
        pcall(function() self._ihmControlsWindow:close() end)
        self._ihmControlsWindow = nil
    end
    -- 4) optional bulk close
    if W and W.closeAll then pcall(function() W:closeAll() end) end
end

-- Computes required min width so header text won't overlap right-side mini controls
local function _IHM_minPanelWidth(panel)
    if not panel then return 260 end

    local tm = getTextManager()
    local font = UIFont.Small
    local smallH = _IHM_smallFontHgt()
    local pad = math.max(8, math.floor(smallH * 0.5))
    local gap = math.max(6, math.floor(smallH * 0.35))

    local leftStart = (panel.pageRightButton and panel.pageRightButton:getRight() or (pad * 2 + _IHM_compactButtonH())) + gap
    local pages = tostring(panel.pageCurrent or 1) .. "/" .. tostring((panel.getNumberOfPages and panel:getNumberOfPages()) or 1)
    local pagesW = tm:MeasureStringX(font, pages)
    -- Reserve width for the header name only when it is actually drawn, otherwise
    -- the title bar keeps a gap for text that is not there.
    local _showHdr = rawget(_G, "IHM_ShowHeaderName")
    local titleW = (_showHdr and _showHdr())
        and tm:MeasureStringX(font, _IHM_getEquippedDisplayName(panel.isBeard)) or 0

    local rightW = 0
    local ctrl = panel.hairControlsBtn or panel.beardControlsBtn
    if panel.closeXBtn then
        rightW = rightW + panel.closeXBtn:getWidth() + gap
    end
    if panel.hairColorBtn then
        rightW = rightW + panel.hairColorBtn:getWidth() + gap
    end
    if panel.stubbleTickBox then
        rightW = rightW + panel.stubbleTickBox:getWidth() + gap
    end
    if ctrl then
        rightW = rightW + ctrl:getWidth() + gap
    end

    local required = leftStart + pagesW + gap + titleW + pad + rightW + pad
    return math.max(260, math.floor(required))
end

-- Clamp rows/cols/avatar to fit on screen; return clamped values + minPanelW
local function _IHM_fitGridToScreen(avatar_px, rows, cols, boundsW, boundsH)
    local screenW = boundsW or getCore():getScreenWidth()
    local screenH = boundsH or getCore():getScreenHeight()
    local maxW = math.max(320, screenW - 80)
    local maxH = math.max(240, screenH - 120)

    local gap = 3
    local reserveW = 40
    local reserveH = 64

    local function fits(a, r, c)
        local panelW = (a * c) + (gap * math.max(0, c - 1)) + reserveW
        local panelH = (a * r) + (gap * math.max(0, r - 1)) + reserveH
        return panelW <= maxW and panelH <= maxH
    end

    local maxAvatar = _IHM_maxAvatarPxForBounds(rows, cols, boundsW, boundsH)
    avatar_px = math.max(32, math.min(math.floor(avatar_px + 0.5), maxAvatar))

    -- Preserve rows/cols first; shrink avatar size before shrinking page layout.
    while avatar_px > 32 and not fits(avatar_px, rows, cols) do
        avatar_px = avatar_px - 4
    end

    -- Fallback only if even 32px avatars don't fit with the chosen rows/cols.
    while not fits(avatar_px, rows, cols) and cols > 1 do
        cols = cols - 1
    end
    while not fits(avatar_px, rows, cols) and rows > 1 do
        rows = rows - 1
    end

    local minPanelW = math.min(maxW, _IHM_minPanelWidth())
    return avatar_px, rows, cols, minPanelW
end

local _IHM_rebuildMenu
--[[ Ensure the in-panel close X exists.

    Character creation used to close the grid with a full-width Close bar under
    the last row. That bar is gone in 1.4.0: the panel is draggable now, so its
    close control has to live *inside* the panel and travel with it - and a red X
    in the header corner is what every other Neat window uses (NI_SquareButton +
    Icon_False + activeColor 0.8/0.2/0.2, see IHM_NeatKit's header).

    Idempotent, so the rebuild path can call it unconditionally. Unlike the colour
    swatch and the stubble tick, this button carries no state, so a rebuild makes
    a fresh one instead of reparenting the old.
]]
local function _IHM_ensureCloseButton(self, panel)
    if not panel or panel.closeXBtn then return end

    local NS   = rawget(_G, "IHM_NeatStyle")
    local size = _IHM_compactButtonH()
    local icon = (NS and NS.iconFalse) and NS.iconFalse() or nil
    local red  = { r = 0.8, g = 0.2, b = 0.2 }

    local onClick = function()
        if panel.close then panel:close()
        elseif panel.onClose then panel.onClose() end
    end

    local btn
    if NS and NS.newSquareButton then
        btn = NS.newSquareButton(0, 0, size, icon, self, onClick, red)
    else
        btn = ISButton:new(0, 0, size, size, icon and "" or "X", self, onClick)
        btn:initialise()
        btn:instantiate()
        if icon and btn.setImage then btn:setImage(icon) end
    end

    panel:addChild(btn)
    panel.closeXBtn = btn
end

-- Ensure the in-panel CONTROLS button exists (works for hair and beard).
-- isBeard = false for hair panel, true for beard panel.
local function _IHM_ensureControlsButton(self, panel, isBeard)
    if not panel then return end

    local ctrlLbl = (getText and getText("UI_IHM_Controls")) or "Controls"
    local ctrlW = _IHM_controlsButtonWidth()
    local ctrlH = _IHM_compactButtonH()
    local propName = isBeard and "beardControlsBtn" or "hairControlsBtn"

    if not panel[propName] then
        local btn = ISButton:new(0, 0, ctrlW, ctrlH, ctrlLbl, self, function()
            local win = IHM_GridControlsWindow.toggleWindow(self, {
                context = "charcreation",
                onChange = function()
                    self._IHM_suppressScrimClose = true
                    if _IHM_rebuildMenu then
                        _IHM_rebuildMenu(self, false)
                        _IHM_rebuildMenu(self, true)
                    end
                    self._IHM_suppressScrimClose = false
                    if self.hairMenu then _IHM_layoutTopRightControls(self.hairMenu) end
                    if self.beardMenu then _IHM_layoutTopRightControls(self.beardMenu) end
                end,
            })
            if win ~= nil then
                self._ihmControlsWindow = win
            end
        end)
        btn:initialise()
        btn:instantiate()
        if btn.setBorderRGBA then btn:setBorderRGBA(0.3, 0.3, 0.3, 0.9) end
        btn:setDisplayBackground(true)
        btn:setBackgroundRGBA(0, 0, 0, 0.15)
        do local NS = rawget(_G, "IHM_NeatStyle"); if NS and NS.styleFullButton then NS.styleFullButton(btn, false) end end

        panel:addChild(btn)
        panel[propName] = btn
    else
        local btn = panel[propName]
        btn:setWidth(ctrlW)
        btn:setHeight(ctrlH)
        panel:addChild(btn)
    end

    _IHM_layoutTopRightControls(panel)
end

-- ======== REBUILD (MODAL-ONLY) ===============================================
function _IHM_rebuildMenu(self, isBeard)
    local _, avatar_px, ms = _resolveSettings(isBeard)
    local pw, ph = self:getWidth(), self:getHeight()
	avatar_px, ms.rows, ms.cols, _IHM_minW = _IHM_fitGridToScreen(avatar_px, ms.rows, ms.cols, pw, ph)

    local panelKey  = isBeard and "beardMenu" or "hairMenu"
    local buttonKey = isBeard and "beardMenuButton" or "hairMenuButton"
    local scrimKey  = isBeard and "beardMenuScrim" or "hairMenuScrim"

    local old = self[panelKey]
    local btn = self[buttonKey]
    local modalOpen = (self[scrimKey] ~= nil) or (btn and btn.expanded)

	local oldOnSelect = old and old.onSelect or nil
    local oldOnClose = old and old.onClose or nil
    local oldColor   = old and old.hairColorBtn or nil
    local oldStubble = old and old.stubbleTickBox or nil
    local oldCtrl    = old and (old.hairControlsBtn or old.beardControlsBtn) or nil

    if old then
        if oldColor   then old:removeChild(oldColor)   end
        if oldStubble then old:removeChild(oldStubble) end
        if oldCtrl    then old:removeChild(oldCtrl)    end
        pcall(function() self:removeChild(old) end)
    end

   local panelType = rawget(_G, "HairMenuPanelModal")
    if not panelType then
        pcall(require, "improvedhairmenu/HairMenuPanelModal")
        panelType = rawget(_G, "HairMenuPanelModal")
    end
    if not panelType then
        pcall(require, "improvedhairmenu/HairMenuPanel")
        panelType = rawget(_G, "HairMenuPanel")
    end
    if not panelType then
        print("[IHM] _IHM_rebuildMenu: No HairMenuPanelModal/HairMenuPanel available; aborting rebuild.")
        return
    end

    local newPanel = panelType:new(0, 0, avatar_px, avatar_px, ms.rows, ms.cols, 3, isBeard)

    -- Cosa fare quando si lascia la maniglia d'angolo. Impostato **prima** di
    -- initialise, che e' dove la maniglia si aggancia e se lo va a leggere.
    local owner = self
    newPanel._ihmApplyGrid = function(cols, rows)
        if IHM_LiveConfig then
            IHM_LiveConfig:updateAndSave("cc_modal_cols", cols)
            IHM_LiveConfig:updateAndSave("cc_modal_rows", rows)
        end
        -- Solo la griglia che si sta trascinando. Prima si rifacevano tutte
        -- e due, capelli e barba, a ogni scatto di conteggio: il doppio del
        -- lavoro per meta' del risultato visibile, ed e' da li' che veniva la
        -- lentezza. L'altra si riallinea da sola quando la si apre, perche'
        -- legge la stessa impostazione.
        owner._IHM_suppressScrimClose = true
        _IHM_rebuildMenu(owner, isBeard)
        owner._IHM_suppressScrimClose = false
    end

    newPanel:initialise()
    _IHM_postInitPanel(self, newPanel, isBeard)
	if oldOnSelect then newPanel.onSelect = oldOnSelect end

    -- Reattach mini-controls
    if oldColor   then newPanel:addChild(oldColor);   newPanel.hairColorBtn   = oldColor   end
    if oldStubble then newPanel:addChild(oldStubble); newPanel.stubbleTickBox = oldStubble end
    if oldCtrl    then
        newPanel:addChild(oldCtrl)
        if isBeard then newPanel.beardControlsBtn = oldCtrl else newPanel.hairControlsBtn = oldCtrl end
    else
        _IHM_ensureControlsButton(self, newPanel, isBeard)
    end
    _IHM_ensureCloseButton(self, newPanel)

    if oldOnClose then newPanel.onClose = oldOnClose end
    self[panelKey] = newPanel
    if btn then btn.attachedMenu = newPanel end

    -- -------- width clamp incl. equipped title + right cluster, then center grid
    do
        local sw   = getCore():getScreenWidth()
        local maxW = math.max(320, sw - 80)
        local w0   = newPanel:getWidth()

        local pad, gap = 8, 6
        local tm, font = getTextManager(), UIFont.Small

        local arrowsW = 0
        if newPanel.pageLeftButton  then arrowsW = arrowsW + newPanel.pageLeftButton:getWidth()  end
        if newPanel.pageRightButton then arrowsW = arrowsW + newPanel.pageRightButton:getWidth() end
        local pagesStr = tostring(newPanel.pageCurrent or 1) .. "/" ..
                         tostring((newPanel.getNumberOfPages and newPanel:getNumberOfPages()) or 1)
        local pagesW   = tm:MeasureStringX(font, pagesStr)

        local _showHdr = rawget(_G, "IHM_ShowHeaderName")
        local titleW = (_showHdr and _showHdr())
            and tm:MeasureStringX(font, _IHM_getEquippedDisplayName(isBeard) or "") or 0

        local leftW = pad + arrowsW + gap + pagesW + gap + titleW + pad

        local rightW = pad
        local ctrl = newPanel.hairControlsBtn or newPanel.beardControlsBtn
        if ctrl                 then rightW = rightW + ctrl:getWidth()                 + gap end
        if newPanel.stubbleTickBox then rightW = rightW + newPanel.stubbleTickBox:getWidth() + gap end
        if newPanel.hairColorBtn   then rightW = rightW + newPanel.hairColorBtn:getWidth()   + gap end
        if newPanel.closeXBtn      then rightW = rightW + newPanel.closeXBtn:getWidth()      + gap end
        rightW = rightW + pad

        local minHeaderW = leftW + rightW

        local minGeneric = _IHM_minW or 260
        local targetW    = math.min(maxW, math.max(w0, minGeneric, minHeaderW)) + 8 

        if targetW ~= w0 and newPanel.setWidth then
            newPanel:setWidth(targetW)
        end

        local gridW = (newPanel.gridCols * newPanel.gridSizeX) + (newPanel.gap * (newPanel.gridCols - 1))
        local left  = math.max(8, math.floor((newPanel:getWidth() - gridW) / 2))

        if newPanel.avatarList then
            for i = 1, #newPanel.avatarList do
                local av = newPanel.avatarList[i]
                if av then
                    local col = ((i - 1) % newPanel.gridCols) + 1
                    local x   = left + (col - 1) * (newPanel.gridSizeX + newPanel.gap)
                    av:setX(x)
                end
            end
        end
    end
    -- ---------------------------------------------------------------------------

    if modalOpen then
        -- Keep it open and centered; keep button expanded & focus
        self:addChild(newPanel)
        newPanel:setX((self:getWidth()  / 2) - (newPanel:getWidth()  / 2))
        newPanel:setY((self:getHeight() / 2) - (newPanel:getHeight() / 2))
        if newPanel.bringToTop then newPanel:bringToTop() end
        if btn then btn.expanded = true end
        if newPanel.setJoypadFocused then newPanel:setJoypadFocused(true, nil) end
    end

    _IHM_layoutTopRightControls(newPanel)
end

-- ======== COLOR PICKER: APPLY TO BOTH GRIDS ==================================
local _IHM_onHairColorPicked = CharacterCreationMain.onHairColorPicked
function CharacterCreationMain:onHairColorPicked(color, mouseUp)
    _IHM_onHairColorPicked(self, color, mouseUp)

    _IHM_syncHairColorButtons(self, color)

    local desc = MainScreen.instance and MainScreen.instance.desc
    if not desc then return end

    local CCH = _IHM_ccHeader()
    local header = CCH and CCH.instance
    if header and header.avatarPanel and header.avatarPanel.setSurvivorDesc then
        header.avatarPanel:setSurvivorDesc(desc)
    end

    local function refreshGrid(panel)
        if not panel then return end
        if panel.setDesc then panel:setDesc(desc) end
        if panel.applyVisual then panel:applyVisual(desc) end
    end

    refreshGrid(self.hairMenu)
    refreshGrid(self.beardMenu)

    if self.disableBtn then self:disableBtn() end
end

--################################################################################
--## Hair Styles (modal only)                                                    ##
--################################################################################
-- Queste due (capelli e barba) sono le uniche che NON richiamano la versione
-- precedente, e non e' una svista.
--
-- createNameAndGender la richiama, perche' li' ci limitiamo ad aggiungere un
-- titolo sopra: il nome, il cognome e il sesso li costruisce ancora chi c'era
-- prima di noi. Qui no: la sezione capelli **prende il posto** di quella di
-- vanilla, tendina compresa, e la sostituisce con una griglia. Chiamare la
-- precedente costruirebbe due sezioni capelli, una sopra l'altra, con gli stessi
-- campi su `self` a puntare ai widget sbagliati.
--
-- Il prezzo lo paga chi ha appeso un controllo dentro queste due funzioni prima
-- che caricassimo noi: il suo controllo non viene costruito. Non possiamo
-- eseguirlo senza eseguire anche vanilla, che sta nello stesso corpo. Per non
-- lasciare il guasto muto, la versione precedente resta raggiungibile qui sotto
-- e la sostituzione viene scritta nel log una volta per avvio: cosi' chi cerca
-- il proprio controllo scomparso trova almeno da dove partire.
--
-- Chi invece carica DOPO di noi non ha alcun problema: avvolge la nostra e
-- appende sotto, come farebbe con vanilla.
CharacterCreationMain.IHM_previous_createHairTypeBtn  = CharacterCreationMain.createHairTypeBtn
CharacterCreationMain.IHM_previous_createBeardTypeBtn = CharacterCreationMain.createBeardTypeBtn

Events.OnGameBoot.Add(function()
    print("[NeatUI Hairstyler] createHairTypeBtn/createBeardTypeBtn replaced: the drop-down becomes a grid. "
        .. "A mod that added controls inside those two functions and loaded BEFORE this one will not build them. "
        .. "The previous implementations are kept as CharacterCreationMain.IHM_previous_createHairTypeBtn "
        .. "and .IHM_previous_createBeardTypeBtn. createNameAndGender chains and is not affected.")
end)

function CharacterCreationMain:createHairTypeBtn()
    local use_modal, avatar_size, menu_size = _resolveSettings(false)
    local smallH = _IHM_smallFontHgt()
    local mediumH = _IHM_mediumFontHgt()
    local comboHgt = math.max(24, smallH + 6)
    local openBtnW = _IHM_openButtonWidth()
    local openBtnH = _IHM_modalLauncherH()
    local swatchSize = _IHM_colorSwatchSize()
    local sectionGap = math.max(5, math.floor(smallH * 0.4))

    local x0 = self.xOffset or 0
    local w0 = self.comboWid or 0

    local lbl = ISLabel:new(x0, self.yOffset, mediumH, getText("UI_characreation_hair"), 1, 1, 1, 1, UIFont.Medium, true)
    lbl:initialise()
    lbl:instantiate()
    self.characterPanel:addChild(lbl)
    self.hairLbl = lbl

    local rect = ISRect:new(x0, self.yOffset + mediumH + sectionGap, math.max(300, w0), 1, 1, 0.3, 0.3, 0.3)
    rect:setAnchorRight(false)
    rect:initialise()
    rect:instantiate()
    self.characterPanel:addChild(rect)
    self.hairRect = rect

    self.yOffset = self.yOffset + mediumH + (sectionGap * 2)

    self.hairTypeCombo = ISComboBox:new(x0 + 90, self.yOffset, w0, comboHgt, self, CharacterCreationMain.onHairTypeSelected)
    self.hairTypeCombo:initialise()
    self.characterPanel:addChild(self.hairTypeCombo)
    self.hairTypeCombo:setVisible(false)
    self.hairType = 0

    local panelType = rawget(_G, "HairMenuPanelModal")
    if not panelType then
        pcall(require, "improvedhairmenu/HairMenuPanelModal")
        panelType = rawget(_G, "HairMenuPanelModal")
    end
    if not panelType then
        pcall(require, "improvedhairmenu/HairMenuPanel")
        panelType = rawget(_G, "HairMenuPanel")
    end

    self.hairMenu = panelType:new(x0, self.yOffset, avatar_size, avatar_size, menu_size.rows, menu_size.cols, 3, false)
    self.hairMenu:initialise()
    _IHM_postInitPanel(self, self.hairMenu, false)

    self.hairMenu.onSelect = function(info)
        local desc = MainScreen.instance and MainScreen.instance.desc
        if not desc then return end

        self.hairType = 1
        if info and info.id then
            desc:getHumanVisual():setHairModel(info.id)
        end

        local CCH = _IHM_ccHeader()
        local avatarPanel =
            (CCH and CCH.instance and CCH.instance.avatarPanel)
            or
            (CharacterCreationMain and CharacterCreationMain.instance and CharacterCreationMain.instance.avatarPanel)

        if avatarPanel and avatarPanel.setSurvivorDesc then
            avatarPanel:setSurvivorDesc(desc)
        end

        if self.disableBtn then self:disableBtn() end
        -- La griglia resta aperta dopo la scelta: si chiude con la sua X. Le
        -- alternative si guardano una dopo l altra, ed e per questo che
        -- esiste una griglia invece di un elenco a tendina.
    end

    if use_modal then
        local function makeScrim(parent, closeFn)
            local scrim = ISPanel:new(0, 0, parent:getWidth(), parent:getHeight())
            scrim:initialise()
            scrim:instantiate()
            scrim.background = true
            scrim.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
            scrim:setAnchorRight(true)
            scrim:setAnchorBottom(true)
            function scrim:onMouseDown(...) return true end
            function scrim:onRightMouseDown(...) return true end
            function scrim:onMouseUp(...)
                if parent._IHM_suppressScrimClose then return true end
                -- Anche il velo dietro chiude al clic, e trascinando l angolo
                -- verso l esterno il rilascio ci finisce sopra.
                if IHM_GridResize and IHM_GridResize.isResizing() then return true end
                closeFn()
                return true
            end
            function scrim:onRightMouseUp(...)
                if parent._IHM_suppressScrimClose then return true end
                -- Anche il velo dietro chiude al clic, e trascinando l angolo
                -- verso l esterno il rilascio ci finisce sopra.
                if IHM_GridResize and IHM_GridResize.isResizing() then return true end
                closeFn()
                return true
            end
            return scrim
        end

        local function showMenu(target)
            target.hairMenuScrim = makeScrim(target, function()
                if target.hairMenu and target.hairMenu.onClose then target.hairMenu:onClose() end
            end)
            target:addChild(target.hairMenuScrim)

            _IHM_rebuildMenu(target, false)

            target.hairMenuButton.expanded = true
            if target.hairMenuButton.attachedMenu and target.hairMenuButton.attachedMenu.setJoypadFocused then
                target.hairMenuButton.attachedMenu:setJoypadFocused(true, nil)
            end

            target:removeChild(target.hairMenu)
            target:addChild(target.hairMenu)
            target.hairMenu:setX((target:getWidth() / 2) - (target.hairMenu:getWidth() / 2))
            target.hairMenu:setY((target:getHeight() / 2) - (target.hairMenu:getHeight() / 2))
            _IHM_layoutTopRightControls(target.hairMenu)
        end

        self.hairMenu.onClose = function()
            self:removeChild(self.hairMenu)
            if self.hairMenuScrim then
                self:removeChild(self.hairMenuScrim)
                self.hairMenuScrim = nil
            end
            if self.hairMenuButton then
                self.hairMenuButton.expanded = false
                self.hairMenuButton.attachedMenu:setJoypadFocused(false, nil)
            end
            _IHM_closeControls(self)
        end

        local launcherY = self.yOffset
        local launcherGap = math.max(6, math.floor(smallH * 0.35))
        local mainSwatchSize = openBtnH

        self.hairMenuButton = _IHM_newLauncher(x0, launcherY, openBtnH, self, showMenu, false)
        self.hairMenuButton.isHairMenuButton = true
        self.hairMenuButton.isButton = nil
        self.hairMenuButton.expanded = false
        self.hairMenuButton.attachedMenu = self.hairMenu

        local setJoypadFocused = self.hairMenuButton.setJoypadFocused
        self.hairMenuButton.setJoypadFocused = function(btn, focused, joypadData)
            btn.focused = focused
            if btn.expanded then
                btn.attachedMenu:setJoypadFocused(focused, joypadData)
            else
                btn.attachedMenu:setJoypadFocused(false, joypadData)
            end
            setJoypadFocused(btn, focused, joypadData)
        end

        self.characterPanel:addChild(self.hairMenuButton)

        self.hairColorMainButton = ISButton:new(
            x0 + openBtnW + launcherGap,
            launcherY + math.floor((openBtnH - mainSwatchSize) / 2),
            mainSwatchSize,
            mainSwatchSize,
            "",
            self,
            CharacterCreationMain.onHairColorMouseDown
        )
        self.hairColorMainButton:initialise()
        self.hairColorMainButton:instantiate()
        do local NS = rawget(_G, "IHM_NeatStyle"); if NS and NS.styleSwatchButton then NS.styleSwatchButton(self.hairColorMainButton) end end
        self.characterPanel:addChild(self.hairColorMainButton)

        self.yOffset = launcherY + math.max(self.hairMenuButton:getHeight(), self.hairColorMainButton:getHeight()) + sectionGap
    else
        self.characterPanel:addChild(self.hairMenu)
        self.yOffset = self.yOffset + self.hairMenu:getHeight() + sectionGap
    end

    local hairColors = MainScreen.instance.desc:getCommonHairColor()
    local hairColors1 = {}
    local info = ColorInfo.new()
    for i = 1, hairColors:size() do
        local c = hairColors:get(i - 1)
        info:set(c:getRedFloat(), c:getGreenFloat(), c:getBlueFloat(), 1)
        table.insert(hairColors1, { r = info:getR(), g = info:getG(), b = info:getB() })
    end

    local hairColorBtn = ISButton:new(0, 0, swatchSize, swatchSize, "", self, CharacterCreationMain.onHairColorMouseDown)
    hairColorBtn:initialise()
    hairColorBtn:instantiate()
    do local NS = rawget(_G, "IHM_NeatStyle"); if NS and NS.styleSwatchButton then NS.styleSwatchButton(hairColorBtn) end end

    local color = hairColors1[1]
    _IHM_setSwatchButtonColor(hairColorBtn, color.r, color.g, color.b, 1)

    self.hairMenu:addChild(hairColorBtn)
    self.hairMenu.hairColorBtn = hairColorBtn
    self.hairColorPreviewButton = hairColorBtn

    self.hairColorButton = self.hairColorMainButton or hairColorBtn
    self._ihmHairColors = hairColors1

    local pickerAllowed = _IHM_hasImprovedHairPicker() and _IHM_isImprovedHairPickerAllowed()

    -- The "Improved Color Picker" tick box used to sit here, eating a row of the
    -- character panel. It is a CONTROLS entry now, next to the other preview
    -- options, and it is on by default.
    self.hairPickerToggleLbl = nil
    self.hairPickerToggle = nil
    if not pickerAllowed then
        _IHM_setImprovedHairPickerEnabled(false)
    end

    _IHM_buildHairColorPicker(self, hairColors1)

    self.hairStubbleLbl = ISLabel:new(x0, self.yOffset + smallH, comboHgt, getText("UI_Stubble"), 1, 1, 1, 1, UIFont.Small)
    self.hairStubbleLbl:initialise()
    self.hairStubbleLbl:instantiate()
    self.characterPanel:addChild(self.hairStubbleLbl)

    local tickSize = math.max(16, smallH + 2)
    self.hairStubbleTickBox = ISTickBox:new(0, 0, tickSize, tickSize, "", self, CharacterCreationMain.onShavedHairSelected)
    self.hairStubbleTickBox:initialise()
    self.hairStubbleTickBox:addOption("")
    _IHM_neatTooltip(self.hairStubbleTickBox, getText("UI_IHM_Stubble_Tooltip"))
    do local NS = rawget(_G, "IHM_NeatStyle"); if NS and NS.styleTickBox then NS.styleTickBox(self.hairStubbleTickBox) end end
    self.hairMenu:addChild(self.hairStubbleTickBox)
    self.hairMenu.stubbleTickBox = self.hairStubbleTickBox

    _IHM_ensureCloseButton(self, self.hairMenu)
    _IHM_ensureControlsButton(self, self.hairMenu, false)
    _IHM_layoutTopRightControls(self.hairMenu)
    _IHM_syncHairColorButtons(self)
end

-- Color picker mouse capture to prevent click-through on tiles
local base_CharacterCreationMain_onHairColorMouseDown = CharacterCreationMain.onHairColorMouseDown
function CharacterCreationMain:onHairColorMouseDown(button, x, y)
    local previousHairColorButton = self.hairColorButton

    if button then
        self.hairColorButton = button
    end

    local wantsImproved = _IHM_hasImprovedHairPicker() and _IHM_isImprovedHairPickerEnabled(self)
    if self._ihmHairPickerImproved ~= wantsImproved then
        _IHM_buildHairColorPicker(self, self._ihmHairColors or {})
    end

    base_CharacterCreationMain_onHairColorMouseDown(self, button, x, y)

    self.hairColorButton = self.hairColorMainButton or self.hairColorPreviewButton or button or previousHairColorButton

    if wantsImproved and self.colorPickerHair then
        local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
        if MainScreen and MainScreen.instance and MainScreen.instance.isReallyVisible and MainScreen.instance:isReallyVisible() then
            w, h = MainScreen.instance:getWidth(), MainScreen.instance:getHeight()
        end

        local pw = self.colorPickerHair:getWidth()
        local ph = self.colorPickerHair:getHeight()

        local cx = math.floor((w - pw) / 2)
        local cy = math.floor((h - ph) / 2) - 40
        if cx < 0 then cx = 0 end
        if cy < 0 then cy = 0 end

        self.colorPickerHair:setX(cx)
        self.colorPickerHair:setY(cy)
    end

    if self.colorPickerHair and self.colorPickerHair.setCapture then
        self.colorPickerHair:setCapture(true)
    end
end

--################################################################################
--## Beard Styles (modal only)                                                   ##
--################################################################################
function CharacterCreationMain:createBeardTypeBtn()
    local use_modal, avatar_size, menu_size = _resolveSettings(true)
    local smallH = _IHM_smallFontHgt()
    local mediumH = _IHM_mediumFontHgt()
    local comboHgt = math.max(24, smallH + 6)
    local openBtnW = _IHM_openButtonWidth()
    local openBtnH = _IHM_modalLauncherH()
    local sectionGap = math.max(5, math.floor(smallH * 0.4))

    local x0 = self.xOffset or 0
    local w0 = self.comboWid or 0

    self.beardLbl = ISLabel:new(x0, self.yOffset, mediumH, getText("UI_characreation_beard"), 1, 1, 1, 1, UIFont.Medium, true)
    self.beardLbl:initialise()
    self.beardLbl:instantiate()
    self.beardLbl:setVisible(false)
    self.characterPanel:addChild(self.beardLbl)

    self.beardRect = ISRect:new(x0, self.yOffset + mediumH + sectionGap, math.max(300, w0), 1, 1, 0.3, 0.3, 0.3)
    self.beardRect:setAnchorRight(false)
    self.beardRect:initialise()
    self.beardRect:instantiate()
    self.beardRect:setVisible(false)
    self.characterPanel:addChild(self.beardRect)

    self.yOffset = self.yOffset + mediumH + (sectionGap * 2)

    self.beardTypeLbl = ISLabel:new(x0 + 70, self.yOffset, comboHgt, getText("UI_characreation_beardtype"), 1, 1, 1, 1, UIFont.Small)
    self.beardTypeLbl:initialise()
    self.beardTypeLbl:instantiate()
    self.beardTypeLbl:setVisible(false)
    self.characterPanel:addChild(self.beardTypeLbl)

    self.beardTypeCombo = ISComboBox:new(x0 + 90, self.yOffset, w0, comboHgt, self, CharacterCreationMain.onBeardTypeSelected)
    self.beardTypeCombo:initialise()
    self.beardTypeCombo:setVisible(false)
    self.characterPanel:addChild(self.beardTypeCombo)

    local panelType = rawget(_G, "HairMenuPanelModal")
    if not panelType then
        pcall(require, "improvedhairmenu/HairMenuPanelModal")
        panelType = rawget(_G, "HairMenuPanelModal")
    end
    if not panelType then
        pcall(require, "improvedhairmenu/HairMenuPanel")
        panelType = rawget(_G, "HairMenuPanel")
    end

    self.beardMenu = panelType:new(x0, self.yOffset, avatar_size, avatar_size, menu_size.rows, menu_size.cols, 3, true)
    self.beardMenu:initialise()
    _IHM_postInitPanel(self, self.beardMenu, true)

    self.beardMenu.onSelect = function(info)
        local desc = MainScreen.instance and MainScreen.instance.desc
        if not desc then return end

        if info and info.id then
            desc:getHumanVisual():setBeardModel(info.id)
        end

        local CCH = _IHM_ccHeader()
        local avatarPanel =
            (CCH and CCH.instance and CCH.instance.avatarPanel)
            or
            (CharacterCreationMain and CharacterCreationMain.instance and CharacterCreationMain.instance.avatarPanel)

        if avatarPanel and avatarPanel.setSurvivorDesc then
            avatarPanel:setSurvivorDesc(desc)
        end

        if self.disableBtn then self:disableBtn() end
        -- Come sopra: si chiude solo con la X.
    end

    if use_modal then
        local function makeScrim(parent, closeFn)
            local scrim = ISPanel:new(0, 0, parent:getWidth(), parent:getHeight())
            scrim:initialise()
            scrim:instantiate()
            scrim.background = true
            scrim.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
            scrim:setAnchorRight(true)
            scrim:setAnchorBottom(true)
            function scrim:onMouseDown(...) return true end
            function scrim:onRightMouseDown(...) return true end
            function scrim:onMouseUp(...)
                if parent._IHM_suppressScrimClose then return true end
                -- Anche il velo dietro chiude al clic, e trascinando l angolo
                -- verso l esterno il rilascio ci finisce sopra.
                if IHM_GridResize and IHM_GridResize.isResizing() then return true end
                closeFn()
                return true
            end
            function scrim:onRightMouseUp(...)
                if parent._IHM_suppressScrimClose then return true end
                -- Anche il velo dietro chiude al clic, e trascinando l angolo
                -- verso l esterno il rilascio ci finisce sopra.
                if IHM_GridResize and IHM_GridResize.isResizing() then return true end
                closeFn()
                return true
            end
            return scrim
        end

        local function showMenu(target)
            target.beardMenuScrim = makeScrim(target, function()
                if target.beardMenu and target.beardMenu.onClose then target.beardMenu:onClose() end
            end)
            target:addChild(target.beardMenuScrim)

            _IHM_rebuildMenu(target, true)

            target.beardMenuButton.expanded = true
            if target.beardMenuButton.attachedMenu and target.beardMenuButton.attachedMenu.setJoypadFocused then
                target.beardMenuButton.attachedMenu:setJoypadFocused(true, nil)
            end

            target:removeChild(target.beardMenu)
            target:addChild(target.beardMenu)
            target.beardMenu:setX((target:getWidth() / 2) - (target.beardMenu:getWidth() / 2))
            target.beardMenu:setY((target:getHeight() / 2) - (target.beardMenu:getHeight() / 2))
            _IHM_layoutTopRightControls(target.beardMenu)
        end

        self.beardMenu.onClose = function()
            self:removeChild(self.beardMenu)
            if self.beardMenuScrim then
                self:removeChild(self.beardMenuScrim)
                self.beardMenuScrim = nil
            end
            if self.beardMenuButton then
                self.beardMenuButton.expanded = false
                self.beardMenuButton.attachedMenu:setJoypadFocused(false, nil)
            end
            _IHM_closeControls(self)
        end

        self.beardMenuButton = _IHM_newLauncher(x0, self.yOffset, openBtnH, self, showMenu, true)
        self.beardMenuButton.isHairMenuButton = true
        self.beardMenuButton.isButton = nil
        self.beardMenuButton.expanded = false
        self.beardMenuButton.attachedMenu = self.beardMenu

        local setJoypadFocused = self.beardMenuButton.setJoypadFocused
        self.beardMenuButton.setJoypadFocused = function(btn, focused, joypadData)
            btn.focused = focused
            if btn.expanded then
                btn.attachedMenu:setJoypadFocused(focused, joypadData)
            else
                btn.attachedMenu:setJoypadFocused(false, joypadData)
            end
            setJoypadFocused(btn, focused, joypadData)
        end

        self.characterPanel:addChild(self.beardMenuButton)
        self.yOffset = self.yOffset + self.beardMenuButton:getHeight() + sectionGap
    else
        self.characterPanel:addChild(self.beardMenu)
        self.yOffset = self.yOffset + self.beardMenu:getHeight() + sectionGap
    end

    self.beardStubbleLbl = ISLabel:new(x0 + 70, self.yOffset, comboHgt, getText("UI_Stubble"), 1, 1, 1, 1, UIFont.Small)
    self.beardStubbleLbl:initialise()
    self.beardStubbleLbl:instantiate()
    self.characterPanel:addChild(self.beardStubbleLbl)

    local tickSize = math.max(16, smallH + 2)
    self.beardStubbleTickBox = ISTickBox:new(0, 0, tickSize, tickSize, "", self, CharacterCreationMain.onBeardStubbleSelected)
    self.beardStubbleTickBox:initialise()
    self.beardStubbleTickBox:addOption("")
    _IHM_neatTooltip(self.beardStubbleTickBox, getText("UI_IHM_Stubble_Tooltip"))
    do local NS = rawget(_G, "IHM_NeatStyle"); if NS and NS.styleTickBox then NS.styleTickBox(self.beardStubbleTickBox) end end
    self.beardMenu:addChild(self.beardStubbleTickBox)
    self.beardMenu.stubbleTickBox = self.beardStubbleTickBox

    _IHM_ensureCloseButton(self, self.beardMenu)
    _IHM_ensureControlsButton(self, self.beardMenu, true)
    _IHM_layoutTopRightControls(self.beardMenu)

    self.yOffset = self.yOffset + comboHgt + sectionGap
end
