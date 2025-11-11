-- Admin Client Script V1.0
-- Client-side admin interface for the checkpoint system

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.CheckpointSystem.Config.Settings)

-- Remote events
local AdminCommandEvent = ReplicatedStorage.CheckpointSystem.Remotes.AdminCommand
local SystemStatusEvent = ReplicatedStorage.CheckpointSystem.Remotes.SystemStatus
local GlobalDataEvent = ReplicatedStorage.CheckpointSystem.Remotes.GlobalData

-- Local player
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Admin GUI variables
local adminGui = nil
local commandHistory = {}
local isAdmin = false

-- Initialize admin client
function Initialize()
    if not Settings.ENABLE_ADMIN_SYSTEM then
        return
    end

    -- Check if player is admin
    CheckAdminStatus()

    -- Set up remote event listeners
    AdminCommandEvent.OnClientEvent:Connect(OnCommandResponse)
    SystemStatusEvent.OnClientEvent:Connect(OnStatusResponse)
    GlobalDataEvent.OnClientEvent:Connect(OnDataResponse)

    -- Create admin GUI if admin
    if isAdmin then
        CreateAdminGUI()
        print("[AdminClient] Admin interface initialized")
    end
end

-- Check if player is admin (basic client-side check)
function CheckAdminStatus()
    -- This is a basic check - server will validate all commands
    local userId = player.UserId
    isAdmin = Settings.ADMIN_UIDS[userId] ~= nil

    if isAdmin then
        print("[AdminClient] Admin access granted for:", player.Name)
    end
end

-- Create admin GUI
function CreateAdminGUI()
    -- Create ScreenGui
    adminGui = Instance.new("ScreenGui")
    adminGui.Name = "AdminGUI"
    adminGui.ResetOnSpawn = false
    adminGui.Parent = playerGui

    -- Main frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 400, 0, 300)
    mainFrame.Position = UDim2.new(0.5, -200, 0.5, -150)
    mainFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    mainFrame.BorderSizePixel = 2
    mainFrame.BorderColor3 = Color3.fromRGB(255, 255, 255)
    mainFrame.Parent = adminGui

    -- Add rounded corners
    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0, 8)
    uiCorner.Parent = mainFrame

    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 30)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    titleLabel.Text = "Checkpoint Admin Panel"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 16
    titleLabel.Font = Enum.Font.SourceSansBold
    titleLabel.Parent = mainFrame

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = titleLabel

    -- Command input
    local commandBox = Instance.new("TextBox")
    commandBox.Name = "CommandBox"
    commandBox.Size = UDim2.new(1, -20, 0, 30)
    commandBox.Position = UDim2.new(0, 10, 0, 40)
    commandBox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    commandBox.Text = "Enter command..."
    commandBox.TextColor3 = Color3.fromRGB(200, 200, 200)
    commandBox.TextSize = 14
    commandBox.Font = Enum.Font.SourceSans
    commandBox.ClearTextOnFocus = true
    commandBox.Parent = mainFrame

    local commandCorner = Instance.new("UICorner")
    commandCorner.CornerRadius = UDim.new(0, 4)
    commandCorner.Parent = commandBox

    -- Execute button
    local executeButton = Instance.new("TextButton")
    executeButton.Name = "ExecuteButton"
    executeButton.Size = UDim2.new(0, 80, 0, 30)
    executeButton.Position = UDim2.new(1, -90, 0, 40)
    executeButton.BackgroundColor3 = Color3.fromRGB(70, 130, 180)
    executeButton.Text = "Execute"
    executeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    executeButton.TextSize = 14
    executeButton.Font = Enum.Font.SourceSansBold
    executeButton.Parent = mainFrame

    local executeCorner = Instance.new("UICorner")
    executeCorner.CornerRadius = UDim.new(0, 4)
    executeCorner.Parent = executeButton

    -- Output scroll frame
    local outputFrame = Instance.new("ScrollingFrame")
    outputFrame.Name = "OutputFrame"
    outputFrame.Size = UDim2.new(1, -20, 1, -120)
    outputFrame.Position = UDim2.new(0, 10, 0, 80)
    outputFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    outputFrame.BorderSizePixel = 1
    outputFrame.BorderColor3 = Color3.fromRGB(100, 100, 100)
    outputFrame.ScrollBarThickness = 8
    outputFrame.Parent = mainFrame

    local outputCorner = Instance.new("UICorner")
    outputCorner.CornerRadius = UDim.new(0, 4)
    outputCorner.Parent = outputFrame

    -- Output layout
    local outputLayout = Instance.new("UIListLayout")
    outputLayout.SortOrder = Enum.SortOrder.LayoutOrder
    outputLayout.Padding = UDim.new(0, 2)
    outputLayout.Parent = outputFrame

    -- Connect events
    executeButton.MouseButton1Click:Connect(function()
        ExecuteCommand(commandBox.Text)
        commandBox.Text = ""
    end)

    commandBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            ExecuteCommand(commandBox.Text)
            commandBox.Text = ""
        end
    end)

    -- Toggle visibility button
    CreateToggleButton()

    -- Initially hide GUI
    mainFrame.Visible = false
