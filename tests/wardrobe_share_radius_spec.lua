local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

dofile(resourceRoot .. '/shared/wardrobe_share.lua')

local policy = assert(WardrobeSharePolicy, 'WardrobeSharePolicy was not initialized')

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertClose(actual, expected, message)
    if math.abs(actual - expected) > 0.000001 then
        error(('%s: expected %.8f, got %.8f'):format(message, expected, actual), 2)
    end
end

-- The server accepts finite positive configuration values verbatim.
assertClose(policy.normalizeRadius(6.25), 6.25, 'configured radius')
assertClose(policy.normalizeRadius('9.5'), 9.5, 'numeric-string radius')

-- Invalid configuration must resolve to one safe server default.
for _, invalid in ipairs({ false, 0, -1, math.huge, -math.huge }) do
    assertClose(policy.normalizeRadius(invalid), policy.DEFAULT_RADIUS, 'invalid radius fallback')
end
assertClose(policy.normalizeRadius(0 / 0), policy.DEFAULT_RADIUS, 'NaN radius fallback')

-- Discovery, client filtering, and final server validation share an inclusive boundary.
local radius = policy.normalizeRadius(8.0)
assertEqual(policy.isDistanceSquaredWithinRadius(63.999999, radius), true, 'point just inside radius')
assertEqual(policy.isDistanceSquaredWithinRadius(64.0, radius), true, 'point exactly on radius')
assertEqual(policy.isDistanceSquaredWithinRadius(64.000001, radius), false, 'point just outside radius')

-- Invalid measurements are always rejected rather than widening the boundary.
for _, invalidDistance in ipairs({ -1, math.huge, -math.huge, false }) do
    assertEqual(policy.isDistanceSquaredWithinRadius(invalidDistance, radius), false, 'invalid distance rejection')
end
assertEqual(policy.isDistanceSquaredWithinRadius(0 / 0, radius), false, 'NaN distance rejection')
assertEqual(policy.isDistanceSquaredWithinRadius(1.0, 0), false, 'invalid boundary rejection')

-- Client filtering only proceeds with the radius returned by the server snapshot.
local snapshot = policy.validateTargetSnapshot({
    radius = 6.5,
    targets = { 2, 3 },
})
assertEqual(type(snapshot), 'table', 'valid snapshot')
assertClose(snapshot.radius, 6.5, 'snapshot radius')
assertEqual(snapshot.targets[1], 2, 'snapshot targets')
assertEqual(policy.validateTargetSnapshot({ radius = 0, targets = { 2 } }), nil, 'invalid snapshot radius')
assertEqual(policy.validateTargetSnapshot({ radius = 8.0, targets = false }), nil, 'invalid snapshot targets')

print('wardrobe share radius boundary tests passed')
