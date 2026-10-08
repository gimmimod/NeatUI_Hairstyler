if isServer() then return end

local function _normalize(id)
    return id and id:lower():gsub("[/\\%s]+", "") or ""
end

local function isModActive(targetIds)
    local mods = getActivatedMods()
    if not mods or mods:size() == 0 then return false end

    local want = {}
    for _, tid in ipairs(targetIds) do
        want[_normalize(tid)] = true
    end

    for i = 0, mods:size() - 1 do
        local id = _normalize(mods:get(i))
        if want[id] then
            return true
        end
    end

    return false
end

if not isModActive({ "SpnHairAPI" }) then
    return
end

print("[IHM][SpongieHairUnlockerCompat] Spongie detected -> compat enabled.")

local function itemHasTag(item, tagObj, fallbackString)
    if not item or not item.hasTag then return false end

    if tagObj ~= nil then
        local ok, result = pcall(item.hasTag, item, tagObj)
        if ok then
            return result == true
        end
    end

    if fallbackString ~= nil then
        local ok, result = pcall(item.hasTag, item, fallbackString)
        return ok and result == true
    end

    return false
end

local function predicateRazor(item)
    if item:isBroken() then return false end
    if item:getType() == "Razor" then return true end
    return itemHasTag(item, ItemTag and ItemTag.RAZOR or nil, "Razor")
end

local function predicateScissors(item)
    if item:isBroken() then return false end
    if item:getType() == "Scissors" then return true end
    return itemHasTag(item, ItemTag and ItemTag.SCISSORS or nil, "Scissors")
end

local function compareHairStyle(a, b)
    if a:getName() == "Bald" then return true end
    if b:getName() == "Bald" then return false end
    local nameA = getText("IGUI_Hair_" .. a:getName())
    local nameB = getText("IGUI_Hair_" .. b:getName())
    return not string.sort(nameA, nameB)
end

local function addUniqueHairStyle(list, seen, hairStyle)
    if not hairStyle then return end
    if hairStyle:isAttachedHair() then return end
    if hairStyle:isNoChoose() then return end
    if hairStyle:getName() == "" then return end

    local id = hairStyle:getName()
    if seen[id] then return end

    seen[id] = true
    table.insert(list, hairStyle)
end
local patchedHairMenu
local function rebindHairButton(screen)
    if not screen or not screen.hairButton then return end

    local button = screen.hairButton

    ISCharacterScreen.hairMenu = patchedHairMenu
    screen.hairMenu = patchedHairMenu

    button.target = screen
    button.onclick = patchedHairMenu
    button.onClick = patchedHairMenu

    if not button._IHM_SpongieWrapped then
        button._IHM_SpongieWrapped = true

        function button:onMouseUp(x, y)
            self.downX = nil
            self.downY = nil
            self.pressed = false

            pcall(function()
                patchedHairMenu(screen, self)
            end)

            return true
        end

        function button:forceClick()
            pcall(function()
                patchedHairMenu(screen, self)
            end)

            return true
        end
    end
end

