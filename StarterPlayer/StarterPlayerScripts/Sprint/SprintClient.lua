-- SprintClient.lua - FIXED VERSION
-- Improved sync request handling with retry logic

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local SharedTypes = require(ReplicatedStorage.Modules.SharedTypes)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local SprintClient = {}

-- Private variables
local player = Players.LocalPlayer
local isSprinting = false
local lastRequestTime = 0
local throttleActive = false
local character = nil
local humanoid = nil
local isWaitingForSync = false
local syncRetryCount = 0
local MAX_SYNC_RETRIES = 3

-- GUI reference
local sprintGUI = nil

-- Initialize client
function SprintClient.Init()
	print("[SprintClient] Initializing client for", player.Name)

	-- Load and initialize SprintGUI
	local success, result = pcall(function()
		local guiModule = script.Parent:FindFirstChild("SprintGUI")

		if not guiModule then
			error("SprintGUI not found in same folder as SprintClient")
		end

		if not guiModule:IsA("ModuleScript") then
			error("SprintGUI must be a ModuleScript, found: " .. guiModule.ClassName)
		end

		return require(guiModule)
	end)

	if success and result then
		result.SetClient(SprintClient)
		SprintClient.SetGUI(result)
		result.Init()
		print("[SprintClient] SprintGUI loaded and initialized successfully")
	else
		warn("[SprintClient] Failed to load SprintGUI:", result)
	end

	-- Wait for character
	SprintClient.WaitForCharacter()

	-- Setup input handling
	SprintClient.SetupInputHandling()

	-- Connect to server sync
	RemoteEvents.OnSyncReceived(SprintClient.OnSyncReceived)

	print("[SprintClient] Client initialized")
end

-- ✅ IMPROVED: Wait for character with better sync request
function SprintClient.WaitForCharacter()
	local function onCharacterAdded(newCharacter)
		character = newCharacter
		humanoid = character:WaitForChild("Humanoid")

		-- Reset sync state
		isWaitingForSync = true
		syncRetryCount = 0
		lastRequestTime = 0

		print("[SprintClient] Character loaded - requesting server sync...")

		-- ⭐ Request sync immediately with retry logic
		SprintClient.RequestServerSync()
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
end

-- ✅ NEW: Request server sync with retry logic
function SprintClient.RequestServerSync()
	if syncRetryCount >= MAX_SYNC_RETRIES then
		warn("[SprintClient] ❌ Max sync retries reached - using default state")
		isWaitingForSync = false
		SprintClient.SetLocalState(false) -- Default to OFF
		return
	end

	syncRetryCount = syncRetryCount + 1
	print(string.format("[SprintClient] 🔄 Requesting sync (attempt %d/%d)", syncRetryCount, MAX_SYNC_RETRIES))

	-- Check if SprintSyncRequestEvent exists
	if not RemoteEvents.SprintSyncRequestEvent then
		warn("[SprintClient] ⚠️ SprintSyncRequestEvent not found! Creating fallback...")

		-- Fallback: Try requesting via toggle with current state
		task.wait(0.5)
		RemoteEvents.FireToggle(false) -- Request with OFF state

		-- Schedule retry
		task.delay(1, function()
			if isWaitingForSync then
				SprintClient.RequestServerSync()
			end
		end)
		return
	end

	-- Fire sync request to server
	local success, err = pcall(function()
		RemoteEvents.SprintSyncRequestEvent:FireServer()
	end)

	if not success then
		warn("[SprintClient] ⚠️ Sync request failed:", err)
	end

	-- Set timeout for this attempt
	task.delay(2, function()
		if isWaitingForSync and syncRetryCount < MAX_SYNC_RETRIES then
			warn(string.format("[SprintClient] ⏱️ Sync timeout (attempt %d) - retrying...", syncRetryCount))
			SprintClient.RequestServerSync()
		elseif isWaitingForSync then
			warn("[SprintClient] ❌ All sync attempts failed - using default state")
			isWaitingForSync = false
			SprintClient.SetLocalState(false)
		end
	end)
end

-- Setup input handling
function SprintClient.SetupInputHandling()
	-- No keyboard input - using GUI button only
end

-- Request sprint toggle
function SprintClient.RequestToggle()
	if throttleActive then 
		warn("[SprintClient] Toggle blocked: throttle active")
		return 
	end

	if isWaitingForSync then 
		warn("[SprintClient] Still waiting for server sync - ignoring toggle")
		return 
	end

	-- Local throttle check
	local timeSinceLastRequest = tick() - lastRequestTime
	if timeSinceLastRequest < Config.DEBOUNCE_TIME then
		warn("[SprintClient] Toggle blocked: debounce time not elapsed")
		return
	end

	-- Toggle state
	local newState = not isSprinting

	print(string.format("[SprintClient] Requesting toggle: %s -> %s", tostring(isSprinting), tostring(newState)))

	-- Send request to server
	RemoteEvents.FireToggle(newState)

	-- Update local state optimistically
	SprintClient.SetLocalState(newState)

	-- Start throttle
	throttleActive = true
	task.delay(Config.DEBOUNCE_TIME, function()
		throttleActive = false
	end)

	lastRequestTime = tick()
end

-- ✅ IMPROVED: Handle server sync with ACK support
function SprintClient.OnSyncReceived(syncData)
	-- Clear waiting flag
	if isWaitingForSync then
		print(string.format("[SprintClient] ✅ Sync received after %d attempts", syncRetryCount))
	end

	isWaitingForSync = false
	syncRetryCount = 0

	-- Update local state from server (authoritative)
	local previousState = isSprinting
	SprintClient.SetLocalState(syncData.isSprinting)

	-- Update GUI
	if sprintGUI then
		sprintGUI.UpdateVisualState(syncData.isSprinting)
	end

	-- Send ACK if required
	if syncData.ackRequired and syncData.timestamp then
		RemoteEvents.FireSyncAck({
			timestamp = syncData.timestamp
		})
		print("[SprintClient] 📡 ACK sent for sync")
	end

	-- Log state changes for debugging
	if previousState ~= syncData.isSprinting then
		print(string.format("[SprintClient] 🔄 State synced from server: %s -> %s",
			tostring(previousState), tostring(syncData.isSprinting)))
	end
end

-- Set local sprint state
function SprintClient.SetLocalState(newState)
	isSprinting = newState

	-- Update GUI
	if sprintGUI then
		sprintGUI.UpdateVisualState(newState)
	end
end

-- Get current state
function SprintClient.GetCurrentState()
	return isSprinting
end

-- Check if can toggle
function SprintClient.CanToggle()
	return not throttleActive and not isWaitingForSync and character and humanoid
end

-- Set GUI reference
function SprintClient.SetGUI(guiModule)
	sprintGUI = guiModule
	print("[SprintClient] GUI reference set")
end

-- Handle request failure (called by GUI)
function SprintClient.OnRequestFailed()
	-- Revert optimistic update
	SprintClient.SetLocalState(not isSprinting)
	warn("[SprintClient] Request failed - state reverted")
end

-- Cleanup
function SprintClient.Cleanup()
	if sprintGUI then
		sprintGUI.Cleanup()
	end
	character = nil
	humanoid = nil
	sprintGUI = nil
	isWaitingForSync = false
	syncRetryCount = 0
end

-- Initialize when script runs
SprintClient.Init()

return SprintClient