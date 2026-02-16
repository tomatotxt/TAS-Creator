--[[ 
    TAS Creator - Modular Loader 
    Entry Point
]]

getgenv().TAS_Active = true 

local TAS = {
    Services = {},
    Connections = {},
    BaseURL = "https://raw.githubusercontent.com/tomatotxt/TAS-Creator/refs/heads/main/Modules/"
}

function TAS:LoadModule(Name)
    local URL = self.BaseURL .. Name .. ".luau"
    print("[TAS] Fetching: " .. Name)
    
    local success, result = pcall(function()
        return game:HttpGet(URL)
    end)
    
    if not success then 
        warn("[TAS] NETWORK ERROR on " .. Name .. ": " .. tostring(result)) 
        return 
    end
    
    local func, err = loadstring(result)
    if not func then 
        warn("[TAS] SYNTAX ERROR in " .. Name .. ": " .. tostring(err)) 
        return 
    end
    
    local serviceSuccess, service = pcall(function() return func(self) end)
    if not serviceSuccess then
         warn("[TAS] RUNTIME ERROR in " .. Name .. ": " .. tostring(service))
         return
    end

    self.Services[Name] = service
    print("[TAS] Loaded Service: " .. Name)
end

function TAS:Cleanup()
    getgenv().TAS_Active = false
    for _, con in pairs(self.Connections) do
        if con then con:Disconnect() end
    end
    
    if self.Services.Interface and self.Services.Interface.Destroy then
        self.Services.Interface.Destroy()
    end
    
    if self.Services.MapEngine and self.Services.MapEngine.Cleanup then
        self.Services.MapEngine.Cleanup()
    end
    
    print("[TAS] System Unloaded")
end

-- // BOOT SEQUENCE //
TAS:LoadModule("State")
TAS:LoadModule("Serializer")
TAS:LoadModule("UI_API")
TAS:LoadModule("Interface")
TAS:LoadModule("MapEngine")
TAS:LoadModule("Controller") -- Controller triggers the logic

print("[TAS] Boot Complete. Check Game Screen for Alerts.")

return TAS
