--!strict
-- Anime Miner Tycoon :: boosts, combined multipliers, quests

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local WeatherService = require(script.Parent:WaitForChild("WeatherService"))

local ProgressService = {}

local boostById: { [string]: any } = {}
for _, boost in ipairs(Config.Boosts) do
	boostById[boost.id] = boost
end
ProgressService.BoostById = boostById

local function now(): number
	return os.time()
end

-- Strip expired boosts and return the live ones.
function ProgressService.ActiveBoosts(profile)
	profile.boosts = profile.boosts or {}
	local live = {}
	local currentTime = now()
	for boostId, endsAt in pairs(profile.boosts) do
		local def = boostById[boostId]
		if not def or type(endsAt) ~= "number" or endsAt <= currentTime then
			profile.boosts[boostId] = nil
		else
			live[#live + 1] = {
				id = def.id,
				name = def.name,
				desc = def.desc,
				color = def.color,
				timeLeft = endsAt - currentTime,
				duration = def.duration,
			}
		end
	end
	table.sort(live, function(a, b)
		return a.id < b.id
	end)
	return live
end

-- Personal boost multipliers, expressed the same way as weather multipliers.
function ProgressService.BoostMultipliers(profile)
	local added = { coin = 1, power = 1, speed = 1, luck = 1 }
	local currentTime = now()
	profile.boosts = profile.boosts or {}
	for boostId, endsAt in pairs(profile.boosts) do
		local def = boostById[boostId]
		if def and type(endsAt) == "number" and endsAt > currentTime then
			if def.kind == "coin" then
				added.coin *= def.value
			elseif def.kind == "power" then
				added.power *= def.value
			elseif def.kind == "speed" then
				added.speed *= def.value
			elseif def.kind == "luck" then
				added.luck *= (1 + def.value)
			end
		end
	end
	return added
end

-- Weather x personal boosts, in the shape CrewService and MiningService expect.
-- gamepass multipliers (owned perks) are injected here so every system that
-- already reads Combined() honours them without duplicating the logic
local passProvider = nil

function ProgressService.SetPassProvider(fn)
	passProvider = fn
end

function ProgressService.Combined(profile)
	local weather = WeatherService.Multipliers()
	local boosts = ProgressService.BoostMultipliers(profile)
	local pass = nil
	if passProvider then
		local ok, value = pcall(passProvider, profile)
		if ok then
			pass = value
		end
	end
	local passPower = (pass and pass.power) or 1
	local passSpeed = (pass and pass.speed) or 1
	local passCoin = (pass and pass.coin) or 1
	local passLuck = (pass and pass.luck) or 1
	-- rebirth multipliers are permanent and sit on top of weather/boosts/passes
	local rebirthPower = ProgressService.RebirthPowerMultiplier(profile)
	local rebirthCoin = ProgressService.RebirthCoinMultiplier(profile)
	return {
		power = weather.power * boosts.power * passPower * rebirthPower,
		speed = weather.speed * boosts.speed * passSpeed,
		coin = weather.coin * boosts.coin * passCoin * rebirthCoin,
		luck = weather.luck * boosts.luck * passLuck,
	}
end

function ProgressService.BuyBoost(profile, boostId: string)
	local def = boostById[boostId]
	if not def then
		return false, "Unknown boost."
	end
	if profile.gems < def.cost then
		return false, "Need " .. def.cost .. " gems for " .. def.name .. "."
	end
	profile.gems -= def.cost
	profile.boosts = profile.boosts or {}
	local currentTime = now()
	local existing = profile.boosts[boostId]
	if type(existing) == "number" and existing > currentTime then
		profile.boosts[boostId] = existing + def.duration
	else
		profile.boosts[boostId] = currentTime + def.duration
	end
	return true, def.name .. " activated!"
end

function ProgressService.ShopPayload(profile)
	local active = {}
	for _, entry in ipairs(ProgressService.ActiveBoosts(profile)) do
		active[entry.id] = entry.timeLeft
	end
	local list = {}
	for _, def in ipairs(Config.Boosts) do
		list[#list + 1] = {
			id = def.id,
			name = def.name,
			desc = def.desc,
			cost = def.cost,
			duration = def.duration,
			color = def.color,
			timeLeft = active[def.id] or 0,
		}
	end
	return list
end

local MAX_PICKAXE = 25

function ProgressService.PickaxeCost(profile): number
	local level = math.clamp(profile.pickaxe or 1, 1, MAX_PICKAXE)
	return math.floor(180 * 1.52 ^ (level - 1))
end

function ProgressService.PickaxePower(profile): number
	return 1 + 0.3 * ((profile.pickaxe or 1) - 1)
end

function ProgressService.PickaxeMaxed(profile): boolean
	return (profile.pickaxe or 1) >= MAX_PICKAXE
end

function ProgressService.PickaxeLevel(profile): number
	return profile.pickaxe or 1
end

function ProgressService.BuyPickaxe(profile)
	local level = profile.pickaxe or 1
	if level >= MAX_PICKAXE then
		return false, "Your pickaxe is already maxed."
	end
	local cost = ProgressService.PickaxeCost(profile)
	if profile.coins < cost then
		return false, "Need " .. cost .. " coins to forge the next level."
	end
	profile.coins -= cost
	profile.pickaxe = level + 1
	return true, "Pickaxe forged to level " .. profile.pickaxe .. " (+30% swing)!"
