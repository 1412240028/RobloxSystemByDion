-- ServerScriptService/CheckpointSystem/HealthMonitor.lua
-- Health Monitoring & Alerting System for Production

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local HealthMonitor = {}

-- Metrics collection
local metrics = {
	checkpointTouches = 0,
	saves = 0,
	saveFails = 0,
	respawns = 0,
	dataStoreErrors = 0,
	adminCommands = 0,
	lastHealthCheck = os.time(),
	startTime = os.time()
}

-- Health check configuration
local HEALTH_CHECK_INTERVAL = 60 -- 1 minute
local METRICS_SAVE_INTERVAL = 300 -- 5 minutes
local ALERT_THRESHOLD_SAVE_RATE = 95 -- %
local ALERT_THRESHOLD_MEMORY_MB = 500

-- Logger
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end
	local prefix = "[HealthMonitor]"
	if level == "ERROR" or level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	else
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Initialize monitoring
function HealthMonitor:Init()
	Log("INFO", "Initializing health monitoring system")
	
	-- Periodic health checks
	task.spawn(function()
		while true do
			task.wait(HEALTH_CHECK_INTERVAL)
			self:PerformHealthCheck()
		end
	end)
	
	-- Periodic metrics persistence
	task.spawn(function()
		while true do
			task.wait(METRICS_SAVE_INTERVAL)
			self:SaveMetrics()
		end
	end)
	
	Log("INFO", "Health monitoring started")
end

-- Perform comprehensive health check
function HealthMonitor:PerformHealthCheck()
	local status = {
		timestamp = os.time(),
		serverId = game.JobId:sub(1, 8),
		placeId = game.PlaceId,
		playerCount = #game.Players:GetPlayers(),
		metrics = metrics,
		health = "HEALTHY",
		alerts = {}
	}
	
	-- 1. Check DataStore connectivity
	local dsHealth = self:CheckDataStoreHealth()
	if not dsHealth then
		status.health = "DEGRADED"
		table.insert(status.alerts, "DataStore connectivity issues")
	end
	
	-- 2. Check save success rate
	if metrics.saves > 0 then
		local saveRate = ((metrics.saves - metrics.saveFails) / metrics.saves) * 100
		
		if saveRate < ALERT_THRESHOLD_SAVE_RATE then
			status.health = "DEGRADED"
			table.insert(status.alerts, string.format("Low save success rate: %.1f%%", saveRate))
		end
		
		status.saveSuccessRate = saveRate
	end
	
	-- 3. Check memory usage
	local memoryMB = gcinfo() / 1024
	status.memoryUsageMB = memoryMB
	
	if memoryMB > ALERT_THRESHOLD_MEMORY_MB then
		status.health = "WARNING"
		table.insert(status.alerts, string.format("High memory usage: %.1f MB", memoryMB))
	end
	
	-- 4. Check uptime
	local uptimeMinutes = (os.time() - metrics.startTime) / 60
	status.uptimeMinutes = uptimeMinutes
	
	-- 5. Check MessagingService quota (if GlobalMessenger available)
	local GlobalMessenger = require(game.ReplicatedStorage.CheckpointSystem.Modules.GlobalMessenger)
	local messengerStatus = GlobalMessenger:GetStatus()
	status.messagingQuota = messengerStatus
	
	if messengerStatus.QuotaUtilization > 90 then
		status.health = "WARNING"
		table.insert(status.alerts, string.format("High messaging quota usage: %.1f%%", 
			messengerStatus.QuotaUtilization))
	end
	
	-- Log health status
	if status.health ~= "HEALTHY" then
		Log("WARN", "Health check: %s", status.health)
		for _, alert in ipairs(status.alerts) do
			Log("WARN", "  - %s", alert)
		end
	else
		Log("DEBUG", "Health check: OK (players: %d, saves: %d, memory: %.1f MB)", 
			status.playerCount, metrics.saves, memoryMB)
	end
	
	-- Send to external monitoring (if configured)
	self:SendToMonitoring(status)
	
	metrics.lastHealthCheck = os.time()
	return status
end

-- Check DataStore health
function HealthMonitor:CheckDataStoreHealth()
	local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
	
	local testData = {
		test = true,
		timestamp = os.time()
	}
	
	local success = pcall(function()
		DataHandler.SaveCheckpoint(0, testData) -- Use UID 0 for test
	end)
	
	if not success then
		metrics.dataStoreErrors = metrics.dataStoreErrors + 1
	end
	
	return success
