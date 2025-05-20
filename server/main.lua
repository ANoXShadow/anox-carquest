local Bridge = require('bridge/loader')
local Framework = Bridge.Load()

local ADDITIONAL_REWARD_PERCENTAGE = Config.AdditionalRewardPercentage or 50

local RateLimits = {
    deliverCar = {},
    collectReward = {},
    tokens = {},
    stateRequests = {}
}

local SecurityTokens = {}
local PlayerStateCache = {}
local Security = {}

function Security.generatePlayerToken(identifier)
    return GetGameTimer() .. "_" .. string.gsub(identifier, ":", "_")
end

function Security.getPlayerSafely(source)
    if not source or source <= 0 then 
        Bridge.Debug("Security warning: Invalid source detected")
        return nil 
    end
    local xPlayer = Framework.GetPlayer(source)
    if not xPlayer then
        Bridge.Debug("Security warning: Failed to get player for source " .. source)
        return nil
    end
    return xPlayer
end

function ValidateReward(reward, source)
    local maxReward = 100000
    if Config.Security and Config.Security.maxReward then
        maxReward = Config.Security.maxReward
    end
    if reward < 0 or reward > maxReward then
        Bridge.Debug("Warning: Suspicious reward value " .. reward .. " for player " .. GetPlayerName(source))
        return math.min(math.max(0, reward), maxReward)
    end
    return reward
end

function CheckRateLimit(source, actionType)
    local xPlayer = Security.getPlayerSafely(source)
    if not xPlayer then return true end
    local identifier = Framework.GetIdentifier(xPlayer)
    local currentTime = GetGameTimer()
    local limitMs = Config.Security.rateLimit.delivery
    if actionType == "delivery" then
        limitMs = Config.Security.rateLimit.delivery
        if not RateLimits.deliverCar[identifier] then
            RateLimits.deliverCar[identifier] = 0
        end
        if (currentTime - RateLimits.deliverCar[identifier]) < limitMs then
            return true
        end
        RateLimits.deliverCar[identifier] = currentTime
    elseif actionType == "reward" then
        limitMs = Config.Security.rateLimit.reward
        if not RateLimits.collectReward[identifier] then
            RateLimits.collectReward[identifier] = 0
        end
        if (currentTime - RateLimits.collectReward[identifier]) < limitMs then
            return true
        end
        RateLimits.collectReward[identifier] = currentTime
    elseif actionType == "menu" then
        limitMs = Config.Security.rateLimit.menu
        if not RateLimits.tokens[identifier] then
            RateLimits.tokens[identifier] = 0
        end
        if (currentTime - RateLimits.tokens[identifier]) < limitMs then
            return true
        end
        RateLimits.tokens[identifier] = currentTime
    end
    return false
end

function VerifySecurityToken(source, token)
    local xPlayer = Security.getPlayerSafely(source)
    if not xPlayer then return false end
    local identifier = Framework.GetIdentifier(xPlayer)
    if not SecurityTokens[identifier] or SecurityTokens[identifier] ~= token then
        Bridge.Debug("Security warning: Invalid token from player " .. GetPlayerName(source))
        return false
    end
    if Config.Security.tokenTimeout then
        local tokenTime = tonumber(string.match(token, "^(%d+)_"))
        if tokenTime and (GetGameTimer() - tokenTime) > (Config.Security.tokenTimeout * 1000) then
            Bridge.Debug("Security warning: Token expired for player " .. GetPlayerName(source))
            SecurityTokens[identifier] = Security.generatePlayerToken(identifier)
            return false
        end
    end
    return true
end

Citizen.CreateThread(function()
    Wait(1000)
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `anox_carquest` (
            `identifier` VARCHAR(60) NOT NULL,
            `state` LONGTEXT NOT NULL,
            `last_updated` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        )
    ]], {}, function(rowsChanged)
        Bridge.Debug("Database table checked/created")
    end)
end)

