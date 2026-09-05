local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

dofile(resourceRoot .. '/shared/appearance_catalog.lua')
dofile(resourceRoot .. '/shared/appearance_randomizer.lua')

local defaults = AppearanceRandomizer.sanitizeOptions(nil)
assert(defaults.mode == 'outfit', 'outfit-only must be the safe default')
assert(defaults.style == 'polished', 'polished must be the default style')
assert(defaults.gender == 'keep', 'generator must preserve the current model by default')
assert(defaults.hairTone == 'any', 'all natural hair tones must be eligible by default')
assert(defaults.palette == 'neutral', 'neutral textures must be the default')
assert(defaults.faceProfile == 'everyday', 'full characters must default to the reviewed everyday face pool')
assert(defaults.ageProfile == 'young', 'female generation must default to a youthful adult complexion')
assert(defaults.complexion == 'clean', 'female generation must default to clean skin')
assert(defaults.hairStyle == 'any', 'all reviewed hair shapes must be eligible by default')
assert(defaults.makeup == 'subtle', 'female cosmetics must default to a subtle preset')
assert(defaults.accessories == false, 'accessories must be opt-in')

local sanitized = AppearanceRandomizer.sanitizeOptions({
    mode = 'CHARACTER',
    style = 'street',
    gender = 'female',
    hairTone = 'warm',
    palette = 'tonal',
    faceProfile = 'east_asian',
    ageProfile = 'adult',
    complexion = 'natural',
    hairStyle = 'updo',
    makeup = 'polished',
    accessories = true,
    ignored = string.rep('x', 2048),
})
assert(sanitized.mode == 'character')
assert(sanitized.style == 'street')
assert(sanitized.gender == 'female')
assert(sanitized.hairTone == 'warm')
assert(sanitized.palette == 'tonal')
assert(sanitized.faceProfile == 'east_asian')
assert(sanitized.ageProfile == 'adult')
assert(sanitized.complexion == 'natural')
assert(sanitized.hairStyle == 'updo')
assert(sanitized.makeup == 'polished')
assert(sanitized.accessories == true)
assert(sanitized.ignored == nil, 'unknown NUI fields must not cross into the generator')

local invalid = AppearanceRandomizer.sanitizeOptions({
    mode = {},
    style = 'costume',
    gender = 'invalid',
    hairTone = 'neon',
    palette = 'ultraviolet',
    faceProfile = 'random_noise',
    ageProfile = 'ancient',
    complexion = 'damaged',
    hairStyle = 'rainbow',
    makeup = 'clown',
    accessories = 'true',
})
assert(invalid.mode == 'outfit')
assert(invalid.style == 'polished')
assert(invalid.gender == 'keep')
assert(invalid.hairTone == 'any')
assert(invalid.palette == 'neutral')
assert(invalid.faceProfile == 'everyday')
assert(invalid.ageProfile == 'young')
assert(invalid.complexion == 'clean')
assert(invalid.hairStyle == 'any')
assert(invalid.makeup == 'subtle')
assert(invalid.accessories == false)

local oversized = AppearanceRandomizer.sanitizeOptions({
    mode = string.rep('character', 10000),
    style = string.rep('street', 10000),
})
assert(oversized.mode == 'outfit' and oversized.style == 'polished', 'oversized enum strings must be rejected before normalization')

assert(AppearanceRandomizer.isNaturalHairRgb(26, 19, 15), 'dark brown should be natural')
assert(AppearanceRandomizer.isNaturalHairRgb(181, 143, 91), 'blonde should be natural')
assert(AppearanceRandomizer.isNaturalHairRgb(122, 122, 118), 'grey should be natural')
assert(not AppearanceRandomizer.isNaturalHairRgb(30, 90, 220), 'blue dye must be rejected')
assert(not AppearanceRandomizer.isNaturalHairRgb(35, 210, 70), 'green dye must be rejected')
assert(not AppearanceRandomizer.isNaturalHairRgb('bad', 0, 0), 'malformed RGB values must be rejected')

