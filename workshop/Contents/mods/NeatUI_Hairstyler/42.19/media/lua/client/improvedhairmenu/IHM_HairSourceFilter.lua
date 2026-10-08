if isServer() then return end

IHM_HairSourceFilter = IHM_HairSourceFilter or {}
local M = IHM_HairSourceFilter

M.ALL_ID = "__all__"
M.BASE_ID = "__base__"
M.VANILLA_ORDER = 9000
M.DEFAULT_SOURCE_ORDER = 5000

-- Vanilla style IDs from Build 42.17.
-- These must never be claimed by mods in the source filter.
M.vanillaHairStyles = M.vanillaHairStyles or {
    ["Bald"] = true,
    ["Picard"] = true,
    ["CrewCut"] = true,
    ["Baldspot"] = true,
    ["Recede"] = true,
    ["Hat"] = true,
    ["Messy"] = true,
    ["Short"] = true,
    ["Donny"] = true,
    ["Mullet"] = true,
    ["Metal"] = true,
    ["Fabian"] = true,
    ["PonyTail"] = true,
    ["FabianCurly"] = true,
    ["MessyCurly"] = true,
    ["MulletCurly"] = true,
    ["ShortAfroCurly"] = true,
    ["ShortHatCurly"] = true,
    ["CentreParting"] = true,
    ["LeftParting"] = true,
    ["RightParting"] = true,
    ["CentrePartingLong"] = true,
    ["Cornrows"] = true,
    ["Fresh"] = true,
    ["LibertySpikes"] = true,
    ["MohawkFan"] = true,
    ["MohawkShort"] = true,
    ["MohawkSpike"] = true,
    ["MohawkFlat"] = true,
    ["FlatTop"] = true,
    ["Buffont"] = true,
    ["GreasedBack"] = true,
    ["Spike"] = true,
    ["LongBraids"] = true,
    ["PonyTailBraids"] = true,
    ["LongBraids02"] = true,
    ["Braids"] = true,
    ["Grungey"] = true,
    ["GrungeyBehindEars"] = true,
    ["HatLong"] = true,
    ["HatLongBraided"] = true,
    ["HatLongCurly"] = true,
    ["Demi"] = true,
    ["OverEye"] = true,
    ["Bob"] = true,
    ["Bun"] = true,
    ["Back"] = true,
    ["Long"] = true,
    ["Kate"] = true,
    ["Long2"] = true,
    ["Longcurly"] = true,
    ["Long2curly"] = true,
    ["BobCurly"] = true,
    ["BunCurly"] = true,
    ["HatCurly"] = true,
    ["KateCurly"] = true,
    ["OverEyeCurly"] = true,
    ["RachelCurly"] = true,
    ["ShortCurly"] = true,
    ["Rachel"] = true,
    ["TopCurls"] = true,
    ["GrungeyParted"] = true,
    ["Grungey02"] = true,
    ["OverLeftEye"] = true,
}

M.vanillaBeardStyles = M.vanillaBeardStyles or {
    ["Chops"] = true,
    ["Moustache"] = true,
    ["Goatee"] = true,
    ["BeardOnly"] = true,
    ["Full"] = true,
    ["Long"] = true,
    ["LongScruffy"] = true,
    ["Chin"] = true,
    ["PointyChin"] = true,
}

-- Patch-only hair mods should not claim vanilla hairstyles in the source filter.
M.excludedModIds = M.excludedModIds or {
    FH = true, -- Fluffy Hair [B41 & B42ish]
}

M.excludedNameTokens = M.excludedNameTokens or {
    ["fluffy hair"] = true,
}

local HAIR_STYLE_FILE_PATHS = {
    "media/hairStyles/hairStyles.xml",
    "common/media/hairStyles/hairStyles.xml",

    "42/media/hairStyles/hairStyles.xml",
    "42/common/media/hairStyles/hairStyles.xml",

    "42.12/media/hairStyles/hairStyles.xml",
    "42.12/common/media/hairStyles/hairStyles.xml",

    "42.13/media/hairStyles/hairStyles.xml",
    "42.13/common/media/hairStyles/hairStyles.xml",

    "42.14/media/hairStyles/hairStyles.xml",
    "42.14/common/media/hairStyles/hairStyles.xml",

    "42.15/media/hairStyles/hairStyles.xml",
    "42.15/common/media/hairStyles/hairStyles.xml",

    "42.16/media/hairStyles/hairStyles.xml",
    "42.16/common/media/hairStyles/hairStyles.xml",

    "42.17/media/hairStyles/hairStyles.xml",
    "42.17/common/media/hairStyles/hairStyles.xml",
}

