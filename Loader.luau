--[[ 
    TAS Creator - Modular Loader 
    FIXED: Forces Core Initialization
]]

getgenv().TAS_Active = true 

-- // 1. BYPASSES //
local OldIndex
OldIndex = hookmetamethod(game, "__index", function(self, key)
    if not checkcaller() then
        if key == "Archivable" then return false end
        if getgenv().IsSwimming and key == "Position" and self.Name == "HumanoidRootPart" then
            return Vector3.new(-23, -153, 0)
        end
    end
    return OldIndex(self, key)
end)

pcall(function() game:GetService("ReplicatedStorage").Remote.ReqPasskey:InvokeServer() end)

-- // 2. MODULE SYSTEM //
local TAS = {
    Services = {},
    BaseURL = "https://raw.githubusercontent.com/tomatotxt/TAS-Creator/refs/heads/main/Modules/"
}

function TAS:LoadModule(Name)
    local URL = self.BaseURL .. Name .. ".luau"
    print("[TAS] Fetching: " .. Name)
    local s, r = pcall(function() return game:HttpGet(URL) end)
    if not s then return warn("FAILED TO LOAD: " .. Name) end
    local f, e = loadstring(r)
    if not f then return warn("SYNTAX ERROR: " .. Name .. " | " .. tostring(e)) end
    self.Services[Name] = f(self)
    print("[TAS] Loaded: " .. Name)
end

-- // 3. LOAD ORDER //
TAS:LoadModule("State")
TAS:LoadModule("Serializer")
TAS:LoadModule("UI")
TAS:LoadModule("Core")

-- // 4. FORCE START //
if TAS.Services.Core and TAS.Services.Core.Init then
    print("[TAS] Starting Core Engine...")
    task.spawn(TAS.Services.Core.Init)
else
    warn("[TAS] Core Module failed to load properly!")
end

return TAS
