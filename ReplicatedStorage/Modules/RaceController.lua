-- RaceController.lua
-- Dedicated race system controller module
-- Manages race lifecycle, state, and statistics

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local DataManager = require(ReplicatedStorage.Modules.DataManager)

local RaceController = {}

-- Private variables
local raceActive = false
local startingRace = false -- ✅ FIXED: Atomic lock to prevent concurrent race starts
local raceStartTime = 0
local raceParticipants = {} -- player -> race data
local raceCooldownEnd = 0
local raceWinner = nil
local raceQueue = {} -- list of players in queue
local autoSchedulerConnection = nil -- connection for auto-scheduler
local raceStats = {
	totalRaces = 0,
	averageParticipants = 0,
	averageDuration = 0,
	lastRaceTime = 0
}

-- Initialize race controller
function RaceController.Init()
	print("[RaceController] Initializing race controller")

	-- Send initial leaderboard
	local leaderboard = DataManager.GetRaceLeaderboard()
	RemoteEvents.BroadcastLeaderboardUpdate(leaderboard)

	print("[RaceController] Race controller initialized")
end

-- Start a race
function RaceController.StartRace()
	-- ✅ FIXED: Atomic lock to prevent concurrent race starts
	if startingRace then
		warn("[RaceController] Race start already in progress")
		return false
	end

	if raceActive then
		warn("[RaceController] Race already active")
		return false
	end

	if tick() < raceCooldownEnd then
		warn("[RaceController] Race on cooldown")
		return false
	end

	local playerCount = 0
	for _ in pairs(Players:GetPlayers()) do
		playerCount = playerCount + 1
	end

	if playerCount < Config.MIN_PLAYERS_FOR_RACE then
		warn(string.format("[RaceController] Not enough players for race: %d/%d", playerCount, Config.MIN_PLAYERS_FOR_RACE))
		return false
	end

	-- Set atomic lock
	startingRace = true

	-- Start race
	raceActive = true
	raceStartTime = tick() + Config.RACE_START_DELAY
	raceParticipants = {}
	raceWinner = nil

	-- Prepare participants
	local participantCount = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if participantCount < Config.MAX_RACE_PARTICIPANTS then
			DataManager.StartRaceForPlayer(player)
			raceParticipants[player] = {
				startTime = raceStartTime,
				checkpoints = 0,
				finished = false
			}
			participantCount = participantCount + 1
		end
	end

	-- Broadcast race start
	RemoteEvents.BroadcastRaceStart({
		startTime = raceStartTime,
		participantCount = participantCount,
		maxTime = Config.RACE_DURATION_SECONDS
	})

	-- Schedule race timeout
	task.delay(Config.RACE_DURATION_SECONDS, function()
		if raceActive then
			RaceController.EndRace(false)
		end
	end)

	-- Update stats
	raceStats.totalRaces = raceStats.totalRaces + 1
	raceStats.lastRaceTime = tick()

	-- Release atomic lock
	startingRace = false

	print(string.format("[RaceController] Race started with %d participants", participantCount))
	return true
end

-- End a race
function RaceController.EndRace(completed)
	if not raceActive then return end

	raceActive = false
	raceCooldownEnd = tick() + Config.RACE_COOLDOWN_SECONDS

	local results = {
		completed = completed,
		winner = raceWinner and raceWinner.Name or nil,
		participants = {}
	}

	-- Process results
	for player, raceData in pairs(raceParticipants) do
		local finished = raceData.finished
		DataManager.EndRaceForPlayer(player, finished)

		table.insert(results.participants, {
			playerName = player.Name,
			finished = finished,
			checkpoints = raceData.checkpoints,
			time = finished and (raceData.finishTime - raceData.startTime) or nil
		})
	end

	-- Update leaderboard
	local leaderboard = DataManager.GetRaceLeaderboard()
	RemoteEvents.BroadcastLeaderboardUpdate(leaderboard)

	-- Broadcast race end
	RemoteEvents.BroadcastRaceEnd(results)

	-- Update average stats
	local participantCount = #results.participants
	if participantCount > 0 then
		raceStats.averageParticipants = (raceStats.averageParticipants * (raceStats.totalRaces - 1) + participantCount) / raceStats.totalRaces
		if completed then
			local duration = tick() - raceStartTime
			raceStats.averageDuration = (raceStats.averageDuration * (raceStats.totalRaces - 1) + duration) / raceStats.totalRaces
		end
	end

	print(string.format("[RaceController] Race ended - completed: %s, winner: %s",
		tostring(completed), results.winner or "none"))
end

