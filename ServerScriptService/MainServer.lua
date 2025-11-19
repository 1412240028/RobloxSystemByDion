-- MainServer.lua (FIXED VERSION)
-- ✅ FIXED: Checkpoint reset now works properly
-- ✅ FIXED: Checkpoint colors reset to RED
-- ✅ FIXED: Proper sync to client after reset

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local SharedTypes = require(ReplicatedStorage.Modules.SharedTypes)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local DataManager = require(ReplicatedStorage.Modules.DataManager)
local RaceController = require(ReplicatedStorage.Modules.RaceController)
local SystemManager = require(ReplicatedStorage.Modules.SystemManager)

local MainServer = {}

-- Private variables
local activePlayers = {}
local heartbeatConnection = nil
local Checkpoints = workspace:WaitForChild("Checkpoints")
local playerTouchedCheckpoints = {}
local checkpointDebounce = {}
local playerConnections = {}
local autoSaveConnection = nil
local lastAutoSaveTime = 0

-- ✨ Checkpoint color configurations
local CHECKPOINT_COLORS = {
	UNTOUCHED = Color3.fromRGB(255, 0, 0),    -- Red
	TOUCHED = Color3.fromRGB(0, 255, 0),      -- Green
	RACING = Color3.fromRGB(255, 215, 0)      -- Gold (during race)
}

-- Initialize server
function MainServer.Init()
	print("[MainServer] Initializing Unified System v1.5 (Ring Checkpoints)")

	Players.PlayerAdded:Connect(MainServer.OnPlayerAdded)
	Players.PlayerRemoving:Connect(MainServer.OnPlayerRemoving)

	RemoteEvents.OnToggleRequested(MainServer.OnSprintToggleRequested)
	RemoteEvents.OnResetRequested(MainServer.ResetPlayerCheckpoints)
	RemoteEvents.OnRaceQueueJoinReceived(MainServer.OnRaceQueueJoin)
	RemoteEvents.OnRaceQueueLeaveReceived(MainServer.OnRaceQueueLeave)

	MainServer.SetupCheckpointTouches()

	MainServer.StartHeartbeat()
	DataManager.StartAutoSave()

	if Config.ENABLE_ADMIN_SYSTEM then
		local success = SystemManager:Init()
		if success then
			print("[MainServer] Admin system initialized successfully")
		else
			warn("[MainServer] Failed to initialize admin system")
		end
	end

	if Config.ENABLE_RACE_SYSTEM then
		MainServer.InitializeRaceSystem()
		RaceController.Init()
		RaceController.StartAutoScheduler()
	end

	print("[MainServer] Unified System initialized successfully")
end

-- Setup checkpoint touch detection
function MainServer.SetupCheckpointTouches()
	for i, checkpoint in pairs(Checkpoints:GetChildren()) do
		if checkpoint:IsA("BasePart") then
			MainServer.ConnectCheckpointPart(checkpoint, checkpoint)
		elseif checkpoint:IsA("Model") then
			local wall = checkpoint:FindFirstChild("Wall")
			if wall and wall:IsA("BasePart") then
				MainServer.ConnectCheckpointPart(wall, checkpoint)
				print(string.format("[MainServer] ✓ Ring checkpoint detected: %s", checkpoint.Name))
			else
				warn(string.format("[MainServer] ⚠️ Model checkpoint '%s' has no 'Wall' part!", checkpoint.Name))
			end
		end
	end
	print("[MainServer] Checkpoint touch detection setup complete")
end

-- Connect touch event for checkpoint part
function MainServer.ConnectCheckpointPart(touchPart, checkpointModel)
	touchPart.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character:FindFirstChild("Humanoid") then return end

		local player = Players:GetPlayerFromCharacter(character)
		if player then
			MainServer.OnCheckpointTouched(player, touchPart, checkpointModel)
		end
	end)
end

-- Create leaderstats
function MainServer.CreateLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local checkpointValue = Instance.new("IntValue")
	checkpointValue.Name = "CP"
	checkpointValue.Value = 0
	checkpointValue.Parent = leaderstats

	print(string.format("[MainServer] Leaderstats created for %s", player.Name))
	return checkpointValue
end

