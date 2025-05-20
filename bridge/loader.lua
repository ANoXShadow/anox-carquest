local Bridge = {}
local isClient = IsDuplicityVersion() == false

function Bridge.Debug(msg)
    if Config.Debug then
        print('^3[anox-carquest]^7 ' .. msg)
    end
end 

function Bridge.Load()
    local framework = string.lower(Config.Framework)
    local supportedFrameworks = {
        esx = true,
        qb = true,
        qbx = true,
    }
    if not supportedFrameworks[framework] then
        Bridge.Debug('^1Unsupported framework: ' .. framework)
        return nil
    end
    local bridgePath = isClient and 'bridge/client/' .. framework or 'bridge/server/' .. framework
    local success, frameworkBridge = pcall(function()
        return require(bridgePath)
    end)
    if success then
        if frameworkBridge and frameworkBridge.Init() then
            Bridge.Debug('^2Successfully loaded ' .. framework .. ' bridge for ' .. (isClient and 'client' or 'server'))
            if frameworkBridge.RegisterEvents then
                frameworkBridge.RegisterEvents()
            end
            return frameworkBridge
        else
            Bridge.Debug('^1Failed to initialize ' .. framework .. ' bridge for ' .. (isClient and 'client' or 'server'))
            return nil
        end
    else
        Bridge.Debug('^1Failed to load ' .. framework .. ' bridge for ' .. (isClient and 'client' or 'server') .. ': ' .. tostring(frameworkBridge))
        return nil
    end
end

local UIPresets = {
    notify = {
        default = {
            backgroundColor = '#4B2E2B',
            color = '#B86B4B',
            position = 'center-right',
            duration = 6000,
            icon = 'car'
        },
        error = {
            backgroundColor = '#4B2E2B',
            color = '#B86B4B',
            position = 'center-right',
            duration = 6000,
            icon = 'car'
        },
        success = {
            backgroundColor = '#4B2E2B',
            color = '#B86B4B',
            position = 'center-right',
            duration = 6000,
            icon = 'car'
        },
        info = {
            backgroundColor = '#4B2E2B',
            color = '#B86B4B',
            position = 'center-right',
            duration = 6000,
            icon = 'car'
        },
        warning = {
            backgroundColor = '#4B2E2B',
            color = '#B86B4B',
            position = 'center-right',
            duration = 6000,
            icon = 'car'
        }
    },
    progressBar = {
        default = {
            duration = 5000,
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = {
                car = true,
                move = true,
                combat = true
            }
        },
        delivery = {
            duration = 3000,
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = {
                car = true,
                move = true,
                combat = true
            }
        }
    },
    textUI = {
        default = {
            backgroundColor = 'rgba(0, 0, 0, 0.5)',
            color = '#F87171',
            icon = 'info',
            position = 'top-center'
        },
        delivery = {
            backgroundColor = '#4B2E2B',
            color = '#FFFFFF',
            icon = 'door-open',
            position = 'top-center'
        }
    },
    alertDialog = {
        default = {
            size = 'md',
            centered = true,
            cancel = true,
            confirmLabel = "Confirm",
            cancelLabel = "Cancel"
        }
    }
}

Bridge.Notify = function(source, message, styleKey, title)
    if Config.UISystem.Notify == 'ox' then
        local notifyType = styleKey or 'info'
        local notifyStyle = UIPresets.notify[notifyType] or UIPresets.notify.info
        local msgStr = tostring(message or "")
        local style = {
            backgroundColor = notifyStyle.backgroundColor or '#000000',
            color = notifyStyle.color or '#FFD700',
            borderRadius = 14,
            fontSize = '16px',
            fontWeight = 'bold',
            textAlign = 'left',
            padding = '14px 20px',
            border = '1px solid ' .. (notifyStyle.color or '#FFD700'),
            letterSpacing = '0.5px'
        }
        if not source then
            style.boxShadow = '0 0 12px rgba(96, 165, 250, 0.4)'
        end
        if source then
            TriggerClientEvent('ox_lib:notify', source, {
                title = title or 'Notification',
                description = msgStr,
                type = notifyType,
                icon = notifyStyle.icon,
                style = style,
                position = notifyStyle.position,
                duration = notifyStyle.duration
            })
        else
            lib.notify({
                title = title,
                description = msgStr, 
                type = notifyType,
                icon = notifyStyle.icon,
                style = style,
                position = notifyStyle.position,
                duration = notifyStyle.duration
            })
        end
    else
        if isClient then
            BeginTextCommandThefeedPost('STRING')
            AddTextComponentSubstringPlayerName(message)
            EndTextCommandThefeedPostTicker(false, false)
        else
            Bridge.Debug("NOTIFICATION: " .. message)
        end
    end
