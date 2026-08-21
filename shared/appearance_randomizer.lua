AppearanceRandomizer = AppearanceRandomizer or {}

local VALID_MODES = { outfit = true, character = true }
local VALID_STYLES = { polished = true, casual = true, street = true }
local VALID_GENDERS = { keep = true, male = true, female = true, random = true }
local VALID_HAIR_TONES = { any = true, dark = true, warm = true, light = true }
local VALID_PALETTES = { neutral = true, tonal = true, varied = true }
local VALID_FACE_PROFILES = { everyday = true, east_asian = true, soft = true }
local VALID_AGE_PROFILES = { young = true, adult = true, mature = true }
local VALID_COMPLEXIONS = { clean = true, natural = true }
local VALID_HAIR_STYLES = { any = true, short = true, medium = true, long = true, updo = true }
local VALID_MAKEUP = { none = true, subtle = true, polished = true }

-- Curated from rendered MP freemode catalogs. Pieces are interchangeable only
-- inside their declared style pool. An upper-body piece owns arms, undershirt,
-- and top together so a roll cannot create sleeve holes or mismatched layers.
--
-- Catalogs: https://wiki.rage.mp/wiki/Clothes
--           https://github.com/Colbss/FiveM-ClothingData
-- Indexing: https://docs.fivem.net/docs/scripting-manual/using-new-game-features/collection-based-natives/
local BASE_GAME_COLLECTION = ''

