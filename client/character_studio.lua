-- The admin menu remains the sole NUI focus owner. This module owns only
-- its camera, streaming focus and temporary ped detail/freeze state.
local Admin = EsAdmin
local studio = { active = false, generation = 0, cam = nil, ped = nil, wasFrozen = false, angle = 0.0, zoom = 1.0, frame = 'body', lodBefore = nil, lodApplied = nil }
local FOV = 36.0
Admin.isCharacterStudioActive = function() return studio.active end
-- GetRenderingCam may have no published handle during camera activation or
-- teardown. Only a concrete different handle establishes another camera owner.
local function otherCameraOwnsRendering(rendering)
    return rendering ~= nil and rendering ~= -1 and rendering ~= 0 and rendering ~= studio.cam
end
local frames = {
    body = { center = 0.5, span = 1.0 },
    face = { center = 0.93, span = 0.32 },
    torso = { center = 0.70, span = 0.58 },
    legs = { center = 0.27, span = 0.57 },
}

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end

local function distance(a, b)
    if not a or not b or not finite(a.x) or not finite(a.y) or not finite(a.z)
        or not finite(b.x) or not finite(b.y) or not finite(b.z) then return math.huge end
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end

-- Bounded, local evidence for the reported world-LOD regression. No network
-- traffic or per-frame logging. The F8 command prints entry and settled samples.
local samples = {}
local function diagnosticSample(phase)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local rendered = GetFinalRenderedCamCoord()
    local cam = studio.cam and DoesCamExist(studio.cam) and GetCamCoord(studio.cam) or nil
    local function xyz(v) return v and { x = v.x, y = v.y, z = v.z } or nil end
    local function measured(a, b) local d = distance(a, b); return finite(d) and d or 'invalid' end
    return {
        revision = 'studio-lod-diag-2', phase = phase, ms = GetGameTimer(), ped = ped,
        active = studio.active, renderRequested = studio.renderRequested == true,
        camActive = studio.cam and DoesCamExist(studio.cam) and IsCamActive(studio.cam) or false,
        player = xyz(pos), playerMoved = studio.entryPosition and measured(pos, studio.entryPosition) or 0,
        camera = xyz(cam), rendered = xyz(rendered), renderedRotation = xyz(GetFinalRenderedCamRot(2)),
        intendedCamera = xyz(studio.intendedCamera),
        cameraWriteError = cam and studio.intendedCamera and measured(cam, studio.intendedCamera),
        cameraDistance = cam and measured(cam, pos), renderedDistance = measured(rendered, pos),
        cameraMismatch = cam and measured(rendered, cam), renderingCam = GetRenderingCam(), studioCam = studio.cam,
        fov = GetFinalRenderedCamFov(), playerIsFocus = IsEntityFocus(ped), focusMode = studio.focusMode or 'player',
        boneFallback = studio.boneFallback or false, lod = GetEntityLodDist(ped),
        streamingRequests = GetNumberOfStreamingRequests(),
    }
end