end


Bridge.ProgressBar = function(label, duration, style)
    if not isClient then return false end
    if Config.UISystem.ProgressBar == 'ox' then
        local progressStyle = style and UIPresets.progressBar[style] or UIPresets.progressBar.default
        local progressOptions = {
            duration = duration or progressStyle.duration or 5000,
            label = label,
            position = progressStyle.position,
            useWhileDead = progressStyle.useWhileDead,
            canCancel = progressStyle.canCancel,
            disable = progressStyle.disable
        }
        if progressStyle.anim then
            progressOptions.anim = progressStyle.anim
        end
        if progressStyle.prop then
            progressOptions.prop = progressStyle.prop
        end
        return lib.progressBar(progressOptions)
    else
        Citizen.Wait(duration or 5000)
        return true
    end
end

Bridge.ShowTextUI = function(message, style)
    if Config.UISystem.TextUI == 'ox' then
        local textUIStyle = style and UIPresets.textUI[style] or UIPresets.textUI.default
        lib.showTextUI(message, {
            position = textUIStyle.position,
            icon = textUIStyle.icon,
            style = {
                backgroundColor = textUIStyle.backgroundColor,
                color = textUIStyle.color,
                borderRadius = 6,
                border = '1px solid ' .. textUIStyle.color,
                fontSize = '15px',
                fontWeight = '600',
                padding = '6px 12px',
                letterSpacing = '0.5px',
            }
        })
    else
        -- 
    end
end

Bridge.HideTextUI = function()
    if not isClient then return end
    if Config.UISystem.TextUI == 'ox' then
        lib.hideTextUI()
    else
        -- 
    end
end

Bridge.AlertDialog = function(title, message, options)
    if not isClient then return 'confirm' end
    if Config.UISystem.AlertDialog == 'ox' then
        local style = options and options.style or 'default'
        local dialogStyle = UIPresets.alertDialog[style] or UIPresets.alertDialog.default
        return lib.alertDialog({
            header = title,
            content = message,
            size = options and options.size or dialogStyle.size,
            centered = options and options.centered ~= nil and options.centered or dialogStyle.centered,
            cancel = options and options.cancel ~= nil and options.cancel or dialogStyle.cancel,
            labels = {
                confirm = options and options.confirmLabel or dialogStyle.confirmLabel,
                cancel = options and options.cancelLabel or dialogStyle.cancelLabel
            }
        })
    else
        -- 
        return 'confirm'
    end
end

Bridge.RegisterContext = function(data)
    if not isClient then return end
    if Config.UISystem.Menu == 'ox' then
        return lib.registerContext(data)
    else
        -- 
        return false
    end
end

Bridge.ShowContext = function(id)
    if not isClient then return false end
    if Config.UISystem.Menu == 'ox' then
        lib.showContext(id)
        return true
    else
        -- 
        return false
    end
end

Bridge.HideContext = function()
    if not isClient then return false end
    
    if Config.UISystem.Menu == 'ox' then
        return lib.hideContext()
    else
        -- 
        return false
    end
end

Bridge.Target = {
    AddLocalEntity = function(entity, options)
        if not isClient then return end
        if Config.Target == 'ox' then
            exports.ox_target:addLocalEntity(entity, options)
        elseif Config.Target == 'qb' then
            local qbOptions = {}
            for _, opt in ipairs(options) do
                table.insert(qbOptions, {
                    type = opt.type or 'client',
                    event = opt.event,
                    icon = opt.icon,
                    label = opt.label,
                    canInteract = opt.canInteract,
                    job = opt.job,
                    action = opt.onSelect and function()
                        opt.onSelect()
                    end
                })
            end
            exports['qb-target']:AddTargetEntity(entity, {
                options = qbOptions,
                distance = 2.0
            })
        else
            Bridge.Debug('Target system not supported: ' .. tostring(Config.Target))
        end
    end
}

return Bridge