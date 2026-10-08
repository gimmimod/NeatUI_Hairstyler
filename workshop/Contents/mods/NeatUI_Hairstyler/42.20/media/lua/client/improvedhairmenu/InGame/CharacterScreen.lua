--[[
	Here we add the menu to the in-game haircut menu.

	Initially we read the hair options out of the context menu and collated them into the menu
	but this I believe might be the source of some errors on non-english languages.

	Instead I've opted to directly override the context menu generation and use the same code from
	the vanilla game to get the hairstyles
]]
if isServer() then return end
-- Build 42.13+ uses ItemTag objects (not strings) for hasTag / containsTagEvalRecurse.

local MenuLabel_CutHair   = getText("ContextMenu_CutHair")
local MenuLabel_TieHair   = getText("ContextMenu_TieHair")
local MenuLabel_TrimBeard = getText("ContextMenu_TrimBeard")

local function IHM_itemHasTag(item, tagObj, fallbackString)
	if not item or not item.hasTag then return false end

	if tagObj ~= nil then
		local ok, res = pcall(item.hasTag, item, tagObj)
		if ok then return res == true end
	end

	-- Back-compat: older builds (or other environments) may still accept strings
	if fallbackString ~= nil then
		local ok, res = pcall(item.hasTag, item, fallbackString)
		return ok and res == true
	end

	return false
end

local function predicateRazor(item)
	if item:isBroken() then return false end
	if item:getType() == "Razor" then return true end

	-- Prefer ItemTag constant (42.13+)
	local tagObj = (ItemTag and ItemTag.RAZOR) or nil
	return IHM_itemHasTag(item, tagObj, "Razor")
end

local function predicateScissors(item)
	if item:isBroken() then return false end
	if item:getType() == "Scissors" then return true end

	local tagObj = (ItemTag and ItemTag.SCISSORS) or nil
	return IHM_itemHasTag(item, tagObj, "Scissors")
end

-- 42.20 vanilla styles a hairdo with hair gel OR hair spray (ItemTag.DO_HAIRDO),
-- while a slicked-back cut still wants gel specifically and a Buffont wants spray.
-- Matching the tags instead of hard-coded item types keeps modded products working.
local function predicateDoHairdo(item)
	local tagObj = (ItemTag and ItemTag.DO_HAIRDO) or nil
	if IHM_itemHasTag(item, tagObj, "DoHairdo") then return true end
	local t = item:getType()
	return t == "Hairgel" or t == "Hairspray2"
end

local function predicateSlickHair(item)
	return item:getType() == "Hairgel"
end

local function predicateNotBroken(item)
	return not item:isBroken()
end

local function compareHairStyle(a, b)
	if a:getName() == "Bald" then return true end
	if b:getName() == "Bald" then return false end
	local nameA = getText("IGUI_Hair_" .. a:getName())
	local nameB = getText("IGUI_Hair_" .. b:getName())
	return not string.sort(nameA, nameB)
end

