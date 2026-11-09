--!strict
-- Anime Miner Tycoon :: persistence
-- Uses DataStore when available; Studio without API access falls back to memory.

local DataStoreService = game:GetService("DataStoreService")

local DataService = {}

local store = nil
local ok, result = pcall(function()
	return DataStoreService:GetDataStore("AnimeMinerTycoon_v2")
end)
if ok then
	store = result
end

local profiles: { [number]: any } = {}
DataService.Profiles = profiles

function DataService.Default()
	return {
		coins = 300,
		gems = 60,
		zone = 1,
		units = {},
		pets = {},
		nextUnitId = 1,
		research = {},
		pickaxe = 1,
		rebirths = 0,
		lastDaily = 0,
		tutorial = 1,
		tutorialStarted = false,
		tutorialDone = false,
		tutorialRewarded = false,
		boosts = {},
		claimed = {},
		discovered = {},
		settings = { quality = "normal", petsVisible = true, hudVisible = false },
		sideQuests = {},
		stats = { blocksMined = 0, coinsEarned = 0, rolls = 0, bestRarity = "None", bestLevel = 0, chestsOpened = 0, rebirthBlocks = 0 },
	}
end

local function deepMerge(default, loaded)
	for key, value in pairs(loaded) do
		if type(value) == "table" and type(default[key]) == "table" then
			for nestedKey, nestedValue in pairs(value) do
				default[key][nestedKey] = nestedValue
			end
		else
			default[key] = value
		end
	end
	return default
end

function DataService.Load(player: Player)
	local profile = DataService.Default()
	if store then
		local success, data = pcall(function()
			return store:GetAsync("player_" .. player.UserId)
		end)
		if success and type(data) == "table" then
			profile = deepMerge(profile, data)
		end
	end
	profile.userId = player.UserId
	profiles[player.UserId] = profile
	return profile
end

function DataService.Get(player: Player)
	return profiles[player.UserId]
end

-- developer tool: wipe a profile back to a fresh save
function DataService.Reset(player: Player)
	local profile = DataService.Default()
	profile.userId = player.UserId
	profiles[player.UserId] = profile
	return profile
end

function DataService.Save(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return false
	end
	if store then
		local success = pcall(function()
			store:SetAsync("player_" .. player.UserId, {
				coins = profile.coins,
				gems = profile.gems,
				zone = profile.zone,
				units = profile.units,
				pets = profile.pets,
				nextUnitId = profile.nextUnitId,
				research = profile.research,
				pickaxe = profile.pickaxe,
				rebirths = profile.rebirths,
				lastDaily = profile.lastDaily,
				tutorial = profile.tutorial,
				tutorialStarted = profile.tutorialStarted,
				tutorialDone = profile.tutorialDone,
				tutorialRewarded = profile.tutorialRewarded,
				boosts = profile.boosts,
				claimed = profile.claimed,
				discovered = profile.discovered,
				settings = profile.settings,
				stats = profile.stats,
			})
		end)
		return success
	end
	return true
end

function DataService.Release(player: Player)
	DataService.Save(player)
	profiles[player.UserId] = nil
end

return DataService
