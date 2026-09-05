local path = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = path:match('^(.*)/tests/[^/]+$') or '.'
local file = assert(io.open(root .. '/client/actions.lua', 'r'))
local source = file:read('*a'); file:close()
local env = setmetatable({}, { __index = _G })
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(last, start + #first, true))
    assert(load(source:sub(start, finish - 1), '@client/actions.lua:' .. first, 't', env))()
end
local current = { model = 1, hair = 17, highlight = 42 }
local restored, saved, failures = {}, {}, {}
local function check(actual, expected, label)
    if actual ~= expected then failures[#failures + 1] = label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual) end
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    local array = #value > 0 and value[0] == nil
    for key, child in pairs(value) do result[array and key or tostring(key)] = copy(child) end
    return result
end
env.Admin = { debugTrace = function() end }
env.getPed = function() return 10 end
env.GetEntityModel = function() return current.model end
env.joaat = function(name) return name == 'mp_m_freemode_01' and 1 or 2 end
env.isFreemodeModel = function(model) return model == 1 or model == 2 end
env.isFreemodePed = function() return env.isFreemodeModel(current.model) end
env.DoesEntityExist = function() return true end
env.GetPedHairColor = function() return current.hair end
env.GetPedHairHighlightColor = function() return current.highlight end
env.SetPedHairColor = function(_, primary, secondary) current.hair, current.highlight = primary, secondary end
-- A padded native struct, not nine Lua return values. The test substitutes the
-- native's buffer write at unpack time because stock Lua strings are immutable.
local packed = string.pack('<i4xxxxi4xxxxi4xxxxi4xxxxi4xxxxi4xxxxfxxxxfxxxxfxxxxi4xxxx', 21, 7, 3, 12, 8, 4, 0.25, 0.75, 0.125, 1)
local nativeBuffer
env.string = setmetatable({ unpack = function(format, buffer, offset)
    return string.unpack(format, buffer == nativeBuffer and packed or buffer, offset)
end }, { __index = string })
env.Citizen = { ReturnResultAnyway = function() return 'result' end, InvokeNative = function(hash, ped, buffer)
    assert(hash == 0x2746BD9D88C5C5D0 and ped == 10 and #buffer == 80)
    nativeBuffer = buffer
    return true
end }
env.GetPedHeadBlendData = function() return true, 21 end
env.GetPedDrawableVariation = function(_, id) return id + 3 end
env.GetPedTextureVariation = function(_, id) return id % 3 end
env.GetPedPaletteVariation = function(_, id) return id % 4 end
env.GetPedPropIndex = function(_, id) return id == 0 and 5 or -1 end
env.GetPedPropTextureIndex = function() return 2 end
env.GetPedFaceFeature = function(_, id) return (id - 10) / 10 end
env.GetPedEyeColor = function() return 13 end
env.GetPedHeadOverlayData = function(_, id) return true, id == 11 and 255 or id + 1, 2, 17, 42, 0.5 end
env.GetNumHeadOverlayValues = function() return 30 end
env.clampInteger = function(value, low, high) return math.max(low, math.min(high, tonumber(value) or low)) end
env.resolveComponentVariation = function(_, _, drawable, texture) return drawable, texture, false end
env.resolvePropVariation = env.resolveComponentVariation
env.SetPedComponentVariation = function(_, id, drawable, texture, palette) restored.components[id] = { drawable, texture, palette } end
env.SetPedPropIndex = function(_, id, drawable, texture) restored.props[id] = { drawable, texture } end
env.ClearPedProp = function(_, id) restored.props[id] = { -1, 0 } end
env.SetPedHeadBlendData = function(_, ...) restored.blend = { ... } end
env.SetPedFaceFeature = function(_, id, value) restored.features[id] = value end
env.SetPedEyeColor = function(_, value) restored.eye = value end
env.SetPedHeadOverlay = function(_, id, style, opacity) restored.overlays[id] = { style, opacity } end
env.SetPedHeadOverlayColor = function(_, id, colorType, color, highlight) restored.colors[id] = { colorType, color, highlight } end
env.ClearPedDecorations = function() end
env.authorizeModel = function(_, _, action) restored.authorization = action; return true end
env.exports = { ['cortex-lib'] = { requestModel = function() return true end } }
env.PlayerId = function() return 0 end
env.SetPlayerModel = function(_, model) current.model = model end
env.SetModelAsNoLongerNeeded = function() end
env.Wait = function() end
env.notify = function() end
env.kvpKey = function(prefix, name) return prefix .. name end
env.saveKvpJson = function(key, value) saved[key] = copy(value); return true end
env.loadKvpJson = function(key) return saved[key] end
local overlayStart = assert(source:find('local PED_OVERLAY_MAP =', 1, true))
local overlayEnd = assert(source:find('local LEGACY_FACE_FEATURE_FIELDS =', overlayStart, true))
env.PED_OVERLAY_MAP = assert(load(source:sub(overlayStart, overlayEnd - 1) .. '\nreturn PED_OVERLAY_MAP', 'overlays', 't', env))()
local featureStart = assert(source:find('local LEGACY_FACE_FEATURE_FIELDS =', 1, true))
local featureEnd = assert(source:find('local WARDROBE_SHARE_COMPONENT_BLACKLIST =', featureStart, true))
env.LEGACY_FACE_FEATURE_FIELDS = assert(load(source:sub(featureStart, featureEnd - 1) .. '\nreturn LEGACY_FACE_FEATURE_FIELDS', 'features', 't', env))()
env.C = { MODEL_HASH_MP_M = 1 }
env.cloneJsonTable = copy
env.isTableEmpty = function(value) return type(value) ~= 'table' or next(value) == nil end
section('function getCurrentHairColors(', 'function getWardrobeShareTargetSnapshot(')
section('function setPedComponent(', 'function applySharedWardrobeData(')
section('function buildDefaultHeadBlend(', 'function normalizeMpPedData(')
section('function normalizeMpPedData(', 'function isSavedMpPedData(')
section('function fetchPedComponent(', 'function buildSharedWardrobeData(')
section('function applyMpPedData(', '-- Register early')
section('function actionSavePed(', 'local function configuredWeaponModels(')

local function reset() restored = { components = {}, props = {}, features = {}, overlays = {}, colors = {} } end
reset()
env.Admin.setPedAppearance({ type = 'color', colorType = 'hairHighlight', value = 35 })
check(current.hair, 17, 'editing highlights preserves primary hair color')
env.Admin.setPedAppearance({ type = 'color', colorType = 'hair', value = 23 })
check(current.highlight, 35, 'editing hair preserves highlights')
current.hair, current.highlight = 17, 42
local appearance = env.Admin.getPedAppearance()
check(appearance.hairColor, 17, 'menu hair readback')
check(appearance.hairHighlightColor, 42, 'menu highlight readback')
local captured = env.captureMpPedData(10, 'Regression')
check(captured.HairColor, 17, 'saved hair color')
check(captured.HairHighlightColor, 42, 'saved highlights')
check(captured.PedHeadBlendData.shapeSecondID, 7, 'saved facial heritage')
check(captured.PedHeadBlendData.skinMix, 0.75, 'saved skin blend')
check(captured.HeadOverlays[12] and captured.HeadOverlays[12].style, 13, 'saved additional body blemishes')
check(captured.DrawableVariations.clothes[3][3], 3, 'saved component palette')
current.hair, current.highlight = 0, 0
local normalized = env.normalizeMpPedData(copy(captured))
check(normalized.DrawableVariations.clothes[2], nil, 'normalization must not insert a second hair component over JSON string keys')
assert(env.applyMpPedData(10, normalized))
check(current.hair, 17, 'restored hair color')
check(current.highlight, 42, 'restored highlights')
check(restored.blend[2], 7, 'restored facial heritage')
check(restored.blend[10], true, 'restored inheritance flag')
check(restored.features[4], -0.6, 'restored face features with JSON string keys')
check(restored.eye, 13, 'restored eye color')
check(restored.overlays[11][1], 255, 'disabled overlay stays disabled')
check(restored.colors[4][3], 42, 'restored secondary makeup color')
check(restored.components[3][3], 3, 'restored component palette')
check(restored.props[0][1], 5, 'restored props')
env.actionSavePed({ name = 'Freemode' })
current.hair, current.highlight = 0, 0
env.actionLoadPed({ name = 'Freemode' })
check(current.hair, 17, 'generic Save Ped preserves freemode appearance')
check(restored.authorization, 'player.loadPed', 'generic load retains its permission')
current.model = 99
env.actionSavePed({ name = 'NPC' })
reset()
env.actionLoadPed({ name = 'NPC' })
check(restored.components[3] and restored.components[3][1], 6, 'generic Save Ped preserves NPC clothing')
saved.ped_Legacy = { ModelHash = 98, Version = 1 }
env.actionLoadPed({ name = 'Legacy' })
check(current.model, 98, 'legacy model-only saves still load')
-- Old component tuples have no palette; retain the previous default.
reset()
assert(env.applyMpPedData(10, { ModelHash = 98, DrawableVariations = { clothes = { ['3'] = { 6, 1 } } } }))
check(restored.components[3][3], 2, 'legacy clothing palette default')
-- Never apply a saved appearance to the wrong model after streaming fails.
reset()
env.exports['cortex-lib'].requestModel = function() return false end
check(env.applyMpPedData(10, captured), false, 'model streaming failure')
check(next(restored.components), nil, 'no clothing applied after streaming failure')
env.authorizeModel = function() return false end
check(env.applyMpPedData(10, captured), false, 'unauthorized model rejected')
check(next(restored.components), nil, 'no clothing applied without authorization')
-- Failed native reads must not throw or return negative color sentinels.
env.GetPedHairColor = function() return -1 end
env.GetPedHairHighlightColor = function() error('native unavailable') end
local primary, highlight = env.readPedHairColorsSafely(10)
check(primary, 0, 'invalid hair native fallback')
check(highlight, 0, 'failed highlight native fallback')
env.Citizen.InvokeNative = function() return false end
local blend, found = env.readPedHeadBlendSafely(10)
check(found, false, 'missing head blend reported')
check(blend.shapeMix, 0.5, 'missing head blend fallback')
if #failures > 0 then error(table.concat(failures, '\n')) end
print('ped appearance save/edit/restore regression tests passed')
