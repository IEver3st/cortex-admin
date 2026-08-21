-- Reviewed official GTA Online clothing used by the modular appearance
-- generator. Drawable IDs are the official global indexes from the source
-- catalogs; the client resolves them to collection-local indexes at runtime.
--
-- Names: root-cause/v-clothingnames @ 84020cfa80b1a2fdc86f0e8eb438d313f343c015
-- Torsos: root-cause/v-besttorso     @ a2eba9f862baf7c6da34a4b5d1bd36a4abbf8e03
-- Reviewed: 2026-08-18. Costume, holiday, underwear and novelty pieces were
-- excluded. Every top includes the torso recommended by v-besttorso.

AppearanceCatalog = AppearanceCatalog or {}

local P = { 'polished' }
local C = { 'casual' }
local S = { 'street' }
local PC = { 'polished', 'casual' }
local CS = { 'casual', 'street' }

local function color(name, texture)
    return { name = name, texture = texture }
end

local function top(id, drawable, torso, styles, neutral, tonal, varied)
    return {
        id = id,
        drawable = drawable,
        torso = torso,
        styles = styles,
        variants = { neutral = { neutral }, tonal = { tonal }, varied = { varied } },
    }
end

local function garment(id, drawable, styles, neutral, tonal, varied)
    return {
        id = id,
        drawable = drawable,
        styles = styles,
        variants = { neutral = { neutral }, tonal = { tonal }, varied = { varied } },
    }
end

