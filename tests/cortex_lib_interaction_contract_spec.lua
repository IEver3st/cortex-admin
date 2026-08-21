local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

local function readSource(relativePath)
    local file = assert(io.open(resourceRoot .. '/' .. relativePath, 'rb'))
    local source = file:read('*a')
    file:close()
    return source:gsub('\r\n', '\n')
end

local function isolate(source, first, last)
    local startIndex = assert(source:find(first, 1, true), 'missing source contract: ' .. first)
    local endIndex = assert(source:find(last, startIndex, true), 'missing source contract: ' .. last)
    return source:sub(startIndex, endIndex - 1)
end

local mainSource = readSource('client/main.lua')
local actionsSource = readSource('client/actions.lua')

local notifyHelper = isolate(mainSource, 'local function notify(notifyType, message)', 'EsAdmin.notify = notify')
assert(notifyHelper:lower():find('position', 1, true), 'notification helper must document the cortex-lib-owned position contract')
assert(not notifyHelper:find('position =', 1, true), 'cortex-admin must not override the cortex-lib notification position')
assert(not notifyHelper:find('sound =', 1, true), 'cortex-admin must not override the cortex-lib notification sound setting')
assert(notifyHelper:find("exports['cortex-lib']:notify", 1, true), 'notifications must be rendered by cortex-lib')

local networkNotify = isolate(
    mainSource,
    "RegisterNetEvent('cortex-admin:client:notify'",
    "RegisterNetEvent('cortex-admin:client:copyText'"
)
assert(networkNotify:find('notify(notifyType, message)', 1, true), 'server notifications must use the shared preference-aware helper')
assert(not networkNotify:find('PlaySoundFrontend', 1, true), 'server notifications must not bypass cortex-lib sound preferences')
assert(not networkNotify:find('position', 1, true), 'server notifications must not override cortex-lib placement')

local actionClipboard = isolate(actionsSource, 'function copyToClipboard(text)', 'function buildCoordClipboardText(format)')
assert(actionClipboard:find('Admin.copyToClipboard(text)', 1, true), 'admin actions must use the centralized cortex-lib clipboard bridge')

local clipboardBridge = isolate(mainSource, 'function EsAdmin.copyToClipboard(text)', 'local function getCurrentWeather()')
assert(clipboardBridge:find("exports['cortex-lib']:copyToClipboard", 1, true), 'clipboard writes must use cortex-lib')

local stopEvent = "AddEventHandler('onResourceStop', function(resourceName)"
local firstStopHandlerStart = assert(actionsSource:find(stopEvent, 1, true))
local finalStopHandlerStart = assert(actionsSource:find(stopEvent, firstStopHandlerStart + #stopEvent, true))
local finalStopHandlerEnd = assert(actionsSource:find('CreateThread(function()', finalStopHandlerStart, true))
local finalStopHandler = actionsSource:sub(finalStopHandlerStart, finalStopHandlerEnd - 1)
assert(finalStopHandler:find('setFreecam(false, true)', 1, true), 'resource stop must clear freecam help')
assert(finalStopHandler:find('if noclip.enabled then', 1, true), 'resource stop must detect active noclip help')
assert(finalStopHandler:find('setNoclip(false)', 1, true), 'resource stop must clear noclip help through cortex-lib')

print('cortex-lib interaction contract tests passed')
