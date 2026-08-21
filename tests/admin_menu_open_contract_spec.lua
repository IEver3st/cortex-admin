local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

local function readSource(relativePath)
    local file = assert(io.open(resourceRoot .. '/' .. relativePath, 'rb'))
    local source = file:read('*a')
    file:close()
    return source:gsub('\r\n', '\n')
end

local mainSource = readSource('client/main.lua')
local vmenuSource = readSource('client/vmenu_compat.lua')
local nuiSource = readSource('client/nui.lua')

local function assertContains(source, fragment, message)
    assert(source:find(fragment, 1, true), message or ('missing source contract: ' .. fragment))
end

local function assertBefore(source, first, second, message)
    local firstIndex = assert(source:find(first, 1, true), 'missing first source contract: ' .. first)
    local secondIndex = assert(source:find(second, 1, true), 'missing second source contract: ' .. second)
    assert(firstIndex < secondIndex, message or (first .. ' must precede ' .. second))
end

assertContains(mainSource, 'local function sendUiState(includeStatic)', 'UI state sender must distinguish static hydration from dynamic refreshes')
assertContains(mainSource, 'if includeStatic then', 'full UI state must remain available for NUI initialization')
assertContains(mainSource, 'local uiReady = false', 'client must track NUI readiness for open-before-ready fallback')
assertContains(mainSource, 'local MENU_TOGGLE_CLOSE_GUARD_MS = 500', 'key toggles need a bounded close guard after opening')
assertContains(mainSource, 'local elapsedSinceOpen = GetGameTimer() - menuOpenedAt', 'toggle close guard must use the game timer')
assertContains(mainSource, 'elapsedSinceOpen < MENU_TOGGLE_CLOSE_GUARD_MS', 'duplicate key activations must not immediately close a newly opened menu')
local hydrationStart = assert(mainSource:find('local function startMenuHydration(openGeneration)', 1, true))
local hydrationSource = mainSource:sub(hydrationStart)
assertBefore(hydrationSource, 'Wait(0)', 'refreshPlayerList()', 'hydration must yield before refreshing the player list')

local setOpenStart = assert(mainSource:find('local function setOpen(open)', 1, true))
local setOpenEnd = assert(mainSource:find('EsAdmin.setOpen = setOpen', setOpenStart, true))
local setOpenSource = mainSource:sub(setOpenStart, setOpenEnd)
assertBefore(setOpenSource, "SendNUIMessage({ action = 'cortex-admin:open' })", 'startMenuHydration(', 'visible open signal must precede expensive hydration')
assertContains(setOpenSource, 'startMenuControlThread()', 'menu controls must start without waiting for state hydration')
assertContains(setOpenSource, 'startMenuHydration(openGeneration)', 'state hydration must be deferred from the command callback')
assertContains(mainSource, [=[if uiReady then
            sendUiState(false)
        else
            -- If open raced the NUI ready callback, retain a full-state fallback.
            sendUiState(true)
        end]=], 'reopen must use dynamic state while retaining a full-state readiness fallback')
assertContains(mainSource, 'local function toggleMenu()', 'all key/command entry points must use one toggle helper')
assertContains(mainSource, 'EsAdmin.toggleMenu = toggleMenu', 'vMenu compatibility must be able to call the centralized toggle helper')
assertContains(vmenuSource, 'Admin.toggleMenu()', 'vMenu alias must use the centralized toggle behavior')
assertContains(nuiSource, 'Admin.markUiReady()', 'NUI ready must explicitly hydrate the full initial state')
assertContains(nuiSource, "Admin.setOpen(false)", 'explicit NUI close/Escape must remain an unconditional close path')
assert(not mainSource:find('now %- menuFocusTick >= 500'), 'focus must not be reasserted on a recurring 500 ms timer')
assert(not mainSource:find('menuFocusTick', 1, true), 'obsolete periodic focus timer state must be removed')

print('admin menu open latency and toggle race contract tests passed')
