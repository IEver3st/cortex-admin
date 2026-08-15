local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

local file = assert(io.open(resourceRoot .. '/client/actions.lua', 'rb'))
local clientSource = file:read('*a')
file:close()

assert(
    not clientSource:find('Config.WardrobeShareRadius', 1, true),
    'client must not own an independent wardrobe-share radius'
)
assert(
    clientSource:find('WardrobeSharePolicy.validateTargetSnapshot', 1, true),
    'client must validate the target snapshot returned by the server'
)
assert(
    clientSource:find('WardrobeSharePolicy.isDistanceSquaredWithinRadius', 1, true),
    'client and server must use the same inclusive radius boundary helper'
)

print('wardrobe share client radius contract tests passed')
