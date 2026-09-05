local Admin, Policy = EsAdmin, WardrobeCatalog
local prefix = 'cortex-admin:catalog:'
local job, reads, requestId = nil, {}, 0
local slots = { component = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }, prop = { 0, 1, 2, 6, 7 } }
local settleMs = tonumber(Config.WardrobeCapture and Config.WardrobeCapture.settleMs)
if not settleMs or settleMs ~= settleMs or settleMs < 250 or settleMs > 5000 then
    error('Config.WardrobeCapture.settleMs must be between 250 and 5000 milliseconds.')
end

local function message(text) print('[wardrobe-catalog] ' .. text) end
local commandSequence, commandPending = 0, nil
RegisterCommand('cortex_catalog', function(_, args)
    local mode = args[1] or 'status'
    if #mode > 16 then return message('Usage: cortex_catalog [status|sample|build|update|rebuild|cancel]') end
    if commandPending then return message('Waiting for the previous command to reach the server.') end
    commandSequence = commandSequence % 2147483647 + 1
    local request = commandSequence
    commandPending = request
    message(('Requesting %s from server...'):format(mode))
    TriggerServerEvent(prefix .. 'command', request, mode)
    SetTimeout(5000, function()
        if commandPending ~= request then return end
        commandPending = nil
        message('No server acknowledgement. In the server console run refresh, then restart cortex-admin. Check for the wardrobe-catalog Server ready message.')
    end)
end, false)
RegisterNetEvent(prefix .. 'commandAck', function(request)
    if commandPending == request then commandPending = nil end
end)
RegisterNetEvent(prefix .. 'message', message)
RegisterNetEvent(prefix .. 'changed', function() SendNUIMessage({ action = prefix .. 'changed' }) end)
Admin.isWardrobeCaptureActive = function() return job ~= nil end

local function cleanup(reason)
    local old = job
    if not old then return end
    job = nil
    if old.cam then
        local rendering = GetRenderingCam()
        if rendering == old.cam or rendering == -1 or rendering == 0 then
            RenderScriptCams(false, false, 0, true, false)
            ClearFocus()
        end
        DestroyCam(old.cam, false)
    end
    if old.ped and DoesEntityExist(old.ped) then DeleteEntity(old.ped) end
    if old.model then SetModelAsNoLongerNeeded(old.model) end
    if old.player and DoesEntityExist(old.player) and not old.frozen then FreezeEntityPosition(old.player, false) end
    message(reason or 'Capture stopped.')
end

local function abort(reason)
    if not job then return end
    TriggerServerEvent(prefix .. 'abort', job.id)
    cleanup(reason)
end

local function waitFor(current, predicate, timeout)
    local started = GetGameTimer()
    while job == current and not predicate() do
        if GetGameTimer() - started > timeout then error('Timed out waiting for capture or server response.') end
        Wait(0)
    end
    if job ~= current then error('Capture cancelled.') end
end

local function identity(ped, gender, kind, slot, drawable)
    local component = kind == 'component'
    return { gender = gender, kind = kind, slot = slot,
        collection = component and GetPedCollectionNameFromDrawable(ped, slot, drawable) or GetPedCollectionNameFromProp(ped, slot, drawable),
        drawable = component and GetPedCollectionLocalIndexFromDrawable(ped, slot, drawable) or GetPedCollectionLocalIndexFromProp(ped, slot, drawable) }
end

local function frame(current, kind, slot)
    current.rear = kind == 'component' and slot == 5
    local head = GetPedBoneCoords(current.ped, 31086, 0.0, 0.0, 0.15)
    local foot = GetPedBoneCoords(current.ped, 14201, 0.0, 0.0, -0.08)
    local height = math.max(1.5, head.z - foot.z)
    -- Generous source framing accommodates long coats. NUI fits the visible
    -- garment bounds into the final tile, rather than fitting a whole person.
    local center, span = 0.50, 1.12
    if (kind == 'prop' and slot <= 2) or (kind == 'component' and (slot == 1 or slot == 2)) then center, span = 0.88, 0.32
    elseif kind == 'component' and slot == 4 then center, span = 0.29, 0.59
    elseif kind == 'component' and slot == 6 then center, span = 0.08, 0.25
    elseif kind == 'prop' then center, span = 0.43, 0.58 end
    local z = foot.z + height * center
    current.frameZ = z
    local distance = height * span / (1.5 * math.tan(math.rad(30 / 2)))
    -- NUI crops the central square, so framing is independent of aspect ratio.
    local width, screenHeight = GetActiveScreenResolution()
    distance = distance * math.max(1.0, screenHeight / math.max(1, width))
    SetCamCoord(current.cam, current.x, current.y + (current.rear and -distance or distance), z)
    PointCamAtCoord(current.cam, current.x, current.y, z)
