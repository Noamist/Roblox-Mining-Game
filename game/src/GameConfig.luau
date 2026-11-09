--!strict
-- Anime Miner Tycoon :: shared configuration
-- Every tunable value in the game lives here so the client and server agree.

local RunService = game:GetService("RunService")

local Config = {}

Config.TITLE = "ANIME MINER TYCOON"
Config.SUBTITLE = "Recruit heroes. Break the world. Descend."

Config.RollCost = { single = 100, multi = 900 }
Config.MutationCost = 25
Config.EnchantCost = 15
Config.BaseCrewSlots = 2
Config.MaxUnits = 60
Config.BlockRespawn = 7
Config.ChestCooldown = 22

Config.Rarities = {
	{ id = "Common", weight = 55, color = Color3.fromRGB(176, 196, 214) },
	{ id = "Rare", weight = 27, color = Color3.fromRGB(88, 168, 255) },
	{ id = "Epic", weight = 12, color = Color3.fromRGB(186, 108, 255) },
	{ id = "Legendary", weight = 5, color = Color3.fromRGB(255, 190, 64) },
	{ id = "Mythic", weight = 1, color = Color3.fromRGB(255, 82, 118) },
}

Config.Heroes = {
	{ id = "kaida", name = "Kaida, Ember Fist", rarity = "Common", power = 7, speed = 1.15, color = Color3.fromRGB(255, 126, 80), quote = "Sparks fly where I walk." },
	{ id = "renji", name = "Renji, Stone Breath", rarity = "Common", power = 9, speed = 0.85, color = Color3.fromRGB(190, 170, 140), quote = "Mountains are just slow rocks." },
	{ id = "mika", name = "Mika, Windstep", rarity = "Common", power = 5, speed = 1.55, color = Color3.fromRGB(150, 240, 200), quote = "You missed me already." },
	{ id = "sora", name = "Sora, Tidecaller", rarity = "Rare", power = 14, speed = 1.2, color = Color3.fromRGB(96, 200, 255), quote = "The tide always returns." },
	{ id = "yuki", name = "Yuki, Frostblade", rarity = "Rare", power = 17, speed = 1.05, color = Color3.fromRGB(180, 225, 255), quote = "Cold hands, sharp edges." },
	{ id = "kaito", name = "Kaito, Thunderclap", rarity = "Rare", power = 12, speed = 1.65, color = Color3.fromRGB(255, 235, 120), quote = "Blink and it's over." },
	{ id = "akane", name = "Akane, Blood Lotus", rarity = "Epic", power = 28, speed = 1.3, color = Color3.fromRGB(255, 90, 120), quote = "Petals fall. So do you." },
	{ id = "kuro", name = "Kuro, Void Fang", rarity = "Epic", power = 34, speed = 1.1, color = Color3.fromRGB(130, 100, 200), quote = "Nothing escapes the dark." },
	{ id = "hana", name = "Hana, Bloomkeeper", rarity = "Epic", power = 22, speed = 1.85, color = Color3.fromRGB(255, 150, 220), quote = "Everything grows for me." },
	{ id = "genji", name = "Genji, Iron Saint", rarity = "Legendary", power = 62, speed = 1.2, color = Color3.fromRGB(240, 200, 90), quote = "Steel is a promise." },
	{ id = "amaterasu", name = "Amaterasu, Sun Regent", rarity = "Legendary", power = 74, speed = 1.35, color = Color3.fromRGB(255, 170, 60), quote = "The sun does not negotiate." },
	{ id = "susano", name = "Susano, Storm Sovereign", rarity = "Mythic", power = 140, speed = 1.55, color = Color3.fromRGB(120, 200, 255), quote = "Kneel to the storm." },
	{ id = "izanami", name = "Izanami, Eclipse Queen", rarity = "Mythic", power = 155, speed = 1.45, color = Color3.fromRGB(200, 120, 255), quote = "Light ends where I begin." },
}