AddEventHandler('anox-carquest:playerLoaded', function(playerId, xPlayer)
    Wait(1000)
    local identifier = Framework.GetIdentifier(xPlayer)
    SecurityTokens[identifier] = Security.generatePlayerToken(identifier)
    LoadPlayerStateFromDatabase(playerId, xPlayer)
end)

AddEventHandler('anox-carquest:resourceStart', function()
    Wait(3000)
    local players = Framework.GetExtendedPlayers()
    for _, xPlayer in ipairs(players) do
        local identifier = Framework.GetIdentifier(xPlayer)
        SecurityTokens[identifier] = Security.generatePlayerToken(identifier)
        local playerId = nil
        if xPlayer.PlayerData and xPlayer.PlayerData.source then
            playerId = xPlayer.PlayerData.source
        else
            playerId = xPlayer.source
        end
        LoadPlayerStateFromDatabase(playerId, xPlayer)
    end
    Bridge.Debug("Resource started, initialized all online players")
end)

function LoadPlayerStateFromDatabase(playerId, xPlayer)
    if not xPlayer then
        Bridge.Debug("Error: Attempted to load state for invalid player")
        return
    end
    local identifier = Framework.GetIdentifier(xPlayer)
    MySQL.Async.fetchAll('SELECT state FROM anox_carquest WHERE identifier = ?', {identifier}, function(result)
        local playerState = {}
        if result and result[1] and result[1].state then
            local success, decodedState = pcall(json.decode, result[1].state)
            if success and decodedState then
                playerState = decodedState
                Bridge.Debug("Loaded existing state for player: " .. GetPlayerName(playerId))
            else
                Bridge.Debug("Error: Failed to decode state for player: " .. GetPlayerName(playerId))
                playerState = CreateInitialState()
            end
            UpdatePlayerState(playerId, xPlayer, playerState)
        else
            playerState = CreateInitialState()
            SavePlayerStateToDatabase(identifier, playerState)
            Bridge.Debug("Created new state for player: " .. GetPlayerName(playerId))
        end
        PlayerStateCache[identifier] = playerState
        TriggerClientEvent('anox-carquest:setPlayerState', playerId, playerState, SecurityTokens[identifier])
    end)
end

function CreateInitialState()
    local initialState = {}
    for listName, listData in pairs(Config.Lists) do
        if listData.number == 1 then
            initialState[listName] = {
                delivered_cars = {},
                completed = false,
                reward_collected = false
            }
            break
        end
    end
    return initialState
end

function SavePlayerStateToDatabase(identifier, state)
    if not identifier or type(identifier) ~= "string" or identifier == "" then
        Bridge.Debug("Error: Invalid identifier for SavePlayerStateToDatabase")
        return false
    end
    if not state or type(state) ~= "table" then
        Bridge.Debug("Error: Invalid state for SavePlayerStateToDatabase")
        return false
    end
    local success, encodedState = pcall(json.encode, state)
    if not success or not encodedState then
        Bridge.Debug("Error: Failed to encode state for: " .. identifier)
        return false
    end
    PlayerStateCache[identifier] = state
    MySQL.Async.execute('INSERT INTO anox_carquest (identifier, state) VALUES (?, ?) ON DUPLICATE KEY UPDATE state = ?', {
        identifier,
        encodedState,
        encodedState
    }, function(rowsChanged)
        if rowsChanged <= 0 then
            Bridge.Debug("ERROR: Failed to save state to database for: " .. identifier)
        end
    end)
    return true
end

function HandleNewCarsInList(source, xPlayer, listName, state)
    if not state[listName] or not Config.Lists[listName] then return state end
    if not state[listName].reward_collected then return state end
    if not state[listName].delivered_cars then
        state[listName].delivered_cars = {}
    end
    local hasNewCars = false
    for _, car in ipairs(Config.Lists[listName].cars) do
        if not state[listName].delivered_cars[car.model] then
            hasNewCars = true
            break
        end
    end
    if hasNewCars and state[listName].completed then
        state[listName].completed = false
        Bridge.Debug("Reset completed flag for list " .. listName .. " to allow access to new cars")
    end
    return state
end