-- Modified vanilla function to produce `hairInfo` instead of context menu options
function ISCharacterScreen:hairMenu(button)
	local player = self.char;
	local context = ISContextMenu.get(self.char:getPlayerNum(), button:getAbsoluteX(), button:getAbsoluteY() + button:getHeight());
	local playerInv = player:getInventory()
	
	local currentHairStyle = getHairStylesInstance():FindMaleStyle(player:getHumanVisual():getHairModel())
	local hairStyles = getHairStylesInstance():getAllMaleStyles();
	if player:isFemale() then
		currentHairStyle = getHairStylesInstance():FindFemaleStyle(player:getHumanVisual():getHairModel())
		hairStyles = getHairStylesInstance():getAllFemaleStyles();
	end
	local hairList = {}
	for i=1,hairStyles:size() do
		table.insert(hairList, hairStyles:get(i-1))
	end
	table.sort(hairList, compareHairStyle)
	-- if we have hair long enough to trim it
	if currentHairStyle and currentHairStyle:getLevel() > 0 then
		local hairMenu = context

		local tie_options = {}
		local cut_options = {}
		
		if isDebugEnabled() then
			if player:isFemale() then
				hairMenu:addOption("[DEBUG] Grow Long2", player, ISCharacterScreen.onCutHair, "Long2", 10);
			else
				hairMenu:addOption("[DEBUG] Grow Fabian", player, ISCharacterScreen.onCutHair, "Fabian", 10);
			end
		end
		
		-- if we have an attached hair model but non nonAttachedHair reference, we get one
		if currentHairStyle:isAttachedHair() and not player:getVisual():getNonAttachedHair() then
			-- get the growReference of our current level, it'll become our nonAttachedHair, so if we decide to detach our hair (from a pony tail for ex.) we'll go back to this growReference
			for _,hairStyle in ipairs(hairList) do
				if hairStyle:getLevel() == currentHairStyle:getLevel() and hairStyle:isGrowReference() then
					player:getVisual():setNonAttachedHair(hairStyle:getName());
				end
			end
		end
		
		-- untie hair
		if player:getVisual():getNonAttachedHair() then
			hairMenu:addOption(getText("ContextMenu_UntieHair"), player, ISCharacterScreen.onCutHair, player:getVisual():getNonAttachedHair(), 100);
		end
		
		if not player:getVisual():getNonAttachedHair() then
			-- add attached hair
			for _,hairStyle in ipairs(hairList) do
				if hairStyle:getLevel() <= currentHairStyle:getLevel() and hairStyle:getName() ~= currentHairStyle:getName() and hairStyle:isAttachedHair() and hairStyle:getName() ~= "" then
					table.insert(tie_options, {
						id = hairStyle:getName(),
						display = getText("IGUI_Hair_" .. hairStyle:getName()),
						getterName = "getHairModel",
						setterName = "setHairModel",
						selected = false,
						requirements = nil,
						actionTime = 100, 
					})
				end
			end

			local hairList2 = {}
			-- add all "under level" we can find, any level 2 hair can be cut into a level 1
			for _,hairStyle in ipairs(hairList) do
				if not hairStyle:isAttachedHair() and not hairStyle:isNoChoose() and hairStyle:getLevel() < currentHairStyle:getLevel() and hairStyle:getName() ~= "" then
					table.insert(hairList2, hairStyle)
				end
			end
			-- add other special trim
			for i=1,currentHairStyle:getTrimChoices():size() do
				local styleId = currentHairStyle:getTrimChoices():get(i-1)
				local hairStyle = player:isFemale() and getHairStylesInstance():FindFemaleStyle(styleId) or getHairStylesInstance():FindMaleStyle(styleId)
				if hairStyle then
					table.insert(hairList2, hairStyle)
				end
			end
			table.sort(hairList2, compareHairStyle)
			
			local inv = player:getInventory()
			local hasRazor     = inv:containsEvalRecurse(predicateRazor)
			local hasScissors  = inv:containsEvalRecurse(predicateScissors)
			local hasHairdo    = inv:containsEvalRecurse(predicateDoHairdo)
			local hasHairgel   = inv:containsEvalRecurse(predicateSlickHair)
			local hasHairspray = inv:containsTypeRecurse("Hairspray2")

			for _,hairStyle in ipairs(hairList2) do
				local info = {
					id = hairStyle:getName(),
					display = getText("IGUI_Hair_" .. hairStyle:getName()),
					getterName = "getHairModel",
					setterName = "setHairModel",
					selected = false,
					requirements = {},
					actionTime = 300,
				}

				-- Same branches as 42.20 ISCharacterScreen:hairMenu.
				local styleName = hairStyle:getName()
				if styleName == "Bald" then
					info.requirements.razor = hasRazor
					info.requirements.scissors = hasScissors
				elseif (styleName:contains("Mohawk") and styleName ~= "MohawkFlat") or styleName:contains("Spike") then
					info.requirements.hairgel = hasHairdo
				elseif styleName:contains("GreasedBack") then
					info.requirements.hairgel = hasHairgel
				elseif styleName:contains("Buffont") then
					info.requirements.hairgel = hasHairspray
				else
					info.requirements.scissors = hasScissors
				end

				table.insert(cut_options, info)
			end
		end

		if #tie_options > 0 then
			hairMenu:addOption(MenuLabel_TieHair, self, self.ihm_open_hair_menu, tie_options, MenuLabel_TieHair, false)
		end
		if #cut_options > 0 then
			hairMenu:addOption(MenuLabel_CutHair, self, self.ihm_open_hair_menu, cut_options, MenuLabel_CutHair, false)
		end
	else
		local hairMenu = context
		
		if isDebugEnabled() then
			if player:isFemale() then
				hairMenu:addOption("[DEBUG] Grow Long2", player, ISCharacterScreen.onCutHair, "Long2", 10);
			else
				hairMenu:addOption("[DEBUG] Grow Fabian", player, ISCharacterScreen.onCutHair, "Fabian", 10);
			end
		end
	end

	if JoypadState.players[self.playerNum+1] and context.numOptions > 0 then
		context.origin = self
		context.mouseOver = 1
		setJoypadFocus(self.playerNum, context)
	end
