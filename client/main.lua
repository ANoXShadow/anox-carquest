local Bridge = require('bridge/loader')
local Framework = Bridge.Load()

local state = {
    npcPed = nil,
    playerState = {},
    securityToken = nil,
    textUIActive = false,
    cooldowns = {
        deliver = 0,
        menu = 0,
        update = 0
    }
}

local Security = {}
local lastStateHash = nil
local lastStateUpdateTime = 0
local integrityCheckCooldown = 5000

function Security.checkCooldown(action, defaultMs)
    local currentTime = GetGameTimer()
    local lastTime = state.cooldowns[action] or 0
    local timeMs = defaultMs
    if Config.Security and Config.Security.rateLimit then
        if action == 'deliver' and Config.Security.rateLimit.delivery then
            timeMs = Config.Security.rateLimit.delivery
        elseif action == 'update' or action == 'reward' and Config.Security.rateLimit.reward then
            timeMs = Config.Security.rateLimit.reward
        elseif action == 'menu' and Config.Security.rateLimit.menu then
            timeMs = Config.Security.rateLimit.menu
        end
    end
    if (currentTime - lastTime) < timeMs then
        return false -- Still on cooldown
    end
    state.cooldowns[action] = currentTime
    return true -- Not on cooldown
end

local lastStateHash = nil

function Security.hashState(stateTable)
    if not stateTable then return "empty" end
    local stateStr = json.encode(stateTable)
    local hash = 5381
    for i = 1, #stateStr do
        hash = ((hash * 33) + string.byte(stateStr, i)) % 1000000
    end
    return tostring(hash)
end

function Security.verifyStateIntegrity(newState)
    if not lastStateHash then
        lastStateHash = Security.hashState(newState)
        lastStateUpdateTime = GetGameTimer()
        return true
    end
    local newHash = Security.hashState(newState)
    if lastStateHash == newHash then
        return true
    end
    local currentTime = GetGameTimer()
    local timeSinceLastUpdate = currentTime - lastStateUpdateTime
    if timeSinceLastUpdate > 5000 then
        local hashDiff = 0
        if tonumber(lastStateHash) and tonumber(newHash) then
            hashDiff = math.abs(tonumber(lastStateHash) - tonumber(newHash))
        else
            hashDiff = 20000 
        end
        if hashDiff > 10000 then
            Bridge.Debug("Warning: State integrity check failed")
            lastStateUpdateTime = currentTime
            TriggerServerEvent('anox-carquest:requestPlayerState')
            lastStateHash = newHash
            return false
        end
    end
    lastStateHash = newHash
    return true
end

CreateThread(function()
    Wait(1000)
    CreateWorldEntities()
    Wait(3000)
    TriggerServerEvent('anox-carquest:requestPlayerState')
    while true do
        HandleDeliveryTextUI()
        Wait(500)
    end
end)

function CreateWorldEntities()
    if Config.DeliveryPoint.blip and Config.DeliveryPoint.blip.enabled then
        local blip = AddBlipForCoord(Config.DeliveryPoint.coords)
        SetBlipSprite(blip, Config.DeliveryPoint.blip.sprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, Config.DeliveryPoint.blip.scale)
        SetBlipColour(blip, Config.DeliveryPoint.blip.color)
        SetBlipAsShortRange(blip, Config.DeliveryPoint.blip.shortRange)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(_L('carquest.delivery.point_blip'))
        EndTextCommandSetBlipName(blip)
    end
    if Config.NPC.blip and Config.NPC.blip.enabled then
        local npcBlip = AddBlipForCoord(Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)
        SetBlipSprite(npcBlip, Config.NPC.blip.sprite)
        SetBlipDisplay(npcBlip, 4)
        SetBlipScale(npcBlip, Config.NPC.blip.scale)
        SetBlipColour(npcBlip, Config.NPC.blip.color)
        SetBlipAsShortRange(npcBlip, Config.NPC.blip.shortRange)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(_L('carquest.delivery.npc_blip'))
        EndTextCommandSetBlipName(npcBlip)
    end
    CreateNPC()
end

