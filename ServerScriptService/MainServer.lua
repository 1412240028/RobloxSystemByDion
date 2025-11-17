-- MainServer.lua
-- Unified server script for checkpoint and sprint systems
-- HYBRID VERSION: Combines flexible checkpoint system with leaderstats & respawn
-- v1.4 - FIXED: One-time checkpoint touch with spam prevention

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local SharedTypes = require(ReplicatedStorage.Modules.SharedTypes)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local DataManager = require(ReplicatedStorage.Modules.DataManager)

local MainServer = {}

-- Private variables
local activePlayers = {} -- player -> playerData
local heartbeatConnection = nil
local Checkpoints = workspace:WaitForChild("Checkpoints") -- Reference to checkpoints folder

-- ✅ NEW: Track which checkpoints have been touched by each player (PERMANENT)
local playerTouchedCheckpoints = {} -- [userId][checkpointId] = true

-- ✅ NEW: Anti-spam debounce (prevents log spam while standing on checkpoint)
local checkpointDebounce = {} -- [userId][checkpointId] -> lastTouchTime

-- Race system variables
local raceActive = false
local raceStartTime = 0
local raceParticipants = {} -- player -> race data
local raceCooldownEnd = 0
local raceWinner = nil

-- Initialize server
function MainServer.Init()
	print("[MainServer] Initializing Unified System v1.4 (One-Time Touch)")

	-- Setup player connections
	Players.PlayerAdded:Connect(MainServer.OnPlayerAdded)
	Players.PlayerRemoving:Connect(MainServer.OnPlayerRemoving)

	-- Setup remote event connections
	RemoteEvents.OnToggleRequested(MainServer.OnSprintToggleRequested)
	RemoteEvents.OnResetRequested(MainServer.ResetPlayerCheckpoints)

	-- Setup physical checkpoint touch detection
	MainServer.SetupCheckpointTouches()

	-- Start anti-cheat heartbeat
	MainServer.StartHeartbeat()

	-- Initialize race system if enabled
	if Config.ENABLE_RACE_SYSTEM then
		MainServer.InitializeRaceSystem()
	end

	print("[MainServer] Unified System initialized successfully")
end

-- Setup checkpoint touch detection
function MainServer.SetupCheckpointTouches()
	for i, checkpoint in pairs(Checkpoints:GetChildren()) do
		if checkpoint:IsA("BasePart") then
			checkpoint.Touched:Connect(function(hit)
				-- Check if hit part belongs to a character
				local character = hit.Parent
				if not character:FindFirstChild("Humanoid") then return end

				local player = Players:GetPlayerFromCharacter(character)
				if player then
					MainServer.OnCheckpointTouched(player, checkpoint)
				end
			end)
		end
	end
	print("[MainServer] Checkpoint touch detection setup complete")
end

-- Create leaderstats for player
function MainServer.CreateLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local checkpointValue = Instance.new("IntValue")
	checkpointValue.Name = "CP"
	checkpointValue.Value = 0 -- Start at 0, will be updated when checkpoint is touched
	checkpointValue.Parent = leaderstats

	print(string.format("[MainServer] Leaderstats created for %s", player.Name))
	return checkpointValue
end

-- Handle player joining
function MainServer.OnPlayerAdded(player)
	print("[MainServer] Player joined:", player.Name)

	-- Create leaderstats
	local checkpointValue = MainServer.CreateLeaderstats(player)

	-- Create player data
	local playerData = DataManager.CreatePlayerData(player)
	activePlayers[player] = playerData

	-- ✅ NEW: Initialize checkpoint tracking tables
	local userId = player.UserId
	if not playerTouchedCheckpoints[userId] then
		playerTouchedCheckpoints[userId] = {}
	end
	if not checkpointDebounce[userId] then
		checkpointDebounce[userId] = {}
	end

	-- Load saved data
	DataManager.LoadPlayerData(player)

	-- ✅ NEW: Restore touched checkpoints from saved history
	if playerData.checkpointHistory then
		for _, checkpointId in ipairs(playerData.checkpointHistory) do
			playerTouchedCheckpoints[userId][checkpointId] = true
		end
	end

	-- Sync leaderstats with saved checkpoint data
	local savedCheckpoint = playerData.currentCheckpoint
	if savedCheckpoint then
		checkpointValue.Value = savedCheckpoint
	end

	-- Wait for character and setup
	player.CharacterAdded:Connect(function(character)
		MainServer.SetupCharacter(player, character)
	end)

	-- If character already exists
	if player.Character then
		MainServer.SetupCharacter(player, player.Character)
	end
