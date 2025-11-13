-- RemoteEvents.lua
-- Centralized remote management for multiple systems
-- Avoid hardcoded remote names & type-safe communication

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- System folders
local SprintFolder = ReplicatedStorage:WaitForChild("Sprint")
local SprintEventsFolder = SprintFolder:WaitForChild("RemoteEvents")

local CheckpointFolder = ReplicatedStorage:WaitForChild("Checkpoint")
local CheckpointEventsFolder = CheckpointFolder:WaitForChild("Remotes")

local RemoteEvents = {
    -- Sprint Remote Events
    SprintToggleEvent = SprintEventsFolder:FindFirstChild("SprintToggleEvent"), -- RemoteEvent: Client -> Server
    SprintSyncEvent = SprintEventsFolder:FindFirstChild("SprintSyncEvent"), -- RemoteEvent: Server -> Client

    -- Checkpoint Remote Events
    CheckpointTouchedEvent = CheckpointEventsFolder:FindFirstChild("CheckpointTouchedEvent"), -- RemoteEvent: Client -> Server
    CheckpointSyncEvent = CheckpointEventsFolder:FindFirstChild("CheckpointSyncEvent"), -- RemoteEvent: Server -> Client
    ResetCheckpoints = CheckpointEventsFolder:FindFirstChild("ResetCheckpoints"), -- RemoteEvent: Client -> Server
}

-- Fallback warning if events not found
if not RemoteEvents.SprintToggleEvent then
    warn("[RemoteEvents] SprintToggleEvent not found! Sprint system may not work properly.")
end

if not RemoteEvents.SprintSyncEvent then
    warn("[RemoteEvents] SprintSyncEvent not found! Sprint system may not work properly.")
end

if not RemoteEvents.CheckpointTouchedEvent then
    warn("[RemoteEvents] CheckpointTouchedEvent not found! Checkpoint system may not work properly.")
end

if not RemoteEvents.CheckpointSyncEvent then
    warn("[RemoteEvents] CheckpointSyncEvent not found! Checkpoint system may not work properly.")
end

if not RemoteEvents.ResetCheckpoints then
    warn("[RemoteEvents] ResetCheckpoints not found! Reset system may not work properly.")
end

-- Helper Functions

-- Client: Fire toggle request to server
function RemoteEvents.FireToggle(requestedState)
    if not RemoteEvents.SprintToggleEvent then
        warn("[RemoteEvents] Cannot fire toggle - SprintToggleEvent not found!")
        return
    end
    assert(typeof(requestedState) == "boolean", "requestedState must be boolean")
    RemoteEvents.SprintToggleEvent:FireServer(requestedState)
end

-- Server: Send sync data to specific client
function RemoteEvents.SendSync(player, syncData)
    if not RemoteEvents.SprintSyncEvent then
        warn("[RemoteEvents] Cannot send sync - SprintSyncEvent not found!")
        return
    end
    assert(typeof(player) == "Instance" and player:IsA("Player"), "player must be Player instance")
    assert(typeof(syncData) == "table", "syncData must be table")
    RemoteEvents.SprintSyncEvent:FireClient(player, syncData)
end

-- Server: Send sync to all clients (broadcast)
function RemoteEvents.BroadcastSync(syncData)
    if not RemoteEvents.SprintSyncEvent then
        warn("[RemoteEvents] Cannot broadcast sync - SprintSyncEvent not found!")
        return
    end
    assert(typeof(syncData) == "table", "syncData must be table")
    RemoteEvents.SprintSyncEvent:FireAllClients(syncData)
end

-- Client: Connect to sync event
function RemoteEvents.OnSyncReceived(callback)
    if not RemoteEvents.SprintSyncEvent then
        warn("[RemoteEvents] Cannot connect to sync event - SprintSyncEvent not found!")
        return function() end -- Return dummy function
    end
    assert(typeof(callback) == "function", "callback must be function")
    return RemoteEvents.SprintSyncEvent.OnClientEvent:Connect(callback)
end

-- Server: Connect to toggle event
function RemoteEvents.OnToggleRequested(callback)
    if not RemoteEvents.SprintToggleEvent then
        warn("[RemoteEvents] Cannot connect to toggle event - SprintToggleEvent not found!")
        return function() end -- Return dummy function
    end
    assert(typeof(callback) == "function", "callback must be function")
    return RemoteEvents.SprintToggleEvent.OnServerEvent:Connect(callback)
end

-- Client: Fire checkpoint touch to server
function RemoteEvents.FireCheckpointTouch(checkpointId)
    if not RemoteEvents.CheckpointTouchedEvent then
        warn("[RemoteEvents] Cannot fire checkpoint touch - CheckpointTouchedEvent not found!")
        return
    end
    assert(typeof(checkpointId) == "number", "checkpointId must be number")
    RemoteEvents.CheckpointTouchedEvent:FireServer(checkpointId)
end

-- Server: Send checkpoint sync to specific client
function RemoteEvents.SendCheckpointSync(player, syncData)
    if not RemoteEvents.CheckpointSyncEvent then
        warn("[RemoteEvents] Cannot send checkpoint sync - CheckpointSyncEvent not found!")
        return
    end
    assert(typeof(player) == "Instance" and player:IsA("Player"), "player must be Player instance")
    assert(typeof(syncData) == "table", "syncData must be table")
    RemoteEvents.CheckpointSyncEvent:FireClient(player, syncData)
end

-- Server: Send checkpoint sync to all clients (broadcast)
function RemoteEvents.BroadcastCheckpointSync(syncData)
    if not RemoteEvents.CheckpointSyncEvent then
        warn("[RemoteEvents] Cannot broadcast checkpoint sync - CheckpointSyncEvent not found!")
        return
    end
    assert(typeof(syncData) == "table", "syncData must be table")
    RemoteEvents.CheckpointSyncEvent:FireAllClients(syncData)
end

-- Client: Connect to checkpoint sync event
function RemoteEvents.OnCheckpointSyncReceived(callback)
    if not RemoteEvents.CheckpointSyncEvent then
        warn("[RemoteEvents] Cannot connect to checkpoint sync event - CheckpointSyncEvent not found!")
        return function() end -- Return dummy function
    end
    assert(typeof(callback) == "function", "callback must be function")
    return RemoteEvents.CheckpointSyncEvent.OnClientEvent:Connect(callback)
end

-- Server: Connect to checkpoint touched event
function RemoteEvents.OnCheckpointTouched(callback)
    if not RemoteEvents.CheckpointTouchedEvent then
        warn("[RemoteEvents] Cannot connect to checkpoint touched event - CheckpointTouchedEvent not found!")
        return function() end -- Return dummy function
    end
    assert(typeof(callback) == "function", "callback must be function")
    return RemoteEvents.CheckpointTouchedEvent.OnServerEvent:Connect(callback)
end

-- Client: Fire reset request to server
function RemoteEvents.FireReset()
    if not RemoteEvents.ResetCheckpoints then
        warn("[RemoteEvents] Cannot fire reset - ResetCheckpoints not found!")
        return
    end
    RemoteEvents.ResetCheckpoints:FireServer()
end

-- Server: Connect to reset event
function RemoteEvents.OnResetRequested(callback)
    if not RemoteEvents.ResetCheckpoints then
        warn("[RemoteEvents] Cannot connect to reset event - ResetCheckpoints not found!")
        return function() end -- Return dummy function
    end
    assert(typeof(callback) == "function", "callback must be function")
    return RemoteEvents.ResetCheckpoints.OnServerEvent:Connect(callback)
end

return RemoteEvents
