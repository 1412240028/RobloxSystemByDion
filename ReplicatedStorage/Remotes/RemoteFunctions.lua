-- RemoteFunctions.lua
-- Centralized remote function management for client-server communication

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteFunctions = {
    -- Admin System Remote Functions
    GetPlayerRoleInfo = ReplicatedStorage:FindFirstChild("GetPlayerRoleInfo"), -- RemoteFunction: Client -> Server
}

-- Ensure RemoteFunction exists, create it if missing
if not RemoteFunctions.GetPlayerRoleInfo then
    warn("[RemoteFunctions] GetPlayerRoleInfo not found! Creating it dynamically...")
    RemoteFunctions.GetPlayerRoleInfo = Instance.new("RemoteFunction")
    RemoteFunctions.GetPlayerRoleInfo.Name = "GetPlayerRoleInfo"
    RemoteFunctions.GetPlayerRoleInfo.Parent = ReplicatedStorage
    print("[RemoteFunctions] Created missing RemoteFunction: GetPlayerRoleInfo")
end

return RemoteFunctions