-- Handle player joining
function MainServer.OnPlayerAdded(player)
	print("[MainServer] Player joined:", player.Name)

	local checkpointValue = MainServer.CreateLeaderstats(player)
	local playerData = DataManager.CreatePlayerData(player)
	activePlayers[player] = playerData

	local userId = player.UserId
	if not playerTouchedCheckpoints[userId] then
		playerTouchedCheckpoints[userId] = {}
	end
	if not checkpointDebounce[userId] then
		checkpointDebounce[userId] = {}
	end

	DataManager.LoadPlayerData(player)

	-- Restore touched checkpoints from persistent data
	if playerData.touchedCheckpoints then
		for checkpointId, touched in pairs(playerData.touchedCheckpoints) do
			if touched then
				playerTouchedCheckpoints[userId][checkpointId] = true
				MainServer.UpdateCheckpointColor(checkpointId, true, player)
				print(string.format("[MainServer] ✓ Restored touched checkpoint %d for %s", checkpointId, player.Name))
			end
		end
	end

	-- Only save if data was modified during load
	if DataManager.IsDirty(player) then
		DataManager.SavePlayerData(player)
	end

	local savedCheckpoint = playerData.currentCheckpoint
	if savedCheckpoint then
		checkpointValue.Value = savedCheckpoint
	end

	local characterAddedConnection = player.CharacterAdded:Connect(function(character)
		MainServer.SetupCharacter(player, character)
	end)

	if not playerConnections[player] then
		playerConnections[player] = {}
	end
	table.insert(playerConnections[player], characterAddedConnection)

	if player.Character then
		MainServer.SetupCharacter(player, player.Character)
	end
end

-- Setup character
function MainServer.SetupCharacter(player, character)
	local playerData = activePlayers[player]
	if not playerData then return end

	task.wait(0.1)

	playerData.character = character
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		playerData.humanoid = humanoid

		local targetSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED
		humanoid.WalkSpeed = targetSpeed

		if playerData.spawnPosition and playerData.spawnPosition ~= Vector3.new(0, 0, 0) then
			character:MoveTo(playerData.spawnPosition)
			print(string.format("[MainServer] %s respawned at checkpoint %d", 
				player.Name, playerData.currentCheckpoint or 0))
		end

		local function sendSync()
			RemoteEvents.SendSync(player, {
				isSprinting = playerData.isSprinting,
				currentSpeed = targetSpeed,
				timestamp = tick()
			})
		end

		sendSync()
		task.delay(0.1, sendSync)
		task.delay(0.3, sendSync)

		print(string.format("[MainServer] Character setup for %s - sprint state: %s (speed: %d)",
			player.Name, playerData.isSprinting and "ON" or "OFF", targetSpeed))
	end

	local diedConnection = humanoid.Died:Connect(function()
		MainServer.OnCharacterDied(player)
	end)

	if not playerConnections[player] then
		playerConnections[player] = {}
	end
	table.insert(playerConnections[player], diedConnection)
end

-- Handle death
function MainServer.OnCharacterDied(player)
	local playerData = activePlayers[player]
	if not playerData then return end

	DataManager.UpdateDeathCount(player)

	playerData.character = nil
	playerData.humanoid = nil

	print(string.format("[MainServer] %s died - sprint state preserved: %s (total deaths: %d)",
		player.Name, playerData.isSprinting and "ON" or "OFF", playerData.deathCount or 0))
end

-- Handle player leaving
function MainServer.OnPlayerRemoving(player)
	print("[MainServer] Player leaving:", player.Name)

	local playerData = activePlayers[player]
	if playerData then
		DataManager.ClearSaveQueue(player)
		DataManager.SavePlayerData(player)
		DataManager.CleanupPlayerData(player)
		activePlayers[player] = nil
	end

	local userId = player.UserId
	if playerTouchedCheckpoints[userId] then
		playerTouchedCheckpoints[userId] = nil
	end
	if checkpointDebounce[userId] then
		checkpointDebounce[userId] = nil
	end

	if playerConnections[player] then
		for _, connection in ipairs(playerConnections[player]) do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
		playerConnections[player] = nil
	end
end

