-- // Loader.luau //
getgenv().TAS_Active = true

-- Define the Central Hub
local TAS = {
    Services = {},
    Events = {},
    Connections = {} -- centralized cleanup
}

-- Helper to load modules (Supports URL or Local)
local function LoadModule(name, url)
    print("Loading Service:", name)
    -- In production, use game:HttpGet(url)
    -- For testing, you might paste the module code string here
    local content = game:HttpGet(url) 
    local func = loadstring(content)
    
    -- Inject the TAS hub into the module
    TAS.Services[name] = func(TAS) 
end

-- // 1. Load Utilities & State First //
LoadModule("State", "https://.../State.luau")
LoadModule("Serializer", "https://.../Serializer.luau")

-- // 2. Load Logic Systems //
LoadModule("MapEngine", "https://.../MapEngine.luau")
LoadModule("Interface", "https://.../Interface.luau")

-- // 3. Load Controller (Starts the loops) //
LoadModule("Controller", "https://.../Controller.luau")

print("TAS Modular System Loaded")

-- Global Cleanup Function
TAS.Unload = function()
    getgenv().TAS_Active = false
    for _, con in pairs(TAS.Connections) do con:Disconnect() end
    TAS.Services.Interface.Destroy()
    TAS.Services.MapEngine.Cleanup()
    print("TAS Unloaded")
end

return TAS
