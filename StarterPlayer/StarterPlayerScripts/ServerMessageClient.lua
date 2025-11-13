-- StarterPlayer/StarterPlayerScripts/ServerMessageClient.lua
-- Client-side handler for admin server messages

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for RemoteEvent
local serverMessageEvent = ReplicatedStorage:WaitForChild("CheckpointSystem")
	:WaitForChild("Remotes")
	:WaitForChild("ServerMessage")

-- Handle server messages
serverMessageEvent.OnClientEvent:Connect(function(message)
	-- Wait for chat to be ready
	local success = pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = message,
			Color = Color3.fromRGB(255, 255, 0),
			Font = Enum.Font.SourceSansBold,
			FontSize = Enum.FontSize.Size18
		})
	end)
	
	if not success then
		-- Fallback: Print to output
		warn("[ADMIN MESSAGE]", message)
	end
end)

print("[ServerMessageClient] Initialized")