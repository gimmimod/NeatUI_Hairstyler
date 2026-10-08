--[[--------------------------------------------------------------------
  Improved Hair Menu — CharacterUpdateHook.lua
  Purpose: Install late, safe hooks into CharacterCreationHeader and
           its AvatarPanel so we can react to survivor desc changes
           without touching vanilla files directly.

  Fixes:
   - Prevents "attempted index: create of non-table: null" by delaying
     any access to CharacterCreationHeader until it actually exists.
   - Uses nil-safe checks and pcall to avoid cascading errors.
----------------------------------------------------------------------]]
if isServer() then return end
local TAG = "[IHM/CharacterUpdateHook] "

-- Aggancia l'intestazione della creazione personaggio, se esiste.
--
-- Chiesta con rawget e non nominata direttamente: in B42.20 questa classe non
-- c'e' piu' (restano CharacterCreationMain, CharacterCreationAvatar e
-- CharacterCreationProfession), quindi qui dentro si esce quasi sempre alla
-- seconda riga. rawget e' il modo in cui la mod dice "questo potrebbe non
-- esistere" dappertutto, ed e' anche quello che tiene buono globali.js.
local function installHeaderHook()
    local CCH = rawget(_G, "CharacterCreationHeader")

    -- Gia' agganciata?
    if CCH and CCH._IHM_hooked then
        return true
    end

    -- Non c'e', o non e' ancora pronta.
    if type(CCH) ~= "table" or type(CCH.create) ~= "function" then
        return false
    end

    local original_create = CCH.create

    -- Si avvolge create() per poter agganciare l'avatarPanel subito dopo.
    function CCH:create(...)
        -- Call vanilla / previously wrapped create first
        original_create(self, ...)

        -- Guard: avatarPanel may not exist on some paths
        if not self.avatarPanel then
            return
        end

        -- Only hook once per avatarPanel instance
        if self.avatarPanel._IHM_hooked then
            return
        end
        self.avatarPanel._IHM_hooked = true

        -- Wrap setSurvivorDesc to notify our UI (if present)
        local original_set = self.avatarPanel.setSurvivorDesc
        if type(original_set) == "function" then
            self.avatarPanel.setSurvivorDesc = function(panel, desc, ...)
                -- Call vanilla first
                original_set(panel, desc, ...)

                -- If our CharacterCreationMain instance exposes a preview-update method, call it
                local CCM = rawget(_G, "CharacterCreationMain")
                local ok, err = pcall(function()
                    if CCM and CCM.instance and type(CCM.instance.ihm_update_preview_model) == "function" then
                        CCM.instance:ihm_update_preview_model(desc)
                    end
                end)
                if not ok and err then
                    print(TAG .. "ihm_update_preview_model failed: " .. tostring(err))
                end
            end
        end
    end

    CCH._IHM_hooked = true
    return true
end

-- Ci prova a ogni tick, ma non per sempre.
--
-- CharacterCreationHeader e' una classe che B42.20 **non ha piu'**: in
-- media/lua/client/OptionScreens oggi ci sono CharacterCreationMain,
-- CharacterCreationAvatar e CharacterCreationProfession, e basta. Su questa
-- build l'aggancio non riuscira' mai, e senza un limite questa funzione girava
-- a ogni tick per tutta la partita e per tutto il menu principale, a cercare
-- una cosa che non c'e'.
--
-- Il tetto e' generoso di proposito: se la classe esiste - la 42.19, o una
-- build futura che la riporti - compare nei primissimi frame, molto prima di
-- questo numero. Dopo, si smette e non si torna a chiedere.
local TENTATIVI_MAX = 300
local tentativi = 0

local function tryInstallHeaderHook()
    if installHeaderHook() then
        Events.OnTick.Remove(tryInstallHeaderHook)
        return
    end

    tentativi = tentativi + 1
    if tentativi >= TENTATIVI_MAX then
        Events.OnTick.Remove(tryInstallHeaderHook)
    end
end

-- Register the retry on tick (fires in main menu and in-game)
Events.OnTick.Add(tryInstallHeaderHook)

-- Rientrando nel menu principale si riparte da zero: se una mod caricata nel
-- frattempo ha portato la classe, merita un altro giro di tentativi.
Events.OnMainMenuEnter.Add(function()
    local CCH = rawget(_G, "CharacterCreationHeader")
    if not (CCH and CCH._IHM_hooked) then
        tentativi = 0
        Events.OnTick.Remove(tryInstallHeaderHook)
        Events.OnTick.Add(tryInstallHeaderHook)
    end
end)

-- Hard stop during world loading (prevents any CC polling from running while streaming)
if Events.OnInitWorld then
    Events.OnInitWorld.Add(function()
        Events.OnTick.Remove(tryInstallHeaderHook)
    end)
end

-- Nessuna riga di saluto nel log: questo file si carica sempre, e il log del
-- giocatore serve a lui per trovare gli errori.

-- Spongie Original guard: prevent early in-game customisation UI during world bootstrap.

local function IHM__isSpongieOriginalPresent()
    -- Spongie uses this module during character creation data handling.
    -- If it exists, the original mod is very likely present.
    return pcall(require, "CharacterCustomisation/CharacterCreation/StoredCharacterData")
end

local function IHM__closeActiveCCModal()
    local ihm = rawget(_G, "ImprovedHairMenu")
    local modal = ihm and rawget(ihm, "_activeCCModal")
    if modal and modal.close then
        pcall(function() modal:close() end)
    end
end

local function IHM__getPlayerFromArgs(a, b)
    -- Events.OnCreatePlayer often passes (playerIndex, player)
    if type(a) == "number" then return b end
    return a
end

local function IHM__shouldSuppressSpnccPrompt(player)
    -- Target the problematic case: brand new character spawn during world creation.
    if not player or not player.getHoursSurvived then return false end
    return player:getHoursSurvived() <= 0
end

local function IHM__seedSpnccHasCustomised(player)
    if not player or not player.getModData then return end

    local md = player:getModData()
    md.SPNCharCustom = md.SPNCharCustom or {}

    -- Only seed if not already set by Spongie/server.
    if md.SPNCharCustom.hasCustomised == nil then
        md.SPNCharCustom.hasCustomised = true
        md.SPNCharCustom._ihmSeeded = true
    end
end

if Events and IHM__isSpongieOriginalPresent() then
    Events.OnNewGame.Add(function(player)
        IHM__closeActiveCCModal()
        if IHM__shouldSuppressSpnccPrompt(player) then
            IHM__seedSpnccHasCustomised(player)
        end
    end)

    Events.OnCreatePlayer.Add(function(a, b)
        local player = IHM__getPlayerFromArgs(a, b)
        IHM__closeActiveCCModal()
        if IHM__shouldSuppressSpnccPrompt(player) then
            IHM__seedSpnccHasCustomised(player)
        end
    end)
end