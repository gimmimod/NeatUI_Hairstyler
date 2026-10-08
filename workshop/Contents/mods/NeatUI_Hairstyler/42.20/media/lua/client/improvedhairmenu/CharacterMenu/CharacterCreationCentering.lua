if isServer() then return end

local function IHM_CC_GetExtraGapToAvatar()
	local screenW = getCore():getScreenWidth()

	local minWidth = 1920
	local maxWidth = 3840
	local minGap = 0
	local maxGap = 48

	if screenW <= minWidth then
		return minGap
	end

	if screenW >= maxWidth then
		return maxGap
	end

	local t = (screenW - minWidth) / (maxWidth - minWidth)
	return math.floor(minGap + (maxGap - minGap) * t + 0.5)
end

local function IHM_CC_GetTargetControlWidth()
	local screenW = getCore():getScreenWidth()

	local minWidth = 1920
	local maxWidth = 3840
	local minControlWidth = 300
	local maxControlWidth = 420

	if screenW <= minWidth then
		return minControlWidth
	end

	if screenW >= maxWidth then
		return maxControlWidth
	end

	local t = (screenW - minWidth) / (maxWidth - minWidth)
	return math.floor(minControlWidth + (maxControlWidth - minControlWidth) * t + 0.5)
end

local function IHM_CC_GetCenteredLayout(main)
	if not main or not main.characterPanel then
		return 0, 0, 0
	end

	local panel = main.characterPanel
	if panel.scrollBar ~= panel:isVScrollBarVisible() then
		panel.scrollBar = panel:isVScrollBarVisible()
	end

	local UI_BORDER_SPACING = 10
	local scrollbarWidth = 13
	local multiplier = (panel.scrollBar and 1 or 0) * (UI_BORDER_SPACING + scrollbarWidth)

	local columnWidth = panel.columnWidth or main.columnWidth or 0
	local targetControlWidth = IHM_CC_GetTargetControlWidth()
	local maxWidth = columnWidth + targetControlWidth + UI_BORDER_SPACING

	local vanillaXOffset = math.max(panel.width - maxWidth, 0)
	local extraGap = IHM_CC_GetExtraGapToAvatar()
	local xOffset = math.max(vanillaXOffset - extraGap, 0)

	local dividerWidth = math.max(math.min(panel.width, maxWidth) - multiplier, 0)
	local comboWidth = math.max(math.min(targetControlWidth, panel.width - columnWidth - UI_BORDER_SPACING) - multiplier, 0)

	return xOffset, dividerWidth, comboWidth
end

local function IHM_CC_GetCharacterHeaderText()
	local text = getText("UI_characreation_character")
	if text == "UI_characreation_character" then
		return "Character"
	end
	return text
end