function CreateNPC()
    if DoesEntityExist(state.npcPed) then return end
    local model = GetHashKey(Config.NPC.model)
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    if not HasModelLoaded(model) then
        Bridge.Debug("Failed to load NPC model")
        return
    end
    state.npcPed = CreatePed(4, model, Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z - 1.0, Config.NPC.coords.w, false, true)
    SetEntityHeading(state.npcPed, Config.NPC.coords.w)
    FreezeEntityPosition(state.npcPed, true)
    SetEntityInvincible(state.npcPed, true)
    SetBlockingOfNonTemporaryEvents(state.npcPed, true)
    if Config.NPC.scenario then
        TaskStartScenarioInPlace(state.npcPed, Config.NPC.scenario, 0, true)
    end
    
    Bridge.Target.AddLocalEntity(state.npcPed, {
        {
            name = 'anox_carquest_npc',
            icon = 'fas fa-car',
            label = _L('carquest.npc.interaction'),
            onSelect = function()
                if not Security.checkCooldown('menu', Config.Security.rateLimit.menu) then
                    Bridge.Notify(nil, _L('carquest.errors.please_wait_menu'), 'error', 'Please wait')
                    return
                end
                TriggerServerEvent('anox-carquest:requestPlayerState', true)
            end,
            distance = 2.5
        }
    })
    SetModelAsNoLongerNeeded(model)
end

function OpenCarQuestMenu()
    local options = {}
    local listsInOrder = SortLists()
    for _, listInfo in ipairs(listsInOrder) do
        local listName = listInfo.name
        local listData = Config.Lists[listName]
        local listState = state.playerState[listName]
        if not listState then goto continue_menu end
        if not listState.delivered_cars then
            listState.delivered_cars = {}
        end
        local deliveredCount = CountDeliveredCars(listState.delivered_cars)
        local configCarCount = #listData.cars
        local allCarsDelivered = AreAllCarsDelivered(listData.cars, listState.delivered_cars)
        local isCompleted = listState.completed
        local rewardCollected = listState.reward_collected
        local hasNewCars = rewardCollected and not allCarsDelivered
        local listOption = CreateListOption(
            listData, 
            deliveredCount, 
            configCarCount, 
            isCompleted, 
            rewardCollected, 
            hasNewCars, 
            allCarsDelivered
        )
        if not (rewardCollected and not hasNewCars) then
            listOption.menu = 'list_' .. listName
            local carOptions = CreateCarOptionsList(listName, listData, listState, rewardCollected, allCarsDelivered, hasNewCars)
            Bridge.RegisterContext({
                id = 'list_' .. listName,
                title = listData.label,
                menu = 'carquest_main',
                options = carOptions
            })
        end
        table.insert(options, listOption)
        ::continue_menu::
    end
    Bridge.RegisterContext({
        id = 'carquest_main',
        title = _L('carquest.menu.main_title'),
        options = options
    })
    Bridge.ShowContext('carquest_main')
end

function SortLists()
    local listsInOrder = {}
    for listName, listData in pairs(Config.Lists) do
        table.insert(listsInOrder, {name = listName, number = listData.number})
    end
    table.sort(listsInOrder, function(a, b)
        return a.number < b.number
    end)
    return listsInOrder
end

function AreAllCarsDelivered(cars, deliveredCars)
    if not deliveredCars then return false end
    for _, car in ipairs(cars) do
        if not deliveredCars[car.model] then
            return false
        end
    end
    return true
end

function CountDeliveredCars(deliveredCars)
    local count = 0
    for _, _ in pairs(deliveredCars or {}) do
        count = count + 1
    end
    return count
end

function CreateListOption(listData, deliveredCount, configCarCount, isCompleted, rewardCollected, hasNewCars, allCarsDelivered)
    local descriptionText = ""
    if rewardCollected and not hasNewCars then
        descriptionText = _L('carquest.list.completed', listData.reward)
    elseif hasNewCars then
        local rewardPercentage = listData.additionalRewardPercentage or Config.AdditionalRewardPercentage or 50
        local additionalReward = math.floor(listData.reward * (rewardPercentage / 100))
        descriptionText = _L('carquest.list.new_cars', additionalReward)
    elseif allCarsDelivered and not rewardCollected then
        descriptionText = _L('carquest.list.ready_reward', listData.reward)
    else
        descriptionText = _L('carquest.list.in_progress', deliveredCount, configCarCount, listData.reward)
    end
    local listOption = {
        title = listData.label,
        description = descriptionText,
        icon = (rewardCollected and not hasNewCars) and "fas fa-check-circle" or 
               hasNewCars and "fas fa-exclamation-circle" or
               (allCarsDelivered and not rewardCollected) and "fas fa-money-bill" or 
               "fas fa-list",
        iconColor = hasNewCars and "#FFD700" or nil,
        disabled = (rewardCollected and not hasNewCars),
        readOnly = (rewardCollected and not hasNewCars)
    }
    local statusValue = (rewardCollected and not hasNewCars) and _L('carquest.list.status_completed') or 
                       (hasNewCars and _L('carquest.list.status_new_cars')) or
                       (allCarsDelivered and not rewardCollected and _L('carquest.list.status_ready')) or 
                       _L('carquest.list.status_progress')
    local rewardSuffix = ""
    if rewardCollected and not hasNewCars then
        rewardSuffix = _L('carquest.list.reward_collected')
    elseif hasNewCars then
        rewardSuffix = _L('carquest.list.reward_additional')
    end
    local displayReward = hasNewCars and 
        math.floor(listData.reward * (listData.additionalRewardPercentage or Config.AdditionalRewardPercentage or 50) / 100) or 
        listData.reward
    listOption.metadata = {
        {label = 'Status', value = statusValue},
        {label = _L('carquest.list.progress_label'), value = _L('carquest.list.progress_value', deliveredCount, configCarCount)},
        {label = _L('carquest.list.reward_label'), value = _L('carquest.list.reward_value', displayReward, rewardSuffix)}
    }
    return listOption
