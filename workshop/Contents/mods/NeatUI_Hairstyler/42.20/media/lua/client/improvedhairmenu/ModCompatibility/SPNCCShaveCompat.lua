--[[ SPNCCShaveCompat - body shaving from Spongie's Character Customisation,
    folded into the razor menu instead of a row of its own.

    WHO DOES WHAT
    Tomb's Player Body - Customisation requires Spongie's Character
    Customisation (id SPNCC). The body hair and the shaving come from SPNCC,
    not from Tomb: its client file CharacterCustomisation/Ingame/CharacterScreen
    wraps ISCharacterScreen.create and .render to add a "Chest hair" row with a
    plain "Shave" button, which opens a menu with shave body hair / beard
    stubble / head stubble.

    WHY THE ROW BREAKS THE PANEL
    Three things, all in SPNCC's render, which runs after vanilla's:
      * the label is drawn at xOffset + 30, while every vanilla label is
        right-aligned at xOffset - so it hangs off the left of the column;
      * the button is a plain ISButton. Neat Rocco's UI swaps hair, beard and
        literature for square Neat buttons, but it does not know this one;
      * it moves the literature button three rows down. Vanilla has already
        placed "Zombies killed" and sized the panel from where the literature
        button was (ISCharacterScreen.lua:211-246), so the book lands below
        the kill counter and the new row sits on top of the old slot.

    WHAT THIS DOES
      1. The shave options become part of the razor menu, after "Trim beard".
         Female characters have no razor button (vanilla never shows the beard
         row for them), so for them the options go into the scissors menu.
         The options are SPNCC's own - addShaveContext - so their conditions,
         tooltips and actions stay exactly theirs.
      2. The row disappears: the button is hidden, the label is not drawn, and
         the literature button goes back where vanilla put it.
      3. The razor (or scissors) stays clickable when there is something to
         shave even without a beard (or hair) to trim. Vanilla greys it out on
         a clean-shaven face, and that would have locked the body hair away.

    SPNCC's "Appearance" row (Change button) is left in, but moved up into the
    slot the chest hair row leaves free. It only shows for admins, debug, the
    appearance item, or a sandbox that allows changes - off by default.

    Only active when SPNCC's functions are actually there.
]]

if isServer() then return end

local FONT_HGT_SMALL    = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT        = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10
-- One row of the info column: the same step vanilla and SPNCC both use.
local ROW_STEP = BUTTON_HGT + UI_BORDER_SPACING
-- Vanilla offsets a button upwards so its label sits centred on it.
local BUTTON_ALIGN = (BUTTON_HGT - FONT_HGT_SMALL) / 2

-- The names SPNCC gives its shave options. If one of them is already in the
-- menu, somebody has added them this time round and we do not add them twice.
local SHAVE_OPTION_KEYS = {
    "UI_shave_stubble_body",
    "UI_shave_stubble_beard",
    "UI_shave_stubble_head",
}

local function spnccPresent()
    return ISCharacterScreen ~= nil
        and type(ISCharacterScreen.addShaveContext) == "function"
        and type(ISCharacterScreen.onShaveBodyHair) == "function"
end

--- True when SPNCC has something for this character to shave. Read from the
--- fields SPNCC's own render refreshes every couple of seconds.
local function hasSomethingToShave(screen)
    return screen.hasBodyHair == true
        or screen.hasStubbleHead == true
        or screen.hasStubbleBeard == true
        or screen.playerHasAppearanceChanger == true
end

--- The button the shave options hang off: razor for men, scissors for women.
local function shaveAnchor(screen)
    if not screen.char then return nil end
    if screen.char:isFemale() then return screen.hairButton end
    return screen.beardButton
end

-- ---------------------------------------------------------------------------
-- 1. The options, appended to the menu the button has just opened
-- ---------------------------------------------------------------------------
local function appendShaveOptions(screen)
    local context = getPlayerContextMenu(screen.char:getPlayerNum())
    if not context then return end

    for _, key in ipairs(SHAVE_OPTION_KEYS) do
        if context:getOptionFromName(getText(key)) then return end
    end

    -- SPNCC builds its options into self.ShaveContext. Pointing that at the
    -- razor menu is all it takes for them to land after "Trim beard".
    local before = context.numOptions
    screen.ShaveContext = context
    screen:addShaveContext()

    -- Nothing to shave: SPNCC would have shown its button greyed out with a
    -- tooltip. The same thing here, so the option can still be found.
    if context.numOptions == before then
        local option = context:addOption(getText("UI_shave_stubble_body"), nil, nil)
        screen:addTooltip(option, getText("Tooltip_NoBodyHair"))
    end