-- SET_PED_HEAD_BLEND_DATA treats shapeFirst as the mother and shapeSecond as
-- the father. These pools were reviewed against a rendered 0-45 parent grid;
-- each profile keeps one coherent parent pair and controls the resemblance
-- range instead of sampling four unrelated IDs.
--
-- Native contract: https://github.com/citizenfx/natives/blob/master/PED/SetPedHeadBlendData.md
-- Parent renders: https://forum.gta.world/en/topic/3809-gtmp-parent-face-list/
-- Hair stays on named base-game drawables so indexes remain stable across
-- game builds and installed clothing packs.
local IDENTITY_POOLS = {
    male = {
        profiles = {
            everyday = { mothers = { 21, 22, 27, 28, 31, 33, 34, 37, 38, 40, 45 }, fathers = { 0, 1, 7, 10, 12, 16, 18, 19, 20 }, shapeMix = { 0.58, 0.78 } },
            east_asian = { mothers = { 27, 28, 31, 40, 45 }, fathers = { 6, 7, 12, 18, 19 }, shapeMix = { 0.58, 0.76 } },
            soft = { mothers = { 21, 22, 28, 31, 33, 34, 40, 45 }, fathers = { 0, 7, 10, 12, 18 }, shapeMix = { 0.48, 0.66 } },
        },
        hair = {
            { name = 'Buzzcut', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 1, texture = 0 },
            { name = 'Faux hawk', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 2, texture = 0 },
            { name = 'Short cut', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 5, texture = 0 },
            { name = 'Short brushed', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 10, texture = 0 },
            { name = 'Caesar', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 12, texture = 0 },
            { name = 'Short side part', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 18, texture = 0 },
            { name = 'Side-parted', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 4, texture = 0 },
            { name = 'Slicked', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 9, texture = 0 },
            { name = 'Layered', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 13, texture = 0 },
            { name = 'Tousled', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 19, texture = 0 },
            { name = 'Long tied', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 3, texture = 0 },
            { name = 'Braids', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 6, texture = 0 },
            { name = 'Long swept', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 15, texture = 0 },
            { name = 'Long loose', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 16, texture = 0 },
            { name = 'Top knot', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 14, texture = 0 },
            { name = 'Tied back', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 17, texture = 0 },
            { name = 'High knot', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 20, texture = 0 },
        },
    },
    female = {
        profiles = {
            everyday = { mothers = { 21, 22, 27, 28, 31, 33, 34, 37, 38, 40, 45 }, fathers = { 0, 7, 10, 12, 16, 18, 19, 20 }, shapeMix = { 0.16, 0.38 } },
            east_asian = { mothers = { 27, 28, 31, 40, 45 }, fathers = { 6, 7, 12, 18, 19 }, shapeMix = { 0.14, 0.34 } },
            soft = { mothers = { 21, 22, 28, 31, 33, 34, 40, 45 }, fathers = { 0, 7, 10, 12, 18 }, shapeMix = { 0.10, 0.28 } },
        },
        hair = {
            { name = 'Short', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 1, texture = 0 },
            { name = 'Pixie', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 12, texture = 0 },
            { name = 'Shaved fringe', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 13, texture = 0 },
            { name = 'Layered bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 2, texture = 0 },
            { name = 'Bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 7, texture = 0 },
            { name = 'Long bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 10, texture = 0 },
            { name = 'Wavy bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 15, texture = 0 },
            { name = 'Flapper bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 18, texture = 0 },
            { name = 'Twisted bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 20, texture = 0 },
            { name = 'Pigtails', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 3, texture = 0 },
            { name = 'Ponytail', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 4, texture = 0 },
            { name = 'Braided mohawk', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 5, texture = 0 },
            { name = 'Braids', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 6, texture = 0 },
            { name = 'Loose tied', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 11, texture = 0 },
            { name = 'French twist', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 9, texture = 0 },
            { name = 'Top knot', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 14, texture = 0 },
            { name = 'Pin-up', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 16, texture = 0 },
            { name = 'Messy bun', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 17, texture = 0 },
            { name = 'Tight bun', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 19, texture = 0 },
            { name = 'Large bun', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 21, texture = 0 },
            { name = 'Braided top knot', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 22, texture = 0 },
        },
    },
}

-- Narrow, reviewed morph bands keep generated faces recognizable without
-- flattening every roll into the same preset. Profile differences come from
-- the rendered parent pool; no ethnicity is encoded as a facial stereotype.
local FEMALE_FACE_RANGES = {
    [0] = { -0.18, 0.14 }, [1] = { -0.14, 0.16 }, [2] = { -0.18, 0.16 },
    [3] = { -0.14, 0.16 }, [4] = { -0.18, 0.14 }, [5] = { -0.14, 0.16 },
    [6] = { -0.12, 0.18 }, [7] = { -0.10, 0.18 }, [8] = { -0.10, 0.20 },
    [9] = { -0.10, 0.18 }, [10] = { -0.14, 0.12 }, [11] = { -0.12, 0.18 },
    [12] = { -0.22, 0.04 }, [13] = { -0.28, -0.02 }, [14] = { -0.24, 0.02 },
    [15] = { -0.14, 0.14 }, [16] = { -0.12, 0.14 }, [17] = { -0.20, 0.04 },
    [18] = { -0.12, 0.12 }, [19] = { -0.24, -0.04 },
}

local MALE_FACE_RANGES = {
    [0] = { -0.22, 0.22 }, [1] = { -0.18, 0.20 }, [2] = { -0.20, 0.20 },
    [3] = { -0.18, 0.20 }, [4] = { -0.20, 0.20 }, [5] = { -0.18, 0.20 },
    [6] = { -0.18, 0.18 }, [7] = { -0.16, 0.18 }, [8] = { -0.16, 0.20 },
    [9] = { -0.16, 0.18 }, [10] = { -0.18, 0.20 }, [11] = { -0.16, 0.16 },
    [12] = { -0.18, 0.16 }, [13] = { -0.12, 0.24 }, [14] = { -0.10, 0.24 },
    [15] = { -0.16, 0.18 }, [16] = { -0.14, 0.18 }, [17] = { -0.14, 0.18 },
    [18] = { -0.14, 0.16 }, [19] = { -0.12, 0.20 },
}

local function overlay(chance, minimumOpacity, maximumOpacity, color)
    return {
        chance = chance,
        minimumOpacity = minimumOpacity or 0.0,
        maximumOpacity = maximumOpacity or minimumOpacity or 0.0,
        color = color,
    }
end

local function upperVariant(name, undershirtTexture, topTexture)
    return { name = name, textures = { [3] = 0, [8] = undershirtTexture, [11] = topTexture } }
end

local function clothingVariant(name, component, texture)
    return { name = name, textures = { [component] = texture } }
end

local function propVariant(name, texture)
    return { name = name, texture = texture }
end

local PIECES = {
    male = {
        tops = {
            tee_clean = {
                components = { [3] = 0, [8] = 0, [11] = 0 },
                variants = {
                    neutral = { upperVariant('Charcoal T-shirt', 2, 2), upperVariant('Crew T-shirt', 0, 0) },
                    tonal = { upperVariant('Charcoal T-shirt', 2, 2), upperVariant('Sweatbox T-shirt', 8, 8) },
                    varied = { upperVariant('Ranch T-shirt', 4, 4), upperVariant('Pikeys T-shirt', 5, 5) },
                },
            },
            tee_graphic = {
                components = { [3] = 0, [8] = 0, [11] = 0 },
                variants = {
                    neutral = { upperVariant('Charcoal T-shirt', 2, 2), upperVariant('Eris T-shirt', 11, 11) },
                    tonal = { upperVariant('Sweatbox T-shirt', 8, 8), upperVariant('Crew T-shirt', 0, 0) },
                    varied = { upperVariant('Multi-Logo T-shirt', 7, 7), upperVariant('Ranch T-shirt', 4, 4), upperVariant('Pikeys T-shirt', 5, 5) },
                },
            },
            polo = {
                components = { [3] = 0, [8] = 9, [11] = 9 },
                variants = {
                    neutral = { upperVariant('Night polo', 2, 2), upperVariant('Metal polo', 1, 1), upperVariant('White striped polo', 0, 0) },
                    tonal = { upperVariant('Blue polo', 4, 4), upperVariant('Royale polo', 7, 7), upperVariant('Hunter polo', 13, 13) },
                    varied = { upperVariant('Salmon polo', 6, 6), upperVariant('Pro Lite polo', 10, 10), upperVariant('Ice polo', 11, 11) },
                },
            },
        },
        bottoms = {
            regular_jeans = {
                components = { [4] = 0 },
                variants = {
                    neutral = { clothingVariant('Black regular-fit jeans', 4, 12), clothingVariant('Gray regular-fit jeans', 4, 5), clothingVariant('Dark blue regular-fit jeans', 4, 8) },
                    tonal = { clothingVariant('Navy regular-fit jeans', 4, 0), clothingVariant('Faded dark-blue jeans', 4, 4) },
                    varied = { clothingVariant('Tan regular-fit jeans', 4, 3), clothingVariant('Brown regular-fit jeans', 4, 11) },
                },
            },
            ranch_jeans = {
                components = { [4] = 1 },
                variants = {
                    neutral = { clothingVariant('Black Ranch jeans', 4, 1), clothingVariant('Gray Ranch jeans', 4, 2), clothingVariant('Slate jeans', 4, 0) },
                    tonal = { clothingVariant('Navy Ranch jeans', 4, 11), clothingVariant('Blue Ranch jeans', 4, 12) },
                    varied = { clothingVariant('Olive Ranch jeans', 4, 9), clothingVariant('Tan Ranch jeans', 4, 14) },
                },
            },
            chinos = {
                components = { [4] = 8 },
                variants = {
                    neutral = { clothingVariant('Charcoal chinos', 4, 0), clothingVariant('Gray chinos', 4, 4) },
                    tonal = { clothingVariant('Charcoal chinos', 4, 0), clothingVariant('Gray chinos', 4, 4) },
                    varied = { clothingVariant('Tan chinos', 4, 3), clothingVariant('Sky-blue chinos', 4, 14) },
                },
            },
            dress_chinos = {
                components = { [4] = 12 },
                variants = {
                    neutral = { clothingVariant('Black chinos', 4, 0), clothingVariant('Gray chinos', 4, 5) },
                    tonal = { clothingVariant('Navy chinos', 4, 12), clothingVariant('Gray plaid chinos', 4, 4) },
                    varied = { clothingVariant('Tan chinos', 4, 7), clothingVariant('Navy chinos', 4, 12) },
                },
            },
            cargo = {
                components = { [4] = 9 },
                variants = {
                    neutral = { clothingVariant('Black cargo pants', 4, 7), clothingVariant('Urban cargo pants', 4, 10), clothingVariant('Black-camo cargo pants', 4, 13) },
                    tonal = { clothingVariant('Navy cargo pants', 4, 3), clothingVariant('Olive cargo pants', 4, 0) },
                    varied = { clothingVariant('Khaki cargo pants', 4, 1), clothingVariant('Brown cargo pants', 4, 5) },
                },
            },
            baggy = {
                components = { [4] = 13 },
                variants = {
                    neutral = { clothingVariant('Black baggy pants', 4, 0), clothingVariant('Gray baggy pants', 4, 1) },
                    tonal = { clothingVariant('Gray baggy pants', 4, 1), clothingVariant('Blue baggy pants', 4, 2) },
                    varied = { clothingVariant('Blue baggy pants', 4, 2), clothingVariant('Black baggy pants', 4, 0) },
                },
            },
            fitted_cargo = {
                components = { [4] = 15 },
                variants = {
                    neutral = { clothingVariant('Black fitted cargos', 4, 3), clothingVariant('Gray fitted cargos', 4, 5) },
                    tonal = { clothingVariant('Olive fitted cargos', 4, 1), clothingVariant('Blue fitted cargos', 4, 14) },
                    varied = { clothingVariant('Tan fitted cargos', 4, 4), clothingVariant('Brown fitted cargos', 4, 7) },
                },
            },
        },
        shoes = {
            canvas = {
                components = { [6] = 4 },
                variants = {
                    neutral = { clothingVariant('Black canvas shoes', 6, 1), clothingVariant('White canvas shoes', 6, 2) },
                    tonal = { clothingVariant('Navy canvas shoes', 6, 0), clothingVariant('Black canvas shoes', 6, 1) },
                    varied = { clothingVariant('White canvas shoes', 6, 2), clothingVariant('Red canvas shoes', 6, 4) },
                },
            },
            skate = {
                components = { [6] = 1 },
                variants = {
                    neutral = { clothingVariant('Black skate shoes', 6, 14), clothingVariant('Gray skate shoes', 6, 13), clothingVariant('Charcoal skate shoes', 6, 7) },
                    tonal = { clothingVariant('Navy skate shoes', 6, 6), clothingVariant('Slate skate shoes', 6, 2) },
                    varied = { clothingVariant('Olive skate shoes', 6, 11), clothingVariant('Tan skate shoes', 6, 12) },
                },
            },
            boat = {
                components = { [6] = 3 },
                variants = {
                    neutral = { clothingVariant('Black boat shoes', 6, 4), clothingVariant('Gray boat shoes', 6, 2), clothingVariant('Charcoal boat shoes', 6, 13) },
                    tonal = { clothingVariant('Blue-gray boat shoes', 6, 1), clothingVariant('Umber boat shoes', 6, 15) },
                    varied = { clothingVariant('Tan two-tone boat shoes', 6, 9), clothingVariant('Black boat shoes', 6, 4) },
                },
            },
            oxford = {
                components = { [6] = 10 },
                variants = {
                    neutral = { clothingVariant('Black Oxfords', 6, 0) },
                    tonal = { clothingVariant('Coffee Oxfords', 6, 12), clothingVariant('Black Oxfords', 6, 0) },
                    varied = { clothingVariant('Beige Oxfords', 6, 14), clothingVariant('Black Oxfords', 6, 0) },
                },
            },
            chelsea = {
                components = { [6] = 15 },
                variants = {
                    neutral = { clothingVariant('Black Chelsea boots', 6, 0), clothingVariant('Gray Chelsea boots', 6, 13), clothingVariant('Black wingtip Chelsea boots', 6, 10) },
                    tonal = { clothingVariant('Brown Chelsea boots', 6, 1), clothingVariant('Black Chelsea boots', 6, 4) },
                    varied = { clothingVariant('Tan Chelsea boots', 6, 5), clothingVariant('Burgundy Chelsea boots', 6, 2) },
                },
            },
            boots = {
                components = { [6] = 14 },
                variants = {
                    neutral = { clothingVariant('Black boots', 6, 1), clothingVariant('Charcoal boots', 6, 0) },
                    tonal = { clothingVariant('Navy boots', 6, 3), clothingVariant('Olive boots', 6, 2) },
                    varied = { clothingVariant('Tan boots', 6, 4), clothingVariant('Brown boots', 6, 8) },
                },
            },
        },
        accessories = {
            watch = { prop = 6, drawable = 0, variants = { neutral = { propVariant('Black watch', 3) }, tonal = { propVariant('Silver watch', 2) }, varied = { propVariant('Deep Sea watch', 0) } } },
            glasses = { prop = 1, drawable = 3, variants = { neutral = { propVariant('Black Janitor frames', 1) }, tonal = { propVariant('Slate Janitor frames', 0) }, varied = { propVariant('Smoke Janitor frames', 5) } } },
        },
    },
    female = {
        tops = {
            tee_clean = {
                components = { [3] = 0, [8] = 0, [11] = 0 },
                variants = {
                    neutral = { upperVariant('Ash T-shirt', 10, 10), upperVariant('Gray T-shirt', 11, 11), upperVariant('Crew T-shirt', 0, 0) },
                    tonal = { upperVariant('Blue T-shirt', 6, 6), upperVariant('Baby-blue T-shirt', 14, 14), upperVariant('Gray T-shirt', 11, 11) },
                    varied = { upperVariant('Tan T-shirt', 7, 7), upperVariant('Two-tone T-shirt', 13, 13), upperVariant('Two-tone striped T-shirt', 15, 15) },
                },
            },
            polo = {
                components = { [3] = 0, [8] = 14, [11] = 14 },
                variants = {
                    neutral = { upperVariant('Black polo', 0, 3), upperVariant('Gray polo', 0, 0), upperVariant('Black striped polo', 0, 12) },
                    tonal = { upperVariant('Navy polo', 0, 7), upperVariant('Sky-blue polo', 0, 5) },
                    varied = { upperVariant('Black striped polo', 0, 12), upperVariant('White striped polo', 0, 13) },
                },
            },
            shirt = {
                components = { [3] = 0, [8] = 9, [11] = 9 },
                variants = {
                    neutral = { upperVariant('Charcoal shirt', 0, 0), upperVariant('White shirt', 0, 1) },
                    tonal = { upperVariant('Navy-fade shirt', 0, 9), upperVariant('Light-blue shirt', 0, 8), upperVariant('Sky-blue shirt', 0, 2) },
                    varied = { upperVariant('Olive shirt', 0, 3), upperVariant('Peach shirt', 0, 4) },
                },
            },
        },
        bottoms = {
            skinny = {
                components = { [4] = 0 },
                variants = {
                    neutral = { clothingVariant('Black skinny jeans', 4, 1), clothingVariant('Navy faded skinny jeans', 4, 8), clothingVariant('Navy skinny jeans', 4, 0) },
                    tonal = { clothingVariant('Indigo skinny jeans', 4, 2), clothingVariant('Blue faded skinny jeans', 4, 10) },
                    varied = { clothingVariant('Green skinny jeans', 4, 7), clothingVariant('Black skinny jeans', 4, 1) },
                },
            },
            regular_jeans = {
                components = { [4] = 1 },
                variants = {
                    neutral = { clothingVariant('Distressed black jeans', 4, 5), clothingVariant('Slate regular-fit jeans', 4, 6), clothingVariant('Navy regular-fit jeans', 4, 13) },
                    tonal = { clothingVariant('Faded dark-blue jeans', 4, 0), clothingVariant('Dark-blue regular-fit jeans', 4, 4) },
                    varied = { clothingVariant('Brown regular-fit jeans', 4, 11), clothingVariant('White regular-fit jeans', 4, 12) },
                },
            },
            rollups = {
                components = { [4] = 2 },
                variants = {
                    neutral = { clothingVariant('Black rollups', 4, 2), clothingVariant('Charcoal rollups', 4, 1), clothingVariant('Ash rollups', 4, 0) },
                    tonal = { clothingVariant('Charcoal rollups', 4, 1), clothingVariant('Ash rollups', 4, 0) },
                    varied = { clothingVariant('Ash rollups', 4, 0), clothingVariant('Black rollups', 4, 2) },
                },
            },
            chinos = {
                components = { [4] = 3 },
                variants = {
                    neutral = { clothingVariant('Black chinos', 4, 0), clothingVariant('Gray chinos', 4, 2), clothingVariant('Navy chinos', 4, 3) },
                    tonal = { clothingVariant('Navy chinos', 4, 3), clothingVariant('Gray chinos', 4, 2) },
                    varied = { clothingVariant('Khaki chinos', 4, 5), clothingVariant('Beige chinos', 4, 8) },
                },
            },
            suit = {
                components = { [4] = 6 },
                variants = {
                    neutral = { clothingVariant('Black suit trousers', 4, 0), clothingVariant('Charcoal suit trousers', 4, 1), clothingVariant('Navy suit trousers', 4, 2) },
                    tonal = { clothingVariant('Navy suit trousers', 4, 2), clothingVariant('Charcoal suit trousers', 4, 1) },
                    varied = { clothingVariant('Charcoal suit trousers', 4, 1), clothingVariant('Navy suit trousers', 4, 2) },
                },
            },
            cargo = {
                components = { [4] = 11 },
                variants = {
                    neutral = { clothingVariant('Black cargos', 4, 1), clothingVariant('Charcoal cargos', 4, 3), clothingVariant('Gray cargos', 4, 12) },
                    tonal = { clothingVariant('Navy cargos', 4, 4), clothingVariant('Olive cargos', 4, 0) },
                    varied = { clothingVariant('Khaki cargos', 4, 6), clothingVariant('Tan cargos', 4, 7) },
                },
            },
        },
        shoes = {
            canvas = {
                components = { [6] = 3 },
                variants = {
                    neutral = { clothingVariant('Black canvas shoes', 6, 0), clothingVariant('White canvas shoes', 6, 1), clothingVariant('Navy canvas shoes', 6, 3) },
                    tonal = { clothingVariant('Navy canvas shoes', 6, 3), clothingVariant('Blue canvas shoes', 6, 11) },
                    varied = { clothingVariant('White canvas shoes', 6, 1), clothingVariant('Green canvas shoes', 6, 5) },
                },
            },
            sports = {
                components = { [6] = 4 },
                variants = {
                    neutral = { clothingVariant('Black sports shoes', 6, 0), clothingVariant('White sports shoes', 6, 1), clothingVariant('Off-white sports shoes', 6, 2) },
                    tonal = { clothingVariant('Blue sports shoes', 6, 3), clothingVariant('Black sports shoes', 6, 0) },
                    varied = { clothingVariant('White sports shoes', 6, 1), clothingVariant('Off-white sports shoes', 6, 2) },
                },
            },
            runners = {
                components = { [6] = 10 },
                variants = {
                    neutral = { clothingVariant('Gray runners', 6, 1), clothingVariant('Two-tone runners', 6, 3) },
                    tonal = { clothingVariant('Baby-blue runners', 6, 2), clothingVariant('Two-tone runners', 6, 3) },
                    varied = { clothingVariant('Purple-accent runners', 6, 0), clothingVariant('Gray runners', 6, 1) },
                },
            },
            ankle = {
                components = { [6] = 8 },
                variants = {
                    neutral = { clothingVariant('Black ankle boots', 6, 0), clothingVariant('Gray ankle boots', 6, 1), clothingVariant('Charcoal ankle boots', 6, 4) },
                    tonal = { clothingVariant('Charcoal ankle boots', 6, 4), clothingVariant('Brown ankle boots', 6, 2) },
                    varied = { clothingVariant('Cream ankle boots', 6, 5), clothingVariant('Explorer ankle boots', 6, 6) },
                },
            },
            round_toed = {
                components = { [6] = 13 },
                variants = {
                    neutral = { clothingVariant('Charcoal round-toed shoes', 6, 0), clothingVariant('Gray round-toed shoes', 6, 14) },
                    tonal = { clothingVariant('Blue round-toed shoes', 6, 11), clothingVariant('Charcoal round-toed shoes', 6, 0) },
                    varied = { clothingVariant('Wheat round-toed shoes', 6, 6), clothingVariant('Two-tone round-toed shoes', 6, 5) },
                },
            },
            combat = {
                components = { [6] = 7 },
                variants = {
                    neutral = { clothingVariant('Midnight combat boots', 6, 0), clothingVariant('Gray combat boots', 6, 1) },
                    tonal = { clothingVariant('Olive combat boots', 6, 9), clothingVariant('Gray combat boots', 6, 1) },
                    varied = { clothingVariant('Wheat combat boots', 6, 5), clothingVariant('Tan combat boots', 6, 13) },
                },
            },
            high_tops = {
                components = { [6] = 11 },
                variants = {
                    neutral = { clothingVariant('Two-tone high tops', 6, 2), clothingVariant('Elite Shock high tops', 6, 1) },
                    tonal = { clothingVariant('Two-tone high tops', 6, 2), clothingVariant('Elite Shock high tops', 6, 1) },
                    varied = { clothingVariant('Red-accent high tops', 6, 3), clothingVariant('Two-tone high tops', 6, 2) },
                },
            },
        },
        accessories = {
            watch = { prop = 6, drawable = 0, variants = { neutral = { propVariant('Pewter watch', 4) }, tonal = { propVariant('Pewter watch', 4) }, varied = { propVariant('Pewter watch', 4) } } },
            glasses = { prop = 1, drawable = 11, variants = { neutral = { propVariant('Black aviators', 3) }, tonal = { propVariant('Steel aviators', 1) }, varied = { propVariant('Bronze aviators', 2) } } },
        },
    },
}

local STYLE_POOLS = {
    male = {
        polished = { tops = { 'polo' }, bottoms = { 'chinos', 'dress_chinos', 'regular_jeans' }, shoes = { 'oxford', 'chelsea', 'boat' }, accessories = { 'watch', 'glasses' } },
        casual = { tops = { 'tee_clean', 'polo' }, bottoms = { 'regular_jeans', 'ranch_jeans', 'chinos' }, shoes = { 'canvas', 'skate', 'boat' }, accessories = { 'watch', 'glasses' } },
        street = { tops = { 'tee_graphic', 'tee_clean' }, bottoms = { 'cargo', 'baggy', 'fitted_cargo' }, shoes = { 'skate', 'boots', 'canvas' }, accessories = { 'glasses', 'watch' } },
    },
    female = {
        polished = { tops = { 'shirt', 'polo' }, bottoms = { 'suit', 'chinos' }, shoes = { 'round_toed', 'ankle' }, accessories = { 'watch', 'glasses' } },
        casual = { tops = { 'tee_clean' }, bottoms = { 'skinny', 'rollups', 'chinos' }, shoes = { 'canvas', 'sports', 'ankle' }, accessories = { 'glasses', 'watch' } },
        street = { tops = { 'tee_clean' }, bottoms = { 'cargo', 'skinny' }, shoes = { 'combat', 'high_tops', 'canvas' }, accessories = { 'glasses', 'watch' } },
    },
}

local function registerOfficialCatalog()
    if type(AppearanceCatalog) ~= 'table' then return end
    for _, gender in ipairs({ 'male', 'female' }) do
        local catalog = AppearanceCatalog[gender]
        if type(catalog) == 'table' then
            for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
                for _, entry in ipairs(catalog[category] or {}) do
                    local pieceId = ('official_%s_%s'):format(category, entry.id)
                    local variants = { neutral = {}, tonal = {}, varied = {} }
                    for _, palette in ipairs({ 'neutral', 'tonal', 'varied' }) do
                        for _, variant in ipairs(entry.variants[palette] or {}) do
                            if category == 'tops' then
                                variants[palette][#variants[palette] + 1] = upperVariant(variant.name, 0, variant.texture)
                            else
                                local componentId = category == 'bottoms' and 4 or 6
                                variants[palette][#variants[palette] + 1] = clothingVariant(variant.name, componentId, variant.texture)
                            end
                        end
                    end

                    local components
                    if category == 'tops' then
                        components = {
                            [3] = entry.torso,
                            [8] = gender == 'female' and 14 or 15,
                            [11] = entry.drawable,
                        }
                    else
                        components = { [category == 'bottoms' and 4 or 6] = entry.drawable }
                    end
                    PIECES[gender][category][pieceId] = {
                        global = true,
                        components = components,
                        variants = variants,
                    }
                    for _, style in ipairs(entry.styles or {}) do
                        local stylePool = STYLE_POOLS[gender][style]
                        if stylePool then stylePool[category][#stylePool[category] + 1] = pieceId end
                    end
                end
            end
        end
    end
end

registerOfficialCatalog()

local function finiteInteger(value, minimum, maximum)
    if type(value) ~= 'number' and type(value) ~= 'string' then return nil end
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge or number ~= math.floor(number) then return nil end
    if minimum and number < minimum then return nil end
    if maximum and number > maximum then return nil end
    return number
end

local function enumValue(value, allowed, fallback)
    if type(value) ~= 'string' or #value > 24 then return fallback end
    value = value:lower()
    return allowed[value] and value or fallback
end

function AppearanceRandomizer.sanitizeOptions(raw)
    raw = type(raw) == 'table' and raw or {}
    return {
        mode = enumValue(raw.mode, VALID_MODES, 'outfit'), style = enumValue(raw.style, VALID_STYLES, 'polished'),
        gender = enumValue(raw.gender, VALID_GENDERS, 'keep'), hairTone = enumValue(raw.hairTone, VALID_HAIR_TONES, 'any'),
        palette = enumValue(raw.palette, VALID_PALETTES, 'neutral'),
        faceProfile = enumValue(raw.faceProfile, VALID_FACE_PROFILES, 'everyday'),
        ageProfile = enumValue(raw.ageProfile, VALID_AGE_PROFILES, 'young'),
        complexion = enumValue(raw.complexion, VALID_COMPLEXIONS, 'clean'),
        hairStyle = enumValue(raw.hairStyle, VALID_HAIR_STYLES, 'any'),
        makeup = enumValue(raw.makeup, VALID_MAKEUP, 'subtle'),
        accessories = raw.accessories == true,
    }
end

function AppearanceRandomizer.isNaturalHairRgb(red, green, blue)
    red, green, blue = finiteInteger(red, 0, 255), finiteInteger(green, 0, 255), finiteInteger(blue, 0, 255)
    if not red or not green or not blue then return false end
    local maximum, minimum = math.max(red, green, blue), math.min(red, green, blue)
    local spread = maximum - minimum
    local neutral = spread <= 24 and maximum <= 230
    local warm = red >= green and green >= blue and red <= 238 and spread <= 175 and (red < 48 or green >= 18) and (red < 58 or blue >= 5)
    return neutral or warm
end

local function matchesTone(entry, tone)
    local luminance = (entry.r * 0.2126) + (entry.g * 0.7152) + (entry.b * 0.0722)
    if tone == 'dark' then return luminance <= 82 end
    if tone == 'light' then return luminance >= 128 end
    if tone == 'warm' then return entry.r >= entry.g + 7 and luminance > 45 and luminance < 170 end
    return true
end

function AppearanceRandomizer.filterNaturalHairColors(entries, tone)
    tone = VALID_HAIR_TONES[tone] and tone or 'any'
    local natural, toned = {}, {}
    if type(entries) == 'table' then
        for _, entry in ipairs(entries) do
            if type(entry) == 'table' then
                local index = finiteInteger(entry.index, 0, 255)
                local red, green, blue = finiteInteger(entry.r, 0, 255), finiteInteger(entry.g, 0, 255), finiteInteger(entry.b, 0, 255)
                if index and red and green and blue and AppearanceRandomizer.isNaturalHairRgb(red, green, blue) then
                    local color = { index = index, r = red, g = green, b = blue }
                    natural[#natural + 1] = color
                    if matchesTone(color, tone) then toned[#toned + 1] = color end
                end
            end
        end
    end
    if #toned > 0 then return toned end
    if #natural > 0 then return natural end
    return { { index = 0, r = 0, g = 0, b = 0 } }
end

local function materializeClothingPiece(pieceId, definition, palette)
    local pieces = {}
    for variantIndex, variant in ipairs(definition.variants[palette] or definition.variants.neutral) do
        local components = {}
        for componentId, drawable in pairs(definition.components) do
            local component = { component = componentId, texture = variant.textures[componentId] or 0 }
            if definition.global then
                component.globalDrawable = drawable
            else
                component.collection = BASE_GAME_COLLECTION
                component.drawable = drawable
            end
            components[#components + 1] = component
        end
        table.sort(components, function(left, right) return left.component < right.component end)
        pieces[#pieces + 1] = { id = ('%s-%s-%d'):format(pieceId, palette, variantIndex), name = variant.name, components = components }
    end
    return pieces
end

local function materializeAccessory(pieceId, definition, palette)
    local pieces = {}
    for variantIndex, variant in ipairs(definition.variants[palette] or definition.variants.neutral) do
        pieces[#pieces + 1] = { id = ('%s-%s-%d'):format(pieceId, palette, variantIndex), name = variant.name, prop = definition.prop, collection = BASE_GAME_COLLECTION, drawable = definition.drawable, texture = variant.texture }
    end
    return pieces
end

function AppearanceRandomizer.getPiecePools(gender, style, palette)
    gender = gender == 'female' and 'female' or 'male'
    style = VALID_STYLES[style] and style or 'polished'
    palette = VALID_PALETTES[palette] and palette or 'neutral'
    local definitions, stylePool = PIECES[gender], STYLE_POOLS[gender][style]
    local pools = { tops = {}, bottoms = {}, shoes = {}, accessories = {} }
    for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
        -- Mixed outfits vary the focal top while keeping pants and shoes in the
        -- neutral pool. This prevents three independently saturated pieces.
        local piecePalette = palette == 'varied' and category ~= 'tops' and 'neutral' or palette
        for _, pieceId in ipairs(stylePool[category]) do
            for _, piece in ipairs(materializeClothingPiece(pieceId, definitions[category][pieceId], piecePalette)) do
                pools[category][#pools[category] + 1] = piece
            end
        end
    end
    for _, pieceId in ipairs(stylePool.accessories or {}) do
        for _, piece in ipairs(materializeAccessory(pieceId, definitions.accessories[pieceId], palette)) do
            pools.accessories[#pools.accessories + 1] = piece
        end
    end
    return pools
end

function AppearanceRandomizer.filterPiecePools(pools, clothingValidator, accessoryValidator)
    pools = type(pools) == 'table' and pools or {}
    local filtered = { tops = {}, bottoms = {}, shoes = {}, accessories = {} }
    local acceptsClothing = type(clothingValidator) == 'function' and clothingValidator or function() return true end
    local acceptsAccessory = type(accessoryValidator) == 'function' and accessoryValidator or function() return true end

    for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
        for _, piece in ipairs(pools[category] or {}) do
            if acceptsClothing(piece, category) then
                filtered[category][#filtered[category] + 1] = piece
            end
        end
    end
    for _, accessory in ipairs(pools.accessories or {}) do
        if acceptsAccessory(accessory) then
            filtered.accessories[#filtered.accessories + 1] = accessory
        end
    end
    return filtered
end

local function chooseFromPool(pool, chooser, category)
    if type(pool) ~= 'table' or #pool == 0 then return nil end
    local index = type(chooser) == 'function' and finiteInteger(chooser(#pool, category), 1, #pool) or 1
    return pool[index or 1]
end

function AppearanceRandomizer.getIdentityPool(gender, options)
    options = type(options) == 'table' and options or {}
    local source = IDENTITY_POOLS[gender == 'female' and 'female' or 'male']
    local profileName = VALID_FACE_PROFILES[options.faceProfile] and options.faceProfile or 'everyday'
    local hairStyle = VALID_HAIR_STYLES[options.hairStyle] and options.hairStyle or 'any'
    local profile = source.profiles[profileName] or source.profiles.everyday
    local pool = {
        profile = profileName,
        mothers = {},
        fathers = {},
        hair = {},
        shapeMixMin = profile.shapeMix[1],
        shapeMixMax = profile.shapeMix[2],
        skinMixMin = 0.24,
        skinMixMax = 0.76,
    }
    for index, parentId in ipairs(profile.mothers) do pool.mothers[index] = parentId end
    for index, parentId in ipairs(profile.fathers) do pool.fathers[index] = parentId end
    for _, hair in ipairs(source.hair) do
        if hairStyle == 'any' or hair.group == hairStyle then
            pool.hair[#pool.hair + 1] = {
                name = hair.name,
                group = hair.group,
                collection = hair.collection,
                drawable = hair.drawable,
                texture = hair.texture,
            }
        end
    end
    return pool
end

function AppearanceRandomizer.assembleIdentity(gender, options, chooser)
    if type(options) == 'function' then
        chooser, options = options, {}
    end
    local pool = AppearanceRandomizer.getIdentityPool(gender, options)
    local mother = chooseFromPool(pool.mothers, chooser, 'mother')
    local father = chooseFromPool(pool.fathers, chooser, 'father')
    return {
        profile = pool.profile,
        shapeFirst = mother,
        shapeSecond = father,
        skinFirst = mother,
        skinSecond = father,
        shapeMixMin = pool.shapeMixMin,
        shapeMixMax = pool.shapeMixMax,
        skinMixMin = pool.skinMixMin,
        skinMixMax = pool.skinMixMax,
        hair = chooseFromPool(pool.hair, chooser, 'hair'),
    }
end

function AppearanceRandomizer.getFaceFeatureRange(gender, profileName, featureId)
    featureId = finiteInteger(featureId, 0, 19) or 0
    profileName = VALID_FACE_PROFILES[profileName] and profileName or 'everyday'
    local ranges = gender == 'female' and FEMALE_FACE_RANGES or MALE_FACE_RANGES
    local range = ranges[featureId] or { -0.12, 0.12 }
    local minimum, maximum = range[1], range[2]
    if profileName == 'soft' then
        minimum, maximum = minimum * 0.78, maximum * 0.78
    end
    return minimum, maximum
end

function AppearanceRandomizer.getOverlayPlan(gender, options)
    options = type(options) == 'table' and options or {}
    local ageProfile = VALID_AGE_PROFILES[options.ageProfile] and options.ageProfile or 'young'
    local complexion = VALID_COMPLEXIONS[options.complexion] and options.complexion or 'clean'
    local makeup = VALID_MAKEUP[options.makeup] and options.makeup or 'subtle'
    local isFemale = gender == 'female'
    local naturalSkin = complexion == 'natural'
    local isMature = ageProfile == 'mature'
    local isAdult = ageProfile == 'adult'

    local plan = {
        [0] = overlay(naturalSkin and 8 or 0, 0.08, 0.20),
        [1] = overlay(isFemale and 0 or 52, 0.50, 0.88, 'hair'),
        [2] = overlay(100, 0.78, 1.0, 'hair'),
        [3] = overlay(isMature and 42 or (isAdult and 5 or 0), 0.08, isMature and 0.42 or 0.16),
        [4] = overlay(isFemale and (makeup == 'polished' and 48 or (makeup == 'subtle' and 18 or 0)) or 0, 0.08, makeup == 'polished' and 0.38 or 0.22, 'cosmetic'),
        [5] = overlay(isFemale and (makeup == 'polished' and 34 or (makeup == 'subtle' and 12 or 0)) or 0, 0.06, makeup == 'polished' and 0.28 or 0.18, 'cosmetic'),
        [6] = overlay(naturalSkin and 8 or 0, 0.08, 0.20),
        [7] = overlay(isMature and 16 or (isAdult and naturalSkin and 3 or 0), 0.08, 0.20),
        [8] = overlay(isFemale and (makeup == 'polished' and 46 or (makeup == 'subtle' and 18 or 0)) or 0, 0.10, makeup == 'polished' and 0.38 or 0.24, 'cosmetic'),
        [9] = overlay(naturalSkin and 12 or 0, 0.10, 0.28),
        [10] = overlay(isFemale and 0 or 18, 0.28, 0.65, 'hair'),
        [11] = overlay(naturalSkin and 4 or 0, 0.06, 0.16),
    }
    return plan
end

function AppearanceRandomizer.assembleOutfit(pools, includeAccessories, chooser)
    pools = type(pools) == 'table' and pools or {}
    local top = chooseFromPool(pools.tops, chooser, 'tops')
    local bottom = chooseFromPool(pools.bottoms, chooser, 'bottoms')
    local shoes = chooseFromPool(pools.shoes, chooser, 'shoes')
    if not top or not bottom or not shoes then return nil, 'empty_piece_pool' end
    local components = {}
    for _, piece in ipairs({ top, bottom, shoes }) do
        for _, component in ipairs(piece.components) do
            components[#components + 1] = {
                component = component.component,
                collection = component.collection,
                drawable = component.drawable,
                globalDrawable = component.globalDrawable,
                texture = component.texture,
            }
        end
    end
    table.sort(components, function(left, right) return left.component < right.component end)
    local accessories = {}
    if includeAccessories then
        local accessory = chooseFromPool(pools.accessories, chooser, 'accessories')
        if accessory then accessories[1] = { prop = accessory.prop, collection = accessory.collection, drawable = accessory.drawable, texture = accessory.texture } end
    end
    return {
        id = table.concat({ top.id, bottom.id, shoes.id }, '+'),
        name = table.concat({ top.name, bottom.name, shoes.name }, ', '),
        components = components, accessories = accessories,
        pieces = { top = top.id, bottom = bottom.id, shoes = shoes.id },
    }
end