end

-- Setup character connections
function MainServer.SetupCharacter(player, character)
	local playerData = activePlayers[player]
	if not playerData then return end

	-- Wait a frame to ensure character is fully loaded
	task.wait(0.1)

	playerData.character = character
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		playerData.humanoid = humanoid

		-- Apply saved sprint state
		local targetSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED
		humanoid.WalkSpeed = targetSpeed

		-- Respawn at last checkpoint if available
		if playerData.spawnPosition and playerData.spawnPosition ~= Vector3.new(0, 0, 0) then
			character:MoveTo(playerData.spawnPosition)
			print(string.format("[MainServer] %s respawned at checkpoint %d", 
				player.Name, playerData.currentCheckpoint or 0))
		end

		-- Force sync to client multiple times to ensure delivery
		local function sendSync()
			RemoteEvents.SendSync(player, {
				isSprinting = playerData.isSprinting,
				currentSpeed = targetSpeed,
				timestamp = tick()
			})
		end

		-- Send initial sync
		sendSync()

		-- Send again after small delay (in case client wasn't ready)
		task.delay(0.1, sendSync)
		task.delay(0.3, sendSync)

		print(string.format("[MainServer] Character setup for %s - sprint state: %s (speed: %d)",
			player.Name, playerData.isSprinting and "ON" or "OFF", targetSpeed))
	end

	-- Handle character death
	humanoid.Died:Connect(function()
		MainServer.OnCharacterDied(player)
	end)
end

-- Handle character death
function MainServer.OnCharacterDied(player)
	local playerData = activePlayers[player]
	if not playerData then return end

	-- Update death count
	DataManager.UpdateDeathCount(player)

	-- Keep sprint state for next respawn
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
		-- Save data
		DataManager.SavePlayerData(player)
		-- Cleanup
		DataManager.CleanupPlayerData(player)
		activePlayers[player] = nil
	end

	-- ✅ Cleanup checkpoint tracking
	local userId = player.UserId
	if playerTouchedCheckpoints[userId] then
		playerTouchedCheckpoints[userId] = nil
	end
	if checkpointDebounce[userId] then
		checkpointDebounce[userId] = nil
	end
end

-- Handle sprint toggle request
function MainServer.OnSprintToggleRequested(player, requestedState)
	local validation = MainServer.ValidateSprintToggleRequest(player, requestedState)

	if validation.success then
		-- Apply speed change
		local humanoid = validation.playerData.humanoid
		humanoid.WalkSpeed = validation.targetSpeed

		-- Update data
		DataManager.UpdateSprintState(player, requestedState)

		-- Send sync to client
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

		-- Send current state back to client even if rejected
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

-- ✅ FIXED: Validate checkpoint touch with one-time restriction
function MainServer.ValidateCheckpointTouch(player, checkpointPart, checkpointId)
	local result = {success = false, reason = ""}
	local userId = player.UserId

	-- Check if player data exists
	local playerData = activePlayers[player]
	if not playerData then
		result.reason = "Player data not found"
		return result
	end

	-- Check player alive
	local character = playerData.character
	local humanoid = playerData.humanoid
	if not character or not humanoid or humanoid.Health <= 0 then
		result.reason = "Player not alive"
		return result
	end

	-- Check if HumanoidRootPart exists
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		result.reason = "HumanoidRootPart not found"
		return result
	end

	-- ✅ Check distance validation (anti-exploit)
	local distance = (hrp.Position - checkpointPart.Position).Magnitude
	if distance > Config.MAX_DISTANCE_STUDS then
		result.reason = string.format("Too far (%.1f studs)", distance)
		return result
	end

	-- ✅ NEW: Check if checkpoint already touched (PERMANENT BLOCK)
	if playerTouchedCheckpoints[userId] and playerTouchedCheckpoints[userId][checkpointId] then
		result.reason = "Already touched"
		result.alreadyTouched = true -- Flag for silent rejection
		return result
	end

	-- ✅ Anti-spam debounce (prevents rapid log spam)
	local now = tick()
	local lastDebounce = checkpointDebounce[userId][checkpointId] or 0
	if now - lastDebounce < 0.5 then -- 0.5 second debounce for log spam prevention
		result.reason = "Debounce active"
		result.isDebounce = true -- Flag for silent rejection
		return result
	end

	-- Update debounce
	checkpointDebounce[userId][checkpointId] = now

	-- All checks passed
	result.success = true
	return result
end

-- ✅ FIXED: Handle checkpoint touch with one-time logic
function MainServer.OnCheckpointTouched(player, checkpointPart)
	-- Extract checkpoint ID from part name (supports multiple formats)
	local checkpointId = tonumber(string.match(checkpointPart.Name, "%d+")) 
		or checkpointPart:GetAttribute("Order")

	if not checkpointId then
		if Config.DEBUG_MODE then
			warn(string.format("[MainServer] Invalid checkpoint part: %s (no valid ID)", checkpointPart.Name))
		end
		return
	end

	-- ✅ Validate touch with all security checks
	local validation = MainServer.ValidateCheckpointTouch(player, checkpointPart, checkpointId)
	
	if not validation.success then
		-- ✅ Silent rejection for already touched or debounce (no log spam)
		if validation.alreadyTouched or validation.isDebounce then
			return -- Silently ignore
		end
		
		-- Log other validation failures in debug mode only
		if Config.DEBUG_MODE then
			warn(string.format("[MainServer] Touch rejected for %s at checkpoint %d: %s", 
				player.Name, checkpointId, validation.reason))
		end
		return
	end

	-- ✅ Mark checkpoint as touched PERMANENTLY
	local userId = player.UserId
	if not playerTouchedCheckpoints[userId] then
		playerTouchedCheckpoints[userId] = {}
	end
	playerTouchedCheckpoints[userId][checkpointId] = true

	-- Get spawn position with offset
	local spawnPosition = checkpointPart.Position + Config.CHECKPOINT_SPAWN_OFFSET

	-- Update checkpoint data in DataManager
	DataManager.UpdateCheckpointData(player, checkpointId, spawnPosition)

	-- Update leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local checkpointValue = leaderstats:FindFirstChild("CP")
		if checkpointValue then
			checkpointValue.Value = checkpointId
		end
	end

	-- Send checkpoint sync to client
	local playerCheckpointData = DataManager.GetPlayerData(player)
	if playerCheckpointData then
		RemoteEvents.SendCheckpointSync(player, {
			currentCheckpoint = playerCheckpointData.currentCheckpoint,
			checkpointHistory = playerCheckpointData.checkpointHistory,
			spawnPosition = playerCheckpointData.spawnPosition,
			timestamp = tick()
		})
	end

	-- Check race finish if race is active
	MainServer.CheckRaceFinish(player, checkpointId)

	-- ✅ Log checkpoint touch ONCE
	print(string.format("[MainServer] ✓ %s reached checkpoint %d (distance: %.1f studs)",
		player.Name, checkpointId,
		(player.Character.HumanoidRootPart.Position - checkpointPart.Position).Magnitude))
end

-- ✅ NEW: Reset player checkpoints (for reset button)
function MainServer.ResetPlayerCheckpoints(player)
	local userId = player.UserId
	
	-- Clear touched checkpoints
	if playerTouchedCheckpoints[userId] then
		playerTouchedCheckpoints[userId] = {}
	end
	
	-- Clear debounce
	if checkpointDebounce[userId] then
		checkpointDebounce[userId] = {}
	end
	
	-- Reset checkpoint data in DataManager
	local playerData = activePlayers[player]
	if playerData then
		playerData.currentCheckpoint = 0
		playerData.checkpointHistory = {}
		playerData.spawnPosition = Vector3.new(0, 0, 0)
		
		-- Update leaderstats
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local checkpointValue = leaderstats:FindFirstChild("CP")
			if checkpointValue then
				checkpointValue.Value = 0
			end
		end
		
		-- Save reset data
		DataManager.SavePlayerData(player)
		
		print(string.format("[MainServer] Reset checkpoints for %s", player.Name))
	end
end

-- Validate sprint toggle request
function MainServer.ValidateSprintToggleRequest(player, requestedState)
	local response = table.clone(SharedTypes.ValidationResponse)
	response.success = false
	response.reason = SharedTypes.ValidationResult.INVALID_REQUEST
	response.targetSpeed = Config.NORMAL_SPEED

	-- Basic type validation
	if typeof(requestedState) ~= "boolean" then
		response.reason = SharedTypes.ValidationResult.INVALID_REQUEST
		return response
	end

	-- Check if player exists
	if not player or not player:IsA("Player") then
		response.reason = SharedTypes.ValidationResult.PLAYER_NOT_FOUND
		return response
	end

	-- Get player data
	local playerData = DataManager.GetPlayerData(player)
	if not playerData then
		response.reason = SharedTypes.ValidationResult.PLAYER_NOT_FOUND
		return response
	end

	-- Check character and humanoid
	if not playerData.character or not playerData.humanoid then
		response.reason = SharedTypes.ValidationResult.CHARACTER_NOT_FOUND
		return response
	end

	-- Rate limiting check
	local timeSinceLastToggle = tick() - playerData.lastToggleTime
	if timeSinceLastToggle < Config.DEBOUNCE_TIME then
		response.reason = SharedTypes.ValidationResult.DEBOUNCE_ACTIVE
		return response
	end

	-- All checks passed
	response.success = true
	response.reason = SharedTypes.ValidationResult.SUCCESS
	response.playerData = playerData
	response.targetSpeed = requestedState and Config.SPRINT_SPEED or Config.NORMAL_SPEED

	return response
end

-- Start anti-cheat heartbeat
function MainServer.StartHeartbeat()
	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		MainServer.CheckSpeedIntegrity()
	end)