function CheckForNewCars(source, xPlayer)
    if not xPlayer then return {} end
    local identifier = Framework.GetIdentifier(xPlayer)
    local state = PlayerStateCache[identifier] or {}
    local changed = false
    for listName, _ in pairs(state) do
        local oldState = json.encode(state[listName] or {})
        state = HandleNewCarsInList(source, xPlayer, listName, state)
        if json.encode(state[listName] or {}) ~= oldState then
            changed = true
        end
    end
    if changed then
        PlayerStateCache[identifier] = state
        SavePlayerStateToDatabase(identifier, state)
        TriggerClientEvent('anox-carquest:setPlayerState', source, state, SecurityTokens[identifier])
    end
    return state
end

function UpdatePlayerState(playerId, xPlayer, currentState)
    if not playerId or not xPlayer or not currentState or type(currentState) ~= "table" then
        Bridge.Debug("Error: Invalid parameters for UpdatePlayerState")
        return currentState
    end
    local stateChanged = false
    local highestCompletedNumber = 0
    for listName, listData in pairs(currentState) do
        if Config.Lists[listName] and listData.reward_collected then
            local listNumber = Config.Lists[listName].number
            if listNumber > highestCompletedNumber then
                highestCompletedNumber = listNumber
            end
        end
    end
    for listName, listData in pairs(currentState) do
        if not Config.Lists[listName] then goto continue_update end
        if not listData.delivered_cars then
            currentState[listName].delivered_cars = {}
            stateChanged = true
        end
        local hasNewCars = false
        if listData.reward_collected then
            for _, car in ipairs(Config.Lists[listName].cars) do
                if not currentState[listName].delivered_cars[car.model] then
                    hasNewCars = true
                    break
                end
            end
            if hasNewCars and listData.completed then
                currentState[listName].completed = false
                stateChanged = true
                Bridge.Debug("Reset completion status for list " .. listName .. " due to new cars")
            end
        end
        ::continue_update::
    end
    for listName, listConfig in pairs(Config.Lists) do
        if currentState[listName] then goto continue_unlock end
        local shouldUnlock = false
        if listConfig.number == 1 then
            shouldUnlock = true
        elseif listConfig.number == highestCompletedNumber + 1 then
            shouldUnlock = true
        else
            local allPreviousCompleted = true
            for otherListName, otherListConfig in pairs(Config.Lists) do
                if otherListConfig.number < listConfig.number then
                    local playerHasList = currentState[otherListName] ~= nil
                    local listCompleted = playerHasList and currentState[otherListName].reward_collected
                    if not listCompleted then
                        allPreviousCompleted = false
                        break
                    end
                end
            end
            if allPreviousCompleted then
                shouldUnlock = true
            end
        end
        if shouldUnlock then
            currentState[listName] = {
                delivered_cars = {},
                completed = false,
                reward_collected = false
            }
            stateChanged = true
            Bridge.Debug("Unlocked new list " .. listName .. " for player: " .. GetPlayerName(playerId))
        end
        ::continue_unlock::
    end
    if stateChanged then
        local identifier = Framework.GetIdentifier(xPlayer)
        PlayerStateCache[identifier] = currentState
        SavePlayerStateToDatabase(identifier, currentState)
        TriggerClientEvent('anox-carquest:setPlayerState', playerId, currentState, SecurityTokens[identifier])
    end
    return currentState
end

Framework.RegisterServerCallback('anox-carquest:getPlayerState', function(source, cb)
    local xPlayer = Security.getPlayerSafely(source)
    if not xPlayer then return cb({}, nil) end
    local identifier = Framework.GetIdentifier(xPlayer)
    if PlayerStateCache[identifier] then
        return cb(PlayerStateCache[identifier], SecurityTokens[identifier])
    end
    MySQL.Async.fetchAll('SELECT state FROM anox_carquest WHERE identifier = ?', {identifier}, function(result)
        local playerState = {}
        if result and result[1] and result[1].state then
            local success, decodedState = pcall(json.decode, result[1].state)
            if success and decodedState then
                playerState = decodedState
            else
                Bridge.Debug("Error: Failed to decode state from database for: " .. identifier)
                playerState = CreateInitialState()
            end
            PlayerStateCache[identifier] = playerState
            cb(playerState, SecurityTokens[identifier])
        else
            playerState = CreateInitialState()
            PlayerStateCache[identifier] = playerState
            SavePlayerStateToDatabase(identifier, playerState)
            cb(playerState, SecurityTokens[identifier])
        end
    end)
end)

