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
	SprintSyncRequestEvent = SprintEventsFolder:FindFirstChild("SprintSyncRequestEvent"), -- RemoteEvent: Client -> Server

	-- Checkpoint Remote Events
	CheckpointTouchedEvent = CheckpointEventsFolder:FindFirstChild("CheckpointTouchedEvent"), -- RemoteEvent: Client -> Server
	CheckpointSyncEvent = CheckpointEventsFolder:FindFirstChild("CheckpointSyncEvent"), -- RemoteEvent: Server -> Client
	ResetCheckpoints = CheckpointEventsFolder:FindFirstChild("ResetCheckpoints"), -- RemoteEvent: Client -> Server

	-- Race Remote Events
	RaceStartEvent = CheckpointEventsFolder:FindFirstChild("RaceStartEvent"), -- RemoteEvent: Server -> Client
	RaceEndEvent = CheckpointEventsFolder:FindFirstChild("RaceEndEvent"), -- RemoteEvent: Server -> Client
	LeaderboardUpdateEvent = CheckpointEventsFolder:FindFirstChild("LeaderboardUpdateEvent"), -- RemoteEvent: Server -> Client
	RaceNotificationEvent = CheckpointEventsFolder:FindFirstChild("RaceNotificationEvent"), -- RemoteEvent: Server -> Client
	RaceVoteEvent = CheckpointEventsFolder:FindFirstChild("RaceVoteEvent"), -- RemoteEvent: Client -> Server
	RaceQueueJoinEvent = CheckpointEventsFolder:FindFirstChild("RaceQueueJoinEvent"), -- RemoteEvent: Client -> Server
	RaceQueueLeaveEvent = CheckpointEventsFolder:FindFirstChild("RaceQueueLeaveEvent"), -- RemoteEvent: Client -> Server
	RaceQueueUpdateEvent = CheckpointEventsFolder:FindFirstChild("RaceQueueUpdateEvent"), -- RemoteEvent: Server -> Client

	-- Checkpoint Notification Events
	CheckpointSkipNotificationEvent = CheckpointEventsFolder:FindFirstChild("CheckpointSkipNotificationEvent"), -- RemoteEvent: Server -> Client
	CheckpointSuccessNotificationEvent = CheckpointEventsFolder:FindFirstChild("CheckpointSuccessNotificationEvent"), -- RemoteEvent: Server -> Client
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

if not RemoteEvents.RaceStartEvent then
	warn("[RemoteEvents] RaceStartEvent not found! Race system may not work properly.")
end

if not RemoteEvents.RaceEndEvent then
	warn("[RemoteEvents] RaceEndEvent not found! Race system may not work properly.")
end

if not RemoteEvents.LeaderboardUpdateEvent then
	warn("[RemoteEvents] LeaderboardUpdateEvent not found! Leaderboard may not work properly.")
end

if not RemoteEvents.RaceNotificationEvent then
	warn("[RemoteEvents] RaceNotificationEvent not found! Notifications may not work properly.")
end

if not RemoteEvents.RaceVoteEvent then
	warn("[RemoteEvents] RaceVoteEvent not found! Race voting may not work properly.")
end

if not RemoteEvents.RaceQueueJoinEvent then
	warn("[RemoteEvents] RaceQueueJoinEvent not found! Race queue joining may not work properly.")
end

if not RemoteEvents.RaceQueueLeaveEvent then
	warn("[RemoteEvents] RaceQueueLeaveEvent not found! Race queue leaving may not work properly.")
end

if not RemoteEvents.RaceQueueUpdateEvent then
	warn("[RemoteEvents] RaceQueueUpdateEvent not found! Race queue updates may not work properly.")
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

