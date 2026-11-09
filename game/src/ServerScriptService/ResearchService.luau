--!strict
-- Anime Miner Tycoon :: research tree

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local ResearchService = {}

local nodeById: { [string]: any } = {}
for _, node in ipairs(Config.Research) do
	nodeById[node.id] = node
end
ResearchService.NodeById = nodeById

function ResearchService.GetBonuses(profile)
	local bonuses = {
		power = 0,
		luck = 0,
		coin = 0,
		crew = 0,
		trade = false,
		zonesUnlocked = 1,
	}
	for nodeId in pairs(profile.research) do
		local node = nodeById[nodeId]
		if node and node.effect then
			local effect = node.effect
			bonuses.power += effect.power or 0
			bonuses.luck += effect.luck or 0
			bonuses.coin += effect.coin or 0
			bonuses.crew += effect.crew or 0
			if effect.trade then
				bonuses.trade = true
			end
			if effect.zone then
				bonuses.zonesUnlocked = math.max(bonuses.zonesUnlocked, effect.zone)
			end
		end
	end
	return bonuses
end

function ResearchService.IsBought(profile, nodeId: string): boolean
	return profile.research[nodeId] == true
end

function ResearchService.CanBuy(profile, nodeId: string)
	local node = nodeById[nodeId]
	if not node then
		return false, "Unknown research."
	end
	if ResearchService.IsBought(profile, nodeId) then
		return false, "Already researched."
	end
	for _, requirement in ipairs(node.requires) do
		if not ResearchService.IsBought(profile, requirement) then
			local required = nodeById[requirement]
			return false, "Requires " .. (required and required.name or requirement) .. "."
		end
	end
	if profile.coins < node.cost then
		return false, "Not enough coins (" .. node.cost .. " needed)."
	end
	return true, ""
end

function ResearchService.Buy(profile, nodeId: string)
	local canBuy, message = ResearchService.CanBuy(profile, nodeId)
	if not canBuy then
		return false, message
	end
	local node = nodeById[nodeId]
	profile.coins -= node.cost
	profile.research[nodeId] = true
	if node.effect and node.effect.zone then
		profile.zone = math.max(profile.zone, node.effect.zone)
	end
	return true, "Researched " .. node.name .. "!"
end

function ResearchService.Nodes(profile)
	local nodes = {}
	for _, node in ipairs(Config.Research) do
		local canBuy = ResearchService.CanBuy(profile, node.id)
		nodes[#nodes + 1] = {
			id = node.id,
			name = node.name,
			desc = node.desc,
			cost = node.cost,
			bought = ResearchService.IsBought(profile, node.id),
			canBuy = canBuy,
			requiresText = #node.requires > 0 and ("Requires " .. table.concat(node.requires, ", ")) or "No prerequisites",
		}
	end
	return nodes
end

return ResearchService
