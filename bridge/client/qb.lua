local Bridge = {}
local QBCore = nil

function Bridge.Init()
    if QBCore then return true end
    QBCore = exports['qb-core']:GetCoreObject()
    if not QBCore then
        return false
    end
    return true
end

function Bridge.RegisterEvents()
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded')
    AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
        Wait(2000)
        TriggerEvent('anox-carquest:playerLoaded', QBCore.Functions.GetPlayerData())
    end)
end

function Bridge.TriggerServerCallback(name, cb, ...)
    QBCore.Functions.TriggerCallback(name, cb, ...)
end

return Bridge