RegisterNetEvent('anox-carquest:requestPlayerState')
AddEventHandler('anox-carquest:requestPlayerState', function(openMenu)
    local source = source
    local xPlayer = Security.getPlayerSafely(source)
    if not xPlayer then return end
    local identifier = Framework.GetIdentifier(xPlayer)
    local currentTime = GetGameTimer()
    if not RateLimits.stateRequests[identifier] then
        RateLimits.stateRequests[identifier] = 0
    end
    if (currentTime - RateLimits.stateRequests[identifier]) < 3000 then
        if PlayerStateCache[identifier] then
            TriggerClientEvent('anox-carquest:setPlayerState', source, PlayerStateCache[identifier], SecurityTokens[identifier], openMenu)
        end
        return
    end
    RateLimits.stateRequests[identifier] = currentTime
    if openMenu then
        if RateLimits.tokens[identifier] and (currentTime - RateLimits.tokens[identifier]) < Config.Security.rateLimit.menu then
            if PlayerStateCache[identifier] then
                TriggerClientEvent('anox-carquest:setPlayerState', source, PlayerStateCache[identifier], SecurityTokens[identifier], false)
                Bridge.Notify(source, _L('carquest.errors.please_wait_menu'), 'error')
            end
            return
        end
        RateLimits.tokens[identifier] = currentTime
    end
    if PlayerStateCache[identifier] then
        TriggerClientEvent('anox-carquest:setPlayerState', source, PlayerStateCache[identifier], SecurityTokens[identifier], openMenu)
        return
    end
    MySQL.Async.fetchAll('SELECT state FROM anox_carquest WHERE identifier = ?', {identifier}, function(result)
        local playerState = {}
        if result and result[1] and result[1].state then
            local success, decodedState = pcall(json.decode, result[1].state)
            if success and decodedState then
                playerState = decodedState
            else
                Bridge.Debug("Error: Failed to decode state from database for: " .. identifier)
                playerState = CreateInitialState()
            end
            PlayerStateCache[identifier] = playerState
            TriggerClientEvent('anox-carquest:setPlayerState', source, playerState, SecurityTokens[identifier], openMenu)
        else
            playerState = CreateInitialState()
            PlayerStateCache[identifier] = playerState
            SavePlayerStateToDatabase(identifier, playerState)
            TriggerClientEvent('anox-carquest:setPlayerState', source, playerState, SecurityTokens[identifier], openMenu)
        end
    end)
end)

AddEventHandler('anox-carquest:playerDropped', function(source)
    local xPlayer = Framework.GetPlayer(source)
    if xPlayer then
        local identifier = Framework.GetIdentifier(xPlayer)
        RateLimits.deliverCar[identifier] = nil
        RateLimits.collectReward[identifier] = nil
        RateLimits.tokens[identifier] = nil
        RateLimits.stateRequests[identifier] = nil
        SecurityTokens[identifier] = nil
    end
end)


