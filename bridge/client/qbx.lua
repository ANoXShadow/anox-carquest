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
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded')
    AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
        Wait(2000)
        TriggerEvent('anox-carquest:playerLoaded', QBX.Functions.GetPlayerData())
    end)
end

function Bridge.TriggerServerCallback(name, cb, ...)
    QBX.Functions.TriggerCallback(name, cb, ...)
end

return Bridge