-- Checkpoint System V1.0 - Respawn Handler
-- Handles player death detection and respawn logic

local Players = game:GetService("Players")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local RespawnHandler = {}

-- Private variables
local deathConnections = {} -- {player: connection}
local characterConnections = {} -- {player: {connections}}
local respawnDebounce = {} -- Prevent multiple simultaneous respawns
local isInitialized = false

-- Module references (set by ServerMain to avoid circular dependency)
RespawnHandler.ServerMainModule = nil

-- Logger utility
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end

	local prefix = "[RespawnHandler]"
	if level == "ERROR" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Initialize the respawn handler
function RespawnHandler.Initialize()
	if isInitialized then
		Log("WARN", "RespawnHandler already initialized")
		return true
	end

	Log("INFO", "Initializing RespawnHandler...")

	-- Set up player connections
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	isInitialized = true
	Log("INFO", "RespawnHandler initialized successfully")
	return true
end

-- Handle player joining
function OnPlayerAdded(player)
	if not isInitialized then return end

	Log("DEBUG", "Setting up respawn handling for %s", player.Name)

	-- Set up death detection
	SetupDeathDetection(player)

	-- Set up character connections
	SetupCharacterConnections(player)
end

-- Handle player leaving
function OnPlayerRemoving(player)
	if not isInitialized then return end

	CleanupPlayerConnections(player)

	-- Clear debounce
	local userId = player.UserId
	respawnDebounce[userId] = nil
end

-- Set up death detection for player
function SetupDeathDetection(player)
	-- Clean up existing connection
	if deathConnections[player] then
		deathConnections[player]:Disconnect()
	end

	-- Connect to character events
	deathConnections[player] = player.CharacterAdded:Connect(function(character)
		SetupCharacterDeathDetection(player, character)
	end)

	-- Set up for current character
	if player.Character then
		SetupCharacterDeathDetection(player, player.Character)
	end
end

-- Set up death detection for specific character
function SetupCharacterDeathDetection(player, character)
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		Log("WARN", "No humanoid found in character for %s", player.Name)
		return
	end

	-- Connect to death event
	humanoid.Died:Connect(function()
		HandlePlayerDeath(player, character)
	end)

	Log("DEBUG", "Death detection set up for %s", player.Name)
end

-- Handle player death
function HandlePlayerDeath(player, character)
	if not isInitialized then return end

	local userId = player.UserId

	-- Check debounce to prevent multiple simultaneous respawns
	if respawnDebounce[userId] then
		Log("WARN", "Respawn already in progress for %s, ignoring duplicate death event", player.Name)
		return
	end

	-- Set debounce flag
	respawnDebounce[userId] = true

	Log("INFO", "Player %s died", player.Name)

	-- Update death count via ServerMain (using module reference to avoid circular dependency)
	local deathCount = 0
	if RespawnHandler.ServerMainModule then
		deathCount = RespawnHandler.ServerMainModule.UpdatePlayerDeathCount(userId)
	else
		Log("ERROR", "ServerMain module reference not set!")
	end

	-- Wait before respawn (prevent instant respawn issues)
	task.delay(0.5, function()
		local success = RespawnHandler.RespawnPlayer(player, deathCount)

		-- Clear debounce after respawn completes (with additional delay for safety)
		task.delay(2, function()
			respawnDebounce[userId] = nil
			Log("DEBUG", "Respawn debounce cleared for %s", player.Name)
		end)

		if not success then
			Log("ERROR", "Failed to respawn %s", player.Name)
			-- Force clear debounce on failure
			respawnDebounce[userId] = nil
		end
	end)
end