patchedHairMenu = function(self, button)
    local player = self.char
    local context = ISContextMenu.get(self.char:getPlayerNum(), button:getAbsoluteX(), button:getAbsoluteY() + button:getHeight())

    local currentHairStyle = getHairStylesInstance():FindMaleStyle(player:getHumanVisual():getHairModel())
    local hairStyles = getHairStylesInstance():getAllMaleStyles()

    if player:isFemale() then
        currentHairStyle = getHairStylesInstance():FindFemaleStyle(player:getHumanVisual():getHairModel())
        hairStyles = getHairStylesInstance():getAllFemaleStyles()
    end

    local hairList = {}
    for i = 1, hairStyles:size() do
        table.insert(hairList, hairStyles:get(i - 1))
    end
    table.sort(hairList, compareHairStyle)

    if currentHairStyle and currentHairStyle:getLevel() > 0 then
        local tieOptions = {}
        local cutOptions = {}

        if currentHairStyle:isAttachedHair() and not player:getVisual():getNonAttachedHair() then
            for _, hairStyle in ipairs(hairList) do
                if hairStyle:getLevel() == currentHairStyle:getLevel() and hairStyle:isGrowReference() then
                    player:getVisual():setNonAttachedHair(hairStyle:getName())
                end
            end
        end

        if player:getVisual():getNonAttachedHair() then
            context:addOption(getText("ContextMenu_UntieHair"), player, ISCharacterScreen.onCutHair, player:getVisual():getNonAttachedHair(), 100)
        end

        if not player:getVisual():getNonAttachedHair() then
            for _, hairStyle in ipairs(hairList) do
                if hairStyle:getLevel() <= currentHairStyle:getLevel()
                and hairStyle:getName() ~= currentHairStyle:getName()
                and hairStyle:isAttachedHair()
                and hairStyle:getName() ~= "" then
                    table.insert(tieOptions, {
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
            local seen = {}

            for _, hairStyle in ipairs(hairList) do
                if not hairStyle:isAttachedHair()
                and not hairStyle:isNoChoose()
                and hairStyle:getLevel() <= currentHairStyle:getLevel()
                and hairStyle:getName() ~= "" then
                    addUniqueHairStyle(hairList2, seen, hairStyle)
                end
            end

            if currentHairStyle:getTrimChoices() then
                for i = 1, currentHairStyle:getTrimChoices():size() do
                    local styleId = currentHairStyle:getTrimChoices():get(i - 1)
                    local hairStyle = player:isFemale()
                        and getHairStylesInstance():FindFemaleStyle(styleId)
                        or getHairStylesInstance():FindMaleStyle(styleId)
                    addUniqueHairStyle(hairList2, seen, hairStyle)
                end
            end

            table.sort(hairList2, compareHairStyle)

            local inv = player:getInventory()
            local hasRazor = inv:containsEvalRecurse(predicateRazor)
            local hasScissors = inv:containsEvalRecurse(predicateScissors)
            local hasHairGel = inv:containsTypeRecurse("Hairgel") or inv:containsTypeRecurse("HairGel")
            local hasHairSpray = inv:containsTypeRecurse("Hairspray2")

            local SpongieHairAPI = require("SpongieHairUnlocker/SpongieHairAPI")

            for _, hairStyle in ipairs(hairList2) do
                local hairId = hairStyle:getName()
                local info = {
                    id = hairId,
                    display = getText("IGUI_Hair_" .. hairId),
                    getterName = "getHairModel",
                    setterName = "setHairModel",
                    selected = false,
                    requirements = {},
                    actionTime = 300,
                }

                local needsGel = SpongieHairAPI:NeedHairGel(hairId)
                local needsSpray = SpongieHairAPI:NeedHairSpray(hairId)

                if hairId == "Bald" then
                    info.requirements.razor = hasRazor
                    info.requirements.scissors = hasScissors
                elseif needsGel or needsSpray then
                    info.requirements.hairgel = hasHairGel or hasHairSpray
                else
                    info.requirements.scissors = hasScissors
                end

                table.insert(cutOptions, info)
            end
        end

        local MenuLabel_CutHair = getText("ContextMenu_CutHair")
        local MenuLabel_TieHair = getText("ContextMenu_TieHair")

        if #tieOptions > 0 then
            context:addOption(MenuLabel_TieHair, self, self.ihm_open_hair_menu, tieOptions, MenuLabel_TieHair, false)
        end
        if #cutOptions > 0 then
            context:addOption(MenuLabel_CutHair, self, self.ihm_open_hair_menu, cutOptions, MenuLabel_CutHair, false)
        end
    end

    if JoypadState.players[self.playerNum + 1] and context.numOptions > 0 then
        context.origin = self
        context.mouseOver = 1
        setJoypadFocus(self.playerNum, context)
    end
end

local function applyPatch()
    if not ISCharacterScreen then
        return
    end

    if type(ISCharacterScreen.ihm_open_hair_menu) ~= "function" then
        return
    end

    local okAPI, SpongieHairAPI = pcall(require, "SpongieHairUnlocker/SpongieHairAPI")
    if not okAPI or not SpongieHairAPI then
        return
    end

    ISCharacterScreen.hairMenu = patchedHairMenu

    if not rawget(_G, "IHM_SpongieHairUnlockerCompat_CreateWrapped") then
        rawset(_G, "IHM_SpongieHairUnlockerCompat_CreateWrapped", true)

        local originalCreate = ISCharacterScreen.create
        function ISCharacterScreen:create(...)
            originalCreate(self, ...)
            ISCharacterScreen.hairMenu = patchedHairMenu
            self.hairMenu = patchedHairMenu
            rebindHairButton(self)
        end
    end

    if not rawget(_G, "IHM_SpongieHairUnlockerCompat_SetVisibleWrapped") then
        rawset(_G, "IHM_SpongieHairUnlockerCompat_SetVisibleWrapped", true)

        local originalSetVisible = ISCharacterScreen.setVisible
        function ISCharacterScreen:setVisible(visible, joypadData, ...)
            local result = originalSetVisible(self, visible, joypadData, ...)
            if visible then
                ISCharacterScreen.hairMenu = patchedHairMenu
                self.hairMenu = patchedHairMenu
                rebindHairButton(self)
            end
            return result
        end
    end
end

applyPatch()

if Events then
    if Events.OnGameStart then
        Events.OnGameStart.Add(applyPatch)
    end
    if Events.OnCreatePlayer then
        Events.OnCreatePlayer.Add(applyPatch)
    end
end