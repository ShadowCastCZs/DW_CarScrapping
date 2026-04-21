local ESX = exports['es_extended']:getSharedObject()

local activeByVehicle = {}
local activeBySource = {}
local blacklistedModelHashes = {}
local worksitesById = {}
local worksitesList = {}
local dbOwnedQueryFailed = false
local validPartTypes = {}

local function getProfileMode()
    local profile = Config.Profile or {}
    local mode = type(profile.Mode) == 'string' and string.lower(profile.Mode) or 'pro'
    if mode == 'off' then
        return 'off'
    end
    return 'pro'
end

local function getServerDistances()
    local d = Config.Distances or {}
    return {
        pedToVehicle = tonumber(d.ServerPedToVehicle) or 4.5,
        startPointMax = tonumber(d.ServerStartPointMax) or 8.5,
        dropPointMax = tonumber(d.ServerDropPointMax) or 7.5
    }
end

local function sanitizeSqlIdentifier(name)
    if type(name) ~= 'string' or not name:match('^[%w_]+$') then
        return nil
    end
    return name
end

local function buildValidPartTypes()
    validPartTypes = {}
    for _, row in ipairs(Config.TaskOrder or {}) do
        if row.id and row.id ~= '' then
            validPartTypes[row.id] = true
        end
    end
    if Config.PartRewards then
        for key in pairs(Config.PartRewards) do
            validPartTypes[key] = true
        end
    end
end

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

local function safeScalar(query, params)
    local ok, result = pcall(function()
        return MySQL.scalar.await(query, params)
    end)
    if not ok then
        return nil, result
    end
    return result, nil
end

local function safeUpdate(query, params)
    local ok, result = pcall(function()
        return MySQL.update.await(query, params)
    end)
    if not ok then
        return nil, result
    end
    return result, nil
end

local function isOwnedVehicle(plate, policy)
    policy = policy or Config.OwnedVehiclePolicy or {}
    local tableName = sanitizeSqlIdentifier(policy.TableName or 'owned_vehicles') or 'owned_vehicles'
    local query = ('SELECT 1 FROM `%s` WHERE plate = ? LIMIT 1'):format(tableName)
    local owned, err = safeScalar(query, { plate })
    if err then
        if not dbOwnedQueryFailed then
            dbOwnedQueryFailed = true
            print(('[DW_CarScrapping] DB error in owned vehicle check (%s): %s'):format(tableName, tostring(err)))
            print('[DW_CarScrapping] Owned vehicle protection is temporarily bypassed until server restart or query fix.')
        end
        return false
    end

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

local function isDriverSeatOccupied(vehicle)
    if type(IsVehicleSeatFree) == 'function' then
        return not IsVehicleSeatFree(vehicle, -1)
    end

    local ped = GetPedInVehicleSeat(vehicle, -1)
    if ped == nil or ped == 0 or ped == false then
        return false
    end

    return DoesEntityExist(ped)
end

local function getDoorCount(entity)
    if type(DoesVehicleHaveDoor) ~= 'function' then
        return 4
    end

    local count = 0
    for i = 0, 3 do
        if DoesVehicleHaveDoor(entity, i) then
            count = count + 1
        end
    end
    if count <= 0 then
        return 4
    end
    return count
end

local function resolveTaskCountServer(taskCfg, entity)
    if taskCfg.count then
        return taskCfg.count
    end

    if taskCfg.countMode == 'wheels' then
        local wheelCount = 4
        if type(GetVehicleNumberOfWheels) == 'function' then
            wheelCount = GetVehicleNumberOfWheels(entity)
        end
        if not wheelCount or wheelCount <= 0 then
            wheelCount = 4
        end
        return math.max(1, math.min(4, wheelCount))
    end

    if taskCfg.countMode == 'doors' then
        return getDoorCount(entity)
    end

    return 1
end

local function buildRemainingPartsMap(entity)
    local result = {}
    local order = Config.TaskOrder or {}
    for i = 1, #order do
        local taskCfg = order[i]
        local taskId = taskCfg.id
        if taskId and taskId ~= '' then
            local count = math.max(1, tonumber(resolveTaskCountServer(taskCfg, entity)) or 1)
            result[taskId] = count
        end
    end
    return result
