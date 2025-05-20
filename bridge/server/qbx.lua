
local Bridge = {}
local QBX = nil

function Bridge.Init()
    if QBX then return true end
    QBX = exports['qb-core']:GetCoreObject()
    if not QBX then
        return false
    end
    return true
end

function Bridge.RegisterEvents()
    AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
        Wait(1000)
        TriggerEvent('anox-carquest:playerLoaded', Player.PlayerData.source, Player)
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
    return QBX.Functions.GetPlayer(source)
end

function Bridge.GetPlayerFromIdentifier(identifier)
    if not identifier then return nil end
    return QBX.Functions.GetPlayerByCitizenId(identifier)
end

function Bridge.GetPlayers()
    return QBX.Functions.GetPlayers()
end

function Bridge.GetExtendedPlayers()
    local players = {}
    for _, v in pairs(QBX.Functions.GetQBPlayers()) do
        if v then
            table.insert(players, v)
        end
    end
    return players
end

function Bridge.GetIdentifier(player)
    if not player then return nil end
    return player.PlayerData.citizenid
end

function Bridge.AddMoney(player, account, amount)
    if not player or not account or not amount then return false end
    player.Functions.AddMoney(account, amount)
    return true
end

function Bridge.SetMetadata(player, key, value)
    if not player or not key then return false end
    player.Functions.SetMetaData(key, value)
    return true
end

function Bridge.GetMetadata(player, key)
    if not player or not key then return nil end
    return player.PlayerData.metadata[key]
end

function Bridge.RegisterServerCallback(name, cb)
    QBX.Functions.CreateCallback(name, cb)
end

function Bridge.HasPermission(player, permission)
    if not player then return false end
    local pData = player.PlayerData
    if permission == 'admin' then
        return pData.admin or QBX.Functions.HasPermission(pData.source, 'admin')
    elseif permission == 'mod' then
        return pData.admin or QBX.Functions.HasPermission(pData.source, 'mod') or QBX.Functions.HasPermission(pData.source, 'admin')
    elseif permission == 'superadmin' then
        return QBX.Functions.HasPermission(pData.source, 'god')
    end
    
    return false
end

return Bridge