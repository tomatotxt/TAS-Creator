return function(TAS)
    local State = {
        -- Playback Flags
        IsPaused = true,
        EnvPaused = false,
        IsPreviewingForward = false,
        IsPreviewingBackward = false,
        IsAdvancingFrame = false,
        IsRewinding = false,
        IsViewingTAS = false,
        AutoSaved = false,
        AutoResetEnv = false,
        IsSwimming = false,

        -- Time & Frame Data
        TimeOffset = 0,
        PreviewOffset = 0,
        PauseStart = 0,
        RunStart = 0,
        RecordAccumulator = 0,
        TARGET_FPS = 60,
        RECORD_INTERVAL = 1/60,
        
        -- Data Stores
        CurrentAnim = {"idle", 0},
        Savestates = {},
        Frames = {},
        MapEvents = {},
        MapUUIDs = {},
        RecordedButtonSequence = {},
        OrderedButtonRegistry = {},
        ButtonRegistry = {},
        TotalButtons = {},
        WaterParts = {},
        
        -- Map & Physics
        SavedVelocity = Vector3.new(0,0,0),
        ClonedMap = nil,
        RopeTable = nil,
        MapOffset = CFrame.new(),
        MapX = 0, 
        MapY = 0, 
        MapZ = 0,
        
        -- Lighting
        SavedLighting = { Props = {}, Children = {} },
        LightingCaptured = false,
        
        -- Animation Hooks
        OriginalPlayAnim = nil,
        AnimEnv = nil
    }
    return State
end