end

local function rollRewardTotals(rewardList)
    local totals = {}
    if type(rewardList) ~= 'table' then
        return totals
    end

    for i = 1, #rewardList do
        local reward = rewardList[i]
        local chance = tonumber(reward.chance) or 100
        local min = tonumber(reward.min) or 0
        local max = tonumber(reward.max) or min
        local item = reward.item

        if item and item ~= '' and min >= 0 and max >= min then
            local chanceRoll = math.random(1, 100)
            if chanceRoll <= chance then
                local amount = math.random(min, max)
                if amount > 0 then
                    totals[item] = (totals[item] or 0) + amount
                end
            end
        end
    end

    return totals
end

local function playerCanCarryItemCount(xPlayer, itemName, count)
    if count <= 0 then
        return true
    end

    if type(xPlayer.canCarryItem) == 'function' then
        local ok = xPlayer.canCarryItem(itemName, count)
        return ok == true or ok == 1
    end

    if type(ESX.CanCarryItem) == 'function' then
        local ok = ESX.CanCarryItem(xPlayer.source, itemName, count)
        return ok == true or ok == 1
    end

    debugLog('canCarryItem není dostupné (xPlayer ani ESX) — kontrola inventáře se přeskočí.')
    return true
end

local function playerCanCarryRewardTotals(xPlayer, totals)
    for itemName, count in pairs(totals) do
        if not playerCanCarryItemCount(xPlayer, itemName, count) then
            return false, itemName
        end
    end

    return true, nil
end