-- y is the floor centre. Each zone is a sealed cavern 60 studs tall.
-- Difficulty curve: blockHp rises ~3.2x per biome while value/blockHp stays near
-- 0.32-0.5, so income per second grows about 3x per zone and the next pickaxe
-- level is always reachable. MiningService also enforces a 1% max-HP damage floor
-- so an under-geared crew can still break anything instead of stalling forever.
-- Gates are deliberately slow: a biome needs its research node AND a miner level
-- that takes real ore (see Config.MinerLevel), so a fresh save cannot rush the
-- depth in a couple of minutes.
Config.Zones = {
	{
		id = 1, name = "Starlit Quarry", y = -80, blockHp = 14, value = 7, gemChance = 0.05, levelReq = 1,
		blockColor = Color3.fromRGB(120, 150, 200), accent = Color3.fromRGB(150, 200, 255),
		material = Enum.Material.Slate, research = nil,
		wallColor = Color3.fromRGB(52, 60, 92), prop = "crystal", propColor = Color3.fromRGB(140, 190, 255),
	},
	{
		id = 2, name = "Crystal Caverns", y = -170, blockHp = 65, value = 26, gemChance = 0.07, levelReq = 3,
		blockColor = Color3.fromRGB(110, 220, 255), accent = Color3.fromRGB(150, 245, 255),
		material = Enum.Material.Glass, research = "zone2",
		wallColor = Color3.fromRGB(40, 78, 102), prop = "crystal", propColor = Color3.fromRGB(120, 245, 255),
	},
	{
		id = 3, name = "Magma Veins", y = -260, blockHp = 260, value = 85, gemChance = 0.09, levelReq = 6,
		blockColor = Color3.fromRGB(255, 110, 60), accent = Color3.fromRGB(255, 170, 90),
		material = Enum.Material.Neon, research = "zone3",
		wallColor = Color3.fromRGB(66, 32, 32), prop = "lava", propColor = Color3.fromRGB(255, 130, 60),
	},
	{
		id = 4, name = "Frozen Abyss", y = -350, blockHp = 900, value = 280, gemChance = 0.11, levelReq = 10,
		blockColor = Color3.fromRGB(180, 240, 255), accent = Color3.fromRGB(225, 250, 255),
		material = Enum.Material.Ice, research = "zone4",
		wallColor = Color3.fromRGB(52, 86, 112), prop = "ice", propColor = Color3.fromRGB(200, 245, 255),
	},
	{
		id = 5, name = "Void Sanctum", y = -440, blockHp = 2800, value = 950, gemChance = 0.13, levelReq = 15,
		blockColor = Color3.fromRGB(170, 120, 255), accent = Color3.fromRGB(210, 160, 255),
		material = Enum.Material.Neon, research = "zone5",
		wallColor = Color3.fromRGB(34, 26, 58), prop = "void", propColor = Color3.fromRGB(180, 120, 255),
	},
	{
		id = 6, name = "Celestial Core", y = -530, blockHp = 9000, value = 3200, gemChance = 0.16, levelReq = 22,
		blockColor = Color3.fromRGB(255, 235, 160), accent = Color3.fromRGB(255, 245, 210),
		material = Enum.Material.Neon, research = "zone6",
		wallColor = Color3.fromRGB(78, 62, 38), prop = "gold", propColor = Color3.fromRGB(255, 225, 140),
	},
}

