local activeSession = nil
local textVisible = false
local textContent = nil
local actionBusy = false
local lastInteractAt = 0

local worksites = {}
local worksiteById = {}
local blips = {}

---@return number
local function distPrompt()
    local d = Config.Distances or {}
    return tonumber(d.InteractionPrompt) or tonumber(Config.Interaction.Radius) or 3.0
end

---@return number
local function distWorkVehicle()
    local d = Config.Distances or {}
    return tonumber(d.WorkNearVehicle) or tonumber(Config.Scrapping.WorkRadiusFromVehicle) or 4.0
end

---@return number
local function distPartInteract()
    local d = Config.Distances or {}
    return tonumber(d.PartInteract) or tonumber(Config.Scrapping.PartInteractDistance) or 2.0
end

---@return number
local function distPartMarkerDraw()
    local d = Config.Distances or {}
    return tonumber(d.PartMarkerDrawRange) or 8.0
end

---@return number
local function distVehicleMarkerDraw()
    local d = Config.Distances or {}
    return tonumber(d.VehicleMarkerDrawRange) or 12.0
end

---@return number
local function distMarkerDraw()
    local d = Config.Distances or {}
    local v = tonumber(d.MarkerDrawRange)
    if v == nil or v <= 0.0 then
        return 99999.0
    end
    return v
end

local function getProfileMode()
    local profile = Config.Profile or {}
    local mode = type(profile.Mode) == 'string' and string.lower(profile.Mode) or 'pro'
    if mode == 'off' then
        return 'off'
    end
    return 'pro'
end

local function notifyConfig()
    return Config.Notify or (Config.UI and Config.UI.Notify) or {}
end

local function progressConfig()
    return Config.Progress or (Config.UI and Config.UI.Progress) or {}
end

local function finalVehicleStepConfig()
    local scrappingCfg = Config.Scrapping or {}
    return scrappingCfg.FinalVehicleStep or {}
end

local function debugLog(message)
    if Config.Debug then
        print(('[DW_CarScrapping][client] %s'):format(message))
    end
end

local function normalizeAllowedJobs(allowedJobs)
    if type(allowedJobs) ~= 'table' then
        return nil
    end

    local map = {}
    local hasAny = false
    for key, value in pairs(allowedJobs) do
        if type(key) == 'string' and value == true then
            map[key] = true
            hasAny = true
        elseif type(value) == 'string' then
            map[value] = true
            hasAny = true
        end
    end

    if not hasAny then
        return nil
    end

    return map
end

