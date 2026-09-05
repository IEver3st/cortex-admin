-- Stable identities survive global drawable shifts after clothing/DLC updates.
WardrobeCatalog = { version = 2, maxImageBytes = 65536, maxItems = 50000,
    emptyMarker = 'empty:cutout-v2', statusKey = 'wardrobe:v2:lastCompleted' }

function WardrobeCatalog.key(item)
    if type(item) ~= 'table' or (item.gender ~= 'male' and item.gender ~= 'female')
        or (item.kind ~= 'component' and item.kind ~= 'prop')
        or type(item.collection) ~= 'string' or #item.collection > 96
        or item.collection:find('[%c]') then return nil end
    local function integer(n, lo, hi)
        return type(n) == 'number' and n == n and n >= lo and n <= hi and n % 1 == 0
    end
    if not integer(item.slot, 0, item.kind == 'component' and 11 or 7)
        or not integer(item.drawable, 0, 65535) then return nil end
    return ('wardrobe:v%d:%s:%s:%d:%d:%s'):format(WardrobeCatalog.version,
        item.gender, item.kind, item.slot, item.drawable, item.collection)
end

function WardrobeCatalog.validImage(data)
    return type(data) == 'string' and #data > 128 and #data <= WardrobeCatalog.maxImageBytes
        and data:match('^data:image/webp;base64,UklGR[A-Za-z0-9+/=]+$') ~= nil
end

function WardrobeCatalog.validStored(data)
    return data == WardrobeCatalog.emptyMarker or WardrobeCatalog.validImage(data)
end