end

-- Check speed integrity for all players
function MainServer.CheckSpeedIntegrity()
	for player, playerData in pairs(activePlayers) do
		if playerData.humanoid and tick() - playerData.lastSpeedCheck > Config.HEARTBEAT_CHECK_INTERVAL then
			local needsCorrection = MainServer.CheckPlayerSpeedIntegrity(player)

			if needsCorrection then
				-- Force correct speed
				local expectedSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED
				playerData.humanoid.WalkSpeed = expectedSpeed

				-- Send correction sync
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

-- Check speed integrity for a player
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

-- Initialize race system
function MainServer.InitializeRaceSystem()
	print("[MainServer] Initializing race system")

	-- Send initial leaderboard to all players
	local leaderboard = DataManager.GetRaceLeaderboard()
	RemoteEvents.BroadcastLeaderboardUpdate(leaderboard)

	print("[MainServer] Race system initialized")
end

-- Start a race
function MainServer.StartRace()
	if raceActive then
		warn("[MainServer] Race already active")
		return false
	end

	if tick() < raceCooldownEnd then
		warn("[MainServer] Race on cooldown")
		return false
	end

	local playerCount = 0
	for _ in pairs(activePlayers) do
		playerCount = playerCount + 1
	end

	if playerCount < Config.MIN_PLAYERS_FOR_RACE then
		warn(string.format("[MainServer] Not enough players for race: %d/%d", playerCount, Config.MIN_PLAYERS_FOR_RACE))
		return false
	end

	-- Start race
	raceActive = true
	raceStartTime = tick() + Config.RACE_START_DELAY
	raceParticipants = {}
	raceWinner = nil

	-- Prepare participants
	local participantCount = 0
	for player, playerData in pairs(activePlayers) do
		if participantCount < Config.MAX_RACE_PARTICIPANTS then
			DataManager.StartRaceForPlayer(player)
			raceParticipants[player] = {
				startTime = raceStartTime,
				checkpoints = 0,
				finished = false
			}
			participantCount = participantCount + 1
		end
	end

	-- Broadcast race start
	RemoteEvents.BroadcastRaceStart({
		startTime = raceStartTime,
		participantCount = participantCount,
		maxTime = Config.RACE_DURATION_SECONDS
	})

	-- Schedule race timeout
	task.delay(Config.RACE_DURATION_SECONDS, function()
		if raceActive then
			MainServer.EndRace(false)
		end
	end)

	print(string.format("[MainServer] Race started with %d participants", participantCount))
	return true