-- Sprint toggle
function MainServer.OnSprintToggleRequested(player, requestedState)
	local validation = MainServer.ValidateSprintToggleRequest(player, requestedState)

	if validation.success then
		local humanoid = validation.playerData.humanoid
		humanoid.WalkSpeed = validation.targetSpeed

		DataManager.UpdateSprintState(player, requestedState)

		RemoteEvents.SendSync(player, {
			isSprinting = requestedState,
			currentSpeed = validation.targetSpeed,
			timestamp = tick()
		})

		print(string.format("[MainServer] Sprint %s for %s (speed: %d)",
			requestedState and "enabled" or "disabled", player.Name, validation.targetSpeed))
	else
		warn(string.format("[MainServer] Toggle rejected for %s: %s",
			player.Name, validation.reason))

		local playerData = activePlayers[player]
		if playerData then
			RemoteEvents.SendSync(player, {
				isSprinting = playerData.isSprinting,
				currentSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED,
				timestamp = tick()
			})
		end
	end
end

-- Update checkpoint color (Red → Green)
function MainServer.UpdateCheckpointColor(checkpointId, isTouched, player)
	local checkpoint = Checkpoints:FindFirstChild("Checkpoint" .. checkpointId)
	if not checkpoint then return end

	local targetColor = isTouched and CHECKPOINT_COLORS.TOUCHED or CHECKPOINT_COLORS.UNTOUCHED

	-- If it's a Model (ring checkpoint), update all parts
	if checkpoint:IsA("Model") then
		for _, part in pairs(checkpoint:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Color = targetColor
			elseif part:IsA("PointLight") then
				part.Color = targetColor
			end
		end
	elseif checkpoint:IsA("BasePart") then
		-- Old style direct Part
		checkpoint.Color = targetColor
		local light = checkpoint:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = targetColor
		end
	end

	if Config.DEBUG_MODE then
		print(string.format("[MainServer] 🎨 Checkpoint %d color changed to %s for %s", 
			checkpointId, isTouched and "GREEN" or "RED", player and player.Name or "ALL"))
	end
end

-- Validate checkpoint touch
function MainServer.ValidateCheckpointTouch(player, checkpointPart, checkpointId)
	local result = {success = false, reason = ""}
	local userId = player.UserId

	local playerData = activePlayers[player]
	if not playerData then
		result.reason = "Player data not found"
		return result
	end

	local character = playerData.character
	local humanoid = playerData.humanoid
	if not character or not humanoid or humanoid.Health <= 0 then
		result.reason = "Player not alive"
		return result
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		result.reason = "HumanoidRootPart not found"
		return result
	end

	local distance = (hrp.Position - checkpointPart.Position).Magnitude
	if distance > Config.MAX_DISTANCE_STUDS then
		result.reason = string.format("Too far (%.1f studs)", distance)
		return result
	end

	if playerTouchedCheckpoints[userId] and playerTouchedCheckpoints[userId][checkpointId] then
		result.reason = "Already touched"
		result.alreadyTouched = true
		return result
	end

	local now = tick()
	local lastDebounce = checkpointDebounce[userId][checkpointId] or 0
	if now - lastDebounce < 0.5 then
		result.reason = "Debounce active"
		result.isDebounce = true
		return result
	end

	checkpointDebounce[userId][checkpointId] = now

	result.success = true
	return result
end

-- Handle checkpoint touch with color change
function MainServer.OnCheckpointTouched(player, checkpointPart, checkpointModel)
	local checkpointId = tonumber(string.match(checkpointModel.Name, "%d+")) 
		or checkpointModel:GetAttribute("Order")

	if not checkpointId then
		if Config.DEBUG_MODE then
			warn(string.format("[MainServer] Invalid checkpoint: %s (no valid ID)", checkpointModel.Name))
		end
		return
	end

	local validation = MainServer.ValidateCheckpointTouch(player, checkpointPart, checkpointId)

	if not validation.success then
		if validation.alreadyTouched or validation.isDebounce then
			return
		end

		if validation.isSkip then
			-- Send skip notification to client
			RemoteEvents.SendCheckpointSkipNotification(player, validation.reason)
			print(string.format("[MainServer] Checkpoint skip rejected for %s at checkpoint %d: %s",
				player.Name, checkpointId, validation.reason))
			return
		end

		if Config.DEBUG_MODE then
			warn(string.format("[MainServer] Touch rejected for %s at checkpoint %d: %s",
				player.Name, checkpointId, validation.reason))
		end
		return
	end

	local userId = player.UserId
	if not playerTouchedCheckpoints[userId] then
		playerTouchedCheckpoints[userId] = {}
	end
	playerTouchedCheckpoints[userId][checkpointId] = true

	MainServer.UpdateCheckpointColor(checkpointId, true, player)

	local spawnPosition = checkpointPart.Position + Config.CHECKPOINT_SPAWN_OFFSET

	DataManager.UpdateCheckpointData(player, checkpointId, spawnPosition)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local checkpointValue = leaderstats:FindFirstChild("CP")
		if checkpointValue then
			checkpointValue.Value = checkpointId
		end
	end

	local playerCheckpointData = DataManager.GetPlayerData(player)
	if playerCheckpointData then
		RemoteEvents.SendCheckpointSync(player, {
			currentCheckpoint = playerCheckpointData.currentCheckpoint,
			checkpointHistory = playerCheckpointData.checkpointHistory,
			spawnPosition = playerCheckpointData.spawnPosition,
			timestamp = tick()
		})
	end

	RaceController.CheckRaceFinish(player, checkpointId)

	-- Send success notification to client
	RemoteEvents.SendCheckpointSuccessNotification(player, checkpointId)

	print(string.format("[MainServer] ✓ %s reached checkpoint %d → 🟢 GREEN",
		player.Name, checkpointId))

	local saveSuccess = DataManager.SavePlayerData(player)
	if not saveSuccess then
		warn(string.format("[MainServer] ⚠️ Failed to save checkpoint data for %s!", player.Name))
	end
end

-- ✅ FIXED: Reset player checkpoints with proper color reset and sync
function MainServer.ResetPlayerCheckpoints(player)
	local userId = player.UserId

	print(string.format("[MainServer] 🔄 Resetting checkpoints for %s...", player.Name))

	-- Get currently touched checkpoints BEFORE clearing
	local touchedCheckpoints = {}
	if playerTouchedCheckpoints[userId] then
		for checkpointId, _ in pairs(playerTouchedCheckpoints[userId]) do
			table.insert(touchedCheckpoints, checkpointId)
		end
	end

	-- ✅ Change all touched checkpoints back to RED
	for _, checkpointId in ipairs(touchedCheckpoints) do
		MainServer.UpdateCheckpointColor(checkpointId, false, player)
		print(string.format("[MainServer]   → Checkpoint %d: 🔴 RED", checkpointId))
	end

	-- Clear tracking
	if playerTouchedCheckpoints[userId] then
		playerTouchedCheckpoints[userId] = {}
	end

	if checkpointDebounce[userId] then
		checkpointDebounce[userId] = {}
	end

	-- ✅ Reset checkpoint data using DataManager
	DataManager.ResetCheckpointData(player)

	local playerData = activePlayers[player]
	if playerData then
		-- Update leaderstats
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local checkpointValue = leaderstats:FindFirstChild("CP")
			if checkpointValue then
				checkpointValue.Value = 0
			end
		end

		-- ✅ Send sync to client to update UI
		RemoteEvents.SendCheckpointSync(player, {
			currentCheckpoint = 0,
			checkpointHistory = {},
			spawnPosition = Vector3.new(0, 0, 0),
			timestamp = tick()
		})

		-- ✅ Save immediately to ensure persistence
		local saveSuccess = DataManager.SavePlayerData(player)
		if saveSuccess then
			print(string.format("[MainServer] ✅ Reset complete for %s - All checkpoints 🔴 RED", player.Name))
		else
			warn(string.format("[MainServer] ⚠️ Reset successful but save failed for %s!", player.Name))
		end
	else
		warn(string.format("[MainServer] ⚠️ Reset failed for %s - player data not found!", player.Name))
	end
end

-- Validate sprint
function MainServer.ValidateSprintToggleRequest(player, requestedState)
	local response = table.clone(SharedTypes.ValidationResponse)
	response.success = false
	response.reason = SharedTypes.ValidationResult.INVALID_REQUEST
	response.targetSpeed = Config.NORMAL_SPEED

	if typeof(requestedState) ~= "boolean" then
		response.reason = SharedTypes.ValidationResult.INVALID_REQUEST
		return response
	end

	if not player or not player:IsA("Player") then
		response.reason = SharedTypes.ValidationResult.PLAYER_NOT_FOUND
		return response
	end

	local playerData = DataManager.GetPlayerData(player)
	if not playerData then
		response.reason = SharedTypes.ValidationResult.PLAYER_NOT_FOUND
		return response
	end

	if not playerData.character or not playerData.humanoid then
		response.reason = SharedTypes.ValidationResult.CHARACTER_NOT_FOUND
		return response
	end

	local timeSinceLastToggle = tick() - playerData.lastToggleTime
	if timeSinceLastToggle < Config.DEBOUNCE_TIME then
		response.reason = SharedTypes.ValidationResult.DEBOUNCE_ACTIVE
		return response
	end

	response.success = true
	response.reason = SharedTypes.ValidationResult.SUCCESS
	response.playerData = playerData
	response.targetSpeed = requestedState and Config.SPRINT_SPEED or Config.NORMAL_SPEED

	return response
end

-- Heartbeat
function MainServer.StartHeartbeat()
	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		MainServer.CheckSpeedIntegrity()
		MainServer.CheckAutoSave()
	end)
	print("[MainServer] Heartbeat system started")