-- Server: Connect to sync request event
function RemoteEvents.OnSyncRequestReceived(callback)
	if not RemoteEvents.SprintSyncRequestEvent then
		warn("[RemoteEvents] Cannot connect to sync request event - SprintSyncRequestEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.SprintSyncRequestEvent.OnServerEvent:Connect(callback)
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

-- Server: Send race start to all clients
function RemoteEvents.BroadcastRaceStart(raceData)
	if not RemoteEvents.RaceStartEvent then
		warn("[RemoteEvents] Cannot broadcast race start - RaceStartEvent not found!")
		return
	end
	assert(typeof(raceData) == "table", "raceData must be table")
	RemoteEvents.RaceStartEvent:FireAllClients(raceData)
end

-- Server: Send race end to all clients
function RemoteEvents.BroadcastRaceEnd(raceResults)
	if not RemoteEvents.RaceEndEvent then
		warn("[RemoteEvents] Cannot broadcast race end - RaceEndEvent not found!")
		return
	end
	assert(typeof(raceResults) == "table", "raceResults must be table")
	RemoteEvents.RaceEndEvent:FireAllClients(raceResults)
end

-- Server: Send leaderboard update to all clients
function RemoteEvents.BroadcastLeaderboardUpdate(leaderboard)
	if not RemoteEvents.LeaderboardUpdateEvent then
		warn("[RemoteEvents] Cannot broadcast leaderboard - LeaderboardUpdateEvent not found!")
		return
	end
	assert(typeof(leaderboard) == "table", "leaderboard must be table")
	RemoteEvents.LeaderboardUpdateEvent:FireAllClients(leaderboard)
end

-- Server: Send race notification to specific client
function RemoteEvents.SendRaceNotification(player, notificationData)
	if not RemoteEvents.RaceNotificationEvent then
		warn("[RemoteEvents] Cannot send race notification - RaceNotificationEvent not found!")
		return
	end
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player must be Player instance")
	assert(typeof(notificationData) == "table", "notificationData must be table")
	RemoteEvents.RaceNotificationEvent:FireClient(player, notificationData)
end

-- Server: Send race notification to all clients
function RemoteEvents.BroadcastRaceNotification(notificationData)
	if not RemoteEvents.RaceNotificationEvent then
		warn("[RemoteEvents] Cannot broadcast race notification - RaceNotificationEvent not found!")
		return
	end
	assert(typeof(notificationData) == "table", "notificationData must be table")
	RemoteEvents.RaceNotificationEvent:FireAllClients(notificationData)
end

-- Client: Connect to race start event
function RemoteEvents.OnRaceStartReceived(callback)
	if not RemoteEvents.RaceStartEvent then
		warn("[RemoteEvents] Cannot connect to race start event - RaceStartEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.RaceStartEvent.OnClientEvent:Connect(callback)
end

-- Client: Connect to race end event
function RemoteEvents.OnRaceEndReceived(callback)
	if not RemoteEvents.RaceEndEvent then
		warn("[RemoteEvents] Cannot connect to race end event - RaceEndEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.RaceEndEvent.OnClientEvent:Connect(callback)
end

-- Client: Connect to leaderboard update event
function RemoteEvents.OnLeaderboardUpdateReceived(callback)
	if not RemoteEvents.LeaderboardUpdateEvent then
		warn("[RemoteEvents] Cannot connect to leaderboard update event - LeaderboardUpdateEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.LeaderboardUpdateEvent.OnClientEvent:Connect(callback)
end

-- Client: Connect to race notification event
function RemoteEvents.OnRaceNotificationReceived(callback)
	if not RemoteEvents.RaceNotificationEvent then
		warn("[RemoteEvents] Cannot connect to race notification event - RaceNotificationEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.RaceNotificationEvent.OnClientEvent:Connect(callback)
end

-- Client: Fire race vote to server
function RemoteEvents.FireRaceVote()
	if not RemoteEvents.RaceVoteEvent then
		warn("[RemoteEvents] Cannot fire race vote - RaceVoteEvent not found!")
		return
	end
	RemoteEvents.RaceVoteEvent:FireServer()
end

-- Server: Connect to race vote event
function RemoteEvents.OnRaceVoteReceived(callback)
	if not RemoteEvents.RaceVoteEvent then
		warn("[RemoteEvents] Cannot connect to race vote event - RaceVoteEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.RaceVoteEvent.OnServerEvent:Connect(callback)
end

-- Client: Fire race queue join to server
function RemoteEvents.FireRaceQueueJoin()
	if not RemoteEvents.RaceQueueJoinEvent then
		warn("[RemoteEvents] Cannot fire race queue join - RaceQueueJoinEvent not found!")
		return
	end
	RemoteEvents.RaceQueueJoinEvent:FireServer()
end

-- Client: Fire race queue leave to server
function RemoteEvents.FireRaceQueueLeave()
	if not RemoteEvents.RaceQueueLeaveEvent then
		warn("[RemoteEvents] Cannot fire race queue leave - RaceQueueLeaveEvent not found!")
		return
	end
	RemoteEvents.RaceQueueLeaveEvent:FireServer()
end

-- Server: Send race queue update to all clients
function RemoteEvents.BroadcastRaceQueueUpdate(queueData)
	if not RemoteEvents.RaceQueueUpdateEvent then
		warn("[RemoteEvents] Cannot broadcast race queue update - RaceQueueUpdateEvent not found!")
		return
	end
	assert(typeof(queueData) == "table", "queueData must be table")
	RemoteEvents.RaceQueueUpdateEvent:FireAllClients(queueData)
end

-- Client: Connect to race queue update event
function RemoteEvents.OnRaceQueueUpdateReceived(callback)
	if not RemoteEvents.RaceQueueUpdateEvent then
		warn("[RemoteEvents] Cannot connect to race queue update event - RaceQueueUpdateEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.RaceQueueUpdateEvent.OnClientEvent:Connect(callback)
end

-- Server: Connect to race queue join event
function RemoteEvents.OnRaceQueueJoinReceived(callback)
	if not RemoteEvents.RaceQueueJoinEvent then
		warn("[RemoteEvents] Cannot connect to race queue join event - RaceQueueJoinEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.RaceQueueJoinEvent.OnServerEvent:Connect(callback)
end

-- Server: Connect to race queue leave event
function RemoteEvents.OnRaceQueueLeaveReceived(callback)
	if not RemoteEvents.RaceQueueLeaveEvent then
		warn("[RemoteEvents] Cannot connect to race queue leave event - RaceQueueLeaveEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.RaceQueueLeaveEvent.OnServerEvent:Connect(callback)
end

-- Server: Send checkpoint skip notification to specific client
function RemoteEvents.SendCheckpointSkipNotification(player, message)
	if not RemoteEvents.CheckpointSkipNotificationEvent then
		warn("[RemoteEvents] Cannot send checkpoint skip notification - CheckpointSkipNotificationEvent not found!")
		return
	end
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player must be Player instance")
	assert(typeof(message) == "string", "message must be string")
	RemoteEvents.CheckpointSkipNotificationEvent:FireClient(player, message)
end

-- Server: Send checkpoint success notification to specific client
function RemoteEvents.SendCheckpointSuccessNotification(player, checkpointId)
	if not RemoteEvents.CheckpointSuccessNotificationEvent then
		warn("[RemoteEvents] Cannot send checkpoint success notification - CheckpointSuccessNotificationEvent not found!")
		return
	end
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player must be Player instance")
	assert(typeof(checkpointId) == "number", "checkpointId must be number")
	RemoteEvents.CheckpointSuccessNotificationEvent:FireClient(player, checkpointId)
end

-- Client: Connect to checkpoint skip notification event
function RemoteEvents.OnCheckpointSkipNotificationReceived(callback)
	if not RemoteEvents.CheckpointSkipNotificationEvent then
		warn("[RemoteEvents] Cannot connect to checkpoint skip notification event - CheckpointSkipNotificationEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.CheckpointSkipNotificationEvent.OnClientEvent:Connect(callback)
end

-- Client: Connect to checkpoint success notification event
function RemoteEvents.OnCheckpointSuccessNotificationReceived(callback)
	if not RemoteEvents.CheckpointSuccessNotificationEvent then
		warn("[RemoteEvents] Cannot connect to checkpoint success notification event - CheckpointSuccessNotificationEvent not found!")
		return function() end -- Return dummy function
	end
	assert(typeof(callback) == "function", "callback must be function")
	return RemoteEvents.CheckpointSuccessNotificationEvent.OnClientEvent:Connect(callback)
end

return RemoteEvents