-- effect keys: power/luck/coin are additive bonuses, crew adds slots, zone unlocks depth, trade unlocks trading
Config.Research = {
	{ id = "power1", name = "Reinforced Picks", desc = "+25% hero power", cost = 250, requires = {}, effect = { power = 0.25 } },
	{ id = "zone2", name = "Cavern Mapping", desc = "Unlock Crystal Caverns", cost = 1800, requires = { "power1" }, effect = { zone = 2 } },
	{ id = "crew1", name = "Recruit Board", desc = "+1 crew slot", cost = 900, requires = { "zone2" }, effect = { crew = 1 } },
	{ id = "luck1", name = "Lucky Lanterns", desc = "+20% gacha luck", cost = 1200, requires = { "zone2" }, effect = { luck = 0.2 } },
	{ id = "zone3", name = "Heat Shielding", desc = "Unlock Magma Veins", cost = 7000, requires = { "crew1" }, effect = { zone = 3 } },
	{ id = "coin1", name = "Ore Refinery", desc = "+35% coin yield", cost = 4200, requires = { "zone3" }, effect = { coin = 0.35 } },
	{ id = "trade", name = "Guild Charter", desc = "Unlock player trading", cost = 6500, requires = { "luck1" }, effect = { trade = true } },
	{ id = "zone4", name = "Cryo Rigs", desc = "Unlock Frozen Abyss", cost = 26000, requires = { "zone3" }, effect = { zone = 4 } },
	{ id = "power2", name = "Hero Dojo", desc = "+40% hero power", cost = 20000, requires = { "zone4" }, effect = { power = 0.4 } },
	{ id = "crew2", name = "Guild Hall", desc = "+2 crew slots", cost = 32000, requires = { "trade" }, effect = { crew = 2 } },
	{ id = "zone5", name = "Void Anchor", desc = "Unlock Void Sanctum", cost = 110000, requires = { "power2" }, effect = { zone = 5 } },
	{ id = "luck2", name = "Star Charts", desc = "+35% gacha luck", cost = 80000, requires = { "zone5" }, effect = { luck = 0.35 } },
	{ id = "zone6", name = "Celestial Key", desc = "Unlock Celestial Core", cost = 320000, requires = { "luck2" }, effect = { zone = 6 } },
	{ id = "power3", name = "Ascension Rite", desc = "+80% hero power", cost = 320000, requires = { "zone6" }, effect = { power = 0.8 } },
}

Config.Mutations = {
	{ id = "none", name = "None", mult = 1, weight = 45, color = Color3.fromRGB(200, 200, 200) },
	{ id = "shiny", name = "Shiny", mult = 1.25, weight = 24, color = Color3.fromRGB(190, 240, 255) },
	{ id = "golden", name = "Golden", mult = 1.6, weight = 15, color = Color3.fromRGB(255, 205, 90) },
	{ id = "crystal", name = "Crystal", mult = 2.0, weight = 9, color = Color3.fromRGB(140, 210, 255) },
	{ id = "void", name = "Void-Touched", mult = 2.6, weight = 5, color = Color3.fromRGB(175, 120, 255) },
	{ id = "celestial", name = "Celestial", mult = 3.5, weight = 2, color = Color3.fromRGB(255, 150, 220) },
}

Config.Enchants = {
	{ id = "none", name = "None", weight = 38, power = 1, luck = 0, color = Color3.fromRGB(200, 200, 200) },
	{ id = "sharp", name = "Sharp", weight = 26, power = 1.15, luck = 0, color = Color3.fromRGB(160, 235, 180) },
	{ id = "fabled", name = "Fabled", weight = 18, power = 1.3, luck = 0.1, color = Color3.fromRGB(120, 190, 255) },
	{ id = "radiant", name = "Radiant", weight = 12, power = 1.45, luck = 0.25, color = Color3.fromRGB(255, 210, 120) },
	{ id = "divine", name = "Divine", weight = 6, power = 1.75, luck = 0.5, color = Color3.fromRGB(255, 140, 220) },
}

Config.TraitRerollCost = 30

-- Rebirth: the one reset that pays forever. A run needs Miner Lv 24 (~16,800
-- ore mined that run); in exchange every rebirth adds a permanent coin and
-- hero-power multiplier. Heroes, pets, gems, boosts and quest claims stay.
Config.Rebirth = {
	levelReq = 24,
	coinPerLevel = 0.4,
	powerPerLevel = 0.12,
}