end

local function drawBackdrop(current)
    local side = current.rear and -1.0 or 1.0
    local x, y, z = current.x, current.y - 1.5 * side, current.z
    local color = current.backdrop == 2 and { 224, 48, 224 } or { 24, 128, 24 }
    -- Similar-luminance backings reduce exposure shifts between matte frames.
    local r, g, b = color[1], color[2], color[3]
    DrawPoly(x-20, y, z-20, x+20, y, z-20, x+20, y, z+20, r, g, b, 255)
    DrawPoly(x-20, y, z-20, x+20, y, z+20, x-20, y, z+20, r, g, b, 255)
    DrawPoly(x+20, y, z+20, x+20, y, z-20, x-20, y, z-20, r, g, b, 255)
    DrawPoly(x-20, y, z+20, x+20, y, z+20, x-20, y, z-20, r, g, b, 255)
    DrawLightWithRange(x, current.y + 2.0 * side, z + 1.0, 255, 255, 255, 8.0, 3.0)
end

local function clearBody(ped)
    ClearAllPedProps(ped)
    -- Empty non-head drawable slots are supported; an empty head is rejected by
    -- current Cfx. Head visibility is handled by reset flag 166 each frame.
    for slot = 1, 11 do SetPedComponentVariation(ped, slot, -1, 0, 0) end
end

local function capturePair(current, calibration)
    current.capture = (current.capture or 0) + 1
    current.calibrating, current.processed = calibration, false
    local capture = current.capture
    local images = {}
    for pass = 1, 4 do
        -- First measure the actual empty stage at this exact camera, then expose
        -- only the isolated garment. This accounts for spatial shading/vignetting.
        SetEntityVisible(current.ped, pass > 2, false)
        current.backdrop = (pass - 1) % 2 + 1
        local readyAt = GetGameTimer() + 150
        waitFor(current, function() return GetGameTimer() >= readyAt end, 5000)
        if job ~= current then error('Capture cancelled.') end
        local result
        exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(data)
            if job == current and current.capture == capture then result = data end
        end)
        waitFor(current, function() return result ~= nil end, 20000)
        if type(result) ~= 'string' or not result:find('^data:image/png;base64,') then error('PNG capture failed.') end
        images[pass] = result
    end
    SendNUIMessage({ action = prefix .. 'process', v = 3, id = current.id, step = current.step,
        capture = capture, calibration = calibration, images = images,
        context = ('%s, item %d, camera Z %.1f, stage Z %.1f'):format(
            calibration and 'body check' or 'garment', current.step, current.frameZ or current.z, current.z) })
    waitFor(current, function() return calibration and current.calibrated or (not calibration and current.saved) end, 60000)
end