end

-- rebirth -------------------------------------------------------------------
function ProgressService.RebirthCount(profile): number
	return math.max(0, math.floor(profile.rebirths or 0))
end

function ProgressService.RebirthCoinMultiplier(profile): number
	return 1 + Config.Rebirth.coinPerLevel * ProgressService.RebirthCount(profile)
end

function ProgressService.RebirthPowerMultiplier(profile): number
	return 1 + Config.Rebirth.powerPerLevel * ProgressService.RebirthCount(profile)
end

function ProgressService.RebirthInfo(profile)
	local count = ProgressService.RebirthCount(profile)
	local blocks = (profile.stats and profile.stats.blocksMined) or 0
	local blocksReq = Config.BlocksForLevel(Config.Rebirth.levelReq)
	local level = Config.MinerLevel(profile.stats)
	return {
		count = count,
		coinMult = ProgressService.RebirthCoinMultiplier(profile),
		powerMult = ProgressService.RebirthPowerMultiplier(profile),
		nextCoinMult = 1 + Config.Rebirth.coinPerLevel * (count + 1),
		nextPowerMult = 1 + Config.Rebirth.powerPerLevel * (count + 1),
		level = level,
		levelReq = Config.Rebirth.levelReq,
		blocks = blocks,
		blocksReq = blocksReq,
		ratio = math.clamp(blocks / math.max(1, blocksReq), 0, 1),
		canRebirth = level >= Config.Rebirth.levelReq,
	}
end

-- resets the run and banks one rebirth: the only thing that survives is the
-- multiplier, plus everything that was never part of the mining loop
function ProgressService.Rebirth(profile)
	local level = Config.MinerLevel(profile.stats)
	if level < Config.Rebirth.levelReq then
		return false, "Rebirth needs Miner Lv " .. Config.Rebirth.levelReq .. " (you are Lv " .. level .. ")."
	end
	local count = ProgressService.RebirthCount(profile) + 1
	profile.stats.rebirthBlocks = (profile.stats.rebirthBlocks or 0) + (profile.stats.blocksMined or 0)
	profile.stats.blocksMined = 0
	profile.stats.coinsEarned = 0
	profile.stats.bestLevel = math.max(profile.stats.bestLevel or 0, level)
	profile.rebirths = count
	profile.coins = 0
	profile.pickaxe = 1
	profile.research = {}
	profile.zone = 1
	local coin = math.floor(Config.Rebirth.coinPerLevel * count * 100 + 0.5)
	local power = math.floor(Config.Rebirth.powerPerLevel * count * 100 + 0.5)
	return true, string.format("REBIRTH %d! +%d%% coins, +%d%% hero power, forever.", count, coin, power)
end

function ProgressService.StatValue(profile, stat: string): number
	if stat == "research" then
		local count = 0
		for _ in pairs(profile.research or {}) do
			count += 1
		end
		return count
	end
	if stat == "bestLevel" then
		return (profile.stats and profile.stats.bestLevel) or 0
	end
	if stat == "bestZone" then
		local best = (profile.stats and profile.stats.bestZone) or 0
		return math.max(best, profile.zone or 1)
	end
	if stat == "pickaxe" then
		return profile.pickaxe or 1
	end
	return (profile.stats and profile.stats[stat]) or 0
end

function ProgressService.Quests(profile)
	profile.claimed = profile.claimed or {}
	local list = {}
	for _, quest in ipairs(Config.Quests) do
		local progress = math.min(ProgressService.StatValue(profile, quest.stat), quest.goal)
		local claimed = profile.claimed[quest.id] == true
		list[#list + 1] = {
			id = quest.id,
			name = quest.name,
			desc = quest.desc,
			goal = quest.goal,
			progress = progress,
			reward = quest.reward,
			claimed = claimed,
			claimable = (not claimed) and progress >= quest.goal,
		}
	end
	return list
end

function ProgressService.Claim(profile, questId: string)
	profile.claimed = profile.claimed or {}
	if profile.claimed[questId] then
		return false, "Already claimed."
	end
	local quest = nil
	for _, entry in ipairs(Config.Quests) do
		if entry.id == questId then
			quest = entry
			break
		end
	end
	if not quest then
		return false, "Unknown quest."
	end
	if ProgressService.StatValue(profile, quest.stat) < quest.goal then
		return false, "Not finished yet."
	end
	profile.claimed[questId] = true
	profile.gems += quest.reward
	return true, quest.name .. " complete! +" .. quest.reward .. " gems"
end

function ProgressService.IndexPayload(profile)
	profile.discovered = profile.discovered or {}
	local list = {}
	for _, hero in ipairs(Config.Heroes) do
		list[#list + 1] = {
			id = hero.id,
			name = hero.name,
			rarity = hero.rarity,
			color = hero.color,
			quote = hero.quote,
			count = profile.discovered[hero.id] or 0,
		}
	end
	return list
end

return ProgressService
