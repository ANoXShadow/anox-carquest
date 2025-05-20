
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
    RegisterNetEvent('esx:playerLoaded')
    AddEventHandler('esx:playerLoaded', function(xPlayer)
        Wait(2000)
        TriggerEvent('anox-carquest:playerLoaded', xPlayer)
    end)
end

function Bridge.TriggerServerCallback(name, cb, ...)
    ESX.TriggerServerCallback(name, cb, ...)
end

return Bridge