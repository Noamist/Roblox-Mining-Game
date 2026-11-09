--!strict
-- Anime Miner Tycoon :: interactive town stations and biome descend pads

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local ProgressService = require(script.Parent:WaitForChild("ProgressService"))
local MiningService = require(script.Parent:WaitForChild("MiningService"))
local NpcService = require(script.Parent:WaitForChild("NpcService"))

local StationService = {}

local DAILY_COOLDOWN = 12 * 60 * 60

function StationService.Start(world: Instance, notify, dirty, eventHook)
	if not world then
		return
	end

	local function onForge(player)
		local profile = DataService.Get(player)
		if not profile then
			return
		end
		local ok, message = ProgressService.BuyPickaxe(profile)
		notify(player, message, ok and "ok" or "error")
		dirty(player)
	end

	local function onDaily(player)
		local profile = DataService.Get(player)
		if not profile then
			return
		end
		local elapsed = os.time() - (profile.lastDaily or 0)
		if elapsed < DAILY_COOLDOWN then
			local hours = math.ceil((DAILY_COOLDOWN - elapsed) / 3600)
			notify(player, "Daily cache restocks in " .. hours .. "h.", "error")
			return
		end
		profile.lastDaily = os.time()
		local coins = 350 + 200 * profile.zone
		local gems = 8 + 2 * profile.zone
		profile.coins += coins
		profile.gems += gems
		profile.stats.coinsEarned += coins
		dirty(player)
		notify(player, "Daily cache: +" .. coins .. " coins and +" .. gems .. " gems", "gacha")
	end

	local function onDescend(player, pad)
		local zoneId = pad:GetAttribute("Zone")
		if not zoneId then
			return
		end
		if zoneId >= #Config.Zones then
			notify(player, "This is the deepest biome.", "error")
			return
		end
		local ok, message = MiningService.SetZone(player, zoneId + 1)
		notify(player, message, ok and "ok" or "error")
		if ok then
			dirty(player)
			if eventHook then
				eventHook(player, "descend")
			end
		end
	end

	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("ClickDetector") then
			if descendant.Name == "ForgeClick" then
				descendant.MouseClick:Connect(onForge)
			elseif descendant.Name == "DailyClick" then
				descendant.MouseClick:Connect(onDaily)
			elseif descendant.Name == "DescendPadClick" then
				descendant.MouseClick:Connect(function(player)
					onDescend(player, descendant.Parent)
				end)
			elseif descendant.Name == "NpcClick" then
				descendant.MouseClick:Connect(function(player)
					local npcId = descendant:GetAttribute("NpcId")
					if npcId then
						local message, kind = NpcService.Talk(player, npcId, "greet")
						if message then
							notify(player, message, kind)
						end
					end
				end)
			end
		end
	end
end

return StationService