local function retainSample(phase)
    samples[#samples + 1] = diagnosticSample(phase)
end

local function releasePed()
    if studio.ped and DoesEntityExist(studio.ped) then
        if not studio.wasFrozen then FreezeEntityPosition(studio.ped, false) end
        if studio.lodApplied and GetEntityLodDist(studio.ped) == studio.lodApplied then
            SetEntityLodDist(studio.ped, studio.lodBefore)
        end
    end
    studio.ped = nil
    studio.anchor = nil
    studio.lodBefore, studio.lodApplied = nil, nil
end

Admin.closeCharacterStudio = function(reason)
    local wasActive = studio.active
    if wasActive then retainSample('closing-' .. (reason or 'requested')) end
    studio.active = false
    studio.generation = studio.generation + 1
    local rendering = GetRenderingCam()
    if studio.ped and not otherCameraOwnsRendering(rendering)
        and (studio.focusMode == 'camera' or IsEntityFocus(studio.ped)) then ClearFocus() end
    -- RenderScriptCams is a separate global mode, not the lifetime of a camera
    -- handle. Release our request even if the handle is still -1 or was lost.
    -- Otherwise DestroyCam can leave the renderer with no camera at all.
    if studio.renderRequested and not otherCameraOwnsRendering(rendering) then
        RenderScriptCams(false, false, 0, true, false)
    end
    studio.renderRequested = false
    if studio.cam and DoesCamExist(studio.cam) then
        SetCamActive(studio.cam, false)
        DestroyCam(studio.cam, false)
    end
    studio.cam = nil
    studio.intendedCamera = nil
    releasePed()
    studio.focusMode = 'player'
    if wasActive then SendNUIMessage({ action = 'cortex-admin:studioClosed' }) end
end

local function updateCamera(force)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
        Admin.closeCharacterStudio()
        return false
    end
    if studio.ped ~= ped then
        releasePed()
        studio.ped = ped
        studio.wasFrozen = IsEntityPositionFrozen(ped)
        FreezeEntityPosition(ped, true)
        studio.lodBefore = GetEntityLodDist(ped)
        studio.lodApplied = math.max(studio.lodBefore, 512)
        SetEntityLodDist(ped, studio.lodApplied)
        SetFocusEntity(ped)
        -- Refresh the skeleton once after taking the close-up camera; do not
        -- run the expensive AI/animation update every frame.
        ForcePedAiAndAnimationUpdate(ped, false, false)
    end
    local pos = GetEntityCoords(ped)
    if not finite(pos.x) or not finite(pos.y) or not finite(pos.z) then
        Admin.closeCharacterStudio()
        return false
    end
    local anchorChanged = false
    if not studio.anchor then
        -- Measure this ped once. Breathing, weight shifts, IK and idle turns
        -- must not become camera motion at the 100 ms lifecycle polling rate.
        local head = GetPedBoneCoords(ped, 0x796E, 0.0, 0.0, 0.0)
        local leftFoot = GetPedBoneCoords(ped, 0x3779, 0.0, 0.0, 0.0)
        local rightFoot = GetPedBoneCoords(ped, 0xCC4D, 0.0, 0.0, 0.0)
        local bottom = math.min(leftFoot.z, rightFoot.z) - 0.08
        local height = math.max(0.6, head.z + 0.18 - bottom)
        studio.boneFallback = distance(head, pos) > 2.5 or distance(leftFoot, pos) > 2.5
            or distance(rightFoot, pos) > 2.5 or not finite(height) or height > 2.5
        if studio.boneFallback then bottom, height = pos.z - 1.0, 2.0 end
        studio.anchor = {
            x = pos.x, y = pos.y, z = pos.z, heading = GetEntityHeading(ped),
            bottomOffset = bottom - pos.z, height = height,
        }
        anchorChanged = true
    end
    local anchor = studio.anchor
    -- Preserve the shot through small root motion. Follow a real external
    -- relocation without remeasuring animated bones or changing orbit heading.
    if distance(pos, anchor) > 2.0 then
        anchor.x, anchor.y, anchor.z = pos.x, pos.y, pos.z
        anchorChanged = true
    end
    if not force and not anchorChanged then
        if studio.focusMode == 'camera' then
            local cam = studio.intendedCamera
            SetFocusPosAndVel(cam.x, cam.y, cam.z, 0.0, 0.0, 0.0)
        end
        return true
    end
    local frame = frames[studio.frame]
    local angle = math.rad(anchor.heading + studio.angle)
    local targetZ = anchor.z + anchor.bottomOffset + anchor.height * frame.center
    -- Frame actual skeletal bounds with 20% vertical breathing room. World
    -- coordinates avoid entity-relative camera offsets changing with the pose.
    local distance = anchor.height * frame.span / (1.6 * math.tan(math.rad(FOV / 2))) * studio.zoom
    local cameraX = anchor.x - math.sin(angle) * distance
    local cameraY = anchor.y + math.cos(angle) * distance
    studio.intendedCamera = { x = cameraX, y = cameraY, z = targetZ }
    SetCamCoord(studio.cam, cameraX, cameraY, targetZ)
    PointCamAtCoord(studio.cam, anchor.x - math.cos(angle) * distance * 0.07,
        anchor.y - math.sin(angle) * distance * 0.07, targetZ)
    if studio.focusMode == 'camera' then
        SetFocusPosAndVel(cameraX, cameraY, targetZ, 0.0, 0.0, 0.0)
    end
    return true
end

Admin.openCharacterStudio = function()
    if studio.active then return { ok = true } end
    if not Admin.state.open or Admin.state.allowed['player.setAppearance'] ~= true then
        return { ok = false, error = 'forbidden' }
    end
    local camera = GetRenderingCam()
    if camera and camera ~= -1 and camera ~= 0 then return { ok = false, error = 'camera_busy' } end
    studio.entryPosition = GetEntityCoords(PlayerPedId())
    studio.focusMode = 'player'
    samples = {}
    retainSample('before-open')
    -- Configure an inactive camera before it can become the rendering camera.
    studio.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    if not studio.cam or studio.cam == 0 or not DoesCamExist(studio.cam) then
        studio.cam = nil
        return { ok = false, error = 'camera_unavailable' }
    end
    studio.generation = studio.generation + 1
    local generation = studio.generation
    studio.active, studio.angle, studio.zoom, studio.frame = true, 0.0, 1.0, 'body'
    SetCamFov(studio.cam, FOV)
    if not updateCamera() then return { ok = false, error = 'stand_on_foot' } end
    SetCamActive(studio.cam, true)
    studio.renderRequested = true
    RenderScriptCams(true, false, 0, true, false)
    local openedAt, sampledOne, sampledThree = GetGameTimer(), false, false
    CreateThread(function()
        -- Let camera activation reach a render tick before inspecting ownership.
        Wait(0)
        while studio.active and studio.generation == generation do
            if not Admin.state.open or Admin.state.allowed['player.setAppearance'] ~= true then
                Admin.closeCharacterStudio('menu-or-permission')
                break
            end
            if otherCameraOwnsRendering(GetRenderingCam()) then
                Admin.closeCharacterStudio('camera-takeover')
                break
            end
            if not DoesCamExist(studio.cam) or not IsCamActive(studio.cam) then
                Admin.closeCharacterStudio('camera-lost')
                break
            end
            if not updateCamera() then break end
            local elapsed = GetGameTimer() - openedAt
            if elapsed >= 1000 and not sampledOne then retainSample('after-1s'); sampledOne = true end
            if elapsed >= 3000 and not sampledThree then retainSample('after-3s'); sampledThree = true end
            Wait(100)
        end
    end)
    return { ok = true }
end

RegisterCommand('cortex_studio_debug', function(_, args)
    if not Admin.state.open or Admin.state.allowed['player.setAppearance'] ~= true then return end
    local mode = args[1] or 'status'
    if mode ~= 'status' and mode ~= 'camera' and mode ~= 'player' then
        print('[cortex-studio-debug] Usage: cortex_studio_debug [status|camera|player]')
        return
    end
    for _, sample in ipairs(samples) do print('[cortex-studio-debug] ' .. json.encode(sample)) end
    print('[cortex-studio-debug] ' .. json.encode(diagnosticSample('command-before-' .. mode)))
    if mode ~= 'status' and studio.active and not otherCameraOwnsRendering(GetRenderingCam())
        and DoesCamExist(studio.cam) and IsCamActive(studio.cam) then
        -- Explicit A/B probe: change only the streaming focus, leaving the ped,
        -- outfit, camera transform and FOV untouched. Close restores defaults.
        ClearFocus()
        studio.focusMode = mode
        if mode == 'player' then SetFocusEntity(PlayerPedId()) end
        updateCamera(true)
        print('[cortex-studio-debug] focus changed to ' .. mode .. '; wait 3 seconds, then run cortex_studio_debug')
    elseif mode ~= 'status' then
        print('[cortex-studio-debug] Focus unchanged: the studio camera is not active or another camera owns rendering.')
    end
end, false)

Admin.moveCharacterStudioCamera = function(data)
    if not studio.active or type(data) ~= 'table' then return { ok = false, error = 'studio_closed' } end
    if frames[data.frame] then studio.frame = data.frame end
    if data.rotate == -1 or data.rotate == 1 then studio.angle = (studio.angle + data.rotate * 20) % 360 end
    if data.zoom == -1 or data.zoom == 1 then studio.zoom = math.max(0.65, math.min(1.4, studio.zoom + data.zoom * 0.1)) end
    if data.reset == true then studio.angle, studio.zoom = 0.0, 1.0 end
    return { ok = updateCamera(true) }
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Admin.closeCharacterStudio() end
end)
