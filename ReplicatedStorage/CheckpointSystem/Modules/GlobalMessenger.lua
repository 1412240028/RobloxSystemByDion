-- ReplicatedStorage/CheckpointSystem/Modules/GlobalMessenger.lua
-- MessagingService with Rate Limiting and Queue Management

local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local GlobalMessenger = {}

-- Rate limiting configuration
local MESSAGE_QUEUE = {}
local LAST_SEND_TIME = 0
local MIN_INTERVAL = 0.5 -- 120 messages/minute = 2/sec = 0.5s interval
local MAX_QUEUE_SIZE = 100

-- Quota tracking (rolling window)
local messagesSentLastMinute = {}
local QUOTA_LIMIT = 140 -- Buffer below 150 limit

-- Subscriptions
local subscriptions = {}

-- Logger
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end
	local prefix = "[GlobalMessenger]"
	if level == "ERROR" or level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	else
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Initialize
function GlobalMessenger:Init()
	Log("INFO", "Initializing GlobalMessenger with rate limiting")
	
	-- Start queue processor
	RunService.Heartbeat:Connect(function()
		self:ProcessQueue()
	end)
	
	-- Clean quota tracker every minute
	task.spawn(function()
		while true do
			task.wait(60)
			self:CleanQuotaTracker()
		end
	end)
	
	Log("INFO", "GlobalMessenger initialized")
end

-- Queue message for sending (with priority support)
function GlobalMessenger:QueueMessage(topic, data, priority)
	if #MESSAGE_QUEUE >= MAX_QUEUE_SIZE then
		Log("ERROR", "Queue full (%d), dropping message", MAX_QUEUE_SIZE)
		return false
	end
	
	table.insert(MESSAGE_QUEUE, {
		topic = topic,
		data = data,
		queuedAt = tick(),
		priority = priority or 0 -- Higher = more important
	})
	
	-- Sort by priority (high to low)
	table.sort(MESSAGE_QUEUE, function(a, b)
		return a.priority > b.priority
	end)
	
	Log("DEBUG", "Queued message (priority: %d, queue size: %d)", priority or 0, #MESSAGE_QUEUE)
	return true
end

-- Process message queue with rate limiting
function GlobalMessenger:ProcessQueue()
	if #MESSAGE_QUEUE == 0 then return end
	
	local now = tick()
	
	-- Check rate limit (time-based)
	if now - LAST_SEND_TIME < MIN_INTERVAL then
		return -- Too soon
	end
	
	-- Check quota limit (count-based)
	if #messagesSentLastMinute >= QUOTA_LIMIT then
		if Settings.DEBUG_MODE then
			Log("WARN", "Approaching quota limit (%d/%d), throttling", 
				#messagesSentLastMinute, QUOTA_LIMIT)
		end
		return
	end
	
	-- Send next message
	local message = table.remove(MESSAGE_QUEUE, 1)
	
	local success, err = pcall(function()
		MessagingService:PublishAsync(message.topic, message.data)
	end)
	
	if success then
		LAST_SEND_TIME = now
		table.insert(messagesSentLastMinute, now)
		
		-- Log high latency
		local queueTime = now - message.queuedAt
		if queueTime > 5 then
			Log("WARN", "High queue latency: %.1fs", queueTime)
		end
		
		Log("DEBUG", "Message sent (queue: %d, quota: %d/%d)", 
			#MESSAGE_QUEUE, #messagesSentLastMinute, QUOTA_LIMIT)
	else
		Log("ERROR", "Send failed: %s", tostring(err))
		
		-- Requeue with lower priority if not too old
		if tick() - message.queuedAt < 60 then
			message.priority = math.max(0, message.priority - 1)
			table.insert(MESSAGE_QUEUE, message)
			Log("DEBUG", "Message requeued with priority %d", message.priority)
		else
			Log("WARN", "Message too old (%.1fs), dropped", tick() - message.queuedAt)
		end
	end
end

-- Clean old quota entries (rolling window)
function GlobalMessenger:CleanQuotaTracker()
	local now = tick()
	local cleaned = {}
	
	for _, timestamp in ipairs(messagesSentLastMinute) do
		if now - timestamp < 60 then
			table.insert(cleaned, timestamp)
		end
	end
	
	local removed = #messagesSentLastMinute - #cleaned
	messagesSentLastMinute = cleaned
	
	if removed > 0 then
		Log("DEBUG", "Cleaned %d old quota entries", removed)
	end
end

-- Send message immediately (bypass queue for CRITICAL messages only)
function GlobalMessenger:SendImmediate(topic, data)
	-- Check quota
	if #messagesSentLastMinute >= QUOTA_LIMIT then
		Log("ERROR", "Quota limit reached (%d/%d), cannot send immediate", 
			#messagesSentLastMinute, QUOTA_LIMIT)
		return false
	end
	
	local success, err = pcall(function()
		MessagingService:PublishAsync(topic, data)
	end)
	
	if success then
		table.insert(messagesSentLastMinute, tick())
		Log("INFO", "Immediate message sent")
		return true
	else
		Log("ERROR", "Immediate send failed: %s", tostring(err))
		return false
	end
end

-- Subscribe to topic (with callback)
function GlobalMessenger:Subscribe(topic, callback)
	if subscriptions[topic] then
		Log("WARN", "Already subscribed to topic: %s", topic)
		return false
	end
	
	local success, connection = pcall(function()
		return MessagingService:SubscribeAsync(topic, function(message)
			local callbackSuccess, callbackErr = pcall(callback, message)
			if not callbackSuccess then
				Log("ERROR", "Callback error for topic '%s': %s", topic, tostring(callbackErr))
			end
		end)
	end)
	
	if success then
		subscriptions[topic] = connection
		Log("INFO", "Subscribed to topic: %s", topic)
		return true
	else
		Log("ERROR", "Failed to subscribe to topic '%s': %s", topic, tostring(connection))
		return false
	end
end

-- Unsubscribe from topic
function GlobalMessenger:Unsubscribe(topic)
	if subscriptions[topic] then
		subscriptions[topic]:Disconnect()
		subscriptions[topic] = nil
		Log("INFO", "Unsubscribed from topic: %s", topic)
		return true
	end
	return false
end

-- Get queue status (for monitoring)
function GlobalMessenger:GetStatus()
	return {
		QueueSize = #MESSAGE_QUEUE,
		QuotaUsed = #messagesSentLastMinute,
		QuotaLimit = QUOTA_LIMIT,
		QuotaRemaining = QUOTA_LIMIT - #messagesSentLastMinute,
		QuotaUtilization = (#messagesSentLastMinute / QUOTA_LIMIT) * 100,
		LastSendTime = LAST_SEND_TIME,
		ActiveSubscriptions = 0 -- Count subscriptions
	}
end

-- Emergency: clear queue
function GlobalMessenger:ClearQueue()
	local oldSize = #MESSAGE_QUEUE
	MESSAGE_QUEUE = {}
	Log("WARN", "Queue cleared (%d messages dropped)", oldSize)
end

return GlobalMessenger