return function(TAS)
    local Serializer = {}
    local HttpService = game:GetService("HttpService")
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    
    local State = TAS.Services.State
    local PACK_FORMAT = "d" .. string.rep("f", 28) .. "s"

    -- // UTILITIES //
    function Serializer.GetUUID(part)
        if not part then return nil end
        local id = part:GetAttribute("TAS_UUID")
        if not id then
            id = HttpService:GenerateGUID(false)
            part:SetAttribute("TAS_UUID", id)
        end
        return id
    end

    function Serializer.IsRandomString(str)
        if #str == 0 then return false end
        for i = 1, #str do
            local ltr = str:sub(i, i)
            if ltr:lower() == ltr then return false end
        end
        return true
    end

    function Serializer.DeepCopy(orig)
        local copy = {}
        if type(orig) == 'table' then
            for k, v in pairs(orig) do copy[k] = v end
        else
            copy = orig
        end
        return copy
    end

    -- // PACKING //
    function Serializer.PackFrame(Time, Vel, CF, CamCF, Anim)
        local animName = Anim[1] or "idle"
        local animSpeed = Anim[2] or 0
        local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = CF:GetComponents()
        local cx, cy, cz, cR00, cR01, cR02, cR10, cR11, cR12, cR20, cR21, cR22 = CamCF:GetComponents()
        return string.pack(PACK_FORMAT, Time, Vel.X, Vel.Y, Vel.Z, x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22, cx, cy, cz, cR00, cR01, cR02, cR10, cR11, cR12, cR20, cR21, cR22, animSpeed, animName)
    end

    function Serializer.UnpackFrame(data)
        local t, vx, vy, vz, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, cm1, cm2, cm3, cm4, cm5, cm6, cm7, cm8, cm9, cm10, cm11, cm12, asp, anm = string.unpack(PACK_FORMAT, data)
        return {
            Time = t, Velocity = Vector3.new(vx, vy, vz),
            CFrame = CFrame.new(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12),
            CameraCFrame = CFrame.new(cm1, cm2, cm3, cm4, cm5, cm6, cm7, cm8, cm9, cm10, cm11, cm12),
            Animation = {anm, asp}
        }
    end
    
    function Serializer.GetPlayerCFrame()
        local Root = LocalPlayer.Character.HumanoidRootPart
        local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = Root.CFrame:GetComponents()
        return CFrame.new(x - State.MapX, y - State.MapY + 1000, z - State.MapZ, R00, R01, R02, R10, R11, R12, R20, R21, R22)
    end

    function Serializer.CaptureFrameData()
        return Serializer.PackFrame(
            tick() - State.RunStart - State.TimeOffset,
            LocalPlayer.Character.HumanoidRootPart.Velocity,
            Serializer.GetPlayerCFrame(),
            workspace.CurrentCamera.CFrame,
            State.CurrentAnim
        )
    end

    -- // FILE SAVING //
    function Serializer.SaveRun()
        local TAS_UI = TAS.Services.Interface
        
        local PressedCount = 0
        for _, data in pairs(State.ButtonRegistry) do if data.IsPressed then PressedCount = PressedCount + 1 end end
        if PressedCount < #State.TotalButtons then TAS_UI.SendAlert("Warning: Missing Buttons!", Color3.fromRGB(255, 255, 0)) end
        
        local function Round(n) return math.floor(n * 1000 + 0.5) / 1000 end
        local Export = {}
        
        local function ProcessFrameList(list)
            for j = 1, #list do
                local FramePacked = list[j]
                if type(FramePacked) == "string" then
                    local F = Serializer.UnpackFrame(FramePacked)
                    local Entry = {}
                    Entry.time = Round(F.Time)
                    Entry.AAnimation = F.Animation or {"walk", 0.1}
                    Entry.AAnimationChanged = F.Animation[2] 
                    Entry.VVelocity = {Round(F.Velocity.X), Round(F.Velocity.Y), Round(F.Velocity.Z)}
                    local rx, ry, rz = F.CFrame:ToEulerAnglesXYZ()
                    Entry.CCFrame = {Round(F.CFrame.X), Round(F.CFrame.Y), Round(F.CFrame.Z), Round(rx), Round(ry), Round(rz)}
                    local cx, cy, cz = F.CameraCFrame.X, F.CameraCFrame.Y, F.CameraCFrame.Z
                    local crx, cry, crz = F.CameraCFrame:ToEulerAnglesXYZ()
                    cx = cx - State.MapX
                    cy = cy - (State.MapY - 1000)
                    cz = cz - State.MapZ
                    Entry.CCameraCFrame = {Round(cx), Round(cy), Round(cz), Round(crx), Round(cry), Round(crz)}
                    table.insert(Export, Entry)
                end
            end
        end

        for i = 1, #State.Savestates do ProcessFrameList(State.Savestates[i]) end
        ProcessFrameList(State.Frames)
        
        if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
        local MapName = State.ClonedMap and State.ClonedMap.Settings:GetAttribute("MapName") or "Unknown"
        writefile("Flood-GUI/TAS FILES/" .. MapName .. ".json", HttpService:JSONEncode(Export))
        TAS_UI.SendAlert("Run Saved to Workspace", Color3.fromRGB(0, 255, 0))
    end

    return Serializer
end