AppearanceCatalog.male = {
    tops = {
        top('double_suit', 20, 1, P, color('Charcoal pinstripe double suit', 2), color('Navy pinstripe double suit', 1), color('Classic ivory double suit', 0)),
        top('sports_coat', 23, 1, P, color('White sports coat', 3), color('Navy sports coat', 2), color('Lilac sports coat', 1)),
        top('smart_jacket', 24, 1, PC, color('Light gray jacket', 0), color('Subtle blue jacket', 4), color('Brown jacket', 5)),
        top('tucked_shirt', 26, 11, P, color('Gray plaid tucked shirt', 9), color('Navy tucked shirt', 0), color('Ash tucked shirt', 2)),
        top('double_breasted', 27, 1, P, color('Black double-breasted jacket', 0), color('Blue double-breasted jacket', 2), color('Gray double-breasted jacket', 1)),
        top('tailored_jacket', 28, 1, P, color('Black tailored jacket', 0), color('Blue tailored jacket', 2), color('Gray tailored jacket', 1)),
        top('smooth_fitted', 30, 1, P, color('Black smooth fitted jacket', 0), color('Navy smooth fitted jacket', 2), color('Teal smooth fitted jacket', 3)),
        top('sharp_fitted', 32, 1, P, color('Black sharp fitted jacket', 0), color('Navy sharp fitted jacket', 2), color('Teal sharp fitted jacket', 3)),
        top('combat_top', 49, 4, S, color('Black combat top', 0), color('Tan combat top', 3), color('Charcoal combat top', 2)),
        top('combat_sweater', 50, 4, S, color('Black combat sweater', 0), color('Tan combat sweater', 3), color('Charcoal combat sweater', 2)),
        top('hooded_jacket', 68, 4, CS, color('Black hooded jacket', 0), color('Navy hooded jacket', 4), color('Dark gray hooded jacket', 2)),
        top('leather_fur_jacket', 70, 4, CS, color('Black leather fur jacket', 2), color('Brown leather fur jacket', 0), color('Fall leather fur jacket', 6)),
        top('wool_coat', 72, 4, PC, color('Gray wool coat', 1), color('Navy wool coat', 3), color('Black wool coat', 2)),
        top('bomber', 74, 4, CS, color('Black SN bomber', 2), color('Brown diamond bomber', 4), color('Classic SN bomber', 0)),
        top('zipped_bomber', 75, 6, CS, color('Black SN zipped bomber', 2), color('Brown zipped bomber', 4), color('Classic SN zipped bomber', 0)),
        top('trench_coat', 76, 14, P, color('Black trench coat', 1), color('Navy trench coat', 2), color('Gray trench coat', 3)),
        top('overcoat', 77, 4, P, color('Gray overcoat', 0), color('Navy overcoat', 2), color('Beige overcoat', 1)),
        top('print_sweater', 78, 6, CS, color('Black geo-print sweater', 2), color('Brown print sweater', 7), color('Hound print sweater', 4)),
        top('loose_polo', 82, 0, PC, color('Black loose polo', 2), color('Blue-stripe loose polo', 6), color('Gray loose polo', 0)),
        top('sport_hoodie', 86, 4, CS, color('Black sport hoodie', 0), color('Blue sport hoodie', 3), color('Gray sport hoodie', 1)),
        top('varsity_jacket', 87, 4, S, color('Black varsity jacket', 2), color('Blue varsity jacket', 10), color('Gray varsity jacket', 5)),
        top('utility_tee', 97, 0, CS, color('Beige T-shirt', 0), color('Khaki T-shirt', 1), color('Beige T-shirt', 0)),
        top('continental_jacket', 100, 1, P, color('White continental jacket', 0), color('Navy continental jacket', 1), color('Lilac continental jacket', 3)),
        top('check_double_suit', 119, 1, P, color('Gray check double suit', 4), color('Blue check double suit', 0), color('Dusk check double suit', 2)),
    },
    bottoms = {
        garment('smart_regular', 22, PC, color('Light gray regular pants', 0), color('Subtle blue regular pants', 4), color('Brown regular pants', 5)),
        garment('skinny_suit', 24, P, color('Black skinny suit pants', 0), color('Navy skinny suit pants', 2), color('Teal skinny suit pants', 3)),
        garment('regular_suit', 25, P, color('Gray regular suit pants', 1), color('Navy regular suit pants', 2), color('Teal regular suit pants', 3)),
        garment('slim_fit', 28, PC, color('Black slim-fit pants', 0), color('Olive slim-fit pants', 4), color('Gray slim-fit pants', 3)),
        garment('striped_chinos', 29, P, color('Thin striped chinos', 0), color('Thin striped chinos', 0), color('Wide striped chinos', 1)),
        garment('scruffy_suit', 37, P, color('Gray scruffy suit pants', 0), color('Blue scruffy suit pants', 3), color('Black scruffy suit pants', 2)),
        garment('flight_pants', 41, S, color('Black flight pants', 0), color('Black flight pants', 0), color('Black flight pants', 0)),
        garment('loose_jeans', 43, CS, color('Black loose jeans', 1), color('Blue loose jeans', 0), color('Blue loose jeans', 0)),
        garment('tracksuit_pants', 55, CS, color('Black tracksuit pants', 0), color('Navy tracksuit pants', 2), color('Teal tracksuit pants', 3)),
        garment('check_suit_pants', 60, P, color('Gray check suit pants', 4), color('Blue check suit pants', 0), color('Dusk check suit pants', 2)),
        garment('work_shorts', 62, C, color('Black work shorts', 0), color('Blue work shorts', 2), color('Khaki work shorts', 3)),
        garment('classic_jeans', 63, C, color('Classic blue jeans', 0), color('Classic blue jeans', 0), color('Classic blue jeans', 0)),
        garment('modern_tracksuit', 64, CS, color('Gray tracksuit pants', 8), color('Blue tracksuit pants', 0), color('Burgundy tracksuit pants', 1)),
        garment('plain_biker', 71, C, color('Black plain pants', 0), color('Chocolate plain pants', 2), color('Worn black plain pants', 3)),
        garment('padded_biker', 73, S, color('Black padded pants', 0), color('Chocolate padded pants', 2), color('Worn black padded pants', 3)),
        garment('ribbed_denim', 75, CS, color('Black ribbed jeans', 7), color('Indigo ribbed jeans', 0), color('Faded ribbed jeans', 2)),
        garment('roadworn_denim', 76, CS, color('Black roadworn jeans', 7), color('Navy roadworn jeans', 3), color('Faded roadworn jeans', 2)),
        garment('low_crotch', 78, S, color('Black low-crotch pants', 2), color('Chocolate low-crotch pants', 0), color('Charcoal low-crotch pants', 5)),
        garment('tapered_low_crotch', 82, S, color('Black tapered pants', 4), color('Navy tapered pants', 0), color('Classic tapered pants', 2)),
        garment('leather_jeans', 83, S, color('Black leather jeans', 0), color('Brown leather jeans', 3), color('Black leather jeans', 0)),
    },
    shoes = {
        garment('toe_oxfords', 18, P, color('Black-toe Oxfords', 0), color('Black-toe Oxfords', 0), color('White-toe Oxfords', 1)),
        garment('two_tone_oxfords', 20, P, color('Gray two-tone Oxfords', 5), color('Chocolate Oxfords', 0), color('Ash Oxfords', 4)),
        garment('slip_ons', 21, PC, color('Black slip-ons', 0), color('Navy slip-ons', 7), color('Copper slip-ons', 5)),
        garment('dlc_canvas', 22, C, color('Gray two-tone canvas shoes', 5), color('Sky-blue canvas shoes', 0), color('Checked canvas shoes', 6)),
        garment('wingtips', 23, P, color('Black wingtips', 6), color('Navy wingtips', 1), color('Gentleman wingtips', 7)),
        garment('flight_boots', 24, S, color('Black flight boots', 0), color('Black flight boots', 0), color('Black flight boots', 0)),
        garment('tactical_boots', 25, S, color('Black tactical boots', 0), color('Black tactical boots', 0), color('Black tactical boots', 0)),
        garment('studded_sneakers', 28, CS, color('Black studded sneakers', 1), color('Blue studded sneakers', 5), color('White studded sneakers', 0)),
        garment('driving_loafers', 30, PC, color('Gray driving loafers', 1), color('Dual driving loafers', 0), color('Dual driving loafers', 0)),
        garment('calypso_runners', 31, CS, color('Calypso runners', 0), color('Calypso runners', 0), color('Buzz runners', 1)),
        garment('hi_top_sneakers', 32, CS, color('Black high-top sneakers', 0), color('Black high-top sneakers', 0), color('Dual high-top sneakers', 2)),
        garment('walking_boots', 35, C, color('Tan walking boots', 0), color('Khaki walking boots', 1), color('Tan walking boots', 0)),
        garment('leather_loafers', 36, PC, color('Black leather loafers', 3), color('Brown leather loafers', 2), color('Sienna leather loafers', 0)),
        garment('tip_oxfords', 40, P, color('Gray-tip Oxfords', 4), color('Blue-tip Oxfords', 0), color('Dusk-tip Oxfords', 2)),
        garment('canvas_slip_ons', 42, PC, color('Black canvas slip-ons', 1), color('Blue canvas slip-ons', 4), color('Striped canvas slip-ons', 5)),
        garment('ankle_boots', 43, CS, color('Black ankle boots', 3), color('Blue ankle boots', 4), color('Denim ankle boots', 2)),
        garment('laceup_boots', 50, CS, color('Black lace-up boots', 0), color('Chocolate lace-up boots', 2), color('Worn black lace-up boots', 3)),
        garment('slack_boots', 53, CS, color('Black slack boots', 0), color('Chocolate slack boots', 2), color('Worn black slack boots', 3)),
        garment('plain_high_tops', 57, CS, color('Silver plain high-tops', 6), color('Blue plain high-tops', 2), color('Bronze plain high-tops', 3)),
        garment('tech_boots', 60, S, color('Black tech boots', 0), color('Brown tech boots', 2), color('Tawny tech boots', 4)),
        garment('moc_toe_boots', 65, CS, color('Black moc-toe boots', 1), color('Chocolate moc-toe boots', 3), color('Classic moc-toe boots', 0)),
        garment('trail_shoes', 72, S, color('Black and sand trail shoes', 1), color('Black and blue trail shoes', 2), color('Mono trail shoes', 0)),
        garment('retro_sneakers', 93, CS, color('Grayscale retro sneakers', 11), color('Blue retro sneakers', 0), color('Two-tone retro sneakers', 5)),
        garment('uniform_boots', 96, S, color('Heavy uniform boots', 0), color('Heavy uniform boots', 0), color('Heavy uniform boots', 0)),
    },
}

