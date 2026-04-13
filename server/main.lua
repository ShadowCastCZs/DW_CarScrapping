local ESX = exports['es_extended']:getSharedObject()

local activeByVehicle = {}
local activeBySource = {}
local scrapDurationMs = math.max(1, tonumber(Config.Scrapping.DurationSeconds) or 1) * 1000
local interactionRadius = (tonumber(Config.Interaction.Radius) or 3.0) + 1.5
local blacklistedModelHashes = {}

local function debugLog(message)
    if Config.Debug then
        print(('[DW_CarScrapping] %s'):format(message))
    end
end

local function trimPlate(plate)
    if not plate then
        return ''
    end

    return plate:gsub('^%s*(.-)%s*$', '%1'):upper()
end

local function isModelBlacklisted(modelHash)
    return blacklistedModelHashes[modelHash] == true
end

local function isOwnedVehicle(plate)
    local owned = MySQL.scalar.await('SELECT 1 FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    return owned == 1
end

local function getVehicleClassServerSafe(entity)
    local model = GetEntityModel(entity)

    if type(GetVehicleClass) == 'function' then
        return GetVehicleClass(entity), model
    end

    if type(GetVehicleClassFromName) == 'function' then
        return GetVehicleClassFromName(model), model
    end

    return nil, model
end

local function getItemCount(xPlayer, itemName)
    local item = xPlayer.getInventoryItem(itemName)
    if not item then
        return 0
    end

    return item.count or 0
end

local function isPlayerJobAllowed(xPlayer)
    local restriction = Config.JobRestriction
    if not restriction or not restriction.enabled then
        return true
    end

    local jobName = xPlayer.job and xPlayer.job.name
    if not jobName then
        return false
    end

    local allowedJobs = restriction.allowedJobs or {}

    if allowedJobs[jobName] == true then
        return true
    end

    for i = 1, #allowedJobs do
        if allowedJobs[i] == jobName then
            return true
        end
    end

    return false
end

local function clearSessionBySource(source)
    local session = activeBySource[source]
    if not session then
        return
    end

    activeBySource[source] = nil
    activeByVehicle[session.netId] = nil
end

local function clearSessionByNetId(netId)
    local session = activeByVehicle[netId]
    if not session then
        return
    end

    activeByVehicle[netId] = nil
    activeBySource[session.source] = nil
end

for modelName in pairs(Config.Scrapping.BlacklistedModels or {}) do
    blacklistedModelHashes[joaat(modelName)] = true
end

lib.callback.register('dw_scrapping:requestStart', function(source, vehicleNetId)
    if activeBySource[source] then
        return { ok = false, message = Config.Locale.InProgress }
    end

    local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return { ok = false, message = Config.Locale.InvalidVehicle }
    end

    if activeByVehicle[vehicleNetId] then
        return { ok = false, message = Config.Locale.Busy }
    end

    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then
        return { ok = false, message = Config.Locale.GenericError }
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return { ok = false, message = Config.Locale.GenericError }
    end

    if not isPlayerJobAllowed(xPlayer) then
        debugLog(('Reject source %s: job %s not allowed.'):format(source, xPlayer.job and xPlayer.job.name or 'unknown'))
        return { ok = false, message = Config.Locale.JobNotAllowed or Config.Locale.GenericError }
    end

    local requiredItem = Config.Scrapping.RequiredItem
    if requiredItem and requiredItem.enabled then
        local requiredCount = requiredItem.count or 1
        local itemCount = getItemCount(xPlayer, requiredItem.item)

        if itemCount < requiredCount then
            debugLog(('Reject source %s: missing required item %s (%s/%s).'):format(source, requiredItem.item, itemCount, requiredCount))
            return { ok = false, message = Config.Locale.MissingRequiredItem or Config.Locale.GenericError }
        end
    end

    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > interactionRadius then
        return { ok = false, message = Config.Locale.TooFar }
    end

    if GetPedInVehicleSeat(entity, -1) ~= 0 then
        debugLog(('Reject netId %s: driver seat occupied.'):format(vehicleNetId))
        return { ok = false, message = Config.Locale.InvalidVehicle }
    end

    local vehicleClass, model = getVehicleClassServerSafe(entity)
    local plate = trimPlate(GetVehicleNumberPlateText(entity))

    if isModelBlacklisted(model) then
        debugLog(('Reject netId %s: model %s is blacklisted.'):format(vehicleNetId, model))
        return { ok = false, message = Config.Locale.InvalidVehicle }
    end

    if vehicleClass ~= nil and not Config.Scrapping.AllowedVehicleClasses[vehicleClass] then
        debugLog(('Reject netId %s: class %s not allowed.'):format(vehicleNetId, vehicleClass))
        return { ok = false, message = Config.Locale.InvalidVehicle }
    end

    if vehicleClass == nil then
        debugLog(('Class not available for netId %s (model %s), skipping class whitelist.'):format(vehicleNetId, model))
    end

    local owned = false
    if plate ~= '' then
        owned = isOwnedVehicle(plate)
    end

    if owned and not Config.OwnedVehiclePolicy.AllowOwnedVehicles then
        debugLog(('Reject netId %s: plate %s is owned vehicle.'):format(vehicleNetId, plate))
        return { ok = false, message = Config.Locale.OwnedBlocked }
    end

    if owned and Config.OwnedVehiclePolicy.AllowOwnedVehicles and Config.OwnedVehiclePolicy.DeleteOwnedRecordWhenAllowed then
        MySQL.update.await('DELETE FROM owned_vehicles WHERE plate = ?', { plate })
        debugLog(('Owned vehicle with plate %s removed from owned_vehicles.'):format(plate))
    end

    if requiredItem and requiredItem.enabled and requiredItem.consumeOnStart then
        local requiredCount = requiredItem.count or 1
        xPlayer.removeInventoryItem(requiredItem.item, requiredCount)
    end

    local session = {
        source = source,
        netId = vehicleNetId,
        entity = entity,
        startedAt = GetGameTimer()
    }

    activeByVehicle[vehicleNetId] = session
    activeBySource[source] = session

    return { ok = true }
end)

RegisterNetEvent('dw_scrapping:cancel', function(vehicleNetId)
    local source = source
    local session = activeByVehicle[vehicleNetId]

    if not session or session.source ~= source then
        return
    end

    clearSessionByNetId(vehicleNetId)
end)

RegisterNetEvent('dw_scrapping:finish', function(vehicleNetId)
    local source = source
    local session = activeByVehicle[vehicleNetId]

    if not session or session.source ~= source then
        TriggerClientEvent('dw_scrapping:notify', source, Config.Locale.GenericError, 'error')
        return
    end

    local ped = GetPlayerPed(source)
    local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
    local elapsed = GetGameTimer() - session.startedAt

    if ped == 0 or not DoesEntityExist(ped) or entity == 0 or not DoesEntityExist(entity) then
        clearSessionByNetId(vehicleNetId)
        TriggerClientEvent('dw_scrapping:notify', source, Config.Locale.GenericError, 'error')
        return
    end

    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > interactionRadius then
        clearSessionByNetId(vehicleNetId)
        TriggerClientEvent('dw_scrapping:notify', source, Config.Locale.TooFar, 'error')
        return
    end

    if elapsed < (scrapDurationMs - 800) then
        clearSessionByNetId(vehicleNetId)
        TriggerClientEvent('dw_scrapping:notify', source, Config.Locale.GenericError, 'error')
        return
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        clearSessionByNetId(vehicleNetId)
        return
    end

    for i = 1, #Config.Rewards do
        local reward = Config.Rewards[i]
        local chanceRoll = math.random(1, 100)

        if chanceRoll <= reward.chance then
            local amount = math.random(reward.min, reward.max)
            if amount > 0 then
                xPlayer.addInventoryItem(reward.item, amount)
            end
        end
    end

    DeleteEntity(entity)
    clearSessionByNetId(vehicleNetId)

    TriggerClientEvent('dw_scrapping:notify', source, Config.Locale.Success, 'success')
end)

AddEventHandler('playerDropped', function()
    local source = source
    clearSessionBySource(source)
end)