RegisterNetEvent('anox-carquest:deliverCar')
AddEventHandler('anox-carquest:deliverCar', function(listName, carModel, netId, securityToken)
    local source = source
    local xPlayer = Security.getPlayerSafely(source)
    if not xPlayer then return end
    if not VerifySecurityToken(source, securityToken) then
        Bridge.Debug("Security warning: Token mismatch on deliverCar from " .. GetPlayerName(source))
        return
    end
    if CheckRateLimit(source, "delivery") then
        Bridge.Notify(source, _L('carquest.errors.please_wait_deliver'), 'error')
        return
    end
    if not Config.Lists[listName] or not netId then
        Bridge.Debug("Invalid delivery attempt from: " .. GetPlayerName(source))
        return
    end
    local identifier = Framework.GetIdentifier(xPlayer)
    local state = PlayerStateCache[identifier] or {}
    if not state[listName] then
        Bridge.Notify(source, _L('carquest.errors.no_access'), 'error')
        return
    end
    local carIsValid = false
    local carLabel = ""
    for _, car in ipairs(Config.Lists[listName].cars) do
        if car.model == carModel then
            carIsValid = true
            carLabel = car.label
            break
        end
    end
    if not carIsValid then
        Bridge.Notify(source, _L('carquest.errors.wrong_vehicle'), 'error')
        return
    end
    if not state[listName].delivered_cars then
        state[listName].delivered_cars = {}
    end
    if state[listName].delivered_cars[carModel] then
        Bridge.Notify(source, _L('carquest.errors.already_delivered'), 'error')
        return
    end
    state[listName].delivered_cars[carModel] = true
    local allDelivered = true
    for _, car in ipairs(Config.Lists[listName].cars) do
        if not state[listName].delivered_cars[car.model] then
            allDelivered = false
            break
        end
    end
    if allDelivered then
        state[listName].completed = true
    end
    local isAdditionalCar = state[listName].reward_collected
    PlayerStateCache[identifier] = state
    SavePlayerStateToDatabase(identifier, state)
    if isAdditionalCar then
        Bridge.Notify(source, _L('carquest.delivery.additional_delivered'), 'success')
    else
        Bridge.Notify(source, _L('carquest.delivery.delivered'), 'success')
    end
    if allDelivered and isAdditionalCar then
        local rewardPercentage = Config.Lists[listName].additionalRewardPercentage or Config.AdditionalRewardPercentage
        local additionalReward = math.floor(Config.Lists[listName].reward * (rewardPercentage / 100))
        additionalReward = ValidateReward(additionalReward, source)
        Framework.AddMoney(xPlayer, 'bank', additionalReward)
        Bridge.Notify(source, 
            _L('carquest.reward.additional', additionalReward), 
            'success')
        Bridge.Debug("Auto-rewarded $" .. additionalReward .. " for additional cars to player " .. GetPlayerName(source))
        state[listName].completed = false
        PlayerStateCache[identifier] = state
        SavePlayerStateToDatabase(identifier, state)
    elseif allDelivered and not isAdditionalCar then
        Bridge.Notify(source, _L('carquest.delivery.all_delivered'), 'success')
    end
    TriggerClientEvent('anox-carquest:setPlayerState', source, state, SecurityTokens[identifier])
end)

RegisterNetEvent('anox-carquest:collectReward')
AddEventHandler('anox-carquest:collectReward', function(listName, isAdditional, securityToken)
    local source = source
    local xPlayer = Security.getPlayerSafely(source)
    if not xPlayer then return end
    if not VerifySecurityToken(source, securityToken) then
        Bridge.Debug("Security warning: Token mismatch on collectReward from " .. GetPlayerName(source))
        return
    end
    if CheckRateLimit(source, "reward") then
        Bridge.Notify(source, _L('carquest.errors.please_wait_reward'), 'error')
        return
    end
    if not Config.Lists[listName] then
        Bridge.Notify(source, _L('carquest.errors.list_not_found'), 'error')
        return
    end
    local identifier = Framework.GetIdentifier(xPlayer)
    local state = PlayerStateCache[identifier] or {}
    if not state[listName] then
        Bridge.Notify(source, _L('carquest.errors.no_access'), 'error')
        return
    end
    if not state[listName].delivered_cars then
        state[listName].delivered_cars = {}
    end
    local allDelivered = true
    for _, car in ipairs(Config.Lists[listName].cars) do
        if not state[listName].delivered_cars[car.model] then
            allDelivered = false
            break
        end
    end
    if not allDelivered then
        Bridge.Notify(source, _L('carquest.errors.all_cars_required'), 'error')
        return
    end
    if not state[listName].completed then
        Bridge.Notify(source, _L('carquest.errors.not_completed'), 'error')
        return
    end
    if state[listName].reward_collected then
        Bridge.Notify(source, _L('carquest.errors.already_collected'), 'error')
        return
    end
    local reward = Config.Lists[listName].reward
    reward = ValidateReward(reward, source)
    Framework.AddMoney(xPlayer, 'bank', reward)
    state[listName].reward_collected = true
    PlayerStateCache[identifier] = state
    SavePlayerStateToDatabase(identifier, state)
    Bridge.Notify(source, 
        _L('carquest.reward.collected', reward), 
        'success')
    Wait(500)
    state = UpdatePlayerState(source, xPlayer, state)
    TriggerClientEvent('anox-carquest:closeMenuOnly', source)
    Wait(1000)
    TriggerClientEvent('anox-carquest:setPlayerState', source, state, SecurityTokens[identifier])
    CheckForNewCars(source, xPlayer)
end)