end

function CreateCarOptionsList(listName, listData, listState, rewardCollected, allCarsDelivered, hasNewCars)
    local carOptions = {}
    if not listState.delivered_cars then
        listState.delivered_cars = {}
    end
    for _, car in ipairs(listData.cars) do
        local isDelivered = listState.delivered_cars and listState.delivered_cars[car.model] or false
        local isNewCar = rewardCollected and not isDelivered
        local description
        if isDelivered then 
            description = _L('carquest.list.car_delivered')
        elseif isNewCar then 
            description = _L('carquest.list.car_new')
        else 
            description = _L('carquest.list.car_not_delivered')
        end
        table.insert(carOptions, {
            title = car.label,
            description = description,
            disabled = isDelivered,
            readOnly = true,
            icon = isNewCar and "fas fa-exclamation-circle" or "fas fa-car",
            iconColor = isNewCar and "#FFD700" or nil,
            metadata = {
                {label = _L('carquest.list.car_model'), value = car.model}
            }
        })
    end

    if allCarsDelivered and not rewardCollected then
        local rewardAmount = listData.reward
        local buttonTitle = _L('carquest.reward.button')
        local description = _L('carquest.reward.description', rewardAmount)
        table.insert(carOptions, 1, {
            title = buttonTitle,
            description = description,
            icon = "fas fa-money-bill",
            iconColor = "#FFD700",
            onSelect = function()
                if not Security.checkCooldown('update', Config.Security.rateLimit.reward) then
                    Bridge.Notify(nil, _L('carquest.errors.please_wait_reward'), 'error', 'Please wait')
                    return 
                end
                local alert = Bridge.AlertDialog(
                    _L('carquest.reward.confirmation_header'),
                    _L('carquest.reward.confirmation_content', rewardAmount, listData.label),
                    {
                        centered = true,
                        cancel = true,
                        confirmLabel = _L('carquest.reward.confirmation_confirm'),
                        cancelLabel = _L('carquest.reward.confirmation_cancel')
                    }
                )
                if alert == 'confirm' then
                    TriggerServerEvent('anox-carquest:collectReward', listName, false, state.securityToken)
                end
            end
        })
    end
    return carOptions
end

function HandleDeliveryTextUI()
    local isInDeliveryPoint = IsPlayerInDeliveryPoint()
    if not isInDeliveryPoint then
        if state.textUIActive then
            Bridge.HideTextUI()
            state.textUIActive = false
        end
        return
    end
    local vehicle, vehicleModelName = GetPlayerVehicleInfo()
    if not vehicle then
        if state.textUIActive then
            Bridge.HideTextUI()
            state.textUIActive = false
        end
        return
    end
    local listName, carModel, carLabel = CheckVehicleForLists(vehicleModelName)
    if listName and carModel then
        local isAdditionalCar = state.playerState[listName] and state.playerState[listName].reward_collected
        if not state.textUIActive or state.textUIActive ~= 'correct' then
            if state.textUIActive then Bridge.HideTextUI() end
            local deliveryText
            if isAdditionalCar then
                deliveryText = _L('carquest.delivery.correct_vehicle_additional', carLabel)
            else
                deliveryText = _L('carquest.delivery.correct_vehicle', carLabel)
            end
            Bridge.ShowTextUI(deliveryText, "delivery")
            state.textUIActive = 'correct'
        end
    else
        if not state.textUIActive or state.textUIActive ~= 'wrong' then
            if state.textUIActive then Bridge.HideTextUI() end
            Bridge.ShowTextUI(_L('carquest.delivery.wrong_vehicle'),"delivery")
            state.textUIActive = 'wrong'
        end
    end
end

function IsPlayerInDeliveryPoint()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local distance = #(playerCoords - Config.DeliveryPoint.coords)
    return distance <= Config.DeliveryPoint.radius
end

