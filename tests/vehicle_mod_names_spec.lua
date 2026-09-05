local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(sourcePath:match('^(.*)/tests/[^/]+$'))
local file = assert(io.open(root .. '/client/actions.lua', 'r'))
local source = file:read('*a'); file:close()
local first = assert(source:find('Admin.getVehicleCustomization = function', 1, true))
local last = assert(source:find('Admin.setVehicleCustomization = function', first, true))
local chunk = source:sub(first, last - 1)

local function fixture(options)
    options = options or {}
    local f = { time = 0, loaded = options.loaded or false, requested = 0, reads = 0, target = 42 }
    local env = setmetatable({ Admin = {} }, { __index = _G })
    function env.getDrivenCustomizationVehicle() return f.target, 'studio_session_expired' end
    function env.HasThisAdditionalTextLoaded(bank, slot)
        assert(bank == 'mod_mnu' and slot == 10)
        return f.loaded
    end
    function env.RequestAdditionalText(bank, slot)
        assert(bank == 'mod_mnu' and slot == 10)
        f.requested = f.requested + 1
    end
    function env.GetGameTimer() return f.time end
    function env.GetGameBuildNumber() return options.build or 3095 end
    function env.safeNativeWholeNumber(fn, fallback)
        local ok, value = pcall(fn)
        return ok and math.floor(value) or fallback
    end
    function env.Wait()
        f.time = f.time + 100
        if not options.timeout then f.loaded = true end
        if options.closed then f.target = nil end
        if options.changed then f.target = 43 end
    end
    function env.SetVehicleModKit(vehicle, kit) assert(vehicle == 42 and kit == 0) end
    function env.GetNumVehicleMods(_, id) return id == 0 and 3 or 0 end
    function env.GetVehicleMod() return -1 end
    function env.GetModTextLabel(_, id, index)
        f.reads = f.reads + 1
        assert(id == 0)
        return ({ 'SPOILER_A', 'SPOILER_B', 'ADDON_MISSING' })[index + 1]
    end
    function env.GetLabelText(label)
        if not f.loaded then return 'NULL' end
        return ({ SPOILER_A = 'Lip Spoiler', SPOILER_B = 'Carbon Wing' })[label] or 'NULL'
    end
    function env.getVehicleLabel() return 'Test vehicle' end
    function env.customizationInteger(value) return value end
    function env.importedExtraLabelsForVehicle() return {} end
    function env.DoesExtraExist() return false end
    for _, name in ipairs({ 'GetVehicleNeonLightsColour', 'GetVehicleTyreSmokeColor',
        'GetVehicleModColor_1', 'GetVehicleModColor_2', 'GetIsVehiclePrimaryColourCustom',
        'GetIsVehicleSecondaryColourCustom', 'GetEntityModel', 'GetVehicleNumberPlateText',
        'GetVehicleLivery', 'GetVehicleNumberPlateTextIndex', 'GetVehicleWindowTint',
        'GetVehicleWheelType', 'GetVehicleXenonLightsColour', 'GetVehicleEnveffScale',
        'IsVehicleNeonLightEnabled', 'IsToggleModOn', 'GetVehicleColours',
        'GetVehicleExtraColours', 'GetVehicleDashboardColour', 'GetVehicleInteriorColour',
        'GetVehicleLiveryCount' }) do env[name] = function() return 0, 0, 0 end end
    assert(load(chunk, '@client/actions.lua:mod-names', 't', env))()
    f.read = env.Admin.getVehicleCustomization
    return f
end

local f = fixture()
local data = assert(f.read('session'))
assert(data.gameBuild == 3095, 'Customization publishes the active game build for plate availability')
assert(f.requested == 1 and f.time == 100, 'Wait for the label bank before reading names')
assert(data.mods['0'].names['0'] == 'Lip Spoiler')
assert(data.mods['0'].names['1'] == 'Carbon Wing')
assert(data.mods['0'].names['2'] == nil, 'Do not invent missing addon names')
assert(data.mods['0'].current == -1 and data.mods['0'].max == 3)
f.read('session'); assert(f.requested == 1, 'Reuse the loaded bank')
f = fixture({ timeout = true })
data = assert(f.read('session'))
assert(f.time == 1000 and data.mods['0'].names['0'] == nil, 'Loading failure must remain bounded')
f = fixture({ closed = true })
local result, err = f.read('session')
assert(result == nil and err == 'studio_session_expired' and f.reads == 0)
f = fixture({ changed = true })
result, err = f.read('session')
assert(result == nil and err == 'vehicle_changed' and f.reads == 0)
print('vehicle modification names, streaming timeout and stale target tests passed')
