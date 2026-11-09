--!strict
-- Anime Miner Tycoon :: player trading (mutual swap)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local CrewService = require(script.Parent:WaitForChild("CrewService"))
local ResearchService = require(script.Parent:WaitForChild("ResearchService"))

local TradeService = {}

-- offers[targetUserId][fromUserId] = { unitId, unitName, heroName }
local offers: { [number]: { [number]: any } } = {}

local function findPlayerByName(name: string)
	name = name:lower()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Name:lower() == name or player.DisplayName:lower() == name then
			return player
		end
	end
	return nil
end

function TradeService.Offer(player: Player, targetName: string, unitId: number)
	local profile = DataService.Get(player)
	if not profile then
		return false, "No profile."
	end
	local bonuses = ResearchService.GetBonuses(profile)
	if not bonuses.trade then
		return false, "Research Guild Charter to unlock trading."
	end
	local target = findPlayerByName(targetName)
	if not target then
		return false, "No player named " .. targetName .. "."
	end
	if target == player then
		return false, "You cannot trade with yourself."
	end
	local unit = CrewService.FindUnit(profile, unitId)
	if not unit then
		return false, "Pick a valid crew member."
	end
	local hero = CrewService.HeroById[unit.heroId]
	offers[target.UserId] = offers[target.UserId] or {}
	offers[target.UserId][player.UserId] = {
		unitId = unit.id,
		unitName = hero.name,
		heroName = hero.name,
		fromName = player.Name,
	}
	return true, "Offered " .. hero.name .. " to " .. target.Name .. "."
end

function TradeService.Incoming(player: Player)
	local list = {}
	local incoming = offers[player.UserId]
	if incoming then
		for fromId, offer in pairs(incoming) do
			local fromPlayer = Players:GetPlayerByUserId(fromId)
			list[#list + 1] = {
				fromName = offer.fromName,
				unitName = offer.unitName,
				fromUserId = fromId,
				online = fromPlayer ~= nil,
			}
		end
	end
	return list
end

-- Completes only when both players offered something to each other.
function TradeService.Accept(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return false, "No profile."
	end
	local incoming = offers[player.UserId]
	if not incoming then
		return false, "No trade offers."
	end

	for fromId, offer in pairs(incoming) do
		local fromPlayer = Players:GetPlayerByUserId(fromId)
		local myOffer = offers[fromId] and offers[fromId][player.UserId]
		if fromPlayer and myOffer then
			local fromProfile = DataService.Get(fromPlayer)
			if fromProfile then
				local theirUnit = CrewService.FindUnit(fromProfile, offer.unitId)
				local myUnit = CrewService.FindUnit(profile, myOffer.unitId)
				if theirUnit and myUnit then
					local function removeUnit(targetProfile, unitId)
						for index, unit in ipairs(targetProfile.units) do
							if unit.id == unitId then
								table.remove(targetProfile.units, index)
								return unit
							end
						end
						return nil
					end

					local theirHero = CrewService.HeroById[theirUnit.heroId]
					local myHero = CrewService.HeroById[myUnit.heroId]

					removeUnit(fromProfile, offer.unitId)
					removeUnit(profile, myOffer.unitId)

					local newForMe = CrewService.NewUnit(profile, theirHero)
					newForMe.level = theirUnit.level
					newForMe.mutation = theirUnit.mutation
					newForMe.enchant = theirUnit.enchant
					profile.units[#profile.units + 1] = newForMe

					local newForThem = CrewService.NewUnit(fromProfile, myHero)
					newForThem.level = myUnit.level
					newForThem.mutation = myUnit.mutation
					newForThem.enchant = myUnit.enchant
					fromProfile.units[#fromProfile.units + 1] = newForThem

					offers[player.UserId][fromId] = nil
					offers[fromId][player.UserId] = nil
					return true, "Traded with " .. fromPlayer.Name .. "!"
				end
			end
		end
	end
	return false, "They have not offered anything back yet."
end

function TradeService.Cancel(player: Player)
	local removed = 0
	local incoming = offers[player.UserId]
	if incoming then
		for _ in pairs(incoming) do
			removed += 1
		end
	end
	offers[player.UserId] = {}
	return true, "Cleared " .. removed .. " incoming offer(s)."
end

function TradeService.Cleanup(player: Player)
	offers[player.UserId] = nil
	for _, targetOffers in pairs(offers) do
		targetOffers[player.UserId] = nil
	end
end

return TradeService