RegisterCommand('carquest_reset', function(source, args)
    if source ~= 0 then
        local xPlayer = Security.getPlayerSafely(source)
        if not xPlayer or not Framework.HasPermission(xPlayer, 'admin') then
            Bridge.Notify(source, _L('carquest.admin.no_permission'), 'error')
            return
        end
    end
    local targetId = tonumber(args[1])
    if not targetId then
        if source == 0 then
            Bridge.Debug("" .. _L('carquest.admin.reset_command_usage'))
        else
            Bridge.Notify(source, _L('carquest.admin.reset_command_usage'), 'error')
        end
        return
    end
    local targetPlayer = Framework.GetPlayer(targetId)
    if not targetPlayer then
        if source == 0 then
            Bridge.Debug("" .. _L('carquest.admin.player_not_found', targetId))
        else
            Bridge.Notify(source, _L('carquest.admin.player_not_found', targetId), 'error')
        end
        return
    end
    ResetPlayerState(targetId, targetPlayer)
    if source == 0 then
        Bridge.Debug("" .. _L('carquest.admin.reset_success', GetPlayerName(targetId)) .. " by console")
    else
        Bridge.Debug("" .. _L('carquest.admin.reset_success', GetPlayerName(targetId)) .. " by admin " .. GetPlayerName(source))
        Bridge.Notify(source, _L('carquest.admin.reset_success', GetPlayerName(targetId)), 'success')
    end
end, true)

function ResetPlayerState(playerId, xPlayer)
    if not playerId or not xPlayer then
        Bridge.Debug("Error: Invalid parameters for ResetPlayerState")
        return
    end
    local newState = CreateInitialState()
    local identifier = Framework.GetIdentifier(xPlayer)
    SecurityTokens[identifier] = Security.generatePlayerToken(identifier)
    PlayerStateCache[identifier] = newState
    SavePlayerStateToDatabase(identifier, newState)
    Bridge.Notify(playerId, 
        _L('carquest.admin.reset_notification'), 
        'info')
    TriggerClientEvent('anox-carquest:setPlayerState', playerId, newState, SecurityTokens[identifier])
    Bridge.Debug("Reset car quest progress for player: " .. GetPlayerName(playerId))
end

AddEventHandler('anox-carquest:playerDropped', function(source)
    local xPlayer = Framework.GetPlayer(source)
    if xPlayer then
        local identifier = Framework.GetIdentifier(xPlayer)
        RateLimits.deliverCar[identifier] = nil
        RateLimits.collectReward[identifier] = nil
        RateLimits.tokens[identifier] = nil
        RateLimits.stateRequests[identifier] = nil
        SecurityTokens[identifier] = nil
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(300000)
        local statesSaved = 0
        for identifier, state in pairs(PlayerStateCache) do
            local xPlayer = Framework.GetPlayerFromIdentifier(identifier)
            if xPlayer then
                SavePlayerStateToDatabase(identifier, state)
                statesSaved = statesSaved + 1
            end
        end
        if statesSaved > 0 then
            Bridge.Debug("Periodic sync: Saved " .. statesSaved .. " player states to database")
        end
    end
end)