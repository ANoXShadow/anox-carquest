local Bridge = {}
local ESX = nil

function Bridge.Init()
    if ESX then return true end
    ESX = exports['es_extended']:getSharedObject()
    if not ESX then
        return false
    end
    return true
end

function Bridge.RegisterEvents()
    AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
        Wait(1000)
        TriggerEvent('anox-carquest:playerLoaded', playerId, xPlayer)
    end)
    AddEventHandler('playerDropped', function()
        TriggerEvent('anox-carquest:playerDropped', source)
    end)
    AddEventHandler('onResourceStart', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            TriggerEvent('anox-carquest:resourceStart')
        end
    end)
end

function Bridge.GetPlayer(source)
    if not source or source <= 0 then return nil end
    return ESX.GetPlayerFromId(source)
end

function Bridge.GetPlayerFromIdentifier(identifier)
    if not identifier then return nil end
    return ESX.GetPlayerFromIdentifier(identifier)
end

function Bridge.GetPlayers()
    return ESX.GetPlayers()
end

function Bridge.GetExtendedPlayers()
    return ESX.GetExtendedPlayers()
end

function Bridge.GetIdentifier(player)
    if not player then return nil end
    return player.getIdentifier()
end

function Bridge.AddMoney(player, account, amount)
    if not player or not account or not amount then return false end
    player.addAccountMoney(account, amount)
    return true
end

function Bridge.SetMetadata(player, key, value)
    if not player or not key then return false end
    player.set(key, value)
    return true
end

function Bridge.GetMetadata(player, key)
    if not player or not key then return nil end
    return player.get(key)
end

function Bridge.RegisterServerCallback(name, cb)
    ESX.RegisterServerCallback(name, cb)
end

function Bridge.HasPermission(player, permission)
    if not player then return false end
    local group = player.getGroup()
    if permission == 'admin' then
        return group == 'admin' or group == 'superadmin'
    elseif permission == 'mod' then
        return group == 'mod' or group == 'admin' or group == 'superadmin'
    elseif permission == 'superadmin' then
        return group == 'superadmin'
    end
    return false
end

return Bridge