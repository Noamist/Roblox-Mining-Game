--!strict
-- Anime Miner Tycoon :: gamepass ownership and permanent perks
-- Ids come from Config.GamePasses. A pass with passId 0 is simply not sold yet;
-- ownership is cached per player and refreshed on purchase, so the perks apply
-- without a rejoin.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local GamePassService = {}

local owned: { [number]: { [string]: boolean } } = {}
local EMPTY: { [string]: boolean } = {}

local function configured(): { any }
	local list = {}
	for _, def in ipairs(Config.GamePasses) do
		if (def.passId or 0) > 0 then
			list[#list + 1] = def
		end
	end
	return list
end

function GamePassService.Refresh(player: Player)
	if not player then
		return
	end
	local set = {}
	for _, def in ipairs(configured()) do
		local ok, has = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.passId)
		end)
		if ok and has then
			set[def.id] = true
		end
	end
	owned[player.UserId] = set
end

function GamePassService.Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
		if purchased then
			task.spawn(GamePassService.Refresh, player)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(GamePassService.Refresh, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player.UserId] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(GamePassService.Refresh, player)
	end
end

local function ownedSet(profile): { [string]: boolean }
	if profile and profile.userId then
		return owned[profile.userId] or EMPTY
	end
	return EMPTY
end

function GamePassService.Multipliers(profile)
	local mult = { coin = 1, power = 1, speed = 1, luck = 1, crew = 0 }
	local set = ownedSet(profile)
	for _, def in ipairs(Config.GamePasses) do
		if (def.passId or 0) > 0 and set[def.id] then
			if def.perk == "crew" then
				mult.crew += def.value
			elseif mult[def.perk] then
				mult[def.perk] *= def.value
			end
		end
	end
	return mult
end

function GamePassService.Payload(profile)
	local set = ownedSet(profile)
	local list = {}
	for _, def in ipairs(Config.GamePasses) do
		list[#list + 1] = {
			id = def.id,
			name = def.name,
			desc = def.desc,
			passId = def.passId or 0,
			color = def.color,
			owned = set[def.id] == true,
			configured = (def.passId or 0) > 0,
		}
	end
	return list
end

return GamePassService
