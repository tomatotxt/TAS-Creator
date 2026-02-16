return function(TAS)
    local State = {
        -- Configuration
        TARGET_FPS = 60,
        RECORD_INTERVAL = 1/60,
        
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
        
        -- Timing
        TimeOffset = 0,
        PreviewOffset = 0,
        PauseStart = 0,
        RunStart = nil, -- Starts as nil
        RecordAccumulator = 0,
        
        -- Data Containers
        Savestates = {},
        Frames = {},
        MapEvents = {},
        MapRecorderCache = {},
        
        -- Map & Physics
        ClonedMap = nil,
        RopeTable = nil,
        MapOffset = nil,
        MapPos = nil,
        MapX = 0, MapY = 0, MapZ = 0,
        MapUUIDs = {},
        WaterParts = {},
        SavedVelocity = Vector3.new(0, 0, 0),
        
        -- Button Logic
        RecordedButtonSequence = {},
        OrderedButtonRegistry = {},
        ButtonRegistry = {},
        TotalButtons = {},
        ButtonPressTimings = {},
        
        -- Lighting
        SavedLighting = { Props = {}, Children = {} },
        LightingCaptured = false,
        
        -- Animation
        CurrentAnim = {},
        OriginalPlayAnim = nil,
        AnimEnv = nil,
        LastTASAnim = nil,
        IsTASSliding = false,
        
        -- Loop Control
        PlaybackIndex = 1
    }
    return State
end
