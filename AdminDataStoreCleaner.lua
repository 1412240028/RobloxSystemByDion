-- AdminDataStoreCleaner.lua (Run ONCE in Studio)
-- Clears corrupted admin data from DataStore
local DataStoreService = game:GetService("DataStoreService")

local adminDataStore = DataStoreService:GetDataStore("AdminData_v1")

-- Clear corrupted data
local success, errorMessage = pcall(function()
    adminDataStore:RemoveAsync("AdminData")
end)

if success then
    print("✅ Corrupted admin data cleared!")
else
    warn("❌ Failed to clear:", errorMessage)
end
