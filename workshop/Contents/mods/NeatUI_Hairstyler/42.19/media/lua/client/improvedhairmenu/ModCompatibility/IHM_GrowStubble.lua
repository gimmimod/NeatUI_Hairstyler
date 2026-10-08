-- Make GrowStubble work regardless of load order, without editing either mod.
local function _normalize(id)
    return id and id:lower():gsub("[/\\%s]+", "") or ""
end

local function isModActive(targetIds)
    local mods = getActivatedMods()
    if not mods or mods:size() == 0 then return false end

    -- Build lookup of normalized target IDs
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

-- Guard: bail out early unless GrowStubble is actually active.
if not isModActive({ "GrowStubble" }) then
     print("[IHM][GrowStubbleCompat] GrowStubble not active -> compat disabled.")
    return
end



if rawget(_G, "IHM_GSCompat") then return end
IHM_GSCompat = { version = "1.0.0" }

local LOG_PREFIX = "[IHM][GrowStubbleCompat] "

local function log(msg)
    -- Keep logging lightweight; uncomment if you want visible logs:
     print(LOG_PREFIX .. tostring(msg))
end

-- Try to ensure the other mod's file is actually loaded.
-- Safe in all cases: if it's already loaded, require() is a no-op.
local function tryRequireGrowStubble()
    if rawget(_G, "GrowStubble") then return true end
    local ok = pcall(require, "GrowStubble")
    if ok and rawget(_G, "GrowStubble") then return true end

    -- Optional extra guesses; harmless if not found.
    pcall(require, "client/GrowStubble")
    pcall(require, "GrowStubble/GrowStubble")

    return rawget(_G, "GrowStubble") ~= nil
end

-- Seed missing modData flags and do a one-time hourly check.
local function ensureInitialisedOnce()
    local GS = rawget(_G, "GrowStubble")
    if not GS then return false end

    -- Guard so we don't wire twice across Lua reloads.
    if GS._ihm_compat_wired then return true end
    GS._ihm_compat_wired = true

    -- When a player is created, only initialise if flags are missing.
    Events.OnCreatePlayer.Add(function(playerNum, player)
        local md = player and player:getModData()
        if not md then return end
        local needBeard = (md.canGrowStubbleBeard == nil)
        local needHair  = (md.canGrowStubbleHair  == nil)
        if (needBeard or needHair) and GS.onCreatePlayer then
            pcall(GS.onCreatePlayer, playerNum, player)
        end
    end)

    -- At game start, retro-init any already active players (SP or splitscreen).
    Events.OnGameStart.Add(function()
        for i = 0, getNumActivePlayers() - 1 do
            local pl = getSpecificPlayer(i)
            if pl and GS.onCreatePlayer then
                local md = pl:getModData()
                local needBeard = (md and md.canGrowStubbleBeard == nil)
                local needHair  = (md and md.canGrowStubbleHair  == nil)
                if needBeard or needHair then
                    pcall(GS.onCreatePlayer, i, pl)
                end
            end
        end

        -- Do a single catch-up tick; do NOT install our own EveryHours loop.
        if GS.hourlyCheck then pcall(GS.hourlyCheck) end
    end)

    log("Compatibility wiring complete.")
    return true
end

-- Late boot hook: handle any load order by retrying briefly until GrowStubble appears.
local function lateInit()
    if tryRequireGrowStubble() and ensureInitialisedOnce() then return end

    local retries = 0
    local maxRetries = 300 -- ~5 seconds @ 60 FPS; enough for menu-time loading.
    local function tick()
        retries = retries + 1
        if tryRequireGrowStubble() and ensureInitialisedOnce() then
            Events.OnTick.Remove(tick)
            return
        end
        if retries >= maxRetries then
            Events.OnTick.Remove(tick)
            log("GrowStubble not detected after retries; giving up (compat stays idle).")
        end
    end
    Events.OnTick.Add(tick)
end

-- Use a very-early hook if present; otherwise fall back to OnGameStart.
if Events.OnGameBoot then
    Events.OnGameBoot.Add(lateInit)
else
    Events.OnGameStart.Add(lateInit)
end