-- Check if player finished race (called when touching final checkpoint)
function RaceController.CheckRaceFinish(player, checkpointId)
	if not raceActive or not raceParticipants[player] then return end

	local raceData = raceParticipants[player]
	local Checkpoints = workspace:WaitForChild("Checkpoints")
	local totalCheckpoints = #Checkpoints:GetChildren()

	if checkpointId >= totalCheckpoints and not raceData.finished then
		raceData.finished = true
		raceData.finishTime = tick()
		raceData.checkpoints = checkpointId

		-- Update finish count
		DataManager.UpdateFinishCount(player)

		local placement = 1
		-- Check if this player is the winner
		if not raceWinner then
			raceWinner = player
			DataManager.UpdateRaceData(player, raceData.finishTime - raceData.startTime, checkpointId)
			player.racesWon = (player.racesWon or 0) + 1

			-- Send notification
			RemoteEvents.SendRaceNotification(player, {
				type = "winner",
				message = "🏆 You won the race!",
				time = raceData.finishTime - raceData.startTime
			})

			-- Check if all participants finished
			local allFinished = true
			for p, rd in pairs(raceParticipants) do
				if not rd.finished then
					allFinished = false
					break
				end
			end

			if allFinished then
				RaceController.EndRace(true)
			end
		else
			-- Send placement notification
			local placement = 1
			for p, rd in pairs(raceParticipants) do
				if rd.finished and rd.finishTime < raceData.finishTime then
					placement = placement + 1
				end
			end

			RemoteEvents.SendRaceNotification(player, {
				type = "finished",
				message = string.format("🎯 Race finished! Position: %d", placement),
				time = raceData.finishTime - raceData.startTime
			})
		end

		print(string.format("[RaceController] %s finished race in position %d", player.Name, placement))
	end
end

-- Get race status
function RaceController.GetRaceStatus()
	return {
		active = raceActive,
		startTime = raceStartTime,
		timeRemaining = raceActive and math.max(0, Config.RACE_DURATION_SECONDS - (tick() - raceStartTime)) or 0,
		participantCount = #raceParticipants,
		winner = raceWinner and raceWinner.Name or nil
	}
end

-- Get race statistics
function RaceController.GetRaceStats()
	return {
		totalRaces = raceStats.totalRaces,
		averageParticipants = raceStats.averageParticipants,
		averageDuration = raceStats.averageDuration,
		lastRaceTime = raceStats.lastRaceTime,
		isActive = raceActive,
		cooldownRemaining = math.max(0, raceCooldownEnd - tick())
	}
end

-- Force end race (admin command)
function RaceController.ForceEndRace()
	if raceActive then
		RaceController.EndRace(false)
		return true
	end
	return false
end

-- Check if race can be started
function RaceController.CanStartRace()
	if raceActive then return false, "Race already active" end
	if tick() < raceCooldownEnd then return false, "Race on cooldown" end

	local playerCount = 0
	for _ in pairs(Players:GetPlayers()) do
		playerCount = playerCount + 1
	end

	if playerCount < Config.MIN_PLAYERS_FOR_RACE then
		return false, string.format("Need %d players, have %d", Config.MIN_PLAYERS_FOR_RACE, playerCount)
	end

	return true
end

-- Join race queue
function RaceController.JoinRaceQueue(player)
	if not player then return false end

	-- Check if already in queue
	for _, entry in ipairs(raceQueue) do
		if entry.player == player then
			return false, "Already in queue"
		end
	end

	-- ✨ NEW: Calculate skill level based on race performance
	local skillLevel = RaceController.CalculateSkillLevel(player)

	-- Add to queue with skill level
	local queueEntry = {
		player = player,
		skillLevel = skillLevel,
		joinTime = tick()
	}
	table.insert(raceQueue, queueEntry)

	-- Sort queue by skill level (group similar skills together)
	table.sort(raceQueue, function(a, b)
		return a.skillLevel < b.skillLevel
	end)

	print(string.format("[RaceController] %s joined race queue (skill: %.2f)", player.Name, skillLevel))

	-- Broadcast queue update
	RaceController.BroadcastQueueUpdate()

	return true
end

