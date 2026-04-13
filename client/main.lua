local isScrapping = false
local activeVehicleNetId
local textVisible = false
local lastPressAt = 0
local scrapDurationMs = math.max(1, tonumber(Config.Scrapping.DurationSeconds) or 1) * 1000

local function notifyConfig()
    return Config.Notify or (Config.UI and Config.UI.Notify) or {}
end

local function progressConfig()
    return Config.Progress or (Config.UI and Config.UI.Progress) or {}
end

local function debugLog(message)
    if Config.Debug then
        print(('[DW_CarScrapping][client] %s'):format(message))
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

local function buildProgressData()
    local cfg = progressConfig()
    local animConfig = cfg.anim or {}

    local data = {
        duration = scrapDurationMs,
        label = Config.Scrapping.ProgressLabel,
        useWhileDead = cfg.useWhileDead == true,
        canCancel = cfg.canCancel ~= false,
        disable = cfg.disable or {
            move = true,
            car = true,
            combat = true
        }
    }

    if animConfig.type == 'dict' then
        data.anim = {
            dict = animConfig.dict or 'amb@world_human_welding@male@base',
            clip = animConfig.clip or 'base',
            flag = animConfig.flag or 49
        }
    else
        data.anim = {
            scenario = animConfig.scenario or 'WORLD_HUMAN_WELDING'
        }
    end

    return data
end

local function hidePrompt()
    if textVisible then
        lib.hideTextUI()
        textVisible = false
    end
end

local function getClosestVehicle(maxDistance)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local vehicle = GetClosestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, maxDistance, 0, 71)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil, maxDistance + 1.0
    end

    local distance = #(playerCoords - GetEntityCoords(vehicle))
    return vehicle, distance
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

local function startScrapProgress(vehicleNetId)
    if isScrapping then
        notify(Config.Locale.InProgress, 'error')
        return
    end

    local vehicle = NetToVeh(vehicleNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        notify(Config.Locale.InvalidVehicle, 'error')
        return
    end

    isScrapping = true
    activeVehicleNetId = vehicleNetId

    local progressData = buildProgressData()
    local progressType = progressConfig().type or 'bar'

    local completed
    if progressType == 'circle' then
        completed = lib.progressCircle(progressData)
    else
        completed = lib.progressBar(progressData)
    end

    if completed then
        TriggerServerEvent('dw_scrapping:finish', vehicleNetId)
    else
        TriggerServerEvent('dw_scrapping:cancel', vehicleNetId)
        notify(Config.Locale.Cancelled, 'error')
    end

    isScrapping = false
    activeVehicleNetId = nil
end

CreateThread(function()
    while true do
        local waitTime = Config.Interaction.ScanIntervalFar

        if not isScrapping then
            local ped = PlayerPedId()

            if not IsPedInAnyVehicle(ped, false) then
                local vehicle, distance = getClosestVehicle(Config.Interaction.Radius)

                if vehicle and distance <= Config.Interaction.Radius then
                    waitTime = Config.Interaction.ScanIntervalNear

                    if not textVisible then
                        lib.showTextUI(Config.Locale.Prompt)
                        textVisible = true
                        debugLog(('Prompt shown for vehicle %s (dist %.2f)'):format(vehicle, distance))
                    end

                    if IsControlJustPressed(0, Config.Interaction.Key) or IsDisabledControlJustPressed(0, Config.Interaction.Key) then
                        local now = GetGameTimer()
                        if now - lastPressAt < 250 then
                            goto continue
                        end

                        lastPressAt = now
                        hidePrompt()
                        debugLog('Interaction key pressed.')

                        local vehicleNetId = getVehicleNetId(vehicle)
                        if vehicleNetId == 0 then
                            debugLog('Failed to get vehicle net ID.')
                            notify(Config.Locale.InvalidVehicle, 'error')
                            Wait(250)
                            goto continue
                        end

                        debugLog(('Requesting scrap start for net ID %s'):format(vehicleNetId))
                        local response = lib.callback.await('dw_scrapping:requestStart', false, vehicleNetId)
                        debugLog(('Server response: %s'):format(json.encode(response)))

                        if response and response.ok then
                            startScrapProgress(vehicleNetId)
                        else
                            notify((response and response.message) or Config.Locale.StartFailed, 'error')
                        end
                    end
                else
                    hidePrompt()
                end
            else
                hidePrompt()
            end
        else
            hidePrompt()
            waitTime = 200
        end

        ::continue::
        Wait(waitTime)
    end
end)

RegisterNetEvent('dw_scrapping:notify', function(message, notificationType)
    notify(message or Config.Locale.GenericError, notificationType)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if isScrapping and activeVehicleNetId then
        TriggerServerEvent('dw_scrapping:cancel', activeVehicleNetId)
    end

    hidePrompt()
end)