-- Traits are rolled once per hero and baked into that unit, so two copies of
-- the same hero can behave differently. Enchant and mutation rerolls already
-- exist; traits are the permanent identity layer the Seer can rewrite.
Config.Traits = {
	{ id = "none", name = "Untempered", desc = "No trait", weight = 30, power = 1, speed = 1, color = Color3.fromRGB(190, 200, 220) },
	{ id = "swift", name = "Swift", desc = "+15% swing speed", weight = 22, power = 1, speed = 1.15, color = Color3.fromRGB(150, 240, 220) },
	{ id = "giant", name = "Giant", desc = "+20% damage", weight = 20, power = 1.2, speed = 1, color = Color3.fromRGB(255, 176, 120) },
	{ id = "gilded", name = "Gilded", desc = "+12% damage and speed", weight = 14, power = 1.12, speed = 1.12, color = Color3.fromRGB(255, 216, 134) },
	{ id = "storm", name = "Stormbound", desc = "+30% swing speed", weight = 9, power = 1, speed = 1.3, color = Color3.fromRGB(150, 186, 255) },
	{ id = "titan", name = "Titan", desc = "+40% damage", weight = 5, power = 1.4, speed = 1, color = Color3.fromRGB(255, 120, 150) },
}

-- pets -----------------------------------------------------------------------
-- Companions follow the owner and add small yield bonuses. One egg costs less
-- than a pickaxe tier, duplicates bond into levels, and PetService caps the
-- equipped total so a full trio never trivialises a biome.
Config.PetCost = 150
Config.PetSlots = 3
Config.PetMaxLevel = 12
Config.Pets = {
	{ id = "mochi", name = "Mochi", rarity = "Common", weight = 34, coin = 0.020, gem = 0.010, shape = "cat", color = Color3.fromRGB(255, 206, 176) },
	{ id = "kitsun", name = "Kitsun", rarity = "Common", weight = 30, coin = 0.025, gem = 0.010, shape = "fox", color = Color3.fromRGB(255, 168, 96) },
	{ id = "pip", name = "Pip", rarity = "Rare", weight = 18, coin = 0.040, gem = 0.020, shape = "bird", color = Color3.fromRGB(150, 232, 255) },
	{ id = "yomi", name = "Yomi", rarity = "Rare", weight = 10, coin = 0.045, gem = 0.030, shape = "spirit", color = Color3.fromRGB(178, 156, 255) },
	{ id = "raiju", name = "Raiju", rarity = "Epic", weight = 5, coin = 0.070, gem = 0.040, shape = "beast", color = Color3.fromRGB(255, 236, 140) },
	{ id = "tsuki", name = "Tsuki", rarity = "Epic", weight = 2.4, coin = 0.060, gem = 0.060, shape = "moon", color = Color3.fromRGB(220, 200, 255) },
	{ id = "orochi", name = "Orochi", rarity = "Legendary", weight = 0.5, coin = 0.090, gem = 0.070, shape = "dragon", color = Color3.fromRGB(255, 120, 150) },
	{ id = "hikari", name = "Hikari", rarity = "Mythic", weight = 0.1, coin = 0.120, gem = 0.100, shape = "celestial", color = Color3.fromRGB(255, 226, 160) },
}

Config.Weather = {
	{ id = "clear", name = "Clear Skies", desc = "Calm air over the mines.", weight = 46, duration = 100, mult = { power = 1, luck = 1, coin = 1, speed = 1 }, color = Color3.fromRGB(150, 200, 255) },
	{ id = "meteor", name = "Meteor Shower", desc = "Luck surges. Rare heroes answer the call.", weight = 16, duration = 90, mult = { power = 1, luck = 2.0, coin = 1.15, speed = 1 }, color = Color3.fromRGB(255, 160, 90) },
	{ id = "aurora", name = "Aurora Veil", desc = "Hero power +50% across the server.", weight = 16, duration = 90, mult = { power = 1.5, luck = 1.15, coin = 1, speed = 1 }, color = Color3.fromRGB(120, 255, 210) },
	{ id = "golden", name = "Golden Fog", desc = "Coin yield +75%. Get digging.", weight = 14, duration = 90, mult = { power = 1, luck = 1.1, coin = 1.75, speed = 1 }, color = Color3.fromRGB(255, 220, 120) },
	{ id = "storm", name = "Thunderstorm", desc = "Heroes mine 40% faster.", weight = 12, duration = 90, mult = { power = 1.1, luck = 1, coin = 1, speed = 1.4 }, color = Color3.fromRGB(150, 170, 255) },
}