local palette = {
    { index = 0, r = 18, g = 15, b = 14 },
    { index = 1, r = 112, g = 72, b = 44 },
    { index = 2, r = 204, g = 174, b = 119 },
    { index = 3, r = 30, g = 90, b = 220 },
}
local dark = AppearanceRandomizer.filterNaturalHairColors(palette, 'dark')
assert(#dark >= 1 and dark[1].index == 0, 'dark palette must prefer low-luminance natural colors')
local light = AppearanceRandomizer.filterNaturalHairColors(palette, 'light')
assert(#light == 1 and light[1].index == 2, 'light palette must select natural blonde rows')
local allNatural = AppearanceRandomizer.filterNaturalHairColors(palette, 'any')
assert(#allNatural == 3, 'saturated dye rows must be removed from the natural palette')

local fallback = AppearanceRandomizer.filterNaturalHairColors({ { index = 4, r = 0, g = 70, b = 220 } }, 'warm')
assert(#fallback == 1 and fallback[1].index == 0, 'empty natural palettes need a safe black fallback')

local femaleIdentity = AppearanceRandomizer.getIdentityPool('female', { faceProfile = 'everyday', hairStyle = 'any' })
assert(type(femaleIdentity) == 'table', 'full-character rolls need a gender-specific identity pool')
local femaleMotherIds = {
    [21] = true, [22] = true, [23] = true, [24] = true, [25] = true, [26] = true,
    [27] = true, [28] = true, [29] = true, [30] = true, [31] = true, [32] = true,
    [33] = true, [34] = true, [35] = true, [36] = true, [37] = true, [38] = true,
    [39] = true, [40] = true, [41] = true, [45] = true,
}
local maleFatherIds = {
    [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
    [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true,
    [12] = true, [13] = true, [14] = true, [15] = true, [16] = true, [17] = true,
    [18] = true, [19] = true, [20] = true, [42] = true, [43] = true, [44] = true,
}
assert(#femaleIdentity.mothers >= 6, 'female faces need a useful reviewed mother pool')
assert(#femaleIdentity.fathers >= 4, 'female faces need a useful reviewed father pool')
for _, parentId in ipairs(femaleIdentity.mothers) do
    assert(femaleMotherIds[parentId], ('female mother pool contains a father ID %s'):format(tostring(parentId)))
end
for _, parentId in ipairs(femaleIdentity.fathers) do
    assert(maleFatherIds[parentId], ('female father pool contains a mother ID %s'):format(tostring(parentId)))
end
assert(#femaleIdentity.hair >= 8, 'female hair needs multiple reviewed styles')
for _, hair in ipairs(femaleIdentity.hair) do
    assert(hair.collection == '', 'female hair must use stable base-game collection indexes')
    assert(type(hair.drawable) == 'number' and hair.drawable > 0, 'female hair must exclude the shaved default')
    assert(type(hair.name) == 'string' and hair.name ~= '', 'curated female hair needs a reviewable name')
end

for motherIndex = 1, #femaleIdentity.mothers do
    for fatherIndex = 1, #femaleIdentity.fathers do
        local identity = AppearanceRandomizer.assembleIdentity('female', { faceProfile = 'everyday', hairStyle = 'any' }, function(_, category)
            if category == 'mother' then return motherIndex end
            if category == 'father' then return fatherIndex end
            return 1
        end)
        assert(femaleMotherIds[identity.shapeFirst], 'shapeFirst must be a reviewed mother, matching the native contract')
        assert(maleFatherIds[identity.shapeSecond], 'shapeSecond must be a reviewed father, matching the native contract')
        assert(identity.skinFirst == identity.shapeFirst and identity.skinSecond == identity.shapeSecond, 'skin and shape must use one coherent parent pair')
        assert(identity.shapeMixMin >= 0.0 and identity.shapeMixMax <= 0.5, 'female faces must remain mother-biased')
    end
end

local eastAsianIdentity = AppearanceRandomizer.getIdentityPool('female', { faceProfile = 'east_asian', hairStyle = 'any' })
assert(#eastAsianIdentity.mothers >= 3 and #eastAsianIdentity.fathers >= 3, 'East Asian generation needs its own rendered parent pool')
local softIdentity = AppearanceRandomizer.getIdentityPool('female', { faceProfile = 'soft', hairStyle = 'any' })
assert(#softIdentity.mothers >= 4 and #softIdentity.fathers >= 3, 'soft female generation needs a reviewed parent pool')

for _, hairStyle in ipairs({ 'short', 'medium', 'long', 'updo' }) do
    local styled = AppearanceRandomizer.getIdentityPool('female', { faceProfile = 'everyday', hairStyle = hairStyle })
    assert(#styled.hair >= 2, ('female %s hair needs multiple reviewed choices'):format(hairStyle))
    for _, hair in ipairs(styled.hair) do
        assert(hair.group == hairStyle, ('%s hair filter leaked a %s style'):format(hairStyle, tostring(hair.group)))
    end
end

for featureId = 0, 19 do
    local minimum, maximum = AppearanceRandomizer.getFaceFeatureRange('female', 'everyday', featureId)
    assert(type(minimum) == 'number' and type(maximum) == 'number' and minimum <= maximum, 'every face morph needs a valid reviewed range')
    assert(minimum >= -0.35 and maximum <= 0.35, ('female face feature %d is too extreme'):format(featureId))
end

local cleanYoung = AppearanceRandomizer.getOverlayPlan('female', {
    ageProfile = 'young', complexion = 'clean', makeup = 'subtle'
})
assert(cleanYoung[0].chance == 0, 'clean female faces must not add blemishes')
assert(cleanYoung[3].chance == 0, 'young female faces must never add ageing')
assert(cleanYoung[6].chance == 0, 'clean female faces must not add random complexion damage')
assert(cleanYoung[7].chance == 0, 'young clean female faces must not add sun damage')
assert(cleanYoung[11].chance == 0, 'clean female faces must not add body blemishes')
assert(cleanYoung[2].chance == 100, 'reviewed eyebrows should always be applied')

local requiredComponents = { [3] = true, [4] = true, [6] = true, [8] = true, [11] = true }
for _, gender in ipairs({ 'male', 'female' }) do
    for _, style in ipairs({ 'polished', 'casual', 'street' }) do
        for _, paletteName in ipairs({ 'neutral', 'tonal', 'varied' }) do
            local pools = AppearanceRandomizer.getPiecePools(gender, style, paletteName)
            assert(#pools.tops >= 10, ('%s %s needs a large reviewed top catalog'):format(gender, style))
            assert(#pools.bottoms >= 10, ('%s %s needs a large reviewed lower-body catalog'):format(gender, style))
            assert(#pools.shoes >= 10, ('%s %s needs a large reviewed footwear catalog'):format(gender, style))
            assert(#pools.accessories >= 2, ('%s %s needs optional reviewed accessories'):format(gender, style))
            assert(#pools.tops * #pools.bottoms * #pools.shoes >= 1000, ('%s %s needs thousands of modular combinations'):format(gender, style))

            local expectedComponents = {
                tops = { [3] = true, [8] = true, [11] = true },
                bottoms = { [4] = true },
                shoes = { [6] = true },
            }
            for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
                local ids = {}
                for _, piece in ipairs(pools[category]) do
                    assert(type(piece.id) == 'string' and piece.id ~= '', 'curated pieces need stable IDs')
                    assert(type(piece.name) == 'string' and piece.name ~= '', 'curated pieces need player-facing names')
                    assert(not ids[piece.id], 'materialized piece IDs must be unique within a pool')
                    ids[piece.id] = true
                    local present = {}
                    for _, component in ipairs(piece.components) do
                        assert(component.collection == '' or type(component.globalDrawable) == 'number', 'curated clothing must use a stable collection or a runtime-resolved official drawable')
                        assert(expectedComponents[category][component.component], 'piece owns a component outside its compatibility boundary')
                        local drawable = component.globalDrawable or component.drawable
                        assert(type(drawable) == 'number' and drawable >= 0)
                        assert(type(component.texture) == 'number' and component.texture >= 0)
                        present[component.component] = true
                    end
                    for componentId in pairs(expectedComponents[category]) do
                        assert(present[componentId], ('piece %s is missing component %d'):format(piece.id, componentId))
                    end
                end
            end

            for _, accessory in ipairs(pools.accessories) do
                assert(accessory.collection == '', 'curated props must use the stable base-game collection')
                assert(accessory.prop == 1 or accessory.prop == 6, 'only reviewed glasses or watches belong in the accessory pool')
            end

            local seen = {}
            for topIndex = 1, #pools.tops do
                for bottomIndex = 1, #pools.bottoms do
                    for shoeIndex = 1, #pools.shoes do
                        local selection = { tops = topIndex, bottoms = bottomIndex, shoes = shoeIndex, accessories = 1 }
                        local outfit = assert(AppearanceRandomizer.assembleOutfit(pools, false, function(_, category)
                            return selection[category]
                        end))
                        assert(not seen[outfit.id], 'each modular piece combination needs a unique outfit ID')
                        seen[outfit.id] = true
                        assert(#outfit.components == 5, 'assembled outfits must contain upper, pants and shoe components')
                        local present = {}
                        for _, component in ipairs(outfit.components) do
                            assert(requiredComponents[component.component], 'assembled outfit contains an unexpected component')
                            present[component.component] = true
                        end
                        for componentId in pairs(requiredComponents) do assert(present[componentId], 'assembled outfit is incomplete') end
                        assert(#outfit.accessories == 0, 'accessories must remain opt-in')
                    end
                end
            end
            assert(#pools.tops * #pools.bottoms * #pools.shoes > 0)

            local withAccessory = assert(AppearanceRandomizer.assembleOutfit(pools, true, function() return 1 end))
            assert(#withAccessory.accessories == 1, 'enabled accessories should select one reviewed prop')
        end
    end
end

for _, gender in ipairs({ 'male', 'female' }) do
    local uniqueDrawables = { tops = {}, bottoms = {}, shoes = {} }
    local componentForCategory = { tops = 11, bottoms = 4, shoes = 6 }
    for _, style in ipairs({ 'polished', 'casual', 'street' }) do
        local pools = AppearanceRandomizer.getPiecePools(gender, style, 'neutral')
        for category, componentId in pairs(componentForCategory) do
            for _, piece in ipairs(pools[category]) do
                for _, component in ipairs(piece.components) do
                    if component.component == componentId then
                        uniqueDrawables[category][component.globalDrawable or component.drawable] = true
                    end
                end
            end
        end
    end
    local function countKeys(values)
        local count = 0
        for _ in pairs(values) do count = count + 1 end
        return count
    end
    assert(countKeys(uniqueDrawables.tops) >= 20, gender .. ' needs at least 20 distinct reviewed upper-body models')
    assert(countKeys(uniqueDrawables.bottoms) >= 18, gender .. ' needs at least 18 distinct reviewed lower-body models')
    assert(countKeys(uniqueDrawables.shoes) >= 18, gender .. ' needs at least 18 distinct reviewed footwear models')
end

for _, style in ipairs({ 'polished', 'casual', 'street' }) do
    for _, paletteName in ipairs({ 'neutral', 'tonal', 'varied' }) do
        local femalePools = AppearanceRandomizer.getPiecePools('female', style, paletteName)
        for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
            for _, piece in ipairs(femalePools[category]) do
                local label = piece.name:lower()
                -- Restrained stays quiet; Tonal and Mixed now intentionally
                -- include later DLC colors for both bodies.
                if paletteName == 'neutral' then
                    assert(not label:match('%f[%a]purple%f[%A]'), 'restrained clothing must not use purple accents')
                    assert(not label:find('hot pink', 1, true), 'restrained clothing must not use hot pink')
                    assert(not label:find('neon', 1, true), 'restrained clothing must not use neon colors')
                end
            end
        end
        if style == 'street' then
            for _, top in ipairs(femalePools.tops) do
                assert(not top.id:find('tee_graphic', 1, true), 'female streetwear must use the clean tee capsule')
            end
        end
    end
end

local isolatedPools = AppearanceRandomizer.getPiecePools('male', 'casual', 'neutral')
isolatedPools.tops[1].name = 'mutated by caller'
assert(AppearanceRandomizer.getPiecePools('male', 'casual', 'neutral').tops[1].name ~= 'mutated by caller', 'callers must not mutate catalog definitions')
local missingOutfit, missingError = AppearanceRandomizer.assembleOutfit({ tops = {}, bottoms = {}, shoes = {} }, false)
assert(missingOutfit == nil and missingError == 'empty_piece_pool', 'empty modular pools must fail deterministically')

local runtimePools = AppearanceRandomizer.getPiecePools('female', 'casual', 'neutral')
local withoutValidAccessories = AppearanceRandomizer.filterPiecePools(
    runtimePools,
    function() return true end,
    function() return false end
)
assert(#withoutValidAccessories.tops == #runtimePools.tops, 'accessory rejection must not remove tops')
assert(#withoutValidAccessories.bottoms == #runtimePools.bottoms, 'accessory rejection must not remove bottoms')
assert(#withoutValidAccessories.shoes == #runtimePools.shoes, 'accessory rejection must not remove shoes')
assert(#withoutValidAccessories.accessories == 0, 'invalid optional accessories should be removed')
local clothingWithoutAccessory = assert(AppearanceRandomizer.assembleOutfit(withoutValidAccessories, true, function() return 1 end))
assert(#clothingWithoutAccessory.components == 5, 'clothing must still assemble when every accessory is invalid')
assert(#clothingWithoutAccessory.accessories == 0, 'an unavailable optional prop must be skipped')

for _, gender in ipairs({ 'male', 'female' }) do
    for _, style in ipairs({ 'polished', 'casual', 'street' }) do
        local mixedPools = AppearanceRandomizer.getPiecePools(gender, style, 'varied')
        for _, top in ipairs(mixedPools.tops) do assert(top.id:find('-varied-', 1, true), 'mixed palettes should vary the focal top') end
        for _, bottom in ipairs(mixedPools.bottoms) do assert(bottom.id:find('-neutral-', 1, true), 'mixed palettes need neutral interchangeable bottoms') end
        for _, shoes in ipairs(mixedPools.shoes) do assert(shoes.id:find('-neutral-', 1, true), 'mixed palettes need neutral interchangeable shoes') end
    end
end

local function readSource(relativePath)
    local file = assert(io.open(resourceRoot .. '/' .. relativePath, 'rb'))
    local source = file:read('*a')
    file:close()
    return source
end

local actionsSource = readSource('client/actions.lua')
local manifestSource = readSource('fxmanifest.lua')
local nuiSource = readSource('client/nui.lua')
local appSource = readSource('ui/app.js')
local cssSource = readSource('ui/style.css')
assert(not actionsSource:find('SetPedRandomComponentVariation', 1, true), 'curated outfits must never call GTA random component generation')
local catalogPosition = assert(manifestSource:find('shared/appearance_catalog.lua', 1, true), 'the expanded catalog must be loaded by the resource')
local randomizerPosition = assert(manifestSource:find('shared/appearance_randomizer.lua', 1, true), 'the appearance randomizer must be loaded by the resource')
assert(catalogPosition < randomizerPosition, 'the expanded catalog must load before the randomizer consumes it')
assert(actionsSource:find('SetPedCollectionComponentVariation', 1, true), 'outfits must apply collection-stable component indexes')
assert(actionsSource:find('GetPedCollectionNameFromDrawable', 1, true), 'official global catalog indexes must resolve to their runtime collection')
assert(actionsSource:find('GetPedCollectionLocalIndexFromDrawable', 1, true), 'official global catalog indexes must resolve to a collection-local index')
assert(not actionsSource:find('IsPedCollectionComponentVariationValid', 1, true), 'the collection validator that rejected valid base pieces must not return')
assert(actionsSource:find('AppearanceRandomizer.getOutfitFamilies', 1, true), 'client generation must select a compatible outfit family')
assert(actionsSource:find('AppearanceRandomizer.assembleOutfit', 1, true), 'client generation must assemble interchangeable pieces')
assert(actionsSource:find('AppearanceRandomizer.filterPiecePools', 1, true), 'runtime compatibility must filter modular pieces independently')
assert(actionsSource:find('generatedClothingPieceIsValid', 1, true), 'invalid clothing must be filtered per piece rather than rejecting a whole style')
assert(actionsSource:find('generatedAccessoryIsValid', 1, true), 'optional props need an independent compatibility filter')
assert(not actionsSource:find('generatedPresetIsValid', 1, true), 'optional prop failures must never invalidate the clothing outfit')
assert(actionsSource:find('AppearanceRandomizer.filterNaturalHairColors', 1, true), 'character generation must filter the live hair palette')
assert(actionsSource:find('AppearanceRandomizer.assembleIdentity', 1, true), 'full characters must use the curated gender-specific identity pool')
assert(not actionsSource:find('math.random(0, 45)', 1, true), 'full characters must never sample the mixed-gender heritage range')
assert(not actionsSource:find('local hairStyles =', 1, true), 'full characters must never sample every installed hair drawable')
assert(actionsSource:find('randomReviewedFaceFeature(gender, identity.profile, featureId)', 1, true), 'full characters must use reviewed per-feature face ranges')
assert(actionsSource:find('AppearanceRandomizer.getOverlayPlan(gender, options)', 1, true), 'skin overlays must follow the selected age, complexion and makeup plan')
assert(not actionsSource:find('setGeneratedOverlay(ped, 3, 18', 1, true), 'female generation must not hard-code an ageing chance')
assert(actionsSource:find('preserveDecorations = true', 1, true), 'undo must not clear tattoos it cannot capture')
assert(nuiSource:find("canInvokeAction('player.randomizeAppearance')", 1, true), 'generator NUI callback must enforce action permission')
assert(nuiSource:find('AppearanceRandomizer.sanitizeOptions(data)', 1, true), 'generator NUI payload must be allowlisted')
assert(not appSource:find('Controlled randomization', 1, true), 'the removed promotional generator hero must not return')
assert(not appSource:find('appearance-generator-icon', 1, true), 'the removed generator hero icon must not return')
assert(appSource:find('FEATURE_RELEASES', 1, true), 'new features need a reusable release registry')
assert(appSource:find('custom-character-generator-2026-08-19', 1, true), 'the custom generator must receive a new discovery release marker')
assert(appSource:find('FEATURE_DISCOVERY_STORAGE_KEY', 1, true), 'feature discovery must persist per player')
assert(appSource:find("markFeatureDiscovered('appearanceGenerator')", 1, true), 'opening the generator must clear its discovery dot')
assert(cssSource:find('.feature-discovery-dot', 1, true), 'new features need the shared blue discovery marker')
assert(not cssSource:find('.appearance-collapsible--generator', 1, true), 'the generator must use the same neutral accordion surface as other tools')
assert(appSource:find("generatorSelect('faceProfile', 'Face profile'", 1, true), 'face profile must use the shared custom dropdown')
assert(appSource:find("generatorSelect('ageProfile', 'Age'", 1, true), 'age must be user-selectable')
assert(appSource:find("generatorSelect('complexion', 'Complexion'", 1, true), 'complexion must be user-selectable')
assert(appSource:find("generatorSelect('hairStyle', 'Hair shape'", 1, true), 'hair shape must be user-selectable')
assert(appSource:find("generatorSelect('makeup', 'Makeup'", 1, true), 'makeup must be user-selectable')
assert(not appSource:find('Changing the body model recreates the player ped', 1, true), 'the crossed-out generator warning must remain removed')
assert(not appSource:find('Each roll is temporary until you save it', 1, true), 'the crossed-out generator footer copy must remain removed')
assert(cssSource:find('background: var(--accent);', 1, true), 'the enabled accessory toggle needs a visible accent state')

print('curated appearance generator policy and contract tests passed')
