local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(sourcePath:match('^(.*)/tests/[^/]+$'))
local file = assert(io.open(root .. '/client/actions.lua', 'r'))
local source = file:read('*a'); file:close()
local first = assert(source:find('local previewVehicle = 0', 1, true))
local last = assert(source:find('function actionRepairVehicle()', first, true))
local chunk = source:sub(first, last - 1)

-- Run the real preview entry points with independently resumable authorization
-- and streaming calls, matching overlapping NUI callback coroutines.
local function fixture()
    local f = { entities = {}, threads = {}, sequence = 0, loadWait = {}, authWait = {}, released = {} }
    local env = setmetatable({}, { __index = _G })
    env.Admin = { sendUiState = function() end }
    env.Config = {}
    env.freecam, env.noclip = { enabled = false }, { enabled = false }
    env.notify = function() end
    env.authorizeModel = function(_, model)
        if f.authWait[model] then coroutine.yield('authorization') end
        return true
    end
    env.exports = { ['cortex-lib'] = {
        requestModel = function(_, model)
            if f.loadWait[model] then coroutine.yield('model') end
            return true
        end,
        showHelp = function() end, hideHelp = function() end,
    } }
    env.joaat = function(model) return model end
    env.getPed = function() return 1 end
    env.GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end
    env.GetEntityHeading = function() return 0 end
    env.GetGroundZFor_3dCoord = function() return true, 0 end
    env.CreateVehicle = function(model, _, _, _, _, networked)
        f.sequence = f.sequence + 1
        f.entities[f.sequence] = { model = model, networked = networked }
        return f.sequence
    end
    env.DoesEntityExist = function(entity) return f.entities[entity] ~= nil end
    env.DeleteEntity = function(entity) f.entities[entity] = nil end
    env.NetworkGetEntityIsNetworked = function(entity) return f.entities[entity].networked end
    env.NetworkGetNetworkIdFromEntity = function(entity) return entity end
    env.Entity = function() return { state = { set = function() end } } end
    env.DoesExtraExist = function() return false end
    env.SetModelAsNoLongerNeeded = function(model) f.released[model] = true end
    env.CreateThread = function(fn) f.threads[#f.threads + 1] = coroutine.create(fn) end
    env.Wait = function() coroutine.yield('tick') end
    env.IsControlJustPressed = function() return f.closePressed == true end
    env.IsNuiFocused = function() return false end
    for _, name in ipairs({ 'RequestCollisionAtCoord', 'SetEntityAsMissionEntity', 'FreezeEntityPosition',
        'SetEntityInvincible', 'SetEntityCollision', 'SetEntityAlpha', 'SetVehicleEngineOn',
        'SetVehicleDirtLevel', 'SetVehicleOnGroundProperly', 'SetNetworkIdExistsOnAllMachines',
        'SetNetworkIdCanMigrate' }) do env[name] = function() end end
    assert(load(chunk, '@client/actions.lua:preview', 't', env))()
    f.admin = env.Admin
    f.resume = function(co)
        local ok, value = coroutine.resume(co)
        assert(ok, value)
        return value
    end
    f.begin = function(model)
        local co = coroutine.create(function() return f.admin.previewVehicle(model) end)
        f.resume(co)
        return co
    end
    f.count = function()
        local n = 0; for _ in pairs(f.entities) do n = n + 1 end; return n
    end
    return f
end

local cases = {
    { 'overlapping model loads leave no orphan after Clear', function(f)
        f.loadWait.first, f.loadWait.second = true, true
        local a, b = f.begin('first'), f.begin('second')
        f.resume(b); f.resume(a)
        f.admin.clearVehiclePreview()
        assert(f.count() == 0, 'Clear left an older preview vehicle stuck in the world')
    end },
    { 'latest selection wins out-of-order model completion', function(f)
        f.loadWait.first, f.loadWait.second = true, true
        local a, b = f.begin('first'), f.begin('second')
        f.resume(b); f.resume(a)
        assert(f.count() == 1 and f.admin.getPreviewVehicleModel() == 'second', 'Stale load replaced the selected preview')
    end },
    { 'Clear cancels a pending model load', function(f)
        f.loadWait.first = true
        local a = f.begin('first')
        f.admin.clearVehiclePreview(); f.resume(a)
        assert(f.count() == 0 and f.admin.getPreviewVehicleModel() == nil, 'Preview appeared after Clear')
        assert(f.released.first, 'Cancelled streaming request must release its model')
    end },
    { 'Clear cancels pending authorization', function(f)
        f.authWait.first = true
        local a = f.begin('first')
        f.admin.clearVehiclePreview(); f.resume(a)
        assert(f.count() == 0, 'Authorization revived a cleared preview')
    end },
    { 'latest selection wins out-of-order authorization', function(f)
        f.authWait.first = true
        local a = f.begin('first')
        f.begin('second'); f.resume(a)
        assert(f.count() == 1 and f.admin.getPreviewVehicleModel() == 'second', 'Stale authorization replaced the selected preview')
    end },
    { 'Clear cancels shared-preview recreation', function(f)
        f.begin('first'); f.loadWait.first = true
        local share = coroutine.create(function() return f.admin.setPreviewShared(true) end)
        f.resume(share); f.admin.clearVehiclePreview(); f.resume(share)
        assert(f.count() == 0 and not f.admin.getPreviewShared(), 'Share recreated a cleared preview')
    end },
    { 'new selection supersedes shared-preview recreation', function(f)
        f.begin('first'); f.loadWait.first = true
        local share = coroutine.create(function() return f.admin.setPreviewShared(true) end)
        f.resume(share); f.begin('second'); f.resume(share)
        assert(f.count() == 1 and f.admin.getPreviewVehicleModel() == 'second', 'Share left an orphan alongside the new preview')
        for _, entity in pairs(f.entities) do assert(entity.model == 'second' and not entity.networked) end
    end },
    { 'Backspace still clears a completed preview', function(f)
        f.begin('first'); f.closePressed = true
        f.resume(f.threads[#f.threads])
        assert(f.count() == 0 and f.admin.getPreviewVehicleModel() == nil)
    end },
}
local failures = {}
for _, case in ipairs(cases) do
    local ok, err = pcall(case[2], fixture())
    if not ok then failures[#failures + 1] = case[1] .. ': ' .. tostring(err) end
end
assert(#failures == 0, table.concat(failures, '\n'))
print(('Vehicle preview lifecycle: %d scenarios passed'):format(#cases))