end

local wrapped = { hair = nil, beard = nil }

local function makeMenuWrapper(base, forFemale)
    return function(self, button, ...)
        base(self, button, ...)
        if self.char and self.char:isFemale() == forFemale then
            appendShaveOptions(self)
        end
    end
end

--- Wraps whichever hairMenu / beardMenu is current.
---
--- Called every frame from render rather than once, because hairMenu does not
--- stay put: SpongieHairUnlockerCompat reassigns it on game start, on player
--- creation and whenever the screen is created or shown. Rocco's scissors
--- button looks the function up at click time, so wrapping what is there now
--- is what counts. The check is one comparison per function.
local function ensureMenusWrapped()
    if ISCharacterScreen.beardMenu ~= wrapped.beard then
        wrapped.beard = makeMenuWrapper(ISCharacterScreen.beardMenu, false)
        ISCharacterScreen.beardMenu = wrapped.beard
    end
    if ISCharacterScreen.hairMenu ~= wrapped.hair then
        wrapped.hair = makeMenuWrapper(ISCharacterScreen.hairMenu, true)
        ISCharacterScreen.hairMenu = wrapped.hair
    end
end

-- ---------------------------------------------------------------------------
-- 2. and 3. The row, taken back out of the panel
-- ---------------------------------------------------------------------------
local function fixLayout(screen, appearanceDrawn)
    local anchor = shaveAnchor(screen)
    if not anchor then return end

    if screen.shaveButton then screen.shaveButton:setVisible(false) end

    -- The first slot under the hair/beard row: where vanilla puts the
    -- literature button (ISCharacterScreen.lua:211).
    local slotY = anchor:getY() + ROW_STEP

    if appearanceDrawn and screen.customisationButton and screen.customisationButton:isVisible() then
        screen.customisationButton:setY(slotY)
        screen.customisationButton:setX(anchor:getX())
        screen:drawTextRight(getText("UI_characreation_appearance"),
            screen.xOffset, slotY + BUTTON_ALIGN, 1, 1, 1, 1, UIFont.Small)
        slotY = slotY + ROW_STEP
    end

    if screen.literatureButton then screen.literatureButton:setY(slotY) end

    -- Rocco copies enable and tooltip from this button to its square one
    -- right after this render returns, so setting them here is enough.
    if not anchor.enable and hasSomethingToShave(screen) then
        anchor.enable = true
        anchor.tooltip = nil
    end
end

local function installRender()
    local base = ISCharacterScreen.render

    ISCharacterScreen.render = function(self, ...)
        ensureMenusWrapped()

        local chestLabel = getText("UI_ChestHair")
        local appearanceLabel = getText("UI_characreation_appearance")
        local appearanceDrawn = false

        -- SPNCC draws its two labels from inside its render, and a drawn label
        -- cannot be taken back. So for the length of that call this instance
        -- skips those two strings and lets every other label through.
        local own = rawget(self, "drawTextRight")
        local real = self.drawTextRight
        -- collide-ok: deliberate, temporary shadowing of ISUIElement:drawTextRight
        -- on this instance only. The real method is kept above and restored
        -- right after the call below.
        self.drawTextRight = function(s, text, ...)
            if text == chestLabel then return end
            if text == appearanceLabel then
                appearanceDrawn = true
                return
            end
            return real(s, text, ...)
        end

        base(self, ...)

        self.drawTextRight = own
        fixLayout(self, appearanceDrawn)
    end
end

--- At boot every mod's Lua has loaded, so SPNCC's render wrapper is already in
--- place and this one goes around it. The info panel itself is built later, in
--- game - which is when Rocco captures `view.render` - so Rocco ends up around
--- this one and reads the corrected positions.
Events.OnGameBoot.Add(function()
    if not spnccPresent() then return end
    installRender()
    ensureMenusWrapped()
end)