local function buildWorksites()
    worksites = {}
    worksiteById = {}

    if type(Config.Worksites) == 'table' and #Config.Worksites > 0 then
        for i = 1, #Config.Worksites do
            local site = Config.Worksites[i]
            if site and site.StartPoint and site.DropPoint then
                local id = site.id or ('worksite_%s'):format(i)
                local normalized = {
                    id = id,
                    label = site.label or id,
                    StartPoint = site.StartPoint,
                    DropPoint = site.DropPoint,
                    allowedJobs = normalizeAllowedJobs(site.allowedJobs)
                }
                worksites[#worksites + 1] = normalized
                worksiteById[id] = normalized
            end
        end
    end

    if #worksites == 0 then
        local points = Config.Points or {}
        if points.StartPoint and points.DropPoint then
            local fallback = {
                id = 'default',
                label = 'Default',
                StartPoint = points.StartPoint,
                DropPoint = points.DropPoint,
                allowedJobs = nil
            }
            worksites[#worksites + 1] = fallback
            worksiteById[fallback.id] = fallback
        end
    end
end

local function createBlips()
    for i = 1, #blips do
        if DoesBlipExist(blips[i]) then
            RemoveBlip(blips[i])
        end
    end
    blips = {}

    local blipCfg = (Config.Points and Config.Points.Blip) or {}
    if blipCfg.enabled == false then
        return
    end

    for i = 1, #worksites do
        local site = worksites[i]
        local sprite = blipCfg.sprite or 365
        local color = blipCfg.color or 3
        local scale = blipCfg.scale or 0.8
        local shortRange = blipCfg.shortRange ~= false

        local startBlip = AddBlipForCoord(site.StartPoint.x, site.StartPoint.y, site.StartPoint.z)
        SetBlipSprite(startBlip, sprite)
        SetBlipColour(startBlip, color)
        SetBlipScale(startBlip, scale)
        SetBlipAsShortRange(startBlip, shortRange)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(("Scrapping Start (%s)"):format(site.label))
        EndTextCommandSetBlipName(startBlip)
        blips[#blips + 1] = startBlip

        local dropBlip = AddBlipForCoord(site.DropPoint.x, site.DropPoint.y, site.DropPoint.z)
        SetBlipSprite(dropBlip, sprite)
        SetBlipColour(dropBlip, color)
        SetBlipScale(dropBlip, scale)
        SetBlipAsShortRange(dropBlip, shortRange)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(("Scrapping Drop (%s)"):format(site.label))
        EndTextCommandSetBlipName(dropBlip)
        blips[#blips + 1] = dropBlip
    end
end

local function notify(description, notificationType)
    local cfg = notifyConfig()
    local system = cfg.system or 'ox_lib'
    local nType = notificationType or 'inform'

    if system == 'esx' then
        TriggerEvent('esx:showNotification', description)
        return
    end

    if system == 'custom' and cfg.customEvent then
        TriggerEvent(cfg.customEvent, description, nType)
        return
    end

    lib.notify({
        title = cfg.title or 'Car Scrapping',
        description = description,
        type = nType,
        duration = cfg.duration or 4000,
        position = cfg.position or 'top-right',
        icon = cfg.icon
    })
end

local function showPrompt(text)
    if not textVisible or textContent ~= text then
        lib.showTextUI(text)
        textVisible = true
        textContent = text
    end
end

local function hidePrompt()
    if textVisible then
        lib.hideTextUI()
        textVisible = false
        textContent = nil
    end
end

local function interactPressed()
    local pressed = IsControlPressed(0, Config.Interaction.Key)
        or IsDisabledControlPressed(0, Config.Interaction.Key)

    if not pressed then
        return false
    end

    local now = GetGameTimer()
    if now - lastInteractAt < 350 then
        return false
    end

    lastInteractAt = now
    return true
end

local function getVehicleNetId(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId ~= 0 then
        return netId
    end

    NetworkRegisterEntityAsNetworked(vehicle)
    netId = NetworkGetNetworkIdFromEntity(vehicle)
    return netId
end

local function drawMarkerAtPoint(coords)
    local markerCfg = (Config.Points and Config.Points.Marker) or {}
    if markerCfg.enabled == false then
        return
    end

    local scale = markerCfg.scale or vec3(1.2, 1.2, 0.35)
    local color = markerCfg.color or { r = 0, g = 170, b = 255, a = 130 }
    DrawMarker(
        markerCfg.type or 1,
        coords.x, coords.y, coords.z - 0.95,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        scale.x or 1.2, scale.y or 1.2, scale.z or 0.35,
        color.r or 0, color.g or 170, color.b or 255, color.a or 130,
        markerCfg.bobUpAndDown == true,
        true,
        2,
        markerCfg.rotate == true,
        nil,
        nil,
        false
    )
end

local function drawPartMarkerAtPoint(coords)
    local guide = (Config.Points and Config.Points.PartGuide) or {}
    local markerCfg = guide.marker or {}
    if guide.enabled == false or markerCfg.enabled == false then
        return
    end

    local scale = markerCfg.scale or vec3(0.22, 0.22, 0.22)
    local color = markerCfg.color or { r = 255, g = 180, b = 0, a = 180 }
    local zOffset = markerCfg.zOffset or 0.05
    DrawMarker(
        markerCfg.type or 2,
        coords.x, coords.y, coords.z + zOffset,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        scale.x or 0.22, scale.y or 0.22, scale.z or 0.22,
        color.r or 255, color.g or 180, color.b or 0, color.a or 180,
        false,
        true,
        2,
        true,
        nil,
        nil,
        false
    )
end

local function getOffsetPartMarkerCoords(vehicle, partCoords, playerCoords)
    local guide = (Config.Points and Config.Points.PartGuide) or {}
    local markerCfg = guide.marker or {}
    local offset = tonumber(markerCfg.forwardOffset) or 0.0
    if offset <= 0.0 or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return partCoords
    end

    if playerCoords then
        local dxp = playerCoords.x - partCoords.x
        local dyp = playerCoords.y - partCoords.y
        local horizontalLen = math.sqrt((dxp * dxp) + (dyp * dyp))
        if horizontalLen > 0.0001 then
            local nx = dxp / horizontalLen
            local ny = dyp / horizontalLen
            return vec3(partCoords.x + (nx * offset), partCoords.y + (ny * offset), partCoords.z)
        end
    end

    local vehicleCoords = GetEntityCoords(vehicle)
    local dx = partCoords.x - vehicleCoords.x
    local dy = partCoords.y - vehicleCoords.y
    local dz = partCoords.z - vehicleCoords.z
    local len = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

    if len <= 0.0001 then
        local forward = GetEntityForwardVector(vehicle)
        return vec3(partCoords.x + (forward.x * offset), partCoords.y + (forward.y * offset), partCoords.z)
    end

    local nx = dx / len
    local ny = dy / len
    local nz = dz / len
    return vec3(partCoords.x + (nx * offset), partCoords.y + (ny * offset), partCoords.z + (nz * offset * 0.1))
end

local function drawStatusLine(x, y, scale, text)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 230)
    SetTextDropshadow(1, 0, 0, 0, 255)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function drawChecklist()
    if not activeSession then
        return
    end

    local x = 0.015
    local y = 0.27
    local row = 0
    local header = Config.Locale.ChecklistTitle or "SEZNAM ROZBORKY"
    drawStatusLine(x, y + (row * 0.028), 0.40, ("~b~%s~s~"):format(header))
    row = row + 1

    for i = 1, #activeSession.tasks do
        local task = activeSession.tasks[i]
        local prefix = i == activeSession.currentTaskIndex and "~y~" or "~w~"
        local done = task.doneCount or 0
        local total = task.totalCount or 0
        drawStatusLine(x, y + (row * 0.028), 0.33, ("%s%d. %s  %d/%d~s~"):format(prefix, i, task.label, done, total))
        row = row + 1
    end

    local finalCfg = finalVehicleStepConfig()
    if finalCfg.enabled ~= false then
        local finalIndex = #activeSession.tasks + 1
        local finalDone = activeSession.finalVehicleDone == true and 1 or 0
        local noTasksLeft = (activeSession.currentTaskIndex or 1) > #activeSession.tasks
        local isFinalActive = (noTasksLeft and not activeSession.carryingPart and finalDone == 0)
        local finalPrefix = isFinalActive and "~y~" or "~w~"
        local finalLabel = Config.Locale.FinalStepLabel or 'Rozebrat zbytek vozidla'
        drawStatusLine(x, y + (row * 0.028), 0.33, ("%s%d. %s  %d/1~s~"):format(finalPrefix, finalIndex, finalLabel, finalDone))
        row = row + 1
    end

    if activeSession.carryingPart then
        local part = activeSession.carryingPart
        drawStatusLine(x, y + (row * 0.028), 0.32, ("~g~Neses dil: %s~s~"):format(part.label))
    end
end

local function getNearestStartWorksite(coords, radius)
    local nearest = nil
    local nearestDist = nil
    for i = 1, #worksites do
        local site = worksites[i]
        local dist = #(coords - site.StartPoint)
        if dist <= radius and (nearestDist == nil or dist < nearestDist) then
            nearest = site
            nearestDist = dist
        end
    end
    return nearest, nearestDist
end

local function getEmoteActionConfig(actionName, partType)
    local emotes = Config.Emotes or {}
    local byPart = emotes.byPart or {}
    if partType and byPart[partType] and byPart[partType][actionName] then
        return byPart[partType][actionName]
    end

    return emotes[actionName]
end

local function startEmote(actionName, partType)
    local emotes = Config.Emotes or {}
    local provider = emotes.provider or 'none'
    local actionCfg = getEmoteActionConfig(actionName, partType)
    if not actionCfg or not actionCfg.emote then
        return
    end

    if provider == 'rpemotes' then
        local scriptName = emotes.scriptName or 'rpemotes-reborn'
        local ok, err = pcall(function()
            exports[scriptName]:EmoteCommandStart(actionCfg.emote)
        end)
        if not ok then
            debugLog(('startEmote failed (%s): %s'):format(actionName, tostring(err)))
        end
    elseif provider == 'custom' and emotes.customStartEvent then
        TriggerEvent(emotes.customStartEvent, actionName, actionCfg.emote, partType)
    end
end

local function stopEmote()
    local emotes = Config.Emotes or {}
    if emotes.stopOnActionEnd == false then
        return
    end

    local provider = emotes.provider or 'none'
    if provider == 'rpemotes' then
        local scriptName = emotes.scriptName or 'rpemotes-reborn'
        pcall(function()
            exports[scriptName]:EmoteCancel()
        end)
    elseif provider == 'custom' and emotes.customStopEvent then
        TriggerEvent(emotes.customStopEvent)
    end
end

local function canShowStartPromptForPed(ped)
    if not Config.Interaction.ShowStartPromptOnlyWhenDriver then
        return true
    end

    if not IsPedInAnyVehicle(ped, false) then
        return false
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    return GetPedInVehicleSeat(vehicle, -1) == ped
end

local function buildProgressData(label, durationMs, canCancel)
    local cfg = progressConfig()
    local animConfig = cfg.anim or {}

    local data = {
        duration = durationMs,
        label = label,
        useWhileDead = cfg.useWhileDead == true,
        canCancel = canCancel == true,
        disable = cfg.disable or {
            move = true,
            car = true,
            combat = true
        }
    }

    if cfg.useAnim == true then
        if animConfig.type == 'dict' then
            data.anim = {
                dict = animConfig.dict or 'amb@world_human_welding@male@base',
                clip = animConfig.clip or 'base',
                flag = animConfig.flag or 49
            }
        elseif animConfig.type == 'scenario' and animConfig.scenario then
            data.anim = {
                scenario = animConfig.scenario
            }
        end
    end

    return data
end

local function runProgress(label, durationMs, canCancel)
    local progressData = buildProgressData(label, durationMs, canCancel)
    local progressType = progressConfig().type or 'bar'
    if progressType == 'circle' then
        return lib.progressCircle(progressData)
    end

    return lib.progressBar(progressData)
end

local function getWheelIndices()
    return { 0, 1, 4, 5 }
end

local function getDoorIndices(vehicle)
    local indices = {}
    for i = 0, 3 do
        if DoesVehicleHaveDoor(vehicle, i) then
            indices[#indices + 1] = i
        end
    end
    return indices
end

local function resolveTaskCount(taskCfg, vehicle)
    if taskCfg.count then
        return taskCfg.count
    end

    if taskCfg.countMode == 'wheels' then
        local wheelCount = GetVehicleNumberOfWheels(vehicle)
        if not wheelCount or wheelCount <= 0 then
            wheelCount = 4
        end
        return math.max(1, math.min(4, wheelCount))
    end

    if taskCfg.countMode == 'doors' then
        local doors = getDoorIndices(vehicle)
        if #doors > 0 then
            return #doors
        end
        return 4
    end

    return 1
end

local function buildTaskParts(taskId, count, vehicle)
    local parts = {}
    if taskId == 'wheels' then
        local wheels = getWheelIndices()
        local wheelBones = {
            [0] = 'wheel_lf',
            [1] = 'wheel_rf',
            [4] = 'wheel_lr',
            [5] = 'wheel_rr'
        }
        for i = 1, count do
            local wheelIndex = wheels[i] or wheels[#wheels]
            parts[#parts + 1] = {
                id = ('wheel_%s'):format(i),
                label = ('Kolo %s'):format(i),
                type = 'wheels',
                wheelIndex = wheelIndex,
                bone = wheelBones[wheelIndex]
            }
        end
        return parts
    end

    if taskId == 'doors' then
        local doorIndices = getDoorIndices(vehicle)
        local doorBones = {
            [0] = 'door_dside_f',
            [1] = 'door_pside_f',
            [2] = 'door_dside_r',
            [3] = 'door_pside_r'
        }
        for i = 1, count do
            local doorIndex = doorIndices[i] or (i - 1)
            parts[#parts + 1] = {
                id = ('door_%s'):format(i),
                label = ('Dvere %s'):format(i),
                type = 'doors',
                doorIndex = doorIndex,
                bone = doorBones[doorIndex]
            }
        end
        return parts
    end

    if taskId == 'hood' then
        return {
            { id = 'hood_1', label = 'Kapota', type = 'hood', bone = 'bonnet' }
        }
    end

    if taskId == 'trunk' then
        return {
            { id = 'trunk_1', label = 'Kufr', type = 'trunk', bone = 'boot' }
        }
    end

    if taskId == 'bumpers' then
        return {
            { id = 'bumper_front', label = 'Predni naraznik', type = 'bumpers', bone = 'bumper_f', bumperSide = 'front' },
            { id = 'bumper_rear', label = 'Zadni naraznik', type = 'bumpers', bone = 'bumper_r', bumperSide = 'rear' }
        }
    end

    if taskId == 'battery' then
        return {
            { id = 'battery_1', label = 'Baterie', type = 'battery', bone = 'bonnet' }
        }
    end

    if taskId == 'exhaust' then
        return {
            { id = 'exhaust_1', label = 'Vyfuk', type = 'exhaust', bone = 'exhaust' }
        }
    end

    if taskId == 'plate' then
        return {
            { id = 'plate_1', label = 'SPZ', type = 'plate', bone = 'platelight' }
        }
    end

    if taskId == 'engine' then
        return {
            { id = 'engine_1', label = 'Motor', type = 'engine', bone = 'engine' }
        }
    end

    for i = 1, count do
        parts[#parts + 1] = {
            id = ('%s_%s'):format(taskId, i),
            label = (Config.Locale and Config.Locale[taskId]) or taskId,
            type = taskId
        }
    end

    return parts
end

local function buildTaskList(vehicle)
    local taskList = {}
    local ordered = Config.TaskOrder or {}
    for i = 1, #ordered do
        local taskCfg = ordered[i]
        local count = math.max(1, tonumber(resolveTaskCount(taskCfg, vehicle)) or 1)
        taskList[#taskList + 1] = {
            id = taskCfg.id,
            label = taskCfg.label or taskCfg.id,
            totalCount = count,
            doneCount = 0,
            parts = buildTaskParts(taskCfg.id, count, vehicle)
        }
    end
    return taskList
end

local function getCurrentTask()
    if not activeSession then
        return nil
    end
    return activeSession.tasks[activeSession.currentTaskIndex]
end

local function getBoneWorldPosition(vehicle, boneName)
    if not boneName then
        return GetEntityCoords(vehicle)
    end

    local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
    if boneIndex and boneIndex ~= -1 then
        return GetWorldPositionOfEntityBone(vehicle, boneIndex)
    end

    return GetEntityCoords(vehicle)
end

local function getPartWorldPosition(vehicle, part, taskId)
    if taskId == 'plate' then
        local model = GetEntityModel(vehicle)
        local minDim, maxDim = GetModelDimensions(model)
        -- Dva body interakce pro SPZ: předek i zadek.
        -- Hráč může sundat kdekoliv z těchto dvou bodů, ale jde stále o jeden díl.
        local front = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (maxDim.y or 1.0) + 0.25, (minDim.z or 0.0) + 0.35)
        local rear = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (minDim.y or -1.0) - 0.25, (minDim.z or 0.0) + 0.35)
        local fromCoords = GetEntityCoords(PlayerPedId())
        if #(fromCoords - front) <= #(fromCoords - rear) then
            return front
        end
        return rear
    end

    if taskId == 'doors' and type(GetEntryPositionOfDoor) == 'function' and part.doorIndex ~= nil then
        local ok, doorPos = pcall(function()
            return GetEntryPositionOfDoor(vehicle, part.doorIndex)
        end)
        if ok and doorPos then
            return doorPos
        end
    end

    return getBoneWorldPosition(vehicle, part.bone)
end

local function findNearestUndetachedPart(task, vehicle, fromCoords)
    local nearestPart = nil
    local nearestDistance = nil

    if not task then
        return nil, nil
    end

    for i = 1, #task.parts do
        local part = task.parts[i]
        if not part.detached then
            local partCoords = getPartWorldPosition(vehicle, part, task.id)
            local dist = #(fromCoords - partCoords)
            if not nearestDistance or dist < nearestDistance then
                nearestDistance = dist
                nearestPart = part
            end
        end
    end

    return nearestPart, nearestDistance
end

local function isTaskFullyDelivered(task)
    if not task then
        return false
    end
    for i = 1, #task.parts do
        if not task.parts[i].delivered then
            return false
        end
    end
    return true
end

local function advanceTaskIfNeeded()
    local task = getCurrentTask()
    while task and isTaskFullyDelivered(task) do
        activeSession.currentTaskIndex = activeSession.currentTaskIndex + 1
        task = getCurrentTask()
    end
end

local function detachVehiclePart(vehicle, part, taskId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end

    if taskId == 'wheels' then
        if type(BreakOffVehicleWheel) == 'function' then
            pcall(function()
                BreakOffVehicleWheel(vehicle, part.wheelIndex or 0, true, true, false, false)
            end)
        end
        SetVehicleTyreBurst(vehicle, part.wheelIndex or 0, true, 1000.0)
        return
    end

    if taskId == 'doors' then
        SetVehicleDoorBroken(vehicle, part.doorIndex or 0, true)
        return
    end

    if taskId == 'hood' then
        SetVehicleDoorBroken(vehicle, 4, true)
        return
    end

    if taskId == 'trunk' then
        SetVehicleDoorBroken(vehicle, 5, true)
        return
    end

    if taskId == 'bumpers' then
        if type(SetVehicleBumper) == 'function' then
            if part.bumperSide == 'front' then
                pcall(function()
                    SetVehicleBumper(vehicle, false, true)
                end)
            elseif part.bumperSide == 'rear' then
                pcall(function()
                    SetVehicleBumper(vehicle, true, true)
                end)
            end
        end
        local health = GetVehicleBodyHealth(vehicle)
        SetVehicleBodyHealth(vehicle, math.max(0.0, health - 120.0))
        return
    end

    if taskId == 'plate' then
        SetVehicleNumberPlateText(vehicle, '')
        return
    end

    if taskId == 'engine' then
        SetVehicleEngineHealth(vehicle, -4000.0)
        return
    end
end

local function lockVehicleForScrap(vehicle)
    SetVehicleDoorsLocked(vehicle, 2)
    SetVehicleDoorsLockedForAllPlayers(vehicle, true)
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleUndriveable(vehicle, true)
    FreezeEntityPosition(vehicle, true)
    Entity(vehicle).state:set('dw_scrapping_workflow_active', true, true)
end

local function unlockVehicle(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    FreezeEntityPosition(vehicle, false)
    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    Entity(vehicle).state:set('dw_scrapping_workflow_active', false, true)
end

local function clearSession(notifyCancel)
    if activeSession and activeSession.vehicleNetId then
        TriggerServerEvent('dw_scrapping:cancel', activeSession.vehicleNetId)
    end

    if activeSession and activeSession.vehicle and DoesEntityExist(activeSession.vehicle) then
        unlockVehicle(activeSession.vehicle)
    end

    activeSession = nil
    actionBusy = false
    stopEmote()
    if notifyCancel then
        notify(Config.Locale.Cancelled, 'error')
    end
end

local function isFinalVehicleStepPending()
    if not activeSession then
        return false
    end
    local finalCfg = finalVehicleStepConfig()
    if finalCfg.enabled == false then
        return false
    end
    if activeSession.finalVehicleDone == true then
        return false
    end
    if activeSession.carryingPart then
        return false
    end
    return getCurrentTask() == nil
end

local function startSessionWithVehicle(vehicle, worksite, opts)
    opts = opts or {}

    if activeSession or actionBusy then
        return false, Config.Locale.InProgress
    end

    if vehicle == nil or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        return false, Config.Locale.InvalidVehicle
    end

    local vehicleState = Entity(vehicle).state
    if vehicleState and vehicleState.dw_scrapping_workflow_active then
        return false, Config.Locale.InProgress
    end

    local vehicleNetId = getVehicleNetId(vehicle)
    if vehicleNetId == 0 then
        return false, Config.Locale.InvalidVehicle
    end

    local worksiteId = worksite and worksite.id or (worksites[1] and worksites[1].id) or nil
    local response = lib.callback.await('dw_scrapping:requestStart', false, vehicleNetId, worksiteId)
    if not response or not response.ok then
        return false, (response and response.message) or Config.Locale.StartFailed
    end

    local scrappingProgress = (Config.Scrapping and Config.Scrapping.Progress) or {}
    local useStartProgress = scrappingProgress.UseStartProgress == true
    local completed = true
    if useStartProgress then
        actionBusy = true
        local startSeconds = math.max(1, tonumber(Config.Scrapping.PartActionSeconds) or 6)
        completed = runProgress(
            scrappingProgress.StartLabel or Config.Scrapping.ProgressLabel or 'Pripravuji vozidlo...',
            startSeconds * 1000,
            false
        )
        actionBusy = false
    end

    if not completed then
        TriggerServerEvent('dw_scrapping:cancel', vehicleNetId)
        return false, Config.Locale.Cancelled
    end

    lockVehicleForScrap(vehicle)
    activeSession = {
        vehicle = vehicle,
        vehicleNetId = vehicleNetId,
        worksite = worksiteById[worksiteId] or worksite,
        tasks = buildTaskList(vehicle),
        currentTaskIndex = 1,
        carryingPart = nil,
        finalVehicleDone = false,
        finalStepNotified = false
    }

    if not opts.silent then
        notify(Config.Locale.VehicleLocked or Config.Locale.StartFailed, 'inform')
    end
    return true, nil
end

local function removeNextPart()
    if not activeSession or actionBusy then
        return
    end

    local ped = PlayerPedId()
    local vehicle = activeSession.vehicle
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        clearSession(true)
        return
    end

    local distFromVehicle = #(GetEntityCoords(ped) - GetEntityCoords(vehicle))
    local maxDist = distWorkVehicle()
    if distFromVehicle > maxDist then
        notify(Config.Locale.NotAtWorkPoint or Config.Locale.TooFar, 'error')
        return
    end

    if activeSession.carryingPart then
        notify(Config.Locale.NoPartToDeliver or Config.Locale.WrongPartOrder, 'error')
        return
    end

    local task = getCurrentTask()
    if not task then
        return
    end

    local part, partDistance = findNearestUndetachedPart(task, vehicle, GetEntityCoords(ped))
    if not part then
        notify(Config.Locale.WrongPartOrder or Config.Locale.GenericError, 'error')
        return
    end

    local maxPartDistance = distPartInteract()
    if not partDistance or partDistance > maxPartDistance then
        notify(Config.Locale.TooFarFromPart or Config.Locale.NotAtWorkPoint or Config.Locale.TooFar, 'error')
        return
    end

    local removeCfg = getEmoteActionConfig('remove', part.type) or {}
    local canCancel = removeCfg.allowCancel == true and ((progressConfig().canCancel ~= false))
    actionBusy = true
    startEmote('remove', part.type)
    local done = runProgress(
        (Config.Scrapping.Progress and Config.Scrapping.Progress.RemoveLabel) or 'Demontujes dil...',
        math.max(1, tonumber(Config.Scrapping.PartActionSeconds) or 6) * 1000,
        canCancel
    )
    stopEmote()
    actionBusy = false

    if not done then
        notify(Config.Locale.Cancelled, 'error')
        return
    end

    part.detached = true
    activeSession.carryingPart = part
    detachVehiclePart(vehicle, part, task.id)
    startEmote('carry', part.type)
    notify(Config.Locale.PartDetached or Config.Locale.NextTask, 'inform')
end

local function finishIfCompleted()
    advanceTaskIfNeeded()
    if getCurrentTask() then
        notify(Config.Locale.NextTask or Config.Locale.PartDelivered, 'success')
        return
    end

    local finalCfg = finalVehicleStepConfig()
    if finalCfg.enabled ~= false then
        if activeSession then
            activeSession.finalStepNotified = true
        end
        notify(Config.Locale.FinalStepReady or Config.Locale.NextTask, 'inform')
        return
    end

    local netId = activeSession and activeSession.vehicleNetId
    local vehicle = activeSession and activeSession.vehicle
    if netId then
        TriggerServerEvent('dw_scrapping:finish', netId)
    end

    if vehicle and DoesEntityExist(vehicle) then
        if Config.Scrapping.AutoDeleteVehicleOnComplete then
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteVehicle(vehicle)
        else
            unlockVehicle(vehicle)
        end
    end

    activeSession = nil
    actionBusy = false
    stopEmote()
end

local function finishFinalVehicleStep()
    if not activeSession or actionBusy then
        return
    end
    if not isFinalVehicleStepPending() then
        return
    end

    local ped = PlayerPedId()
    local vehicle = activeSession.vehicle
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        clearSession(true)
        return
    end

    local distFromVehicle = #(GetEntityCoords(ped) - GetEntityCoords(vehicle))
    local maxDist = distWorkVehicle()
    if distFromVehicle > maxDist then
        notify(Config.Locale.NotAtWorkPoint or Config.Locale.TooFar, 'error')
        return
    end

    local finalCfg = finalVehicleStepConfig()
    local removeCfg = getEmoteActionConfig('remove', 'shell') or getEmoteActionConfig('remove') or {}
    local canCancel = removeCfg.allowCancel == true and ((progressConfig().canCancel ~= false))
    local duration = math.max(1, tonumber(finalCfg.ActionSeconds) or math.max(1, tonumber(Config.Scrapping.PartActionSeconds) or 6)) * 1000
    local label = finalCfg.ProgressLabel or (Config.Locale.FinalStepLabel or 'Rozebiras zbytek vozidla...')

    actionBusy = true
    startEmote('remove', 'shell')
    local done = runProgress(label, duration, canCancel)
    stopEmote()
    actionBusy = false

    if not done then
        notify(Config.Locale.Cancelled, 'error')
        return
    end

    if type(SmashVehicleWindow) == 'function' then
        for i = 0, 7 do
            pcall(function()
                SmashVehicleWindow(vehicle, i)
            end)
        end
    end
    SetVehicleBodyHealth(vehicle, 0.0)
    SetVehicleEngineHealth(vehicle, -4000.0)

    activeSession.finalVehicleDone = true

    local netId = activeSession.vehicleNetId
    if netId then
        TriggerServerEvent('dw_scrapping:finish', netId)
    end

    if DoesEntityExist(vehicle) then
        if Config.Scrapping.AutoDeleteVehicleOnComplete then
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteVehicle(vehicle)
        else
            unlockVehicle(vehicle)
        end
    end

    activeSession = nil
    actionBusy = false
    stopEmote()
end

local function deliverCurrentPart()
    if not activeSession or actionBusy then
        return
    end

    if not activeSession.carryingPart then
        notify(Config.Locale.NoPartToDeliver or Config.Locale.GenericError, 'error')
        return
    end

    local scrappingProgress = (Config.Scrapping and Config.Scrapping.Progress) or {}
    local useDeliveryProgress = scrappingProgress.UseDeliveryProgress == true
    local done = true
    if useDeliveryProgress then
        actionBusy = true
        local carryCfg = getEmoteActionConfig('carry', activeSession.carryingPart.type) or {}
        local canCancel = carryCfg.allowCancel == true and ((progressConfig().canCancel ~= false))
        done = runProgress(
            scrappingProgress.DeliverLabel or 'Odnasis dil...',
            math.max(1, tonumber(Config.Scrapping.DeliveryActionSeconds) or 4) * 1000,
            canCancel
        )
        actionBusy = false
    end

    if not done then
        notify(Config.Locale.Cancelled, 'error')
        return
    end

    local part = activeSession.carryingPart
    local response = lib.callback.await('dw_scrapping:deliverPart', false, activeSession.vehicleNetId, part.type)
    if not response or not response.ok then
        local message = (response and response.message) or Config.Locale.GenericError
        notify(message, 'error')
        return
    end

    local task = getCurrentTask()
    part.delivered = true
    if task then
        task.doneCount = (task.doneCount or 0) + 1
    end
    activeSession.carryingPart = nil
    stopEmote()
    notify(Config.Locale.PartDelivered or Config.Locale.NextTask, 'success')
    finishIfCompleted()
end

local function getStartVehicleForPoint()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        return nil, Config.Locale.MustBeDriver or Config.Locale.InvalidVehicle
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil, Config.Locale.InvalidVehicle
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return nil, Config.Locale.MustBeDriver or Config.Locale.InvalidVehicle
    end

    TaskLeaveVehicle(ped, vehicle, 0)
    local timeout = GetGameTimer() + 2500
    while IsPedInVehicle(ped, vehicle, false) and GetGameTimer() < timeout do
        Wait(50)
    end

    return vehicle, nil
end

local function tryStartFromPoint(worksite)
    local vehicle, err = getStartVehicleForPoint()
    if not vehicle then
        notify(err or Config.Locale.InvalidVehicle, 'error')
        return
    end

    local ok, message = startSessionWithVehicle(vehicle, worksite, { silent = false })
    if not ok then
        notify(message or Config.Locale.StartFailed, 'error')
    end
end

local function isNear(coords, target, radius)
    return #(coords - target) <= radius
end

local function processInteractionPro()
    if #worksites == 0 then
        hidePrompt()
        Wait(1000)
        return
    end

    local waitTime = Config.Interaction.ScanIntervalFar
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local radius = distPrompt()

    if activeSession then
        waitTime = Config.Interaction.ScanIntervalNear
        local worksite = activeSession.worksite
        local dropPoint = worksite and worksite.DropPoint

        if activeSession.carryingPart then
            if dropPoint and isNear(coords, dropPoint, radius) then
                waitTime = 0
                showPrompt(Config.Locale.DropPrompt or '[E] Odevzdat dil')
                if interactPressed() then
                    deliverCurrentPart()
                end
            else
                hidePrompt()
            end
        else
            local vehicle = activeSession.vehicle
            if vehicle == 0 or not DoesEntityExist(vehicle) then
                clearSession(true)
                hidePrompt()
                return
            end

            local vehicleDist = #(coords - GetEntityCoords(vehicle))
            local maxDist = distWorkVehicle()
            if vehicleDist <= maxDist then
                waitTime = 0
                if isFinalVehicleStepPending() then
                    showPrompt(Config.Locale.FinalWorkPrompt or '[E] Rozebrat zbytek vozidla')
                    if interactPressed() then
                        finishFinalVehicleStep()
                    end
                else
                    showPrompt(Config.Locale.WorkPrompt or '[E] Demontovat dalsi kus')
                    if interactPressed() then
                        removeNextPart()
                    end
                end
            else
                hidePrompt()
            end
        end

        Wait(waitTime)
        return
    end

    if not Config.Interaction.BuiltinKeybind then
        hidePrompt()
        Wait(1000)
        return
    end

    local nearestWorksite = getNearestStartWorksite(coords, radius)
    if nearestWorksite and canShowStartPromptForPed(ped) then
        waitTime = 0
        showPrompt(Config.Locale.StartPrompt or '[E] Spustit rozebirani vozidla')
        if interactPressed() then
            tryStartFromPoint(nearestWorksite)
        end
    else
        hidePrompt()
    end

    Wait(waitTime)
end

local function processInteraction()
    local mode = getProfileMode()
    if mode == 'off' then
        hidePrompt()
        Wait(1000)
        return
    end
    processInteractionPro()
end

CreateThread(function()
    local mode = getProfileMode()
    if mode == 'pro' then
        buildWorksites()
        createBlips()
    else
        worksites = {}
        worksiteById = {}
    end
end)

local function shouldDrawWorldUi()
    local mode = getProfileMode()
    if mode ~= 'pro' then
        return false
    end
    if activeSession then
        return true
    end
    local maxR = distMarkerDraw()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    for i = 1, #worksites do
        local s = worksites[i]
        if #(c - s.StartPoint) <= maxR or #(c - s.DropPoint) <= maxR then
            return true
        end
    end
    return false
end

CreateThread(function()
    while true do
        if not shouldDrawWorldUi() then
            Wait(500)
        else
            if #worksites > 0 then
                if activeSession then
                    local site = activeSession.worksite
                    if site and site.DropPoint then
                        drawMarkerAtPoint(site.DropPoint)
                    end
                else
                    for i = 1, #worksites do
                        local site = worksites[i]
                        drawMarkerAtPoint(site.StartPoint)
                    end
                end
            end

            if activeSession then
                drawChecklist()

                local vehicle = activeSession.vehicle
                local task = getCurrentTask()
                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and task and not activeSession.carryingPart then
                    local playerCoords = GetEntityCoords(PlayerPedId())
                local vehicleDist = #(playerCoords - GetEntityCoords(vehicle))
                if vehicleDist <= distVehicleMarkerDraw() then
                    local part, partDist = findNearestUndetachedPart(task, vehicle, playerCoords)
                    if part and partDist and partDist <= distPartMarkerDraw() then
                        local partCoords = getPartWorldPosition(vehicle, part, task.id)
                        local markerCoords = getOffsetPartMarkerCoords(vehicle, partCoords, playerCoords)
                        drawPartMarkerAtPoint(markerCoords)
                    end
                    end
                elseif vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and isFinalVehicleStepPending() then
                    local playerCoords = GetEntityCoords(PlayerPedId())
                    local vehicleDist = #(playerCoords - GetEntityCoords(vehicle))
                    if vehicleDist <= distVehicleMarkerDraw() then
                        drawPartMarkerAtPoint(GetEntityCoords(vehicle))
                    end
                end
            end

            Wait(0)
        end
    end
end)

CreateThread(function()
    while true do
        processInteraction()
    end
end)

RegisterNetEvent('dw_scrapping:notify', function(message, notificationType)
    notify(message or Config.Locale.GenericError, notificationType)
end)

exports('TryScrapVehicle', function(vehicle, opts)
    opts = opts or { silent = true }
    local mode = getProfileMode()
    if mode == 'off' then
        return false, Config.Locale.StartFailed or Config.Locale.GenericError
    end
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local vehicleState = Entity(vehicle).state
        if vehicleState and vehicleState.dw_scrapping_workflow_active then
            return false, Config.Locale.InProgress
        end
    end
    local selectedWorksite = nil
    if opts.worksiteId then
        selectedWorksite = worksiteById[opts.worksiteId]
    end
    if not selectedWorksite then
        local pedCoords = GetEntityCoords(PlayerPedId())
        selectedWorksite = getNearestStartWorksite(pedCoords, 99999.0) or worksites[1]
    end
    return startSessionWithVehicle(vehicle, selectedWorksite, opts)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    clearSession(false)
    hidePrompt()
    for i = 1, #blips do
        if DoesBlipExist(blips[i]) then
            RemoveBlip(blips[i])
        end
    end
end)