local function generate(current)
    for _, gender in ipairs({ 'male', 'female' }) do
        local model = joaat(gender == 'male' and 'mp_m_freemode_01' or 'mp_f_freemode_01')
        current.model = model
        RequestModel(model)
        waitFor(current, function() return HasModelLoaded(model) end, 15000)
        current.ped = CreatePed(4, model, current.x, current.y, current.z, 0.0, false, false)
        if current.ped == 0 then error('Could not create the local mannequin.') end
        SetEntityCollision(current.ped, false, false)
        FreezeEntityPosition(current.ped, true)
        SetEntityInvincible(current.ped, true)
        SetBlockingOfNonTemporaryEvents(current.ped, true)
        SetPedCanPlayAmbientAnims(current.ped, false)
        SetPedCanPlayAmbientBaseAnims(current.ped, false)
        SetEntityLodDist(current.ped, 500)
        -- Same modest three-quarter view as a clothing product photo.
        SetEntityHeading(current.ped, 20.0)
        current.calibrated = false
        for _, kind in ipairs({ 'component', 'prop' }) do
            for _, slot in ipairs(slots[kind]) do
                local count = kind == 'component' and GetNumberOfPedDrawableVariations(current.ped, slot)
                    or GetNumberOfPedPropDrawableVariations(current.ped, slot)
                for drawable = 0, count - 1 do
                    -- Sample covers a top, trousers, shoes and hat for each body.
                    local sample = drawable == 0 and ((kind == 'component' and (slot == 11 or slot == 4 or slot == 6)) or (kind == 'prop' and slot == 0))
                    if current.mode ~= 'sample' or sample then
                        local item = identity(current.ped, gender, kind, slot, drawable)
                        if not Policy.key(item) then error('Collection natives returned an invalid identity; update the FiveM artifact.') end
                        current.step = current.step + 1
                        current.prepared, current.saved, current.processed = false, false, false
                        TriggerServerEvent(prefix .. 'prepare', current.id, current.step, item)
                        waitFor(current, function() return current.prepared end, 15000)
                        if not current.skip then
                            clearBody(current.ped)
                            if not current.calibrated then
                                frame(current, 'component', 11)
                                local ready = GetGameTimer() + settleMs
                                waitFor(current, function() return GetGameTimer() >= ready end, 10000)
                                -- Fail before saving anything if this build cannot hide the body.
                                capturePair(current, true)
                            end
                            if kind == 'component' then
                                SetPedCollectionPreloadVariationData(current.ped, slot, item.collection, item.drawable, 0)
                                waitFor(current, function() return HasPedPreloadVariationDataFinished(current.ped) end, 15000)
                                SetPedCollectionComponentVariation(current.ped, slot, item.collection, item.drawable, 0, 0)
                                ReleasePedPreloadVariationData(current.ped)
                            else
                                SetPedCollectionPreloadPropData(current.ped, slot, item.collection, item.drawable, 0)
                                waitFor(current, function() return HasPedPreloadPropDataFinished(current.ped) end, 15000)
                                SetPedCollectionPropIndex(current.ped, slot, item.collection, item.drawable, 0, true)
                                ReleasePedPreloadPropData(current.ped)
                            end
                            frame(current, kind, slot)
                            local readyAt = GetGameTimer() + settleMs
                            waitFor(current, function() return GetGameTimer() >= readyAt end, 10000)
                            capturePair(current, false)
                        end
                        if current.step % 100 == 0 then message(('Processed %d drawables. /cortex_catalog cancel stops safely.'):format(current.step)) end
                        -- Avoid a burst when most entries are cached.
                        Wait(75)
                    end
                end
            end
        end
        DeleteEntity(current.ped)
        current.ped = nil
        SetModelAsNoLongerNeeded(model)
        current.model = nil
    end
    TriggerServerEvent(prefix .. 'done', current.id)
    waitFor(current, function() return false end, 15000)
end

RegisterNetEvent(prefix .. 'start', function(id, mode)
    if job then return end
    local player = PlayerPedId()
    Admin.setOpen(false)
    local rendering = GetRenderingCam()
    if IsEntityDead(player) or IsPedInAnyVehicle(player, false) or (rendering ~= -1 and rendering ~= 0) then
        TriggerServerEvent(prefix .. 'abort', id)
        return message('Stand on foot and close other cameras before capture.')
    end
    if GetResourceState('screenshot-basic') ~= 'started' then
        TriggerServerEvent(prefix .. 'abort', id)
        return message('screenshot-basic must be started.')
    end
    local pos = GetEntityCoords(player)
    job = { id = id, mode = mode, step = 0, player = player, frozen = IsEntityPositionFrozen(player),
        x = pos.x, y = pos.y, z = pos.z + 1000.0 }
    local current = job
    FreezeEntityPosition(player, true)
    current.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    if not current.cam or current.cam == 0 then return abort('Could not create capture camera.') end
    SetCamCoord(current.cam, current.x, current.y + 3.0, current.z)
    PointCamAtCoord(current.cam, current.x, current.y, current.z)
    SetCamFov(current.cam, 30.0)
    SetFocusPosAndVel(current.x, current.y, current.z, 0.0, 0.0, 0.0)
    SetCamActive(current.cam, true)
    RenderScriptCams(true, false, 0, true, false)
    message('Capturing both freemode wardrobes. Your character stays in place. Cancel with /cortex_catalog cancel or Backspace.')
    CreateThread(function()
        Wait(0)
        while job == current do
            if PlayerPedId() ~= player or IsEntityDead(player) or Admin.state.open
                or GetResourceState('screenshot-basic') ~= 'started'
                or (GetRenderingCam() ~= current.cam and GetRenderingCam() ~= -1 and GetRenderingCam() ~= 0) then
                abort('Capture context changed. Run build to resume.'); break
            end
            DisableAllControlActions(0)
            if IsDisabledControlJustPressed(0, 177) then abort('Cancelled; saved previews retained.'); break end
            HideHudAndRadarThisFrame()
            if current.ped and DoesEntityExist(current.ped) then SetPedResetFlag(current.ped, 166, true) end
            drawBackdrop(current)
            Wait(0)
        end
    end)
    CreateThread(function()
        local ok, err = xpcall(function() generate(current) end, debug.traceback)
        if not ok and job == current then abort(tostring(err)) end
    end)
end)

