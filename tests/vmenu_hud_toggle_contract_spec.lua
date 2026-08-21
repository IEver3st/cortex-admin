local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

local function readSource(relativePath)
    local file = assert(io.open(resourceRoot .. '/' .. relativePath, 'rb'))
    local source = file:read('*a')
    file:close()
    return source:gsub('\r\n', '\n')
end

local function assertContains(source, fragment, message)
    assert(source:find(fragment, 1, true), message or ('missing source contract: ' .. fragment))
end

local clientSource = readSource('client/vmenu_compat.lua')
local uiSource = readSource('ui/app.js')
local uiStyles = readSource('ui/style.css')

assertContains(clientSource, "toggleHandlers['dev.showTime'] = function(enabled)", 'time toggle must own an immediate disable path')
assertContains(clientSource, "SendNUIMessage({ action = 'cortex-admin:setTimeHud', data = { visible = false } })", 'time toggle must immediately hide its HUD')
assertContains(clientSource, 'local function buildVoiceHudPayload()', 'voice HUD state must be reconciled in one helper')
assertContains(clientSource, 'visible = (showStatus and talking) or #speakers > 0', 'enabled voice indicators must not leave an idle HUD onscreen')
assertContains(clientSource, "toggleHandlers['voice.showSpeaker'] = function()", 'speaker toggles must immediately reconcile the HUD')
assertContains(clientSource, "toggleHandlers['voice.showStatus'] = function()", 'status toggles must immediately reconcile the HUD')

assertContains(uiSource, "toggles['dev.showTime'] !== true", 'time HUD must obey authoritative false toggle state')
assertContains(uiSource, "toggles['voice.showSpeaker'] === true", 'voice HUD must obey authoritative speaker toggle state')
assertContains(uiSource, "toggles['voice.showStatus'] === true", 'voice HUD must obey authoritative status toggle state')
assertContains(uiSource, "if (!state.visible || (!state.talking && state.speakers.length === 0)) return null;", 'browser must defensively render no idle voice HUD')
assertContains(uiSource, "localTalking ? 'TRANSMITTING' : 'ACTIVE SPEAKERS'", 'voice HUD must only label live activity')
assert(not uiSource:find('VOICE IDLE', 1, true), 'voice HUD must not include an idle state')
assert(not uiSource:find('No nearby speakers', 1, true), 'voice HUD must not render an idle empty message')
assert(not uiSource:find("className: 'voice-page-header'", 1, true), 'voice workspace must not render a redundant page intro')
assert(not uiSource:find("className: 'voice-telemetry'", 1, true), 'voice workspace must not render a duplicate telemetry card')
assert(not uiSource:find("className: 'voice-switch-state'", 1, true), 'voice toggles must not render ON/OFF containers')
assert(not uiSource:find('voice-proximity-index', 1, true), 'compact proximity controls must omit decorative indexes')
assert(not uiSource:find('voice-proximity-check', 1, true), 'compact proximity controls must omit redundant check icons')
assertContains(uiStyles, '.voice-control-section:last-child', 'voice controls must use flat divided sections')
assertContains(uiStyles, 'grid-template-columns: repeat(4, minmax(0, 1fr));', 'voice proximity must retain a compact four-option row')

print('vMenu HUD toggle lifecycle contract tests passed')
