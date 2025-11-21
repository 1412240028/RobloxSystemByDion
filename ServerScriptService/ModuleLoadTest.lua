-- ModuleLoadTest.lua
-- Test script to verify that modules load without DataStore errors

print("[ModuleLoadTest] Starting module loading tests...")

local testResults = {
	passed = 0,
	failed = 0,
	total = 0
}

local function testModule(name, path)
	testResults.total = testResults.total + 1
	print(string.format("[ModuleLoadTest] Testing %s...", name))

	local success, result = pcall(function()
		return require(path)
	end)

	if success then
		print(string.format("[ModuleLoadTest] ✅ %s loaded successfully", name))
		testResults.passed = testResults.passed + 1
	else
		warn(string.format("[ModuleLoadTest] ❌ %s failed to load: %s", name, result))
		testResults.failed = testResults.failed + 1
	end
end

-- Test the modified modules
testModule("AdminLogger", game.ReplicatedStorage.Modules.AdminLogger)
testModule("DataManager", game.ReplicatedStorage.Modules.DataManager)
testModule("SystemManager", game.ReplicatedStorage.Modules.SystemManager)

-- Test other modules for completeness
testModule("RaceController", game.ReplicatedStorage.Modules.RaceController)
testModule("Config", game.ReplicatedStorage.Config.Config)

print(string.format("[ModuleLoadTest] Results: %d/%d tests passed", testResults.passed, testResults.total))

if testResults.failed == 0 then
	print("[ModuleLoadTest] ✅ All modules loaded successfully - DataStore fix appears to be working!")
else
	warn(string.format("[ModuleLoadTest] ❌ %d modules failed to load", testResults.failed))
end

return testResults