end

-- Modified vanilla function to produce `hairInfo` instead of context menu options
function ISCharacterScreen:beardMenu(button)
	local player = self.char;
	local context = ISContextMenu.get(self.char:getPlayerNum(), button:getAbsoluteX(), button:getAbsoluteY() + button:getHeight());
	local playerInv = player:getInventory()
	
	local currentBeardStyle = getBeardStylesInstance():FindStyle(player:getHumanVisual():getBeardModel())
	-- if we have a beard long enough to trim it
	if currentBeardStyle and currentBeardStyle:getLevel() > 0 then
		local beardMenu = context
		
		if isDebugEnabled() then
			beardMenu:addOption("[DEBUG] Grow Long", player, ISCharacterScreen.onTrimBeard, "Long");
		end

		local all_stlyes = {}
		local options = {}

		-- add all "under level" we can find, any level 2 beard/hair can be trim into a level 1
		local allBeard = getBeardStylesInstance():getAllStyles();
		for i=0, allBeard:size()-1 do
			local beardStyle = allBeard:get(i);
			if beardStyle:getLevel() < currentBeardStyle:getLevel() and beardStyle:getName() ~= "" then
				table.insert(all_stlyes, beardStyle)
			end
		end
		-- add other special trim (a goatee can become a moustache, etc.)
		for i=0, currentBeardStyle:getTrimChoices():size()-1 do
			table.insert(all_stlyes, getBeardStylesInstance():FindStyle(currentBeardStyle:getTrimChoices():get(i)))
		end

		local inv = player:getInventory()
		local hasRazor    = inv:containsEvalRecurse(predicateRazor)
		local hasScissors = inv:containsEvalRecurse(predicateScissors)

		table.insert(options, {
			id = "",
			display = getText("IGUI_Beard_None"),
			selected = false,
			getterName = "getBeardModel",
			setterName = "setBeardModel",
			requirements = {
				razor = hasRazor,
				scissors = hasScissors,
			},
		})

		for k, style in pairs(all_stlyes) do
			table.insert(options, {
				id = style:getName(),
				display = getText("IGUI_Beard_" .. style:getName()),
				getterName = "getBeardModel",
				setterName = "setBeardModel",
				selected = false,
				requirements = {
					razor = hasRazor,
					scissors = hasScissors,
				},
			})
		end

		if #options > 0 then
			context:addOption(MenuLabel_TrimBeard, self, self.ihm_open_hair_menu, options, MenuLabel_TrimBeard, true)
		end
	else
		local beardMenu = context
		
		if isDebugEnabled() then
			beardMenu:addOption("[DEBUG] Grow Long", player, ISCharacterScreen.onTrimBeard, "Long");
		end
	end

	if JoypadState.players[self.playerNum+1] and context.numOptions > 0 then
		context.origin = self
		context.mouseOver = 1
		setJoypadFocus(self.playerNum, context)
	end
end

local opened_menu = nil

function ISCharacterScreen:ihm_open_hair_menu(hair_options, title, isBeard)
	local player = self.char
	local menu = HairMenuPanelWindow:new(200,200,400,400, self.playerNum, self.char, hair_options, isBeard)
	menu.returnFocus = self
	-- La finestra **non** si chiude dopo il taglio: provarne due di fila
	-- voleva dire riaprirla ogni volta, e la griglia esiste proprio per
	-- guardare le alternative una dopo l'altra. Si chiude con la sua X.
	if isBeard == true then 
		menu.onSelect = function(selection)
			ISCharacterScreen.onTrimBeard(player, selection.id)
		end
	else
		menu.onSelect = function(selection)
			ISCharacterScreen.onCutHair(player, selection.id, selection.actionTime)
		end
	end

	menu:initialise()
	menu.title = title
	menu:addToUIManager()

	if opened_menu ~= nil then
		opened_menu:close()
	end
	opened_menu = menu
	setJoypadFocus(self.playerNum, opened_menu)
end