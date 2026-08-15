local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

Config = {
    BanIdentifierTypes = { 'license' },
    KvpKeys = { bans = 'cortex-admin_bans_test' },
}
EsAdminServer = {}

local failEncoding = false
local failWrite = false
local persistedValue

json = {
    encode = function()
        if failEncoding then error('forced ban serialization failure') end
        return '{"version":2}'
    end,
    decode = function() return {} end,
}

function GetResourceKvpString()
    return nil
end

function SetResourceKvp(_, value)
    if failWrite then error('forced KVP write failure') end
    persistedValue = value
end

dofile(resourceRoot .. '/server/actions.lua')

local record = assert(EsAdminServer.addBan(
    { 'license:transactional-unban' },
    'Regression fixture',
    'Test admin',
    0,
    'Test player'
), 'test ban was not added')
assert(persistedValue, 'test ban was not persisted')

failEncoding = true
local removed = EsAdminServer.removeBan(record.id)

assert(removed == false, 'unban should report serialization failure')
local remaining = EsAdminServer.listBans()
assert(#remaining == 1, 'failed unban removed the live ban record')
assert(remaining[1].id == record.id, 'failed unban restored the wrong record')

failEncoding = false
assert(EsAdminServer.removeBan(record.id) == true, 'fixture cleanup failed')

local writeFailureRecord = assert(EsAdminServer.addBan(
    { 'license:transactional-unban-write' },
    'Write failure fixture',
    'Test admin',
    0,
    'Test player'
), 'write failure test ban was not added')

failWrite = true
local callOk, writeRemoved = pcall(EsAdminServer.removeBan, writeFailureRecord.id)
assert(callOk, 'KVP write errors should be reported as persistence failures')
assert(writeRemoved == false, 'unban should report KVP write failure')
remaining = EsAdminServer.listBans()
assert(#remaining == 1, 'KVP write failure removed the live ban record')
assert(remaining[1].id == writeFailureRecord.id, 'KVP write failure restored the wrong record')

print('unban persistence failure-path tests passed')
