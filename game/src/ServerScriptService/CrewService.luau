--!strict
-- Anime Miner Tycoon :: crew, gacha, leveling, mutations, enchant dice

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local CrewService = {}

local heroById: { [string]: any } = {}
for _, hero in ipairs(Config.Heroes) do
	heroById[hero.id] = hero
end

local mutationById: { [string]: any } = {}
for _, mutation in ipairs(Config.Mutations) do
	mutationById[mutation.id] = mutation
end

local enchantById: { [string]: any } = {}
for _, enchant in ipairs(Config.Enchants) do
	enchantById[enchant.id] = enchant
end

local traitById: { [string]: any } = {}
for _, trait in ipairs(Config.Traits) do
	traitById[trait.id] = trait
end

CrewService.HeroById = heroById
CrewService.MutationById = mutationById
CrewService.EnchantById = enchantById
CrewService.TraitById = traitById

function CrewService.TraitPower(unit): number
	local trait = traitById[unit.trait] or traitById.none
	return trait.power or 1
end

function CrewService.TraitSpeed(unit): number
	local trait = traitById[unit.trait] or traitById.none
	return trait.speed or 1
end

function CrewService.RollRarity(luck: number): string
	local weights = {}
	local total = 0
	for index, rarity in ipairs(Config.Rarities) do
		local weight = rarity.weight
		if index > 1 then
			-- luck pushes weight toward the rarer end of the table
			weight *= (1 + luck * 0.18 * (index - 1) * (index - 1))
		end
		weights[index] = weight
		total += weight
	end
	local roll = math.random() * total
	for index, weight in ipairs(weights) do
		roll -= weight
		if roll <= 0 then
			return Config.Rarities[index].id
		end
	end
	return "Common"
end

