--[[------------------------>FOR ASSISTANCE,SCRIPTS AND MORE JOIN OUR DISCORD<-------------------------------------
 ________   ________    ________      ___    ___      ________   _________   ___  ___   ________   ___   ________     
|\   __  \ |\   ___  \ |\   __  \    |\  \  /  /|  ||  |\   ____\ |\___   ___\|\  \|\  \ |\   ___ \ |\  \ |\   __  \    
\ \  \|\  \\ \  \\ \  \\ \  \|\  \   \ \  \/  / /  ||  \ \  \___|_\|___ \  \_|\ \  \\\  \\ \  \_|\ \\ \  \\ \  \|\  \   
 \ \   __  \\ \  \\ \  \\ \  \\\  \   \ \    / /   ||   \ \_____  \    \ \  \  \ \  \\\  \\ \  \ \\ \\ \  \\ \  \\\  \  
  \ \  \ \  \\ \  \\ \  \\ \  \\\  \   /     \/    ||    \|____|\  \    \ \  \  \ \  \\\  \\ \  \_\\ \\ \  \\ \  \\\  \ 
   \ \__\ \__\\ \__\\ \__\\ \_______\ /  /\   \    ||      ____\_\  \    \ \__\  \ \_______\\ \_______\\ \__\\ \_______\
    \|__|\|__| \|__| \|__| \|_______|/__/ /\ __\   ||     |\_________\    \|__|   \|_______| \|_______| \|__| \|_______|
                                     |__|/ \|__|   ||     \|_________|                                                 
------------------------------------->(https://discord.gg/gbJ5SyBJBv)---------------------------------------------------]]                                                                                                 
Config = {}
Config.Debug = false-- Enable debug logs
Config.Framework = 'esx' -- 'esx', 'qb', 'qbx'
Config.Language = 'en' -- 'en'
Config.Target = 'ox' -- 'ox', 'qb'

Config.UISystem = {
    Notify = 'ox', -- 'ox'
    ProgressBar = 'ox', -- 'ox'
    TextUI = 'ox', -- 'ox'
    AlertDialog = 'ox', -- 'ox'
    Menu = 'ox', -- 'ox'
}

Config.Security = {
    rateLimit = {
        delivery = 5000,
        reward = 3000,
        menu = 1000,
    },
    maxReward = 100000,
    tokenTimeout = 1800,
}


Config.NPC = {
    model = "a_m_y_business_02",
    coords =  vector4(-817.09, 182.33, 72.27, 19.93),
    scenario = "WORLD_HUMAN_CLIPBOARD",
    blip = {
        enabled = true,
        sprite = 280,
        color = 3,
        scale = 0.8,
        label = "Car Quest NPC",
        shortRange = true
    }
}

Config.DeliveryPoint = {
    coords =  vector3(-813.26, 186.94, 72.46),
    radius = 5.0,
    blip = {
        enabled = false,
        sprite = 326,
        color = 5,
        scale = 0.8,
        label = "Car Delivery Point",
        shortRange = true
    }
}

Config.AdditionalRewardPercentage = 50 -- 50 = 50%

Config.Lists = {
    ListA = {
        number = 1, -- First list
        label = "Street Cars",
        reward = 1000,
        additionalRewardPercentage = 10,
        cars = {
            { model = "asea", label = "Asea" },
            { model = "blista", label = "Blista" },
            { model = "futo", label = "Futo" },
            { model = "penumbra", label = "Penumbra" },
            { model = "sultan", label = "Sultan" },
            { model = "sentinel", label = "Sentinel" },
        }
    },
    ListB = {
        number = 2, -- Unlocks after ListA
        label = "Bikes",
        reward = 2000,
        additionalRewardPercentage = 25,
        cars = {
            { model = "bati", label = "Bati 801" },
            { model = "akuma", label = "Akuma" },
            { model = "manchez", label = "Manchez" },
            { model = "double", label = "Double T" },
            { model = "vader", label = "Vader" },
            { model = "nemesis", label = "Nemesis" },
        }
    },
    ListC = {
        number = 3, -- Unlocks after ListB
        label = "Luxury Cars",
        reward = 3000,
        additionalRewardPercentage = 50,
        cars = {
            { model = "turismor", label = "Turismo R" },
            { model = "osiris", label = "Osiris" },
            { model = "reaper", label = "Reaper" },
            { model = "seven70", label = "Seven-70" },
            { model = "xa21", label = "XA-21" },
            { model = "ztype", label = "Z-Type" },
        }
    },
}