RegisterNetEvent(prefix .. 'stop', function(id, reason)
    if job and job.id == id then cleanup(reason) end
end)
RegisterNetEvent(prefix .. 'prepared', function(id, step, skip)
    if job and job.id == id and job.step == step then job.prepared, job.skip = true, skip end
end)
RegisterNetEvent(prefix .. 'saved', function(id, step)
    if job and job.id == id and job.step == step then job.saved = true end
end)
RegisterNUICallback(prefix .. 'processed', function(data, cb)
    if type(data) ~= 'table' or not job or data.id ~= job.id or data.step ~= job.step
        or data.capture ~= job.capture or job.processed then
        return cb({ ok = false, error = 'stale_capture' })
    end
    if type(data.error) == 'string' then
        cb({ ok = false, error = 'capture_failed' }); return abort(data.error:sub(1, 240))
    end
    if job.calibrating then
        if data.empty ~= true then
            cb({ ok = false, error = 'body_visible' })
            return abort('Body isolation check failed: skin, clothing or another overlay is still visible. No thumbnail was saved.')
        end
        job.calibrated, job.processed = true, true
        return cb({ ok = true })
    end
    local stored = data.empty == true and Policy.emptyMarker or data.image
    if not Policy.validStored(stored) then
        cb({ ok = false, error = 'invalid_thumbnail' }); return abort('Cutout encoding failed or exceeded the size limit.')
    end
    job.processed = true
    TriggerLatentServerEvent(prefix .. 'save', 128000, job.id, job.step, stored)
    cb({ ok = true })
end)

RegisterNUICallback(prefix .. 'photo', function(data, cb)
    if not Admin.state.open or Admin.state.allowed['player.setAppearance'] ~= true then return cb({ ok = false, error = 'forbidden' }) end
    if type(data) ~= 'table' or (data.kind ~= 'component' and data.kind ~= 'prop')
        or type(data.slot) ~= 'number' or data.slot % 1 ~= 0 or data.slot < 0 or data.slot > (data.kind == 'component' and 11 or 7)
        or type(data.drawable) ~= 'number' or data.drawable % 1 ~= 0 or data.drawable < 0 or data.drawable > 65535 then
        return cb({ ok = false, error = 'invalid_item' })
    end
    local pending = 0
    for _ in pairs(reads) do pending = pending + 1 end
    if pending >= 32 then return cb({ ok = false, error = 'busy' }) end
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    if model ~= joaat('mp_m_freemode_01') and model ~= joaat('mp_f_freemode_01') then return cb({ ok = false, error = 'not_freemode' }) end
    local count = data.kind == 'component' and GetNumberOfPedDrawableVariations(ped, data.slot) or GetNumberOfPedPropDrawableVariations(ped, data.slot)
    if data.drawable >= count then return cb({ ok = false, error = 'invalid_drawable' }) end
    local ok, item = pcall(identity, ped, model == joaat('mp_f_freemode_01') and 'female' or 'male', data.kind, data.slot, data.drawable)
    if not ok or not Policy.key(item) then return cb({ ok = false, error = 'collection_unavailable' }) end
    requestId = requestId % 2147483647 + 1
    local request = requestId
    reads[request] = cb
    TriggerServerEvent(prefix .. 'read', request, item)
    SetTimeout(20000, function()
        if reads[request] then local callback = reads[request]; reads[request] = nil; callback({ ok = false, error = 'timeout' }) end
    end)
end)
RegisterNetEvent(prefix .. 'photo', function(request, result)
    if reads[request] then local cb = reads[request]; reads[request] = nil; cb(result) end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanup('Resource stopped.')
    for request, cb in pairs(reads) do reads[request] = nil; cb({ ok = false, error = 'resource_stopped' }) end
end)

message('Client ready (cutout-4). F8: cortex_catalog sample (no slash). Measured-backdrop capture is enabled.')