end

-- Auto-save
function MainServer.CheckAutoSave()
	local currentTime = tick()
	local autoSaveInterval = Config.AUTO_SAVE_INTERVAL or 60

	if currentTime - lastAutoSaveTime < 5 then
		return
	end

	if currentTime - lastAutoSaveTime >= autoSaveInterval then
		MainServer.PerformAutoSave()
		lastAutoSaveTime = currentTime
	end
end

function MainServer.PerformAutoSave()
	local savedCount = 0
	local failedCount = 0

	for player, playerData in pairs(activePlayers) do
		if DataManager.IsDirty(player) then
			local success = DataManager.SavePlayerData(player)
			if success then
				savedCount = savedCount + 1
			else
				failedCount = failedCount + 1
				warn(string.format("[MainServer] Auto-save failed for %s", player.Name))
			end
		end
	end

	if savedCount > 0 or failedCount > 0 then
		print(string.format("[MainServer] Auto-save completed: %d saved, %d failed", savedCount, failedCount))
	end
end

-- Speed integrity
function MainServer.CheckSpeedIntegrity()
	for player, playerData in pairs(activePlayers) do
		if playerData.humanoid and tick() - playerData.lastSpeedCheck > Config.HEARTBEAT_CHECK_INTERVAL then
			local needsCorrection = MainServer.CheckPlayerSpeedIntegrity(player)

			if needsCorrection then
				local expectedSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED
				playerData.humanoid.WalkSpeed = expectedSpeed

				RemoteEvents.SendSync(player, {
					isSprinting = playerData.isSprinting,
					currentSpeed = expectedSpeed,
					timestamp = tick()
				})

				playerData.speedViolations = playerData.speedViolations + 1
				warn(string.format("[MainServer] Speed corrected for %s (violations: %d)",
					player.Name, playerData.speedViolations))
			end

			playerData.lastSpeedCheck = tick()
		end
	end
