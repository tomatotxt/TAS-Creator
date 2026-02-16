--[[ 
    TAS Creator - Modular Loader 
    Replicates original behavior 1:1
]]

getgenv().TAS_Active = true 

-- // BYPASSES (Must run first) //
local OldIndex
OldIndex = hookmetamethod(game, "__index", function(self, key)
    if not checkcaller() then
        if key == "Archivable" then return false end
        -- Swim Fix
        if getgenv().IsSwimming and key == "Position" and self.Name == "HumanoidRootPart" then
            return Vector3.new(-23, -153, 0)
        end
    end
    return OldIndex(self, key)
end)

-- Passkey
pcall(function() game:GetService("ReplicatedStorage").Remote.ReqPasskey:InvokeServer() end)

-- // MODULE LOADER //
local TAS = {
    Services = {},
    Connections = {},
    BaseURL = "https://raw.githubusercontent.com/tomatotxt/TAS-Creator/refs/heads/main/Modules/"
}

function TAS:LoadModule(Name)
    local URL = self.BaseURL .. Name .. ".luau"
    print("[TAS] Loading: " .. Name)
    
    local success, result = pcall(function() return game:HttpGet(URL) end)
    if not success then return warn("Failed to fetch " .. Name) end
    
    local func, err = loadstring(result)
    if not func then return warn("Syntax Error in " .. Name) end
    
    self.Services[Name] = func(self)
end

-- Load Order matters
TAS:LoadModule("State")
TAS:LoadModule("Serializer")
TAS:LoadModule("UI")
TAS:LoadModule("Core") -- Starts the script

print("TAS Creator: Smart .Changed Recorder Loaded (Modular)")

return TAS
