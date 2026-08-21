local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

local function readSource(relativePath)
    local file = assert(io.open(resourceRoot .. '/' .. relativePath, 'rb'))
    local source = file:read('*a')
    file:close()
    return source
end

local actionsSource = readSource('client/actions.lua')
local appSource = readSource('ui/app.js')
local cssSource = readSource('ui/style.css')

assert(
    actionsSource:find("keyOrName:sub(1, #'mp_character_category_') == 'mp_character_category_'", 1, true),
    'vMenu saved-character keys must be normalized to their player-facing outfit names'
)
assert(
    actionsSource:find("keyOrName:sub(#'mp_character_category_' + 1)", 1, true),
    'vMenu saved-character prefixes must be removed before local import'
)
assert(
    appSource:find('normalizeSavedOutfitEntry', 1, true),
    'saved outfit payloads need a defensive UI name normalizer'
)
assert(
    appSource:find("className: 'appearance-workspace-utility appearance-workspace-utility--empty-share'", 1, true),
    'the no-nearby-player state must render as a compact utility row'
)
assert(
    not appSource:find("className: 'appearance-inline-note appearance-inline-note--tight' }, 'No eligible players nearby'", 1, true),
    'the no-nearby-player state must not use the intrusive informational banner'
)
assert(
    appSource:find("migrationAvailable && React.createElement('div', { className: 'appearance-workspace-utility appearance-workspace-utility--import'", 1, true),
    'vMenu import must stay hidden when there is nothing available to import'
)
assert(
    appSource:find("className: 'appearance-preset-row appearance-saved-outfit-row'", 1, true)
        and cssSource:find('.appearance-saved-outfit-row {', 1, true)
        and cssSource:find('grid-template-columns: minmax(0, 1fr) auto;', 1, true),
    'saved outfit rows must reserve a column for the outfit name'
)
assert(
    cssSource:find('.appearance-workspace-utility {', 1, true),
    'secondary outfit workspace actions need a compact shared utility style'
)

print('outfit workspace name and secondary-state UI contract tests passed')
