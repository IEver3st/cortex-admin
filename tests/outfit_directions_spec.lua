local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(sourcePath:match('^(.*)/tests/[^/]+$'))
dofile(root .. '/shared/appearance_catalog.lua')
dofile(root .. '/shared/appearance_index.lua')
dofile(root .. '/shared/appearance_randomizer.lua')

local styles = { 'polished', 'casual', 'street', 'sport', 'utility', 'biker', 'resort', 'nightlife', 'designer' }
local function read(path)
    local file = assert(io.open(root .. '/' .. path, 'rb'))
    local content = file:read('*a'); file:close(); return content
end
local app = read('ui/app.js')
for _, style in ipairs(styles) do
    assert(AppearanceRandomizer.sanitizeOptions({ style = style }).style == style)
    assert(app:find("generatorChoice('style', '" .. style .. "'", 1, true), 'Missing UI direction: ' .. style)
end

for _, gender in ipairs({ 'male', 'female' }) do
    local used = { tops = {}, bottoms = {}, shoes = {} }
    for _, style in ipairs(styles) do
        for _, palette in ipairs({ 'neutral', 'tonal', 'varied' }) do
            local modern = 0
            for _, family in ipairs(AppearanceRandomizer.getOutfitFamilies(gender, style, palette)) do
                if not family.fallback then
                    modern = modern + 1
                    for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
                        assert(#family.pools[category] > 0)
                        for _, piece in ipairs(family.pools[category]) do
                            for _, component in ipairs(piece.components) do
                                assert(AppearanceIndex[gender][component.component][component.globalDrawable], 'Missing collection or torso identity')
                                if component.component == ({ tops = 11, bottoms = 4, shoes = 6 })[category] then
                                    used[category][component.globalDrawable] = true
                                end
                            end
                            local focal = family.id == 'sneaker_focus' and palette == 'varied' and 'shoes' or 'tops'
                            local expected = category == focal and palette or 'neutral'
                            assert(piece.id:find('-' .. expected .. '-', 1, true), 'Only the focal piece may carry color')
                        end
                    end
                end
            end
            assert(modern >= 2, style .. ' needs distinct modern silhouettes for ' .. gender)
        end
    end
    for category, ids in pairs(used) do
        local count = 0; for _ in pairs(ids) do count = count + 1 end
        assert(count >= ({ tops = 22, bottoms = 12, shoes = 8 })[category], 'Expansion pieces must reach actual outfit families')
    end
end

-- Execute the production selector with native stubs, including addon impostors
-- and missing DLC. A valid global count alone must never authorize a piece.
local actions = read('client/actions.lua')
local start = assert(actions:find('local function generatedComponentIsValid', 1, true))
local finish = assert(actions:find('Admin.getStudioCatalog = function()', start, true))
local gender, availability = 'male', 'modern'
function joaat(name) return name end
function GetEntityModel() return gender == 'male' and 'mp_m_freemode_01' or 'mp_f_freemode_01' end
function GetNumberOfPedDrawableVariations() return 2000 end
function GetNumberOfPedTextureVariations() return 100 end
function GetNumberOfPedPropDrawableVariations() return 0 end
function GetPedCollectionNameFromDrawable(_, slot, drawable)
    local identity = AppearanceIndex[gender][slot][drawable]
    if availability == 'addon' and identity.collection ~= '' then return 'addon_impostor' end
    return identity.collection
end
function GetPedCollectionLocalIndexFromDrawable(_, slot, drawable)
    return AppearanceIndex[gender][slot][drawable].drawable
end
local selectOutfit = assert(load(actions:sub(start, finish - 1) .. '\nreturn selectGeneratedOutfit'))()
math.randomseed(90210)
for _, body in ipairs({ 'male', 'female' }) do
    gender = body
    for _, style in ipairs(styles) do
        availability = 'modern'
        local modernNames = {}
        for _, family in ipairs(AppearanceRandomizer.getOutfitFamilies(gender, style, 'varied')) do
            if not family.fallback then modernNames[family.name] = true end
        end
        for _ = 1, 30 do
            local outfit = assert(selectOutfit(1, { style = style, palette = 'varied', accessories = true }))
            assert(modernNames[outfit.name:match('^(.-): ')], 'Newer compatible families must take priority')
            assert(#outfit.components == 5 and #outfit.accessories == 0)
        end
        availability = 'addon'
        local fallback = selectOutfit(1, { style = style, palette = 'neutral' })
        if fallback then
            for _, component in ipairs(fallback.components) do
                assert(component.collection == '' or AppearanceIndex[gender][component.component][component.globalDrawable].collection == '', 'Addon replaced an absent DLC piece')
            end
        end
        if style == 'polished' or style == 'casual' or style == 'street' then
            assert(fallback, 'Original directions must still support base-game wardrobes')
        end
    end
end
GetNumberOfPedDrawableVariations = function() return 0 end
assert(selectOutfit(1, { style = 'street', palette = 'neutral' }) == nil, 'No valid wardrobe must fail without partial clothing')
print('Outfit directions, modern reachability, palette and runtime collection fallback tests passed')