end

-- End a race
function MainServer.EndRace(completed)
	if not raceActive then return end

	raceActive = false
	raceCooldownEnd = tick() + Config.RACE_COOLDOWN_SECONDS

	local results = {
		completed = completed,
		winner = raceWinner and raceWinner.Name or nil,
		participants = {}
	}

	-- Process results
	for player, raceData in pairs(raceParticipants) do
		local playerData = activePlayers[player]
		if playerData then
			local finished = raceData.finished
			DataManager.EndRaceForPlayer(player, finished)

			table.insert(results.participants, {
				playerName = player.Name,
				finished = finished,
				checkpoints = raceData.checkpoints,
				time = finished and (raceData.finishTime - raceData.startTime) or nil
			})
		end
	end

	-- Update leaderboard
	local leaderboard = DataManager.GetRaceLeaderboard()
	RemoteEvents.BroadcastLeaderboardUpdate(leaderboard)

	-- Broadcast race end
	RemoteEvents.BroadcastRaceEnd(results)

	print(string.format("[MainServer] Race ended - completed: %s, winner: %s",
		tostring(completed), results.winner or "none"))
end

-- Check if player finished race (called when touching final checkpoint)
function MainServer.CheckRaceFinish(player, checkpointId)
	if not raceActive or not raceParticipants[player] then return end

	local raceData = raceParticipants[player]
	local totalCheckpoints = #Checkpoints:GetChildren()

	if checkpointId >= totalCheckpoints and not raceData.finished then
		raceData.finished = true
		raceData.finishTime = tick()
		raceData.checkpoints = checkpointId

		local placement = 1
		-- Check if this player is the winner
		if not raceWinner then
			raceWinner = player
			DataManager.UpdateRaceData(player, raceData.finishTime - raceData.startTime, checkpointId)
			player.racesWon = (player.racesWon or 0) + 1

			-- Send notification
			RemoteEvents.SendRaceNotification(player, {
				type = "winner",
				message = "🏆 You won the race!",
				time = raceData.finishTime - raceData.startTime
			})

			-- Check if all participants finished
			local allFinished = true
			for p, rd in pairs(raceParticipants) do
				if not rd.finished then
					allFinished = false
					break
				end
			end

			if allFinished then
				MainServer.EndRace(true)
			end
		else
			-- Send placement notification
			local placement = 1
			for p, rd in pairs(raceParticipants) do
				if rd.finished and rd.finishTime < raceData.finishTime then
					placement = placement + 1
				end
			end

			RemoteEvents.SendRaceNotification(player, {
				type = "finished",
				message = string.format("🎯 Race finished! Position: %d", placement),
				time = raceData.finishTime - raceData.startTime
			})
		end

		print(string.format("[MainServer] %s finished race in position %d", player.Name, placement))
	end
end

-- Get race status
function MainServer.GetRaceStatus()
	return {
		active = raceActive,
		startTime = raceStartTime,
		timeRemaining = raceActive and math.max(0, Config.RACE_DURATION_SECONDS - (tick() - raceStartTime)) or 0,
		participantCount = #raceParticipants,
		winner = raceWinner and raceWinner.Name or nil
	}
end

-- Cleanup on server shutdown
function MainServer.Cleanup()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	-- End any active race
	if raceActive then
		MainServer.EndRace(false)
	end

	-- Save all player data
	for player in pairs(activePlayers) do
		DataManager.SavePlayerData(player)
	end

	-- Clear character references to prevent memory leaks
	for player, playerData in pairs(activePlayers) do
		playerData.character = nil
		playerData.humanoid = nil
	end

	activePlayers = {}
	playerTouchedCheckpoints = {}
	checkpointDebounce = {}
	raceParticipants = {}
end

-- Initialize when script runs
MainServer.Init()

-- Handle server shutdown
game:BindToClose(function()
	MainServer.Cleanup()
end)

return MainServer