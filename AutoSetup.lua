-- AutoSetup.lua
-- Automatic setup script for Checkpoint System V1.0
-- Run this in Roblox Studio Command Bar to create all necessary folders and remote events

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")

print("🚀 Starting Checkpoint System V1.0 Auto Setup...")

-- Helper function to create folder if not exists
local function CreateFolder(parent, name)
    local folder = parent:FindFirstChild(name)
    if not folder then
        folder = Instance.new("Folder", parent)
        folder.Name = name
        print("📁 Created folder:", parent.Name .. "/" .. name)
    else
        print("📁 Folder already exists:", parent.Name .. "/" .. name)
    end
    return folder
end

-- Helper function to create remote event
local function CreateRemoteEvent(parent, name)
    local event = parent:FindFirstChild(name)
    if not event then
        event = Instance.new("RemoteEvent", parent)
        event.Name = name
        print("🔌 Created RemoteEvent:", parent.Name .. "/" .. name)
    else
        print("🔌 RemoteEvent already exists:", parent.Name .. "/" .. name)
    end
    return event
end

-- 1. Create ReplicatedStorage structure
print("\n📦 Setting up ReplicatedStorage...")
local CheckpointSystem = CreateFolder(ReplicatedStorage, "CheckpointSystem")

-- Modules folder
local Modules = CreateFolder(CheckpointSystem, "Modules")

-- Remotes folder
local Remotes = CreateFolder(CheckpointSystem, "Remotes")

-- Config folder
local Config = CreateFolder(CheckpointSystem, "Config")

-- Create Remote Events
print("\n🔌 Creating Remote Events...")
CreateRemoteEvent(Remotes, "CheckpointReached")
CreateRemoteEvent(Remotes, "AdminCommand")
CreateRemoteEvent(Remotes, "SystemStatus")
CreateRemoteEvent(Remotes, "GlobalData")

-- 2. Create ServerScriptService structure
print("\n📜 Setting up ServerScriptService...")
local ServerCheckpointSystem = CreateFolder(ServerScriptService, "CheckpointSystem")

-- 3. Create StarterPlayerScripts structure
print("\n👤 Setting up StarterPlayerScripts...")
local StarterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if not StarterPlayerScripts then
    StarterPlayerScripts = Instance.new("Folder", StarterPlayer)
    StarterPlayerScripts.Name = "StarterPlayerScripts"
    print("📁 Created StarterPlayerScripts folder")
end

-- 4. Create StarterGui structure
print("\n🖼️ Setting up StarterGui...")
local CheckpointUI = CreateFolder(StarterGui, "CheckpointUI")

print("\n✅ Checkpoint System V1.0 Auto Setup Complete!")
print("📋 Summary:")
print("   - ReplicatedStorage/CheckpointSystem/ (with Modules, Remotes, Config folders)")
print("   - 4 RemoteEvents created in Remotes folder")
print("   - ServerScriptService/CheckpointSystem/ folder")
print("   - StarterGui/CheckpointUI/ folder")
print("\n⚠️ Next steps:")
print("   1. Copy the module scripts from your files to the appropriate folders")
print("   2. Copy the server scripts to ServerScriptService/CheckpointSystem/")
print("   3. Copy client scripts to StarterPlayer/StarterPlayerScripts/")
print("   4. Copy UI elements to StarterGui/CheckpointUI/")
print("   5. Test the system in-game!")

-- Verification function
local function VerifySetup()
    print("\n🔍 Verifying setup...")

    local checks = {
        {"ReplicatedStorage/CheckpointSystem", ReplicatedStorage:FindFirstChild("CheckpointSystem")},
        {"Modules folder", CheckpointSystem:FindFirstChild("Modules")},
        {"Remotes folder", CheckpointSystem:FindFirstChild("Remotes")},
        {"Config folder", CheckpointSystem:FindFirstChild("Config")},
        {"CheckpointReached RemoteEvent", Remotes:FindFirstChild("CheckpointReached")},
        {"AdminCommand RemoteEvent", Remotes:FindFirstChild("AdminCommand")},
        {"SystemStatus RemoteEvent", Remotes:FindFirstChild("SystemStatus")},
        {"GlobalData RemoteEvent", Remotes:FindFirstChild("GlobalData")},
        {"ServerScriptService folder", ServerScriptService:FindFirstChild("CheckpointSystem")},
        {"StarterGui folder", StarterGui:FindFirstChild("CheckpointUI")},
    }

    local allGood = true
    for _, check in ipairs(checks) do
        if check[2] then
            print("✅ " .. check[1])
        else
            print("❌ " .. check[1] .. " - MISSING!")
            allGood = false
        end
    end

    if allGood then
        print("\n🎉 All components verified successfully!")
    else
        print("\n⚠️ Some components are missing. Please run the setup again.")
    end

    return allGood
end

-- Run verification
VerifySetup()

print("\n🎯 Setup script complete! Ready to implement Checkpoint System V1.0 🚀")