function GetPlayerVehicleInfo()
    local playerPed = PlayerPedId()
    if not IsPedInAnyVehicle(playerPed, false) then
        return nil, nil
    end
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if not DoesEntityExist(vehicle) then
        return nil, nil
    end
    local vehicleModel = GetEntityModel(vehicle)
    local vehicleModelName = string.lower(GetDisplayNameFromVehicleModel(vehicleModel))
    if vehicleModelName == "null" or vehicleModelName == "" then
        return nil, nil
    end
    return vehicle, vehicleModelName
end

function CheckVehicleForLists(vehicleModelName)
    if not vehicleModelName then return nil, nil, nil end
    local availableLists = {}
    for listName, listState in pairs(state.playerState) do
        if not Config.Lists[listName] then goto continue end
        local isFullyCompleted = listState.reward_collected
        if isFullyCompleted then
            local hasNewCars = false
            if not listState.delivered_cars then
                listState.delivered_cars = {}
            end
            for _, car in ipairs(Config.Lists[listName].cars) do
                if not listState.delivered_cars[car.model] then
                    hasNewCars = true
                    break
                end
            end
            if not hasNewCars then goto continue end
        end
        table.insert(availableLists, {
            name = listName,
            number = Config.Lists[listName].number,
            state = listState,
            rewardCollected = listState.reward_collected
        })
        ::continue::
    end
    table.sort(availableLists, function(a, b)
        if a.rewardCollected ~= b.rewardCollected then
            return not a.rewardCollected
        else
            return a.number < b.number
        end
    end)
    for _, list in ipairs(availableLists) do
        local listName = list.name
        local listConfig = Config.Lists[listName]
        local listState = list.state
        if not listState.delivered_cars then
            listState.delivered_cars = {}
        end
        for _, car in ipairs(listConfig.cars) do
            if listState.delivered_cars[car.model] then goto nextCar end
            if car.model == vehicleModelName then
                return listName, car.model, car.label
            end
            ::nextCar::
        end
    end
    return nil, nil, nil
end

function DeliverVehicle()
    if not state.securityToken then
        Bridge.Debug("Error: No security token available")
        Bridge.Notify(nil, _L('carquest.errors.token_error'), 'error', 'Error')
        TriggerServerEvent('anox-carquest:requestPlayerState') -- Request fresh state and token
        return
    end
    if not Security.checkCooldown('deliver', Config.Security.rateLimit.delivery) then
        Bridge.Notify(nil, _L('carquest.errors.please_wait_deliver'), 'error', 'Please wait')
        return
    end
    local vehicle, vehicleModelName = GetPlayerVehicleInfo()
    if not vehicle then
        Bridge.Notify(nil, _L('carquest.delivery.not_in_vehicle'), 'error', 'Error')
        return
    end
    local listName, carModel, carLabel = CheckVehicleForLists(vehicleModelName)
    if not listName or not carModel then
        Bridge.Notify(nil, _L('carquest.errors.wrong_vehicle'), 'error', 'Error')
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if Bridge.ProgressBar(_L('carquest.delivery.progress_label'), nil, "delivery") then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteVehicle(vehicle)
        TriggerServerEvent('anox-carquest:deliverCar', listName, carModel, netId, state.securityToken)
    end
end

RegisterCommand('anox_deliver_car', function()
    if IsPlayerInDeliveryPoint() and state.textUIActive == 'correct' then
        DeliverVehicle()
    end
end, false)

RegisterKeyMapping('anox_deliver_car', 'Deliver Car for Quest', 'keyboard', 'E')

RegisterNetEvent('anox-carquest:closeMenuOnly')
AddEventHandler('anox-carquest:closeMenuOnly', function()
    Bridge.HideContext()
end)

RegisterNetEvent('anox-carquest:setPlayerState')
AddEventHandler('anox-carquest:setPlayerState', function(playerState, securityToken, openMenu)
    if not playerState then
        Bridge.Debug("Error: Received empty player state")
        return
    end
    if not Security.verifyStateIntegrity(playerState) then
        Bridge.Debug("Warning: State integrity check failed")
    end
    state.playerState = playerState
    if securityToken then
        state.securityToken = securityToken
    end
    Bridge.Debug("Player state updated from server")
    if openMenu then
        OpenCarQuestMenu()
    end
end)

AddEventHandler('anox-carquest:playerLoaded', function()
    Wait(2000)
    TriggerServerEvent('anox-carquest:requestPlayerState')
    Bridge.Debug("Requested player state after player loaded")
end)

CreateThread(function()
    while true do
        Wait(60000)
        local currentTime = GetGameTimer()
        if (currentTime - lastStateUpdateTime) > 10000 then
            if not Security.verifyStateIntegrity(state.playerState) then
                Bridge.Debug("Periodic check: State integrity issue detected")
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if DoesEntityExist(state.npcPed) then
            DeleteEntity(state.npcPed)
        end
        if state.textUIActive then
            Bridge.HideTextUI()
        end
    end
end)