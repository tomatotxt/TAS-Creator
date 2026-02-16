-- // Modules/MapEngine.luau //
return function(TAS)
    local MapEngine = {}
    local State = TAS.Services.State
    
    function MapEngine.SetupMap()
        -- (Your existing SetupMap logic)
        -- Instead of local variables, access State.MapEvents, etc.
    end

    function MapEngine.UpdateMapState(TargetTime)
        -- (Your existing UpdateMapState logic)
    end
    
    function MapEngine.SyncButtons(VisualTime, RealTime)
       -- (Your button logic)
    end

    function MapEngine.Cleanup()
        if State.ClonedMap then State.ClonedMap:Destroy() end
    end

    return MapEngine
end