function CrewService.RollHero(luck: number)
	local rarity = CrewService.RollRarity(luck)
	local pool = {}
	for _, hero in ipairs(Config.Heroes) do
		if hero.rarity == rarity then
			pool[#pool + 1] = hero
		end
	end
	return pool[math.random(1, #pool)]
end

function CrewService.LevelCost(level: number): number
	return math.floor(60 * 1.3 ^ (level - 1))
end

function CrewService.EnchantPower(unit): number
	local enchant = enchantById[unit.enchant]
	return enchant and enchant.power or 1
end

function CrewService.EnchantLuck(unit): number
	local enchant = enchantById[unit.enchant]
	return enchant and enchant.luck or 0
end

function CrewService.UnitPower(unit, bonuses, weather): number
	local hero = heroById[unit.heroId]
	if not hero then
		return 0
	end
	local mutation = mutationById[unit.mutation] or mutationById.none
	local levelMultiplier = 1 + 0.22 * (unit.level - 1)
	local power = hero.power * levelMultiplier * mutation.mult * CrewService.EnchantPower(unit) * CrewService.TraitPower(unit)
	local weatherPower = weather and weather.power or 1
	return power * (1 + bonuses.power) * weatherPower
end

function CrewService.UnitInterval(unit, weather): number
	local hero = heroById[unit.heroId]
	if not hero then
		return 1
	end
	local weatherSpeed = weather and weather.speed or 1
	local speed = hero.speed * (1 + 0.04 * (unit.level - 1)) * weatherSpeed * CrewService.TraitSpeed(unit)
	return math.max(0.35, 1 / math.max(0.15, speed))
end

function CrewService.UnitInfo(unit, bonuses, weather)
	local hero = heroById[unit.heroId]
	local mutation = mutationById[unit.mutation] or mutationById.none
	local enchant = enchantById[unit.enchant] or enchantById.none
	local trait = traitById[unit.trait] or traitById.none
	local power = CrewService.UnitPower(unit, bonuses, weather)
	local interval = CrewService.UnitInterval(unit, weather)
	return {
		id = unit.id,
		heroId = hero.id,
		heroName = hero.name,
		quote = hero.quote,
		rarity = hero.rarity,
		color = hero.color,
		level = unit.level,
		equipped = unit.equipped,
		mutation = { id = mutation.id, name = mutation.name, mult = mutation.mult, color = mutation.color },
		enchant = { id = enchant.id, name = enchant.name, power = enchant.power, color = enchant.color },
		trait = { id = trait.id, name = trait.name, desc = trait.desc, color = trait.color, power = trait.power, speed = trait.speed },
		power = power,
		speed = 1 / interval,
		interval = interval,
		dps = power / interval,
		levelCost = CrewService.LevelCost(unit.level),
	}
end

function CrewService.NewUnit(profile, hero)
	local unit = {
		id = profile.nextUnitId,
		heroId = hero.id,
		level = 1,
		mutation = "none",
		enchant = "none",
		trait = Config.WeightedPick(Config.Traits).id,
		equipped = false,
	}
	profile.nextUnitId += 1
	return unit
end

-- the Seer rerolls the trait on one deployed hero, so a bad roll is not final
function CrewService.RerollTrait(profile)
	if profile.gems < Config.TraitRerollCost then
		return false, "Need " .. Config.TraitRerollCost .. " gems for a reading."
	end
	local pool = {}
	for _, unit in ipairs(profile.units) do
		if unit.equipped then
			pool[#pool + 1] = unit
		end
	end
	if #pool == 0 then
		for _, unit in ipairs(profile.units) do
			pool[#pool + 1] = unit
		end
	end
	if #pool == 0 then
		return false, "No hero to read."
	end
	profile.gems -= Config.TraitRerollCost
	local unit = pool[math.random(1, #pool)]
	local roll = Config.WeightedPick(Config.Traits)
	unit.trait = roll.id
	local hero = heroById[unit.heroId]
	return true, (hero and hero.name or "Hero") .. " now carries " .. roll.name .. " (" .. roll.desc .. ")"
end

function CrewService.FindUnit(profile, unitId: number)
	for _, unit in ipairs(profile.units) do
		if unit.id == unitId then
			return unit
		end
	end
	return nil
end

function CrewService.EquippedCount(profile): number
	local count = 0
	for _, unit in ipairs(profile.units) do
		if unit.equipped then
			count += 1
		end
	end
	return count
end

-- flat slot bonuses from gamepasses are injected so equip checks and the UI
-- agree on the same number
local crewBonusProvider = nil

function CrewService.SetCrewBonusProvider(fn)
	crewBonusProvider = fn
end

function CrewService.CrewSlots(profile, bonuses): number
	local extra = 0
	if crewBonusProvider then
		local ok, value = pcall(crewBonusProvider, profile)
		if ok and type(value) == "number" then
			extra = value
		end
	end
	return Config.BaseCrewSlots + bonuses.crew + extra
end

function CrewService.Discover(profile, heroId: string)
	profile.discovered = profile.discovered or {}
	profile.discovered[heroId] = (profile.discovered[heroId] or 0) + 1
end

function CrewService.Roll(profile, bonuses, weather, count: number)
	local luck = 0.1 + bonuses.luck + math.max(0, (weather.luck or 1) - 1) * 0.12
	local results = {}
	for _ = 1, count do
		if #profile.units >= Config.MaxUnits then
			return results, "Crew storage full (" .. Config.MaxUnits .. ")."
		end
		local hero = CrewService.RollHero(luck)
		local unit = CrewService.NewUnit(profile, hero)
		profile.units[#profile.units + 1] = unit
		CrewService.Discover(profile, hero.id)
		results[#results + 1] = {
			heroName = hero.name,
			rarity = hero.rarity,
			color = hero.color,
			quote = hero.quote,
			unitId = unit.id,
		}
	end
	return results, nil
end

function CrewService.ToggleEquip(profile, unitId: number, bonuses)
	local unit = CrewService.FindUnit(profile, unitId)
	if not unit then
		return false, "Unit not found."
	end
	if unit.equipped then
		unit.equipped = false
		return true, "Benched " .. heroById[unit.heroId].name .. "."
	end
	local slots = CrewService.CrewSlots(profile, bonuses)
	if CrewService.EquippedCount(profile) >= slots then
		return false, "All " .. slots .. " crew slots are full."
	end
	unit.equipped = true
	return true, "Deployed " .. heroById[unit.heroId].name .. "!"
end

function CrewService.LevelUp(profile, unitId: number)
	local unit = CrewService.FindUnit(profile, unitId)
	if not unit then
		return false, "Unit not found."
	end
	local cost = CrewService.LevelCost(unit.level)
	if profile.coins < cost then
		return false, "Need " .. cost .. " coins to level up."
	end
	profile.coins -= cost
	unit.level += 1
	if unit.level > (profile.stats.bestLevel or 0) then
		profile.stats.bestLevel = unit.level
	end
	return true, heroById[unit.heroId].name .. " reached level " .. unit.level .. "!"
end

function CrewService.Mutate(profile, unitId: number)
	local unit = CrewService.FindUnit(profile, unitId)
	if not unit then
		return false, "Unit not found."
	end
	if profile.gems < Config.MutationCost then
		return false, "Need " .. Config.MutationCost .. " gems to mutate."
	end
	profile.gems -= Config.MutationCost
	local roll = Config.WeightedPick(Config.Mutations)
	local current = mutationById[unit.mutation] or mutationById.none
	if roll.mult <= current.mult then
		return true, "Mutation fizzled... kept " .. current.name .. "."
	end
	unit.mutation = roll.id
	return true, "MUTATION! " .. roll.name .. " (x" .. roll.mult .. " power)!"
end

function CrewService.Enchant(profile, unitId: number)
	local unit = CrewService.FindUnit(profile, unitId)
	if not unit then
		return false, "Unit not found."
	end
	if profile.gems < Config.EnchantCost then
		return false, "Need " .. Config.EnchantCost .. " gems to roll the dice."
	end
	profile.gems -= Config.EnchantCost
	local roll = Config.WeightedPick(Config.Enchants)
	local current = enchantById[unit.enchant] or enchantById.none
	if roll.power <= current.power then
		return true, "Dice landed on " .. roll.name .. "... no upgrade."
	end
	unit.enchant = roll.id
	return true, "ENCHANT! " .. roll.name .. " (x" .. roll.power .. " power)!"
end

return CrewService