-- gem shop: temporary personal buffs
Config.Boosts = {
	{ id = "coin", name = "Coin Surge", desc = "Double coin yield for 5 minutes.", cost = 40, duration = 300, kind = "coin", value = 2, color = Color3.fromRGB(255, 208, 112) },
	{ id = "power", name = "Hero Rally", desc = "+60% hero power for 5 minutes.", cost = 55, duration = 300, kind = "power", value = 1.6, color = Color3.fromRGB(120, 200, 255) },
	{ id = "luck", name = "Fortune Charm", desc = "+60% gacha luck for 5 minutes.", cost = 70, duration = 300, kind = "luck", value = 0.6, color = Color3.fromRGB(255, 132, 200) },
	{ id = "speed", name = "Haste Sigil", desc = "Heroes mine 50% faster for 5 minutes.", cost = 60, duration = 300, kind = "speed", value = 1.5, color = Color3.fromRGB(120, 240, 170) },
}

Config.Quests = {
	{ id = "mine50", name = "First Haul", desc = "Mine 50 ore blocks", stat = "blocksMined", goal = 50, reward = 25 },
	{ id = "mine500", name = "Deep Digger", desc = "Mine 500 ore blocks", stat = "blocksMined", goal = 500, reward = 90 },
	{ id = "mine5000", name = "Worldbreaker", desc = "Mine 5,000 ore blocks", stat = "blocksMined", goal = 5000, reward = 350 },
	{ id = "roll10", name = "Gacha Initiate", desc = "Summon 10 heroes", stat = "rolls", goal = 10, reward = 30 },
	{ id = "roll100", name = "Gacha Devotee", desc = "Summon 100 heroes", stat = "rolls", goal = 100, reward = 150 },
	{ id = "coin10k", name = "Pocket Change", desc = "Earn 10,000 coins", stat = "coinsEarned", goal = 10000, reward = 40 },
	{ id = "coin1m", name = "Mining Magnate", desc = "Earn 1,000,000 coins", stat = "coinsEarned", goal = 1000000, reward = 400 },
	{ id = "research5", name = "Scholar", desc = "Research 5 nodes", stat = "research", goal = 5, reward = 70 },
	{ id = "level10", name = "Veteran", desc = "Level a hero to 10", stat = "bestLevel", goal = 10, reward = 80 },
	{ id = "roll1", name = "First Contract", desc = "Summon your first hero", stat = "rolls", goal = 1, reward = 15 },
	{ id = "mine100", name = "Rock Bottom", desc = "Mine 100 ore blocks", stat = "blocksMined", goal = 100, reward = 35 },
	{ id = "mine1000", name = "Stratum Breaker", desc = "Mine 1,000 ore blocks", stat = "blocksMined", goal = 1000, reward = 130 },
	{ id = "mine10000", name = "Legend of the Deep", desc = "Mine 10,000 ore blocks", stat = "blocksMined", goal = 10000, reward = 500 },
	{ id = "coin100k", name = "Deep Pockets", desc = "Earn 100,000 coins", stat = "coinsEarned", goal = 100000, reward = 120 },
	{ id = "chest10", name = "Cache Raider", desc = "Open 10 reward caches", stat = "chestsOpened", goal = 10, reward = 45 },
	{ id = "chest50", name = "Cache Collector", desc = "Open 50 reward caches", stat = "chestsOpened", goal = 50, reward = 180 },
	{ id = "pickaxe5", name = "Tempered Steel", desc = "Forge the pickaxe to level 5", stat = "pickaxe", goal = 5, reward = 60 },
	{ id = "zone2", name = "Below the Quarry", desc = "Venture into Crystal Caverns", stat = "bestZone", goal = 2, reward = 40 },
	{ id = "zone4", name = "Frozen Trail", desc = "Venture into Frozen Abyss", stat = "bestZone", goal = 4, reward = 140 },
	{ id = "zone6", name = "Edge of the Sky", desc = "Reach the Celestial Core", stat = "bestZone", goal = 6, reward = 400 },
}

