WardrobeSharePolicy = WardrobeSharePolicy or {}

WardrobeSharePolicy.DEFAULT_RADIUS = 8.0

local function finitePositiveNumber(value)
    local number = tonumber(value)
    if not number
        or number ~= number
        or number == math.huge
        or number == -math.huge
        or number <= 0.0 then
        return nil
    end

    return number
end

function WardrobeSharePolicy.validateRadius(value)
    return finitePositiveNumber(value)
end

function WardrobeSharePolicy.normalizeRadius(value)
    return WardrobeSharePolicy.validateRadius(value) or WardrobeSharePolicy.DEFAULT_RADIUS
end

function WardrobeSharePolicy.validateTargetSnapshot(value)
    if type(value) ~= 'table' or type(value.targets) ~= 'table' then
        return nil
    end

    local radius = WardrobeSharePolicy.validateRadius(value.radius)
    if not radius then
        return nil
    end

    return {
        radius = radius,
        targets = value.targets,
    }
end

function WardrobeSharePolicy.isDistanceSquaredWithinRadius(distanceSquared, radius)
    local validRadius = WardrobeSharePolicy.validateRadius(radius)
    local validDistance = tonumber(distanceSquared)
    if not validRadius
        or not validDistance
        or validDistance ~= validDistance
        or validDistance == math.huge
        or validDistance == -math.huge
        or validDistance < 0.0 then
        return false
    end

    return validDistance <= validRadius * validRadius
end