end

-- Create toggle button
function CreateToggleButton()
    local toggleButton = Instance.new("TextButton")
    toggleButton.Name = "AdminToggle"
    toggleButton.Size = UDim2.new(0, 120, 0, 40)
    toggleButton.Position = UDim2.new(0, 10, 1, -50)
    toggleButton.BackgroundColor3 = Color3.fromRGB(70, 130, 180)
    toggleButton.Text = "Admin Panel"
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.TextSize = 14
    toggleButton.Font = Enum.Font.SourceSansBold
    toggleButton.Parent = adminGui

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 6)
    toggleCorner.Parent = toggleButton

    toggleButton.MouseButton1Click:Connect(function()
        if adminGui and adminGui:FindFirstChild("MainFrame") then
            adminGui.MainFrame.Visible = not adminGui.MainFrame.Visible
        end
    end)
end

-- Execute admin command
function ExecuteCommand(commandText)
    if not commandText or commandText == "" then return end

    -- Parse command
    local parts = {}
    for part in string.gmatch(commandText, "%S+") do
        table.insert(parts, part)
    end

    if #parts == 0 then return end

    local command = parts[1]:upper()
    local args = {}
    for i = 2, #parts do
        table.insert(args, parts[i])
    end

    -- Send command to server
    AdminCommandEvent:FireServer(command, args)

    -- Add to history
    table.insert(commandHistory, "> " .. commandText)
    if #commandHistory > 50 then
        table.remove(commandHistory, 1)
    end

    -- Show command in output
    AddOutputText("> " .. commandText, Color3.fromRGB(150, 150, 255))
end

-- Handle command response from server
function OnCommandResponse(success, result)
    local color = success and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 150, 150)
    AddOutputText(tostring(result), color)
end

-- Handle status response
function OnStatusResponse(success, status)
    if success then
        local statusText = string.format(
            "System Status:\nPlayers: %d/%d\nCheckpoints: %d\nDataStore: %s\nUptime: %.1f min",
            status.Players or 0, Settings.MAX_PLAYERS,
            status.Checkpoints or 0,
            status.DataStore or "Unknown",
            (status.Uptime or 0) / 60
        )
        AddOutputText(statusText, Color3.fromRGB(255, 255, 150))
    else
        AddOutputText("Status Error: " .. tostring(status), Color3.fromRGB(255, 150, 150))
    end
end

-- Handle data response
function OnDataResponse(success, data)
    if success then
        AddOutputText(tostring(data), Color3.fromRGB(150, 255, 150))
    else
        AddOutputText("Data Error: " .. tostring(data), Color3.fromRGB(255, 150, 150))
    end
end

-- Add text to output
function AddOutputText(text, color)
    if not adminGui then return end

    local outputFrame = adminGui.MainFrame:FindFirstChild("OutputFrame")
    if not outputFrame then return end

    -- Create text label
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, -10, 0, 20)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = text
    textLabel.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    textLabel.TextSize = 12
    textLabel.Font = Enum.Font.SourceSans
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextWrapped = true
    textLabel.Parent = outputFrame

    -- Auto-resize
    local textBounds = textLabel.TextBounds
    textLabel.Size = UDim2.new(1, -10, 0, math.max(20, textBounds.Y + 4))

    -- Scroll to bottom
    outputFrame.CanvasSize = UDim2.new(0, 0, 0, outputFrame.UIListLayout.AbsoluteContentSize.Y)
    outputFrame.CanvasPosition = Vector2.new(0, outputFrame.CanvasSize.Y.Offset - outputFrame.AbsoluteSize.Y)

    -- Auto-remove old messages
    local children = outputFrame:GetChildren()
    if #children > 100 then
        for i = 1, #children - 100 do
            if children[i]:IsA("TextLabel") then
                children[i]:Destroy()
            end
        end
    end
end

-- Show help text
function ShowHelp()
    local helpText = [[
=== Checkpoint Admin Commands ===

HELP - Show this help
STATUS - Show server status
LIST_ADMINS - List all admins

KICK_PLAYER <username> - Kick player
VIEW_PLAYER_DATA <username> - View player data
RESET_PLAYER <username> - Reset player progress

Permission Levels: TESTER(1), HELPER(2), MODERATOR(3), DEVELOPER(4), OWNER(5)
]]

    AddOutputText(helpText, Color3.fromRGB(255, 255, 150))
end

-- Cleanup
function Cleanup()
    if adminGui then
        adminGui:Destroy()
        adminGui = nil
    end
end

-- Initialize when player joins
Initialize()

-- Cleanup when player leaves
player.AncestryChanged:Connect(function()
    if not player:IsDescendantOf(game) then
        Cleanup()
    end
end)
