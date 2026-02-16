-- // Modules/Serializer.luau //
return function(TAS)
    local Serializer = {}
    local PACK_FORMAT = "d" .. string.rep("f", 28) .. "s"

    function Serializer.PackFrame(Time, Vel, CF, CamCF, Anim)
        -- (Your existing PackFrame logic here)
    end

    function Serializer.UnpackFrame(data)
        -- (Your existing UnpackFrame logic here)
    end

    return Serializer
end