local BEARD_STYLE_FILE_PATHS = {
    "media/hairStyles/beardStyles.xml",
    "common/media/hairStyles/beardStyles.xml",

    "42/media/hairStyles/beardStyles.xml",
    "42/common/media/hairStyles/beardStyles.xml",

    "42.12/media/hairStyles/beardStyles.xml",
    "42.12/common/media/hairStyles/beardStyles.xml",

    "42.13/media/hairStyles/beardStyles.xml",
    "42.13/common/media/hairStyles/beardStyles.xml",

    "42.14/media/hairStyles/beardStyles.xml",
    "42.14/common/media/hairStyles/beardStyles.xml",

    "42.15/media/hairStyles/beardStyles.xml",
    "42.15/common/media/hairStyles/beardStyles.xml",

    "42.16/media/hairStyles/beardStyles.xml",
    "42.16/common/media/hairStyles/beardStyles.xml",

    "42.17/media/hairStyles/beardStyles.xml",
    "42.17/common/media/hairStyles/beardStyles.xml",
}

local cachedSourceIndex = nil
local cachedSourceSignature = nil

local function textOrFallback(key, fallback)
    if getText then
        local txt = getText(key)
        if txt and txt ~= key then return txt end
    end
    return fallback
end

function M.getAllLabel()
    return textOrFallback("UI_IHM_Source_All", "All")
end

function M.getBaseLabel()
    return textOrFallback("UI_IHM_Source_Vanilla", "Vanilla")
end

local function trim(text)
    return string.match(tostring(text or ""), "^%s*(.-)%s*$") or ""
end

local function normalize(text)
    return string.lower(trim(text))
end

local function contains(text, needle)
    return string.find(normalize(text), normalize(needle), 1, true) ~= nil
end

local function isStyleNameInSet(styleName, set)
    if not styleName or not set then return false end

    styleName = trim(styleName)

    if set[styleName] then
        return true
    end

    local normalizedStyleName = normalize(styleName)

    for vanillaName in pairs(set) do
        if normalize(vanillaName) == normalizedStyleName then
            return true
        end
    end

    return false
end

function M.isVanillaStyle(styleName, isBeard)
    if isBeard then
        return isStyleNameInSet(styleName, M.vanillaBeardStyles)
    end

    return isStyleNameInSet(styleName, M.vanillaHairStyles)
end

local function getModDisplayName(modId)
    local modInfo = getModInfoByID and getModInfoByID(modId) or nil
    if modInfo and modInfo.getName then
        local ok, name = pcall(modInfo.getName, modInfo)
        if ok and name and tostring(name) ~= "" then
            return tostring(name)
        end
    end
    return tostring(modId or "")
end

local function makeSource(modId, displayName, group)
    modId = tostring(modId or "")
    displayName = tostring(displayName or modId)

    if group then
        local groupId = tostring(group.id or group.display or "")
        if groupId == "" then groupId = "group" end

        return {
            id = modId .. "::" .. groupId,
            display = group.display or displayName,
            order = group.order or M.DEFAULT_SOURCE_ORDER,
        }
    end

    return {
        id = modId,
        display = displayName ~= "" and displayName or modId,
        order = M.DEFAULT_SOURCE_ORDER,
    }
end

local function sanitizeGroupId(text)
    text = normalize(text or "")
    text = string.gsub(text, "[^%w_%-]+", "_")
    text = string.gsub(text, "^_+", "")
    text = string.gsub(text, "_+$", "")
    if text == "" then text = "group" end
    return text
end

local function parseSourceDirective(comment)
    comment = trim(comment or "")

    if normalize(comment) == "ihm_source_end" then
        return { reset = true }
    end

    local raw =
        string.match(comment, "^IHM_SOURCE%s*:%s*(.+)$") or
        string.match(comment, "^IHM_SOURCE%s*=%s*(.+)$")

    if not raw then
        return nil
    end

    raw = trim(raw)
    if raw == "" then return nil end

    local orderText, display = string.match(raw, "^(%-?%d+)%s*|%s*(.+)$")
    local order = M.DEFAULT_SOURCE_ORDER

    if orderText and display then
        order = tonumber(orderText) or M.DEFAULT_SOURCE_ORDER
        display = trim(display)
    else
        display = raw
    end

    if display == "" then return nil end

    return {
        id = sanitizeGroupId(display),
        display = display,
        order = order,
    }