end

-- Save metrics to DataStore for dashboard
function HealthMonitor:SaveMetrics()
	local metricsStore = DataStoreService:GetDataStore("SystemMetrics_v1")
	
	local metricsData = {
		timestamp = os.time(),
		serverId = game.JobId,
		metrics = metrics,
		playerCount = #game.Players:GetPlayers()
	}
	
	pcall(function()
		metricsStore:SetAsync("Latest_" .. game.JobId, metricsData)
		
		-- Also save to history
		local history = metricsStore:GetAsync("History") or {}
		table.insert(history, 1, metricsData)
		
		-- Keep last 100 entries
		while #history > 100 do
			table.remove(history)
		end
		
		metricsStore:SetAsync("History", history)
	end)
	
	Log("DEBUG", "Metrics saved to DataStore")
end

-- Send to external monitoring (Discord/Slack webhook)
function HealthMonitor:SendToMonitoring(status)
	-- Check if webhook configured
	local webhookUrl = game:GetService("ServerStorage"):FindFirstChild("MonitoringWebhook")
	if not webhookUrl or webhookUrl.Value == "" then
		return
	end
	
	-- Only send on issues or every 10th check
	if status.health == "HEALTHY" and metrics.checkpointTouches % 10 ~= 0 then
		return
	end
	
	local color = status.health == "HEALTHY" and 3066993 or 
	              status.health == "WARNING" and 15844367 or 15158332
	
	local payload = {
		embeds = {{
			title = "Checkpoint System Health: " .. status.health,
			description = string.format(
				"**Server:** %s\n**Players:** %d\n**Uptime:** %.1f min\n**Memory:** %.1f MB",
				status.serverId,
				status.playerCount,
				status.uptimeMinutes or 0,
				status.memoryUsageMB or 0
			),
			color = color,
			fields = {
				{
					name = "Save Success Rate",
					value = string.format("%.1f%%", status.saveSuccessRate or 100),
					inline = true
				},
				{
					name = "Total Saves",
					value = tostring(metrics.saves),
					inline = true
				},
				{
					name = "Checkpoint Touches",
					value = tostring(metrics.checkpointTouches),
					inline = true
				}
			},
			timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
		}}
	}
	
	-- Add alerts if any
	if #status.alerts > 0 then
		payload.embeds[1].fields[#payload.embeds[1].fields + 1] = {
			name = "⚠️ Alerts",
			value = table.concat(status.alerts, "\n"),
			inline = false
		}
	end
	
	pcall(function()
		HttpService:PostAsync(
			webhookUrl.Value,
			HttpService:JSONEncode(payload),
			Enum.HttpContentType.ApplicationJson
		)
	end)
end

-- Increment metric
function HealthMonitor:IncrementMetric(metricName, amount)
	amount = amount or 1
	if metrics[metricName] then
		metrics[metricName] = metrics[metricName] + amount
	else
		Log("WARN", "Unknown metric: %s", metricName)
	end
end

-- Get current metrics
function HealthMonitor:GetMetrics()
	return metrics
end

-- Get detailed status
function HealthMonitor:GetDetailedStatus()
	local status = self:PerformHealthCheck()
	
	-- Add more details
	status.checkpoints = {
		totalTouches = metrics.checkpointTouches,
		averageTouchesPerPlayer = metrics.checkpointTouches / math.max(1, status.playerCount)
	}
	
	status.dataStore = {
		totalSaves = metrics.saves,
		failedSaves = metrics.saveFails,
		errors = metrics.dataStoreErrors,
		successRate = metrics.saves > 0 and 
			((metrics.saves - metrics.saveFails) / metrics.saves * 100) or 100
	}
	
	status.respawns = {
		total = metrics.respawns,
		averagePerPlayer = metrics.respawns / math.max(1, status.playerCount)
	}
	
	return status
end

-- Reset metrics (admin command)
function HealthMonitor:ResetMetrics()
	metrics = {
		checkpointTouches = 0,
		saves = 0,
		saveFails = 0,
		respawns = 0,
		dataStoreErrors = 0,
		adminCommands = 0,
		lastHealthCheck = os.time(),
		startTime = os.time()
	}
	Log("INFO", "Metrics reset")
end

return HealthMonitor