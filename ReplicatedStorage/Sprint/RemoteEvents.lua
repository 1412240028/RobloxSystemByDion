-- RemoteEvents.lua
-- Centralized remote management
-- Avoid hardcoded remote names & type-safe communication

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SprintFolder = ReplicatedStorage:WaitForChild("Sprint")
local EventsFolder = SprintFolder:WaitForChild("Events")

local RemoteEvents = {
    -- Remote Events (with fallback if not found)
    SprintToggleEvent = EventsFolder:FindFirstChild("SprintToggleEvent"), -- RemoteEvent: Client -> Server
    SprintSyncEvent = EventsFolder:FindFirstChild("SprintSyncEvent"), -- RemoteEvent: Server -> Client
}

-- Fallback warning if events not found
if not RemoteEvents.SprintToggleEvent then
    warn("[RemoteEvents] SprintToggleEvent not found! Sprint system may not work properly.")
end

if not RemoteEvents.SprintSyncEvent then
    warn("[RemoteEvents] SprintSyncEvent not found! Sprint system may not work properly.")
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

return RemoteEvents