local function isPlayerJobAllowed(xPlayer, restriction)
    restriction = restriction or Config.JobRestriction
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
    local configured = Config.Worksites
    if type(configured) == 'table' and #configured > 0 then
        for i = 1, #configured do
            local site = configured[i]
            if site and site.StartPoint and site.DropPoint then
                local id = site.id or ('worksite_%s'):format(i)
                local normalized = {
                    id = id,
                    label = site.label or id,
                    StartPoint = site.StartPoint,
                    DropPoint = site.DropPoint,
                    allowedJobs = normalizeAllowedJobs(site.allowedJobs)
                }
                worksitesById[id] = normalized
                worksitesList[#worksitesList + 1] = normalized
            end
        end
        return
    end

    local points = Config.Points or {}
    if points.StartPoint and points.DropPoint then
        local fallback = {
            id = 'default',
            label = 'Default',
            StartPoint = points.StartPoint,
            DropPoint = points.DropPoint,
            allowedJobs = nil
        }
        worksitesById[fallback.id] = fallback
        worksitesList[#worksitesList + 1] = fallback
    end
end

local function getWorksiteById(worksiteId)
    if type(worksiteId) == 'string' and worksiteId ~= '' and worksitesById[worksiteId] then
        return worksitesById[worksiteId]
    end

    return worksitesList[1]
end

local function isJobAllowedAtWorksite(jobName, worksite)
    if not worksite or not worksite.allowedJobs then
        return true
    end
    return worksite.allowedJobs[jobName] == true
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

buildWorksites()
buildValidPartTypes()

lib.callback.register('dw_scrapping:requestStart', function(source, vehicleNetId, worksiteId)
    local profileMode = getProfileMode()
    if profileMode == 'off' then
        return { ok = false, message = Config.Locale.StartFailed or Config.Locale.GenericError }
    end

    if activeBySource[source] then
        return { ok = false, message = Config.Locale.InProgress }
    end

    local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return { ok = false, message = Config.Locale.InvalidVehicle }
    end

    if activeByVehicle[vehicleNetId] then
        return { ok = false, message = Config.Locale.InProgress or Config.Locale.GenericError }
    end

    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then
        return { ok = false, message = Config.Locale.GenericError }
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return { ok = false, message = Config.Locale.GenericError }
    end

    local worksite = nil
    local distCfg = getServerDistances()
    local playerCoords = GetEntityCoords(ped)
    worksite = getWorksiteById(worksiteId)
    if not worksite then
        return { ok = false, message = Config.Locale.GenericError }
    end
    if #(playerCoords - worksite.StartPoint) > distCfg.startPointMax then
        return { ok = false, message = Config.Locale.TooFar }
    end

    local jobRestriction = Config.JobRestriction
    if not isPlayerJobAllowed(xPlayer, jobRestriction) then
        debugLog(('Reject source %s: job %s not allowed.'):format(source, xPlayer.job and xPlayer.job.name or 'unknown'))
        return { ok = false, message = Config.Locale.JobNotAllowed or Config.Locale.GenericError }
    end

    local jobName = xPlayer.job and xPlayer.job.name
    if not isJobAllowedAtWorksite(jobName, worksite) then
        return { ok = false, message = Config.Locale.JobNotAllowed or Config.Locale.GenericError }
    end

    local scrappingCfg = Config.Scrapping or {}
    local requiredItem = scrappingCfg.RequiredItem
    if requiredItem and requiredItem.enabled then
        local requiredCount = requiredItem.count or 1
        local itemCount = getItemCount(xPlayer, requiredItem.item)

        if itemCount < requiredCount then
            debugLog(('Reject source %s: missing required item %s (%s/%s).'):format(source, requiredItem.item, itemCount, requiredCount))
            return { ok = false, message = Config.Locale.MissingRequiredItem or Config.Locale.GenericError }
        end
    end

    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > distCfg.pedToVehicle then
        return { ok = false, message = Config.Locale.TooFar }
    end

    if isDriverSeatOccupied(entity) then
        debugLog(('Reject netId %s: driver seat occupied.'):format(vehicleNetId))
        return { ok = false, message = Config.Locale.DriverSeatOccupied or Config.Locale.InvalidVehicle }
    end

    local vehicleClass, model = getVehicleClassServerSafe(entity)
    local plate = trimPlate(GetVehicleNumberPlateText(entity))

    if isModelBlacklisted(model) then
        debugLog(('Reject netId %s: model %s is blacklisted.'):format(vehicleNetId, model))
        return { ok = false, message = Config.Locale.InvalidVehicle }
    end

    local allowedClasses = scrappingCfg.AllowedVehicleClasses or {}
    if vehicleClass ~= nil and not allowedClasses[vehicleClass] then
        debugLog(('Reject netId %s: class %s not allowed.'):format(vehicleNetId, vehicleClass))
        return { ok = false, message = Config.Locale.InvalidVehicle }
    end

    local ownedPolicy = Config.OwnedVehiclePolicy or {}
    local owned = false
    if plate ~= '' then
        owned = isOwnedVehicle(plate, ownedPolicy)
    end

    if owned and not ownedPolicy.AllowOwnedVehicles then
        debugLog(('Reject netId %s: plate %s is owned vehicle.'):format(vehicleNetId, plate))
        return { ok = false, message = Config.Locale.OwnedBlocked }
    end

    if owned and ownedPolicy.AllowOwnedVehicles and ownedPolicy.DeleteOwnedRecordWhenAllowed then
        local tableName = sanitizeSqlIdentifier(ownedPolicy.TableName or 'owned_vehicles') or 'owned_vehicles'
        local query = ('DELETE FROM `%s` WHERE plate = ?'):format(tableName)
        local _, err = safeUpdate(query, { plate })
        if err then
            print(('[DW_CarScrapping] DB error deleting owned vehicle (%s): %s'):format(tableName, tostring(err)))
        else
            debugLog(('Owned vehicle with plate %s removed from %s.'):format(plate, tableName))
        end
    end

    if requiredItem and requiredItem.enabled and requiredItem.consumeOnStart then
        local requiredCount = requiredItem.count or 1
        xPlayer.removeInventoryItem(requiredItem.item, requiredCount)
    end

    local session = {
        source = source,
        netId = vehicleNetId,
        entity = entity,
        worksiteId = worksite and worksite.id or nil,
        remainingByType = buildRemainingPartsMap(entity),
        lastDeliverAt = 0,
        startedAt = GetGameTimer()
    }

    activeByVehicle[vehicleNetId] = session
    activeBySource[source] = session

    return { ok = true }
end)

lib.callback.register('dw_scrapping:deliverPart', function(source, vehicleNetId, partType)
    local session = activeByVehicle[vehicleNetId]
    if not session or session.source ~= source then
        return { ok = false, message = Config.Locale.SessionMissing or Config.Locale.GenericError }
    end
    if type(session.remainingByType) ~= 'table' then
        return { ok = false, message = Config.Locale.WrongPartOrder or Config.Locale.GenericError }
    end

    if type(partType) ~= 'string' or partType == '' or not validPartTypes[partType] then
        return { ok = false, message = Config.Locale.WrongPartOrder or Config.Locale.GenericError }
    end

    local cooldown = tonumber((Config.Security and Config.Security.DeliverCooldownMs) or 400) or 400
    local now = GetGameTimer()
    if (session.lastDeliverAt or 0) > 0 and (now - session.lastDeliverAt) < cooldown then
        return { ok = false, message = Config.Locale.GenericError }
    end

    local ped = GetPlayerPed(source)
    local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if ped == 0 or not DoesEntityExist(ped) or entity == 0 or not DoesEntityExist(entity) then
        clearSessionByNetId(vehicleNetId)
        return { ok = false, message = Config.Locale.GenericError }
    end

    local worksite = getWorksiteById(session.worksiteId)
    if not worksite then
        clearSessionByNetId(vehicleNetId)
        return { ok = false, message = Config.Locale.GenericError }
    end

    local distCfg = getServerDistances()
    if #(GetEntityCoords(ped) - worksite.DropPoint) > distCfg.dropPointMax then
        return { ok = false, message = Config.Locale.NotAtDropPoint or Config.Locale.TooFar }
    end

    local remainingByType = session.remainingByType or {}
    local remainingCount = tonumber(remainingByType[partType]) or 0
    if remainingCount <= 0 then
        return { ok = false, message = Config.Locale.WrongPartOrder or Config.Locale.GenericError }
    end

    local rewards = Config.PartRewards and Config.PartRewards[partType]
    local rewardTotals = rollRewardTotals(rewards)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        clearSessionByNetId(vehicleNetId)
        return { ok = false, message = Config.Locale.GenericError }
    end

    local canCarry, blockedItem = playerCanCarryRewardTotals(xPlayer, rewardTotals)
    if not canCarry then
        debugLog(('Deliver rejected: cannot carry rewards (item %s).'):format(tostring(blockedItem)))
        return { ok = false, message = Config.Locale.CannotCarryReward or Config.Locale.GenericError }
    end

    for itemName, count in pairs(rewardTotals) do
        if count > 0 then
            xPlayer.addInventoryItem(itemName, count)
        end
    end

    remainingByType[partType] = remainingCount - 1
    session.lastDeliverAt = now
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
    local remainingByType = session.remainingByType or {}
    for _, remaining in pairs(remainingByType) do
        if tonumber(remaining) and tonumber(remaining) > 0 then
            TriggerClientEvent('dw_scrapping:notify', source, Config.Locale.WrongPartOrder or Config.Locale.GenericError, 'error')
            return
        end
    end

    local ped = GetPlayerPed(source)
    local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if ped == 0 or not DoesEntityExist(ped) then
        clearSessionByNetId(vehicleNetId)
        return
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        local shellRewards = Config.PartRewards and Config.PartRewards.shell
        local shellTotals = rollRewardTotals(shellRewards)
        for itemName, count in pairs(shellTotals) do
            if count > 0 then
                xPlayer.addInventoryItem(itemName, count)
            end
        end
    end

    if entity ~= 0 and DoesEntityExist(entity) and Config.Scrapping.AutoDeleteVehicleOnComplete then
        DeleteEntity(entity)
    end

    clearSessionByNetId(vehicleNetId)
    TriggerClientEvent('dw_scrapping:notify', source, Config.Locale.Success, 'success')
end)

AddEventHandler('playerDropped', function()
    clearSessionBySource(source)
end)