end

function M.invalidateCache()
    cachedSourceIndex = nil
    cachedSourceSignature = nil
end

function M.excludeModId(modId)
    if not modId then return end
    M.excludedModIds[tostring(modId)] = true
    M.invalidateCache()
end

function M.excludeNameToken(token)
    if not token then return end
    M.excludedNameTokens[tostring(token)] = true
    M.invalidateCache()
end

function M.isExcludedMod(modId, displayName)
    modId = tostring(modId or "")
    displayName = tostring(displayName or "")

    if M.excludedModIds[modId] then
        return true
    end

    local modIdNorm = normalize(modId)
    for blockedId in pairs(M.excludedModIds) do
        if normalize(blockedId) == modIdNorm then
            return true
        end
    end

    local combined = modId .. " " .. displayName
    for token in pairs(M.excludedNameTokens) do
        if contains(combined, token) then
            return true
        end
    end

    return false
end

local function buildActiveModsSignature()
    local activeMods = getActivatedMods and getActivatedMods() or nil
    if not activeMods then return "" end

    local parts = {}
    for index = 0, activeMods:size() - 1 do
        parts[#parts + 1] = tostring(activeMods:get(index))
    end

    return table.concat(parts, "|")
end

local function readStyleEntriesFromReader(reader, modId, displayName)
    if not reader then return {} end

    local entries = {}
    local seen = {}

    local baseSource = makeSource(modId, displayName, nil)
    local currentSource = baseSource

    while true do
        local ok, line = pcall(function()
            return reader:readLine()
        end)

        if not ok or line == nil then break end
        line = tostring(line)

        for comment in string.gmatch(line, "<!%-%-(.-)%-%->") do
            local directive = parseSourceDirective(comment)

            if directive then
                if directive.reset then
                    currentSource = baseSource
                else
                    currentSource = makeSource(modId, displayName, directive)
                end
            end
        end

        for styleName in string.gmatch(line, "<name>%s*(.-)%s*</name>") do
            local normalized = trim(styleName)

            if normalized ~= "" and not seen[normalized] then
                seen[normalized] = true
                entries[#entries + 1] = {
                    name = normalized,
                    source = currentSource,
                }
            end
        end
    end

    pcall(function() reader:close() end)

    return entries
end

local function readStyleEntriesFromMod(modId, displayName, filePaths)
    if not modId or not getModFileReader then return {} end

    local entries = {}
    local seen = {}

    for _, relativePath in ipairs(filePaths or HAIR_STYLE_FILE_PATHS) do
        local reader = nil
        local ok = pcall(function()
            reader = getModFileReader(modId, relativePath, false)
        end)

        if ok and reader then
            for _, entry in ipairs(readStyleEntriesFromReader(reader, modId, displayName)) do
                if entry.name and not seen[entry.name] then
                    seen[entry.name] = true
                    entries[#entries + 1] = entry
                end
            end
        end
    end

    return entries
end

local function ensureSourceIndex()
    local signature = buildActiveModsSignature()
    if cachedSourceIndex and cachedSourceSignature == signature then
        return cachedSourceIndex
    end

    local index = {
        hair = {},
        beard = {},
    }

    local activeMods = getActivatedMods and getActivatedMods() or nil

    if activeMods then
        for activeIndex = 0, activeMods:size() - 1 do
            local modId = tostring(activeMods:get(activeIndex))
            local displayName = getModDisplayName(modId)

            if not M.isExcludedMod(modId, displayName) then
                local hairStyleEntries = readStyleEntriesFromMod(modId, displayName, HAIR_STYLE_FILE_PATHS)
                for _, entry in ipairs(hairStyleEntries) do
                    if entry.name and not M.isVanillaStyle(entry.name, false) then
                        index.hair[entry.name] = entry.source or makeSource(modId, displayName, nil)
                    end
                end

                local beardStyleEntries = readStyleEntriesFromMod(modId, displayName, BEARD_STYLE_FILE_PATHS)
                for _, entry in ipairs(beardStyleEntries) do
                    if entry.name and not M.isVanillaStyle(entry.name, true) then
                        index.beard[entry.name] = entry.source or makeSource(modId, displayName, nil)
                    end
                end
            end
        end
    end

    cachedSourceIndex = index
    cachedSourceSignature = signature
    return cachedSourceIndex
end

function M.getDefaultSourceFilterId()
    return M.ALL_ID
end

function M.decorateEntries(entries, isBeard)
    if type(entries) ~= "table" then return entries end

    local baseLabel = M.getBaseLabel()
    local sourceIndex = ensureSourceIndex()
    local styleSourceIndex = isBeard and sourceIndex.beard or sourceIndex.hair

    for _, entry in ipairs(entries) do
        entry.sourceId = M.BASE_ID
        entry.sourceDisplay = baseLabel
        entry.sourceOrder = M.VANILLA_ORDER

        local styleName = tostring(entry.id or "")

        -- Vanilla IDs always stay Vanilla, even if a mod also contains them.
        if not M.isVanillaStyle(styleName, isBeard) then
            local source = styleSourceIndex[styleName]

            if source then
                entry.sourceId = source.id or M.BASE_ID
                entry.sourceDisplay = source.display or baseLabel
                entry.sourceOrder = source.order or M.DEFAULT_SOURCE_ORDER
            end
        end
    end

    return entries
end

local function compareEntries(a, b)
    local ao = tonumber(a.sourceOrder or M.DEFAULT_SOURCE_ORDER) or M.DEFAULT_SOURCE_ORDER
    local bo = tonumber(b.sourceOrder or M.DEFAULT_SOURCE_ORDER) or M.DEFAULT_SOURCE_ORDER

    if ao ~= bo then
        return ao < bo
    end

    local as = normalize(a.sourceDisplay or "")
    local bs = normalize(b.sourceDisplay or "")

    if as ~= bs then
        return as < bs
    end

    local ad = normalize(a.display or a.id or "")
    local bd = normalize(b.display or b.id or "")

    if ad ~= bd then
        return ad < bd
    end

    return normalize(a.id or "") < normalize(b.id or "")
end

function M.sortedEntryCopy(entries)
    local copy = {}

    for _, entry in ipairs(entries or {}) do
        copy[#copy + 1] = entry
    end

    table.sort(copy, compareEntries)

    return copy
end

function M.filterEntriesBySource(entries, sourceFilterId)
    local filterId = sourceFilterId or M.ALL_ID

    if filterId == M.ALL_ID then
        return M.sortedEntryCopy(entries or {})
    end

    local filtered = {}
    for _, entry in ipairs(entries or {}) do
        if entry.sourceId == filterId then
            filtered[#filtered + 1] = entry
        end
    end

    table.sort(filtered, compareEntries)

    return filtered
end

local function compareSourceOptions(a, b)
    local ao = tonumber(a.order or M.DEFAULT_SOURCE_ORDER) or M.DEFAULT_SOURCE_ORDER
    local bo = tonumber(b.order or M.DEFAULT_SOURCE_ORDER) or M.DEFAULT_SOURCE_ORDER

    if ao ~= bo then
        return ao < bo
    end

    return tostring(a.display or ""):lower() < tostring(b.display or ""):lower()
end

function M.getSourceFilterOptions(entries)
    local options = {
        { id = M.ALL_ID, display = M.getAllLabel(), order = -999999 },
    }

    local sourceOptions = {}
    local seenSources = {}

    for _, entry in ipairs(entries or {}) do
        local sourceId = entry.sourceId

        if sourceId == M.BASE_ID then
            if not seenSources[M.BASE_ID] then
                seenSources[M.BASE_ID] = true
                sourceOptions[#sourceOptions + 1] = {
                    id = M.BASE_ID,
                    display = M.getBaseLabel(),
                    order = M.VANILLA_ORDER,
                }
            end
        elseif sourceId and not seenSources[sourceId] then
            seenSources[sourceId] = true
            sourceOptions[#sourceOptions + 1] = {
                id = sourceId,
                display = entry.sourceDisplay or tostring(sourceId),
                order = entry.sourceOrder or M.DEFAULT_SOURCE_ORDER,
            }
        end
    end

    table.sort(sourceOptions, compareSourceOptions)

    for _, option in ipairs(sourceOptions) do
        options[#options + 1] = option
    end

    return options
end

function M.hasSourceFilterOption(options, sourceFilterId)
    for _, option in ipairs(options or {}) do
        if option.id == sourceFilterId then
            return true
        end
    end
    return false
end