local function IHM_ApplyCharacterCreationCentering()
	if not CharacterCreationMainCharacterPanel or not CharacterCreationMain then
		return
	end

	if CharacterCreationMain.TTF_IHM_CharacterCenteringApplied then
		return
	end

	CharacterCreationMain.TTF_IHM_CharacterCenteringApplied = true

	function CharacterCreationMain:TTF_IHM_ApplyCenteredControlsLayout(xOffset, dividerWidth, comboWidth)
		local smallH = getTextManager():getFontHeight(UIFont.Small)
		local launcherGap = math.max(6, math.floor(smallH * 0.35))

		self.xOffset = xOffset
		self.comboWid = comboWidth

		if self.hairLbl then
			self.hairLbl:setX(xOffset)
		end
		if self.hairRect then
			self.hairRect:setX(xOffset)
			self.hairRect:setWidth(dividerWidth)
		end
		if self.hairTypeCombo then
			self.hairTypeCombo:setX(xOffset + 90)
			self.hairTypeCombo:setWidth(comboWidth)
		end
		if self.hairMenuButton then
			self.hairMenuButton:setX(xOffset)
		end
		if self.hairColorMainButton and self.hairMenuButton then
			self.hairColorMainButton:setX(xOffset + self.hairMenuButton:getWidth() + launcherGap)
		end
		if self.hairStubbleLbl then
			self.hairStubbleLbl:setX(xOffset)
		end
		if self.hairMenu and self.hairMenu:getParent() == self.characterPanel then
			self.hairMenu:setX(xOffset)
		end

		if self.beardLbl then
			self.beardLbl:setX(xOffset)
		end
		if self.beardRect then
			self.beardRect:setX(xOffset)
			self.beardRect:setWidth(dividerWidth)
		end
		if self.beardTypeLbl then
			self.beardTypeLbl:setX(xOffset + 70)
		end
		if self.beardTypeCombo then
			self.beardTypeCombo:setX(xOffset + 90)
			self.beardTypeCombo:setWidth(comboWidth)
		end
		if self.beardMenuButton then
			self.beardMenuButton:setX(xOffset)
		end
		if self.beardStubbleLbl then
			self.beardStubbleLbl:setX(xOffset + 70)
		end
		if self.beardMenu and self.beardMenu:getParent() == self.characterPanel then
			self.beardMenu:setX(xOffset)
		end
	end

    function CharacterCreationMainCharacterPanel:positionRelativeToScrollBar()
        if self.scrollBar ~= self:isVScrollBarVisible() then
            self.scrollBar = self:isVScrollBarVisible()
        end

        local UI_BORDER_SPACING = 10
        local scrollbarWidth = 13
        local multiplier = (self.scrollBar and 1 or 0) * (UI_BORDER_SPACING + scrollbarWidth)

        local xOffset, dividerWidth, comboWidth = IHM_CC_GetCenteredLayout(self.parent)

        for _,v in pairs(self.reposTable) do
            v:setX(xOffset)
        end

        for _,v in pairs(self.repos2Table) do
            v:setX(xOffset + self.columnWidth - v:getWidth())
        end

        for _,v in pairs(self.repos3Table) do
            v:setX(xOffset + self.columnWidth + UI_BORDER_SPACING)
        end

        for _,v in pairs(self.dividerResizeTable) do
            v:setWidth(dividerWidth)
            v:setX(xOffset)
        end

        for _,v in pairs(self.comboResizeTable) do
            v:setWidth(comboWidth)
        end

        if self.parent and self.parent.characterHeaderLbl then
            self.parent.characterHeaderLbl:setX(math.max(self.width - multiplier - self.parent.characterHeaderLbl:getWidth(), 0))
        end

        if self.parent and self.parent.characterHeaderRect then
            self.parent.characterHeaderRect:setX(0)
            self.parent.characterHeaderRect:setWidth(math.max(self.width - multiplier, 0))
        end

        if self.parent and self.parent.TTF_IHM_ApplyCenteredControlsLayout then
            self.parent:TTF_IHM_ApplyCenteredControlsLayout(xOffset, dividerWidth, comboWidth)
        end
    end

	-- Il titolo "Character" e la riga sotto sono roba nostra: vanilla non li ha,
	-- e vanno SOPRA il nome. Quindi si costruiscono prima, si sposta yOffset, e
	-- il resto - nome, cognome, sesso - lo fa la funzione che c'era gia'.
	--
	-- Prima riscrivevamo anche quella parte, ricopiandola da vanilla. Due danni,
	-- tutti e due silenziosi:
	--
	--   * si perdeva quello che vanilla ci aveva messo dentro nel frattempo. Il
	--     tasto per svuotare i campi di nome e cognome (`setClearButton`) c'e'
	--     in vanilla e da noi era sparito, senza che nessuno se ne accorgesse;
	--   * si buttava via il lavoro di chiunque altro avesse messo mano alla
	--     stessa funzione. Chi appende un controllo qui dentro - un selettore di
	--     specie, per dire - se lo vedeva sparire senza un errore e senza una
	--     riga nel log: la mod sembrava semplicemente non funzionare.
	--
	-- Il richiamo si prende **qui**, dentro OnGameBoot, non a caricamento del
	-- file: a quel punto ogni mod ha gia' caricato il suo Lua, quindi quella che
	-- chiamiamo e' l'ultima versione installata e non per forza quella di
	-- vanilla. Arrivare per ultimi, che prima era il problema, cosi' diventa il
	-- vantaggio: li avvolgiamo tutti invece di scavalcarli.
	local previousCreateNameAndGender = CharacterCreationMain.createNameAndGender

	function CharacterCreationMain:createNameAndGender()
		local UI_BORDER_SPACING = 10
		local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

		local xOffset, _, comboWidth = IHM_CC_GetCenteredLayout(self)
		-- Le leggono createHairTypeBtn e createBeardTypeBtn, che girano dopo.
		self.xOffset = xOffset
		self.comboWid = comboWidth

		local characterHeaderText = IHM_CC_GetCharacterHeaderText()
		self.characterHeaderLbl = ISLabel:new(0, self.yOffset, FONT_HGT_MEDIUM, characterHeaderText, 1, 1, 1, 1, UIFont.Medium, true)
		self.characterHeaderLbl:initialise()
		self.characterHeaderLbl:instantiate()
		self.characterPanel:addChild(self.characterHeaderLbl)
		table.insert(self.characterPanel.reposTable, self.characterHeaderLbl)

		self.characterHeaderRect = ISRect:new(0, self.yOffset + FONT_HGT_MEDIUM + 5, self.characterPanel.width, 1, 1, 0.3, 0.3, 0.3)
		self.characterHeaderRect:initialise()
		self.characterHeaderRect:instantiate()
		self.characterPanel:addChild(self.characterHeaderRect)
		table.insert(self.characterPanel.dividerResizeTable, self.characterHeaderRect)

		self.yOffset = self.yOffset + UI_BORDER_SPACING + FONT_HGT_MEDIUM + 6

		-- Nome, cognome, sesso e tutto quello che un'altra mod ha appeso qui.
		-- Le larghezze non le passiamo: chi costruisce si registra da se' in
		-- comboResizeTable, e positionRelativeToScrollBar le sistema tutte dopo,
		-- comprese quelle che non sono nostre.
		if previousCreateNameAndGender then
			previousCreateNameAndGender(self)
		end
	end
end

Events.OnGameBoot.Add(IHM_ApplyCharacterCreationCentering)