-- // Modules/State.luau //
return function(TAS)
    local State = {
        Savestates = {},
        Frames = {},
        IsPaused = true,
        TimeOffset = 0,
        RunStart = 0,
        MapEvents = {},
        ButtonRegistry = {},
        SavedVelocity = Vector3.zero,
        CurrentAnim = {"idle", 0}
    }
    return State
end