AppearanceCatalog.female = {
    tops = {
        top('blazer', 25, 6, P, color('Cream blazer', 2), color('Blue suede blazer', 4), color('Burgundy blazer', 7)),
        top('blouse', 27, 0, PC, color('Black blouse', 1), color('Tan blouse', 2), color('Gray striped blouse', 3)),
        top('tailored_vest', 28, 0, P, color('Gray vest', 1), color('Navy vest', 2), color('Black vest', 3)),
        top('cropped_biker', 35, 5, CS, color('Silver cropped biker jacket', 10), color('Dark brown cropped biker jacket', 4), color('Mustard cropped biker jacket', 2)),
        top('combat_top', 42, 3, S, color('Black combat top', 0), color('Tan combat top', 3), color('Charcoal combat top', 2)),
        top('combat_sweater', 43, 3, S, color('Black combat sweater', 0), color('Tan combat sweater', 3), color('Charcoal combat sweater', 2)),
        top('rolled_shirt', 56, 14, PC, color('Black rolled shirt', 0), color('Black rolled shirt', 0), color('Black rolled shirt', 0)),
        top('fitted_tux', 58, 3, P, color('Black fitted tux', 0), color('Navy fitted tux', 2), color('Teal fitted tux', 3)),
        top('hooded_jacket', 62, 3, CS, color('Black hooded jacket', 0), color('Navy hooded jacket', 4), color('Dark gray hooded jacket', 2)),
        top('peacoat', 64, 5, PC, color('Black peacoat', 1), color('Navy peacoat', 2), color('Gray peacoat', 3)),
        top('leather_fur_jacket', 65, 5, CS, color('Black leather fur jacket', 3), color('Brown leather fur jacket', 1), color('Fall leather fur jacket', 6)),
        top('belted_jacket', 66, 5, PC, color('Black belted jacket', 0), color('Brown belted jacket', 1), color('Teal belted jacket', 3)),
        top('trench_coat', 70, 5, P, color('Black trench coat', 1), color('Navy trench coat', 2), color('Gray trench coat', 3)),
        top('print_sweater', 71, 1, CS, color('Black geo-print sweater', 2), color('Brown print sweater', 7), color('Hound print sweater', 4)),
        top('loose_tank', 74, 15, CS, color('Black loose tank', 1), color('White loose tank', 0), color('Gray loose tank', 2)),
        top('sport_hoodie', 78, 3, CS, color('Black sport hoodie', 0), color('Blue sport hoodie', 6), color('Lilac sport hoodie', 2)),
        top('varsity_jacket', 81, 3, S, color('Black varsity jacket', 2), color('Blue varsity jacket', 10), color('Gray varsity jacket', 5)),
        top('utility_tee', 88, 14, CS, color('Beige T-shirt', 0), color('Khaki T-shirt', 1), color('Beige T-shirt', 0)),
        top('continental_jacket', 91, 3, P, color('White continental jacket', 0), color('Navy continental jacket', 1), color('Lilac continental jacket', 3)),
        top('shiny_jacket', 93, 3, P, color('Black shiny jacket', 2), color('Blue shiny jacket', 1), color('Black shiny jacket', 2)),
        top('work_shirt', 119, 14, PC, color('Black work shirt', 2), color('Navy work shirt', 1), color('White work shirt', 0)),
    },
    bottoms = {
        garment('tailored_suit', 23, P, color('Gray woven suit pants', 4), color('Blue suit pants', 1), color('Olive suit pants', 5)),
        garment('panel_pencil', 24, P, color('Gray panel pencil skirt', 3), color('Blue pencil skirt', 1), color('Houndstooth pencil skirt', 2)),
        garment('denim_shorts', 25, C, color('Black denim shorts', 6), color('Navy denim shorts', 0), color('Blue denim shorts', 2)),
        garment('leggings', 27, CS, color('Black leggings', 0), color('Navy leggings', 13), color('Gray leggings', 1)),
        garment('combat_pants', 30, S, color('Black combat pants', 0), color('Tan combat pants', 3), color('Charcoal combat pants', 2)),
        garment('heist_pants', 32, S, color('Black heist pants', 0), color('Black heist pants', 0), color('Black heist pants', 0)),
        garment('pencil_skirt', 36, P, color('Gray pencil skirt', 0), color('Blue pencil skirt', 3), color('Black pencil skirt', 2)),
        garment('regular_suit', 37, PC, color('Black regular suit pants', 0), color('Navy regular suit pants', 2), color('Teal regular suit pants', 3)),
        garment('scruffy_suit', 41, P, color('Gray scruffy suit pants', 0), color('Blue scruffy suit pants', 3), color('Black scruffy suit pants', 2)),
        garment('flight_pants', 42, S, color('Black flight pants', 0), color('Black flight pants', 0), color('Black flight pants', 0)),
        garment('leather_zippers', 43, CS, color('Black leather zip pants', 0), color('Brown leather zip pants', 2), color('Burgundy leather zip pants', 4)),
        garment('skinny_cuts', 44, CS, color('Black skinny-cut pants', 0), color('Brown skinny-cut pants', 2), color('Burgundy skinny-cut pants', 4)),
        garment('baggy_cargo', 45, S, color('Black baggy cargo pants', 1), color('Khaki baggy cargo pants', 0), color('Gray baggy cargo pants', 3)),
        garment('battle_pants', 48, S, color('Tan battle pants', 0), color('Khaki battle pants', 1), color('Tan battle pants', 0)),
        garment('utility_pants', 49, S, color('Tan utility pants', 0), color('Khaki utility pants', 1), color('Tan utility pants', 0)),
        garment('tracksuit_pants', 58, CS, color('Black tracksuit pants', 0), color('Navy tracksuit pants', 2), color('Teal tracksuit pants', 3)),
        garment('fitted_chinos', 64, PC, color('Black fitted chinos', 1), color('Khaki fitted chinos', 2), color('Gray fitted chinos', 3)),
        garment('high_waisted', 65, PC, color('Black high-waisted pants', 0), color('Black high-waisted pants', 0), color('Gray high-waisted pants', 2)),
        garment('modern_tracksuit', 66, S, color('Gray tracksuit pants', 8), color('Blue tracksuit pants', 0), color('Burgundy tracksuit pants', 1)),
        garment('ribbed_denim', 73, C, color('Black ribbed jeans', 1), color('Deep-blue ribbed jeans', 2), color('Stonewash ribbed jeans', 3)),
        garment('roadworn_denim', 74, C, color('Black roadworn jeans', 1), color('Deep-blue roadworn jeans', 2), color('Stonewash roadworn jeans', 3)),
        garment('plain_biker', 75, C, color('Black plain pants', 0), color('Mocha plain pants', 1), color('Black plain pants', 0)),
        garment('quilted_biker', 76, C, color('Black quilted pants', 0), color('Mocha quilted pants', 1), color('Black quilted pants', 0)),
        garment('low_crotch', 80, S, color('Black low-crotch pants', 2), color('Chocolate low-crotch pants', 0), color('Charcoal low-crotch pants', 5)),
        garment('leather_low_crotch', 81, S, color('Black leather pants', 0), color('Black leather pants', 0), color('Black leather pants', 0)),
        garment('tapered_low_crotch', 84, S, color('Black tapered pants', 4), color('Navy tapered pants', 0), color('Classic tapered pants', 2)),
        garment('leather_jeans', 85, S, color('Black leather jeans', 0), color('Brown leather jeans', 3), color('Black leather jeans', 0)),
    },
    shoes = {
        garment('platforms', 19, C, color('Olive platforms', 0), color('Blue platforms', 11), color('Earth platforms', 2)),
        garment('patent_heels', 20, PC, color('Gray patent heels', 3), color('Blue patent heels', 6), color('Burgundy patent heels', 2)),
        garment('knee_high_boots', 21, P, color('Gray-accent knee-high boots', 9), color('Coffee knee-high boots', 6), color('Chestnut knee-high boots', 1)),
        garment('folded_boots', 22, PC, color('Black folded boots', 1), color('Coffee folded boots', 2), color('Gray folded boots', 4)),
        garment('flight_boots', 24, S, color('Black flight boots', 0), color('Black flight boots', 0), color('Black flight boots', 0)),
        garment('tactical_boots', 25, S, color('Black tactical boots', 0), color('Black tactical boots', 0), color('Black tactical boots', 0)),
        garment('backside_sneakers', 27, CS, color('All-black backside sneakers', 0), color('All-black backside sneakers', 0), color('All-black backside sneakers', 0)),
        garment('black_sports', 28, CS, color('All-black sports shoes', 0), color('All-black sports shoes', 0), color('All-black sports shoes', 0)),
        garment('dlc_oxfords', 29, P, color('All-black Oxfords', 0), color('Brown Oxfords', 2), color('White Oxfords', 1)),
        garment('studded_boots', 30, S, color('Leather studded boots', 0), color('Leather studded boots', 0), color('Leather studded boots', 0)),
        garment('calypso_runners', 32, CS, color('Calypso runners', 0), color('Calypso runners', 0), color('Buzz runners', 1)),
        garment('canvas_snugs', 33, CS, color('Black canvas shoes', 1), color('Blue canvas shoes', 5), color('White canvas shoes', 3)),
        garment('walking_boots', 36, C, color('Tan walking boots', 0), color('Khaki walking boots', 1), color('Tan walking boots', 0)),
        garment('leather_loafers', 37, PC, color('Black leather loafers', 3), color('Brown leather loafers', 2), color('Sienna leather loafers', 0)),
        garment('rounded_heels', 42, PC, color('Black rounded heels', 2), color('Blue rounded heels', 3), color('Nude rounded heels', 0)),
        garment('sneaker_wedges', 43, CS, color('Black sneaker wedges', 1), color('Blue sneaker wedges', 5), color('White sneaker wedges', 3)),
        garment('sneaker_boots', 44, CS, color('Black sneaker boots', 1), color('Blue sneaker boots', 5), color('White sneaker boots', 3)),
        garment('laceup_boots', 51, CS, color('Black lace-up boots', 0), color('Chocolate lace-up boots', 2), color('Worn black lace-up boots', 3)),
        garment('slack_boots', 54, CS, color('Black slack boots', 0), color('Chocolate slack boots', 2), color('Worn black slack boots', 3)),
        garment('calf_boots', 56, PC, color('Black calf boots', 0), color('Tan calf boots', 2), color('Ox-blood calf boots', 1)),
        garment('plain_high_tops', 60, CS, color('Silver plain high-tops', 6), color('Blue plain high-tops', 2), color('Bronze plain high-tops', 3)),
        garment('tech_boots', 63, S, color('Black tech boots', 0), color('Brown tech boots', 2), color('Tawny tech boots', 4)),
        garment('moc_toe_boots', 68, CS, color('Black moc-toe boots', 1), color('Chocolate moc-toe boots', 3), color('Classic moc-toe boots', 0)),
        garment('trail_shoes', 75, S, color('Black and sand trail shoes', 1), color('Black and blue trail shoes', 2), color('Mono trail shoes', 0)),
        garment('retro_sneakers', 96, CS, color('Grayscale retro sneakers', 11), color('Blue retro sneakers', 0), color('Two-tone retro sneakers', 5)),
        garment('uniform_boots', 100, S, color('Heavy uniform boots', 0), color('Heavy uniform boots', 0), color('Heavy uniform boots', 0)),
    },
}
