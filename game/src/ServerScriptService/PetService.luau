--!strict
-- Anime Miner Tycoon :: pets
-- Pets are small companions that follow the owner. Their yield bonuses are
-- additive and capped here, so owning a trio never replaces the pickaxe/hero
-- progression curve that the zone HP table is tuned against.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local PetService = {}

-- total equipped bonuses are clamped to roughly one research tier
local COIN_CAP = 0.30
local GEM_CAP = 0.22

function PetService.Def(id: string)
	for _, pet in ipairs(Config.Pets) do
		if pet.id == id then
			return pet
		end
	end
	return nil
end

function PetService.LevelMultiplier(level: number): number
	return 1 + 0.05 * (math.max(1, level) - 1)
end

local function ownedList(profile): { any }
	if not profile.pets then
		profile.pets = {}
	end
	return profile.pets
end

function PetService.Find(profile, id: string)
	for _, pet in ipairs(ownedList(profile)) do
		if pet.id == id then
			return pet
		end
	end
	return nil
end

function PetService.EquippedCount(profile): number
	local count = 0
	for _, pet in ipairs(ownedList(profile)) do
		if pet.equipped then
			count += 1
		end
	end
	return count
end

-- applied to ore and cache payouts by MiningService
function PetService.Bonuses(profile)
	local coin, gem = 0, 0
	for _, owned in ipairs(ownedList(profile)) do
		if owned.equipped then
			local def = PetService.Def(owned.id)
			if def then
				local mult = PetService.LevelMultiplier(owned.level or 1)
				coin += def.coin * mult
				gem += def.gem * mult
			end
		end
	end
	return { coin = math.min(coin, COIN_CAP), gem = math.min(gem, GEM_CAP) }
end

-- hatching: duplicates bond into levels instead of filling the roster
function PetService.Hatch(profile)
	if profile.gems < Config.PetCost then
		return false, "Hatching costs " .. Config.PetCost .. " gems."
	end
	local def = Config.WeightedPick(Config.Pets)
	profile.gems -= Config.PetCost
	local existing = PetService.Find(profile, def.id)
	if existing then
		local level = existing.level or 1
		if level >= Config.PetMaxLevel then
			profile.gems += math.floor(Config.PetCost / 2)
			return true, def.name .. " is already max level. Half the gems refunded."
		end
		existing.level = level + 1
		return true, def.name .. " bonded to Lv " .. existing.level .. "!"
	end
	local list = ownedList(profile)
	local equip = PetService.EquippedCount(profile) < Config.PetSlots
	list[#list + 1] = { id = def.id, level = 1, equipped = equip }
	return true, "Hatched " .. def.name .. " (" .. def.rarity .. ")!"
end

function PetService.Toggle(profile, id: string)
	local pet = PetService.Find(profile, id)
	if not pet then
		return false, "Unknown pet."
	end
	local def = PetService.Def(id)
	local name = def and def.name or id
	if pet.equipped then
		pet.equipped = false
		return true, "Benched " .. name .. "."
	end
	if PetService.EquippedCount(profile) >= Config.PetSlots then
		return false, "All " .. Config.PetSlots .. " pet slots are in use."
	end
	pet.equipped = true
	return true, "Equipped " .. name .. "."
end

local function rarityRank(rarityId: string): number
	for index, rarity in ipairs(Config.Rarities) do
		if rarity.id == rarityId then
			return index
		end
	end
	return 0
end

function PetService.Payload(profile)
	local list = {}
	for _, pet in ipairs(ownedList(profile)) do
		local def = PetService.Def(pet.id)
		if def then
			local mult = PetService.LevelMultiplier(pet.level or 1)
			list[#list + 1] = {
				id = def.id,
				name = def.name,
				rarity = def.rarity,
				shape = def.shape,
				color = def.color,
				level = pet.level or 1,
				equipped = pet.equipped == true,
				coin = def.coin * mult,
				gem = def.gem * mult,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		local rankA, rankB = rarityRank(a.rarity), rarityRank(b.rarity)
		if rankA ~= rankB then
			return rankA > rankB
		end
		return a.name < b.name
	end)
	local bonuses = PetService.Bonuses(profile)
	return {
		slots = Config.PetSlots,
		cost = Config.PetCost,
		maxLevel = Config.PetMaxLevel,
		list = list,
		total = #list,
		coin = bonuses.coin,
		gem = bonuses.gem,
	}
end

return PetService
