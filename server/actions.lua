EsAdminServer = EsAdminServer or {}

local bans = {}

local function loadBans()
    local raw = GetResourceKvpString(Config.KvpKeys.bans)
    if not raw or raw == '' then
        bans = {}
        return
    end

    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then
        bans = decoded
    else
        bans = {}
    end
end

local function saveBans()
    SetResourceKvp(Config.KvpKeys.bans, json.encode(bans))
end

local function normalizeIdentifiers(identifiers)
    local list = {}
    for _, identifier in ipairs(identifiers) do
        local prefix = identifier:match('([^:]+):')
        if prefix then
            for _, allowed in ipairs(Config.BanIdentifierTypes) do
                if prefix == allowed then
                    list[#list + 1] = identifier
                    break
                end
            end
        end
    end
    return list
end

local function isBanExpired(entry)
    if not entry then
        return true
    end
    if entry.expires and entry.expires > 0 then
        return os.time() > entry.expires
    end
    return false
end

local function findBan(identifiers)
    for _, identifier in ipairs(normalizeIdentifiers(identifiers)) do
        local entry = bans[identifier]
        if entry then
            if isBanExpired(entry) then
                bans[identifier] = nil
            else
                return entry, identifier
            end
        end
    end
    return nil
end

local function addBan(identifiers, reason, adminName, durationMinutes)
    local expires = nil
    if durationMinutes and durationMinutes > 0 then
        expires = os.time() + math.floor(durationMinutes * 60)
    end

    for _, identifier in ipairs(normalizeIdentifiers(identifiers)) do
        bans[identifier] = {
            reason = reason or 'Banned',
            admin = adminName or 'Console',
            time = os.time(),
            expires = expires,
        }
    end

    saveBans()
end

EsAdminServer.loadBans = loadBans
EsAdminServer.saveBans = saveBans
EsAdminServer.findBan = findBan
EsAdminServer.addBan = addBan

loadBans()