-- Respawn player at checkpoint
function RespawnHandler.RespawnPlayer(player, deathCount)
	if not player or not player:IsA("Player") then
		Log("ERROR", "Invalid player for respawn")
		return false
	end

	local userId = player.UserId
	Log("DEBUG", "Respawning %s (death count: %d)", player.Name, deathCount)

	-- Get current checkpoint via ServerMain
	local checkpointOrder = 0
	if RespawnHandler.ServerMainModule then
		checkpointOrder = RespawnHandler.ServerMainModule.GetPlayerCheckpoint(userId)
	else
		Log("ERROR", "Cannot get player checkpoint - ServerMain not linked")
		return false
	end

	-- Apply death loop protection
	if Settings.ENABLE_DEATH_LOOP_PROTECTION and deathCount >= Settings.DEATH_LOOP_THRESHOLD then
		local oldCheckpoint = checkpointOrder
		checkpointOrder = math.max(0, checkpointOrder - Settings.DEATH_LOOP_FALLBACK_STEPS)
		Log("WARN", "Death loop protection activated for %s, falling back from checkpoint %d to %d",
			player.Name, oldCheckpoint, checkpointOrder)
	end

	-- Get spawn position
	local CheckpointManager = require(game.ReplicatedStorage.CheckpointSystem.Modules.CheckpointManager)
	local spawnPosition = CheckpointManager.GetSpawnPosition(checkpointOrder)

	if not spawnPosition then
		Log("ERROR", "No spawn position found for checkpoint %d", checkpointOrder)
		-- Fallback to safe origin
		spawnPosition = Vector3.new(0, 20, 0)
	end

	-- Validate spawn position
	if Settings.ENABLE_SPAWN_VALIDATION then
		spawnPosition = RespawnHandler.ValidateSpawnPosition(spawnPosition)
	end

	-- Wait for character reload
	local character = RespawnHandler.WaitForCharacterLoad(player, Settings.CHARACTER_LOAD_TIMEOUT)

	if not character then
		Log("ERROR", "Character failed to load for %s within timeout", player.Name)
		return false
	end

	-- Teleport character
	local teleportSuccess = RespawnHandler.TeleportCharacter(character, spawnPosition)

	if not teleportSuccess then
		Log("ERROR", "Failed to teleport character for %s", player.Name)
		return false
	end

	-- Apply temporary shield if death loop protection is active
	if Settings.ENABLE_DEATH_LOOP_PROTECTION and deathCount >= Settings.DEATH_LOOP_THRESHOLD then
		RespawnHandler.ApplyTemporaryShield(character)
	end

	Log("INFO", "Player %s respawned at checkpoint %d", player.Name, checkpointOrder)
	return true
end

-- Validate spawn position for safety
function RespawnHandler.ValidateSpawnPosition(position)
	if not position then 
		Log("WARN", "Invalid spawn position provided, using fallback")
		return Vector3.new(0, 20, 0) 
	end

	-- Spawn higher to avoid instant death from obstacles
	local safePosition = position + Vector3.new(0, 5, 0)

	-- Check ground below
	local rayOrigin = safePosition
	local rayDirection = Vector3.new(0, -20, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {game.Workspace.CurrentCamera}

	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if not raycastResult then
		Log("WARN", "No ground found at spawn position, using fallback")
		return Vector3.new(0, 20, 0)
	end

	-- Position player above ground
	local groundPosition = raycastResult.Position + Vector3.new(0, 5, 0)

	-- Check ceiling
	local ceilingRay = workspace:Raycast(
		groundPosition + Vector3.new(0, 1, 0), 
		Vector3.new(0, Settings.SPAWN_RAYCAST_DISTANCE_UP, 0),
		raycastParams
	)

	if ceilingRay then
		Log("WARN", "Ceiling too low at spawn position, adjusting")
		groundPosition = groundPosition + Vector3.new(0, -2, 0)
	end

	-- Check walls in 4 directions
	local directions = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1)
	}

	local wallDetected = false
	for _, direction in ipairs(directions) do
		local wallRay = workspace:Raycast(
			groundPosition + Vector3.new(0, 1, 0), 
			direction * Settings.SPAWN_RAYCAST_DISTANCE_WALL,
			raycastParams
		)
		if wallRay then
			wallDetected = true
			break
		end
	end

	if wallDetected then
		Log("WARN", "Wall too close at spawn position, using nearby position")
		return RespawnHandler.FindNearbyValidPosition(position)
	end

	Log("DEBUG", "Spawn position validated")
	return groundPosition
end

-- Find nearby valid position using spiral search
function RespawnHandler.FindNearbyValidPosition(centerPosition)
	Log("DEBUG", "Searching for nearby valid position from %s", tostring(centerPosition))

	local angle = 0
	local radius = Settings.SPAWN_VALIDATION_RADIUS_START

	while radius <= Settings.SPAWN_VALIDATION_RADIUS_END do
		for i = 1, 8 do
			local radians = math.rad(angle)
			local offset = Vector3.new(
				math.cos(radians) * radius,
				0,
				math.sin(radians) * radius
			)

			local testPosition = centerPosition + offset
			local validatedPosition = RespawnHandler.ValidateSpawnPosition(testPosition)

			-- If position changed significantly, it means validation passed
			if (validatedPosition - centerPosition).Magnitude > 1 then
				Log("DEBUG", "Found valid position at radius %d", radius)
				return validatedPosition
			end

			angle = angle + Settings.SPAWN_VALIDATION_ANGLE_STEP
		end

		radius = radius + Settings.SPAWN_VALIDATION_RADIUS_STEP
	end

	Log("WARN", "No valid position found in search radius, using safe fallback")
	return Vector3.new(0, 20, 0)
end

