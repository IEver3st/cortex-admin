EsAdminServer = EsAdminServer or {}

local store = { version = 2, nextId = 1, records = {} }
local MAX_BANS = 4096
local MAX_IDENTIFIERS = 16

local function trim(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    if value == '' then return nil end
    if maxLength and #value > maxLength then value = value:sub(1, maxLength) end
    return value
end

local function allowedIdentifier(identifier)
    identifier = trim(identifier, 160)
    if not identifier then return nil end
    local prefix = identifier:match('^([%w_]+):')
    if not prefix then return nil end
    for index = 1, #(Config.BanIdentifierTypes or {}) do
        if prefix == Config.BanIdentifierTypes[index] then return identifier end
    end
    return nil
end

local function normalizeIdentifiers(identifiers)
    local list, seen = {}, {}
    if type(identifiers) ~= 'table' then return list end
    for _, rawIdentifier in pairs(identifiers) do
        local identifier = allowedIdentifier(rawIdentifier)
        if identifier and not seen[identifier] and #list < MAX_IDENTIFIERS then
            seen[identifier] = true
            list[#list + 1] = identifier
        end
    end
    table.sort(list)
    return list
end

local function finiteInteger(value, minValue, maxValue)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge or value ~= math.floor(value) then return nil end
    if minValue and value < minValue or maxValue and value > maxValue then return nil end
    return value
end

local function nextBanId()
    local sequence = finiteInteger(store.nextId, 1, 2147483647) or 1
    store.nextId = sequence + 1
    return ('cban-%d-%06d'):format(os.time(), sequence)
end

local function validBanId(value)
    value = trim(value, 96)
    if not value or not value:match('^[%w_%-:]+$') then return nil end
    return value
end

local function normalizeStoredRecord(raw, forcedId)
    if type(raw) ~= 'table' then return nil end
    local identifiers = normalizeIdentifiers(raw.identifiers)
    if #identifiers == 0 then return nil end
    local id = validBanId(forcedId or raw.id) or nextBanId()
    local createdAt = finiteInteger(raw.createdAt or raw.time, 0, 4102444800) or os.time()
    local expiresAt = finiteInteger(raw.expiresAt or raw.expires, 1, 32503680000)
    return {
        id = id,
        playerName = trim(raw.playerName or raw.name, 96) or 'Unknown player',
        identifiers = identifiers,
        reason = trim(raw.reason or raw.banReason, 240) or 'Banned',
        admin = trim(raw.admin or raw.bannedBy, 96) or 'Console',
        createdAt = createdAt,
        expiresAt = expiresAt,
        importedFrom = trim(raw.importedFrom, 48),
        sourceId = trim(raw.sourceId, 96),
    }
end

local function saveBans()
    local ok, encoded = pcall(json.encode, store)
    if not ok or type(encoded) ~= 'string' or #encoded > 4 * 1024 * 1024 then return false end
    SetResourceKvp(Config.KvpKeys.bans, encoded)
    return true
end

local function migrateLegacy(decoded)
    local grouped = {}
    for identifier, raw in pairs(decoded) do
        local safeIdentifier = allowedIdentifier(identifier)
        if safeIdentifier and type(raw) == 'table' then
            local signature = table.concat({
                tostring(raw.reason or ''), tostring(raw.admin or ''), tostring(raw.time or ''), tostring(raw.expires or ''),
            }, '\0')
            local group = grouped[signature]
            if not group then
                group = {
                    identifiers = {}, reason = raw.reason, admin = raw.admin,
                    time = raw.time, expires = raw.expires, playerName = raw.playerName,
                }
                grouped[signature] = group
            end
            group.identifiers[#group.identifiers + 1] = safeIdentifier
        end
    end
    for _, raw in pairs(grouped) do
        if #store.records >= MAX_BANS then break end
        local record = normalizeStoredRecord(raw)
        if record then store.records[#store.records + 1] = record end
    end
end

local function loadBans()
    store = { version = 2, nextId = 1, records = {} }
    local raw = GetResourceKvpString(Config.KvpKeys.bans)
    if not raw or raw == '' or #raw > 4 * 1024 * 1024 then return end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return end

    if decoded.version == 2 and type(decoded.records) == 'table' then
        store.nextId = finiteInteger(decoded.nextId, 1, 2147483647) or 1
        local seen = {}
        for index = 1, math.min(#decoded.records, MAX_BANS) do
            local record = normalizeStoredRecord(decoded.records[index])
            if record and not seen[record.id] then
                seen[record.id] = true
                store.records[#store.records + 1] = record
            end
        end
    else
        migrateLegacy(decoded)
        saveBans()
    end
end

local function isBanExpired(entry, now)
    if type(entry) ~= 'table' then return true end
    return entry.expiresAt ~= nil and entry.expiresAt > 0 and (now or os.time()) >= entry.expiresAt
end

local function cleanupExpired(saveAfter)
    local now, changed = os.time(), false
    for index = #store.records, 1, -1 do
        if isBanExpired(store.records[index], now) then
            table.remove(store.records, index)
            changed = true
        end
    end
    if changed and saveAfter ~= false then saveBans() end
    return changed
end

local function findBan(identifiers)
    cleanupExpired(true)
    local lookup = {}
    for _, identifier in ipairs(normalizeIdentifiers(identifiers)) do lookup[identifier] = true end
    for index = 1, #store.records do
        local entry = store.records[index]
        for identifierIndex = 1, #entry.identifiers do
            if lookup[entry.identifiers[identifierIndex]] then return entry, entry.identifiers[identifierIndex] end
        end
    end
    return nil
end

local function addBan(identifiers, reason, adminName, durationMinutes, playerName, provenance)
    cleanupExpired(false)
    if #store.records >= MAX_BANS then return nil end
    local normalized = normalizeIdentifiers(identifiers)
    if #normalized == 0 then return nil end
    durationMinutes = finiteInteger(durationMinutes, 0, 525600) or 0
    local createdAt = os.time()
    local record = {
        id = nextBanId(),
        playerName = trim(playerName, 96) or 'Unknown player',
        identifiers = normalized,
        reason = trim(reason, 240) or 'Banned',
        admin = trim(adminName, 96) or 'Console',
        createdAt = createdAt,
        expiresAt = durationMinutes > 0 and createdAt + durationMinutes * 60 or nil,
        importedFrom = trim(provenance, 48),
    }
    store.records[#store.records + 1] = record
    if not saveBans() then
        table.remove(store.records, #store.records)
        return nil
    end
    return record
end

local function listBans()
    cleanupExpired(true)
    local output = {}
    for index = 1, #store.records do
        local entry = store.records[index]
        output[#output + 1] = {
            id = entry.id,
            playerName = entry.playerName,
            identifiers = entry.identifiers,
            reason = entry.reason,
            admin = entry.admin,
            createdAt = entry.createdAt,
            expiresAt = entry.expiresAt,
            importedFrom = entry.importedFrom,
        }
    end
    table.sort(output, function(first, second)
        return (first.createdAt or 0) > (second.createdAt or 0)
    end)
    return output
end

local function removeBan(id)
    id = validBanId(id)
    if not id then return false end
    for index = 1, #store.records do
        if store.records[index].id == id then
            table.remove(store.records, index)
            return saveBans()
        end
    end
    return false
end

local function parseVmenuExpiry(value)
    if type(value) ~= 'string' then return nil end
    local year, month, day, hour, minute, second = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)')
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
    if not year or year >= 3000 then return nil end
    if year < 2020 or not month or not day or not hour or not minute or not second then return nil end
    local ok, timestamp = pcall(os.time, { year = year, month = month, day = day, hour = hour, min = minute, sec = second })
    return ok and timestamp or nil
end

local function importVmenuBans(records)
    if type(records) ~= 'table' then return { imported = 0, skipped = 0, invalid = 1, total = 0 } end
    cleanupExpired(false)
    local result = { imported = 0, skipped = 0, invalid = 0, total = math.min(#records, MAX_BANS) }
    local existingSourceIds = {}
    for index = 1, #store.records do
        local entry = store.records[index]
        if entry.importedFrom == 'vmenu' and entry.sourceId then existingSourceIds[entry.sourceId] = true end
    end

    for index = 1, result.total do
        local raw = records[index]
        local identifiers = type(raw) == 'table' and normalizeIdentifiers(raw.identifiers) or {}
        local sourceId = type(raw) == 'table' and trim(tostring(raw.uuid or ''), 96) or nil
        if #identifiers == 0 or not sourceId or sourceId == '' then
            result.invalid = result.invalid + 1
        elseif existingSourceIds[sourceId] then
            result.skipped = result.skipped + 1
        elseif #store.records >= MAX_BANS then
            result.invalid = result.invalid + 1
        else
            local record = {
                id = validBanId('vmenu-' .. sourceId) or nextBanId(),
                playerName = trim(raw.playerName, 96) or 'Unknown player',
                identifiers = identifiers,
                reason = trim(raw.banReason, 240) or 'Imported vMenu ban',
                admin = trim(raw.bannedBy, 96) or 'vMenu',
                createdAt = os.time(),
                expiresAt = parseVmenuExpiry(raw.bannedUntil),
                importedFrom = 'vmenu',
                sourceId = sourceId,
            }
            store.records[#store.records + 1] = record
            existingSourceIds[sourceId] = true
            result.imported = result.imported + 1
        end
    end
    saveBans()
    return result
end

EsAdminServer.loadBans = loadBans
EsAdminServer.saveBans = saveBans
EsAdminServer.cleanupExpiredBans = cleanupExpired
EsAdminServer.findBan = findBan
EsAdminServer.addBan = addBan
EsAdminServer.listBans = listBans
EsAdminServer.removeBan = removeBan
EsAdminServer.importVmenuBans = importVmenuBans

loadBans()
