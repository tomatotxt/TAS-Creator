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
    print("[TAS] Loading: " .. Name)
    
    local success, result = pcall(function()
        return game:HttpGet(URL)
    end)
    
    if not success then 
        warn("[TAS] Failed to fetch " .. Name .. ": " .. tostring(result)) 
        return 
    end
    
    local func, err = loadstring(result)
    if not func then 
        warn("[TAS] Syntax Error in " .. Name .. ": " .. tostring(err)) 
        return 
    end
    
    self.Services[Name] = func(self)
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
TAS:LoadModule("Interface")
TAS:LoadModule("MapEngine")
TAS:LoadModule("Controller")

print("[TAS] All Modules Loaded Successfully")

return TAS
