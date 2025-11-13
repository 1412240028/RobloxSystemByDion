-- CheckpointClient.lua
-- Client-side controller for checkpoint system
-- Handles reset requests and UI

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local SharedTypes = require(ReplicatedStorage.Modules.SharedTypes)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local CheckpointClient = {}

-- Private variables
local player = Players.LocalPlayer
local lastRequestTime = 0
local throttleActive = false
local character = nil
local humanoid = nil

-- GUI reference (will be set by CheckpointGUI)
local checkpointGUI = nil

-- Initialize client
function CheckpointClient.Init()
	print("[CheckpointClient] Initializing client for", player.Name)

	-- Load and initialize CheckpointGUI
	local success, result = pcall(function()
		local guiModule = script.Parent:FindFirstChild("CheckpointGUI")

		if not guiModule then
			error("CheckpointGUI not found in same folder as CheckpointClient")
		end

		if not guiModule:IsA("ModuleScript") then
			error("CheckpointGUI must be a ModuleScript, found: " .. guiModule.ClassName)
		end

		return require(guiModule)
	end)

	if success and result then
		result.SetClient(CheckpointClient)
		CheckpointClient.SetGUI(result)
		result.Init()

		print("[CheckpointClient] CheckpointGUI loaded and initialized successfully")
	else
		warn("[CheckpointClient] Failed to load CheckpointGUI:", result)
		warn("[CheckpointClient] Make sure CheckpointGUI is a ModuleScript in the same folder!")
	end

	-- Wait for character
	CheckpointClient.WaitForCharacter()

	-- Connect to checkpoint sync
	RemoteEvents.OnCheckpointSyncReceived(CheckpointClient.OnCheckpointSyncReceived)

	print("[CheckpointClient] Client initialized")
end

-- Wait for character and setup
function CheckpointClient.WaitForCharacter()
	local function onCharacterAdded(newCharacter)
		character = newCharacter
		humanoid = character:WaitForChild("Humanoid")

		print("[CheckpointClient] Character loaded")
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
end

-- Request checkpoint reset
function CheckpointClient.RequestReset()
	if throttleActive then
		warn("[CheckpointClient] Reset blocked: throttle active")
		return
	end

	-- Local throttle check
	local timeSinceLastRequest = tick() - lastRequestTime
	if timeSinceLastRequest < Config.DEBOUNCE_TIME then
		warn("[CheckpointClient] Reset blocked: debounce time not elapsed")
		return
	end

	print("[CheckpointClient] Requesting checkpoint reset")

	-- Send request to server
	RemoteEvents.FireReset()

	-- Start throttle
	throttleActive = true
	task.delay(Config.DEBOUNCE_TIME, function()
		throttleActive = false
	end)

	lastRequestTime = tick()
end

-- Handle checkpoint sync
function CheckpointClient.OnCheckpointSyncReceived(syncData)
	-- Update GUI if needed
	if checkpointGUI then
		checkpointGUI.UpdateCheckpointData(syncData)
	end

	print(string.format("[CheckpointClient] Checkpoint sync received: CP %d",
		syncData.currentCheckpoint or 0))
end

-- Set GUI reference
function CheckpointClient.SetGUI(guiModule)
	checkpointGUI = guiModule
	print("[CheckpointClient] GUI reference set")
end

-- Cleanup
function CheckpointClient.Cleanup()
	if checkpointGUI then
		checkpointGUI.Cleanup()
	end
	character = nil
	humanoid = nil
	checkpointGUI = nil
end

-- Initialize when script runs
CheckpointClient.Init()

return CheckpointClient