-- ✨ NEW: Calculate skill level based on race performance
function RaceController.CalculateSkillLevel(player)
	local playerData = DataManager.GetPlayerData(player)
	if not playerData then
		-- ✅ FIXED: Random starting skill for new players (800-1200)
		return 800 + math.random() * 400
	end

	local bestTime = playerData.bestTime
	local totalRaces = playerData.totalRaces or 0
	local totalWins = playerData.totalWins or 0

	if not bestTime or totalRaces < 3 then
		-- ✅ FIXED: Random starting skill for inexperienced players
		return 800 + math.random() * 400
	end

	-- Skill level based on best time (lower time = higher skill)
	-- Assuming typical race times are 30-120 seconds
	local skillLevel = math.max(100, math.min(2000, 2000 - (bestTime * 10)))

	-- ✅ FIXED: Experience penalty (reduce skill for too many races without wins)
	skillLevel = skillLevel - (totalRaces * 2)

	-- ✅ FIXED: Win rate bonus (reward consistent winners)
	local winRate = totalRaces > 0 and (totalWins / totalRaces) or 0
	if winRate > 0.5 then
		skillLevel = skillLevel + (winRate * 200) -- Up to +100 bonus for 50%+ win rate
	elseif winRate < 0.2 then
		skillLevel = skillLevel - 50 -- Penalty for very low win rate
	end

	return math.max(100, math.min(2000, skillLevel)) -- Clamp between 100-2000
end

-- Leave race queue
function RaceController.LeaveRaceQueue(player)
	if not player then return false end

	-- Find and remove from queue (now queue contains entries, not just players)
	for i, entry in ipairs(raceQueue) do
		if entry.player == player then
			table.remove(raceQueue, i)
			print(string.format("[RaceController] %s left race queue", player.Name))

			-- Broadcast queue update
			RaceController.BroadcastQueueUpdate()

			return true
		end
	end

	return false, "Not in queue"
end

-- Get race queue
function RaceController.GetRaceQueue()
	local queueNames = {}
	for _, player in ipairs(raceQueue) do
		table.insert(queueNames, player.Name)
	end
	return queueNames
end

-- Broadcast queue update to all clients
function RaceController.BroadcastQueueUpdate()
	local queueData = {
		queue = RaceController.GetRaceQueue(),
		queueSize = #raceQueue,
		skillLevels = {} -- Include skill levels for matchmaking display
	}

	-- Add skill levels to queue data
	for _, entry in ipairs(raceQueue) do
		table.insert(queueData.skillLevels, {
			playerName = entry.player.Name,
			skillLevel = entry.skillLevel
		})
	end

	RemoteEvents.BroadcastRaceQueueUpdate(queueData)
end

-- Start auto-race scheduler
function RaceController.StartAutoScheduler()
	if autoSchedulerConnection then
		autoSchedulerConnection:Disconnect()
	end

	autoSchedulerConnection = task.spawn(function()
		while true do
			task.wait(Config.AUTO_RACE_INTERVAL_MINUTES * 60) -- Convert minutes to seconds

			-- Check if we can start a race
			local canStart, reason = RaceController.CanStartRace()
			if canStart then
				local success = RaceController.StartRace()
				if success then
					print("[RaceController] ✓ Auto-race started successfully")
				else
					warn("[RaceController] ⚠️ Auto-race failed to start")
				end
			else
				print(string.format("[RaceController] ⏭️ Auto-race skipped: %s", reason))
			end
		end
	end)

	print(string.format("[RaceController] ✓ Auto-race scheduler started (every %d minutes)", Config.AUTO_RACE_INTERVAL_MINUTES))
end

-- ✨ NEW: Manual race trigger for testing (admin command)
function RaceController.TriggerManualRace(adminPlayer)
	if not adminPlayer then
		return false, "Admin player required"
	end

	print(string.format("[RaceController] Manual race trigger requested by %s", adminPlayer.Name))

	-- Check if we can start a race
	local canStart, reason = RaceController.CanStartRace()
	if not canStart then
		warn(string.format("[RaceController] Manual race trigger failed: %s", reason))
		return false, reason
	end

	-- Start the race
	local success = RaceController.StartRace()
	if success then
		print(string.format("[RaceController] ✓ Manual race started by %s", adminPlayer.Name))
		return true, "Race started successfully"
	else
		warn(string.format("[RaceController] ⚠️ Manual race failed to start for %s", adminPlayer.Name))
		return false, "Failed to start race"
	end
end

-- Stop auto-race scheduler
function RaceController.StopAutoScheduler()
	if autoSchedulerConnection then
		task.cancel(autoSchedulerConnection)
		autoSchedulerConnection = nil
		print("[RaceController] Auto-race scheduler stopped")
	end
end

-- Cleanup on server shutdown
function RaceController.Cleanup()
	RaceController.StopAutoScheduler()

	if raceActive then
		RaceController.EndRace(false)
	end
	raceParticipants = {}
	raceQueue = {}
end

return RaceController