-- Roblox gamepasses. Create each pass on the place's Game Passes page and paste
-- its numeric id into `passId`; a pass left at 0 is shown as "not set up" and is
-- never prompted, so a fresh place cannot sell a product that does not exist.
-- perk: coin / power / speed / luck are multipliers, crew is flat slots.
Config.GamePasses = {
	{ id = "double_coins", name = "Double Coins", desc = "Every ore and cache pays twice, forever.", perk = "coin", value = 2, passId = 0, color = Color3.fromRGB(255, 216, 134) },
	{ id = "hero_overdrive", name = "Hero Overdrive", desc = "All deployed heroes hit 50% harder.", perk = "power", value = 1.5, passId = 0, color = Color3.fromRGB(255, 150, 120) },
	{ id = "fast_hands", name = "Fast Hands", desc = "Heroes swing 35% faster and ore respawns quicker.", perk = "speed", value = 1.35, passId = 0, color = Color3.fromRGB(132, 240, 180) },
	{ id = "lucky_charm", name = "Lucky Charm", desc = "+50% summon luck for rarer heroes.", perk = "luck", value = 1.5, passId = 0, color = Color3.fromRGB(250, 154, 208) },
	{ id = "extra_crew", name = "Extra Crew", desc = "Two extra crew slots, always open.", perk = "crew", value = 2, passId = 0, color = Color3.fromRGB(150, 210, 255) },
}

local function weightedPick(list)
	local total = 0
	for _, entry in ipairs(list) do
		total += entry.weight
	end
	local roll = math.random() * total
	for _, entry in ipairs(list) do
		roll -= entry.weight
		if roll <= 0 then
			return entry
		end
	end
	return list[1]
end

Config.WeightedPick = weightedPick

function Config.RarityColor(rarityId: string): Color3
	for _, rarity in ipairs(Config.Rarities) do
		if rarity.id == rarityId then
			return rarity.color
		end
	end
	return Color3.fromRGB(200, 200, 200)
end

-- Miner level is derived from lifetime ore broken, so portals can gate on a
-- level that never needs its own save field and never goes backwards.
-- 30 blocks per level^2 (was 12) makes each miner level roughly 2.5x the ore:
-- Lv 3 (Crystal Caverns) is 120 blocks, Lv 22 (Celestial Core) is 13,230.
function Config.MinerLevel(stats)
	local blocks = (stats and stats.blocksMined) or 0
	return 1 + math.floor(math.sqrt(math.max(0, blocks) / 30))
end

-- inverse of MinerLevel: lifetime ore needed to reach a miner level
function Config.BlocksForLevel(level: number): number
	return 30 * math.max(0, level - 1) ^ 2
end

function Config.MinerProgress(stats)
	local blocks = (stats and stats.blocksMined) or 0
	local level = Config.MinerLevel(stats)
	local floor = 30 * (level - 1) ^ 2
	local ceiling = 30 * level ^ 2
	return {
		level = level,
		blocks = blocks,
		next = ceiling,
		ratio = math.clamp((blocks - floor) / math.max(1, ceiling - floor), 0, 1),
	}
end

-- Developer tools. Studio playtests are always admin, and in a published place
-- the universe owner is. Add extra UserIds here when you need a second tester.
Config.AdminUserIds = {}

function Config.IsAdmin(player): boolean
	if not player then
		return false
	end
	for _, userId in ipairs(Config.AdminUserIds) do
		if player.UserId == userId then
			return true
		end
	end
	if RunService:IsStudio() then
		return true
	end
	local ok, creatorId = pcall(function()
		return game.CreatorId
	end)
	if ok and game.CreatorType == Enum.CreatorType.User and creatorId == player.UserId then
		return true
	end
	return false
end

function Config.ZoneById(zoneId: number)
	for _, zone in ipairs(Config.Zones) do
		if zone.id == zoneId then
			return zone
		end
	end
	return nil
end

return Config