-- Wait for character to load
function RespawnHandler.WaitForCharacterLoad(player, timeout)
	local startTime = tick()

	while tick() - startTime < timeout do
		if player.Character and player.Character:IsDescendantOf(workspace) then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart")

			if humanoid and humanoid.Health > 0 and rootPart then
				Log("DEBUG", "Character loaded for %s", player.Name)
				return player.Character
			end
		end
		task.wait(0.1)
	end

	Log("ERROR", "Character load timeout for %s", player.Name)
	return nil
end

-- Teleport character to position
function RespawnHandler.TeleportCharacter(character, position)
	if not character or not character:IsA("Model") then
		Log("ERROR", "Invalid character for teleport")
		return false
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		Log("ERROR", "No HumanoidRootPart found in character")
		return false
	end

	-- Set position with CFrame (more reliable than Position property)
	humanoidRootPart.CFrame = CFrame.new(position)

	-- Reset velocity to prevent momentum-based deaths
	if humanoidRootPart:IsA("BasePart") then
		humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		humanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end

	-- Reset character state
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		task.wait(0.1)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	Log("DEBUG", "Character teleported to %s", tostring(position))
	return true
end

-- Apply temporary shield/invulnerability
function RespawnHandler.ApplyTemporaryShield(character)
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- Create shield effect (visual)
	local shieldPart = Instance.new("Part")
	shieldPart.Name = "DeathLoopShield"
	shieldPart.Size = Vector3.new(6, 6, 6)
	shieldPart.Shape = Enum.PartType.Ball
	shieldPart.Anchored = true
	shieldPart.CanCollide = false
	shieldPart.Transparency = 0.7
	shieldPart.Material = Enum.Material.ForceField
	shieldPart.BrickColor = BrickColor.new("Bright blue")

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart then
		shieldPart.CFrame = humanoidRootPart.CFrame
		shieldPart.Parent = character

		-- Follow character
		local connection
		connection = game:GetService("RunService").Heartbeat:Connect(function()
			if humanoidRootPart and humanoidRootPart:IsDescendantOf(workspace) and shieldPart.Parent then
				shieldPart.CFrame = humanoidRootPart.CFrame
			else
				if connection then connection:Disconnect() end
				if shieldPart and shieldPart.Parent then shieldPart:Destroy() end
			end
		end)

		-- Remove after duration
		task.delay(Settings.TEMPORARY_SHIELD_DURATION, function()
			if connection then connection:Disconnect() end
			if shieldPart and shieldPart.Parent then
				shieldPart:Destroy()
			end
		end)
	end

	Log("DEBUG", "Temporary shield applied for %d seconds", Settings.TEMPORARY_SHIELD_DURATION)
end

-- Set up character-specific connections
function SetupCharacterConnections(player)
	-- Clean up existing connections
	if characterConnections[player] then
		for _, connection in ipairs(characterConnections[player]) do
			connection:Disconnect()
		end
	end

	characterConnections[player] = {}

	-- Monitor for falling out of map
	local connection = player.CharacterAdded:Connect(function(character)
		local rootPart = character:WaitForChild("HumanoidRootPart", 5)
		if rootPart then
			local positionConnection = rootPart:GetPropertyChangedSignal("Position"):Connect(function()
				if rootPart.Position.Y < -100 then
					Log("WARN", "%s fell out of map (Y: %.1f)", player.Name, rootPart.Position.Y)
					HandlePlayerDeath(player, character)
				end
			end)
			table.insert(characterConnections[player], positionConnection)
		end
	end)

	table.insert(characterConnections[player], connection)
end

-- Cleanup player connections
function CleanupPlayerConnections(player)
	if deathConnections[player] then
		deathConnections[player]:Disconnect()
		deathConnections[player] = nil
	end

	if characterConnections[player] then
		for _, connection in ipairs(characterConnections[player]) do
			connection:Disconnect()
		end
		characterConnections[player] = nil
	end

	Log("DEBUG", "Connections cleaned up for %s", player.Name)
end

-- Force respawn player (for testing/admin commands)
function RespawnHandler.ForceRespawn(player)
	if not Settings.DEBUG_MODE then
		Log("WARN", "Force respawn called outside debug mode")
		return false
	end

	return RespawnHandler.RespawnPlayer(player, 0)
end

-- Get respawn status
function RespawnHandler.GetRespawnStatus()
	local activeDebounces = 0
	for _ in pairs(respawnDebounce) do
		activeDebounces = activeDebounces + 1
	end

	return {
		Initialized = isInitialized,
		ActiveConnections = 0,
		ActiveDebounces = activeDebounces
	}
end

-- Cleanup function
function RespawnHandler.Cleanup()
	-- Cleanup all connections
	for player, _ in pairs(deathConnections) do
		CleanupPlayerConnections(player)
	end

	deathConnections = {}
	characterConnections = {}
	respawnDebounce = {}
	isInitialized = false
	Log("INFO", "RespawnHandler cleaned up")
end

return RespawnHandler