end

function MainServer.CheckPlayerSpeedIntegrity(player)
	local playerData = DataManager.GetPlayerData(player)
	if not playerData or not playerData.humanoid then
		return false
	end

	local actualSpeed = playerData.humanoid.WalkSpeed
	local expectedSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED

	local difference = math.abs(actualSpeed - expectedSpeed)
	return difference > Config.SPEED_TOLERANCE
end

-- Race queue
function MainServer.OnRaceQueueJoin(player)
	local success, reason = RaceController.JoinRaceQueue(player)
	if success then
		print(string.format("[MainServer] %s joined race queue", player.Name))
	else
		warn(string.format("[MainServer] Failed to join race queue for %s: %s", player.Name, reason))
	end
end

function MainServer.OnRaceQueueLeave(player)
	local success, reason = RaceController.LeaveRaceQueue(player)
	if success then
		print(string.format("[MainServer] %s left race queue", player.Name))
	else
		warn(string.format("[MainServer] Failed to leave race queue for %s: %s", player.Name, reason))
	end
end

-- Race init
function MainServer.InitializeRaceSystem()
	print("[MainServer] Initializing race system")
	print("[MainServer] Race system initialized")
end

-- Cleanup
function MainServer.Cleanup()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	for player in pairs(activePlayers) do
		DataManager.SavePlayerData(player)
	end

	for player, playerData in pairs(activePlayers) do
		playerData.character = nil
		playerData.humanoid = nil
	end

	activePlayers = {}
	playerTouchedCheckpoints = {}
	checkpointDebounce = {}
end

MainServer.Init()

game:BindToClose(function()
	MainServer.Cleanup()
end)

return MainServer