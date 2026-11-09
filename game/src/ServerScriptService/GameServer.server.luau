--!strict
-- Anime Miner Tycoon :: server bootstrap and action router

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local DataService = require(ServerScriptService:WaitForChild("DataService"))
local CrewService = require(ServerScriptService:WaitForChild("CrewService"))
local PetService = require(ServerScriptService:WaitForChild("PetService"))
local ResearchService = require(ServerScriptService:WaitForChild("ResearchService"))
local WeatherService = require(ServerScriptService:WaitForChild("WeatherService"))
local ProgressService = require(ServerScriptService:WaitForChild("ProgressService"))
local TutorialService = require(ServerScriptService:WaitForChild("TutorialService"))
local MiningService = require(ServerScriptService:WaitForChild("MiningService"))
local TreasureService = require(ServerScriptService:WaitForChild("TreasureService"))
local StationService = require(ServerScriptService:WaitForChild("StationService"))
local TradeService = require(ServerScriptService:WaitForChild("TradeService"))
local NpcService = require(ServerScriptService:WaitForChild("NpcService"))
local GamePassService = require(ServerScriptService:WaitForChild("GamePassService"))
local LeaderboardService = require(ServerScriptService:WaitForChild("LeaderboardService"))
local HeroVisuals = require(ServerScriptService:WaitForChild("HeroVisuals"))

-- remotes -------------------------------------------------------------------
local existingRemotes = ReplicatedStorage:FindFirstChild("Remotes")
if existingRemotes then
	existingRemotes:Destroy()
end

local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local ActionRemote = Instance.new("RemoteEvent")
ActionRemote.Name = "Action"
ActionRemote.Parent = Remotes

local StateRemote = Instance.new("RemoteEvent")
StateRemote.Name = "State"
StateRemote.Parent = Remotes

local NotifyRemote = Instance.new("RemoteEvent")
NotifyRemote.Name = "Notify"
NotifyRemote.Parent = Remotes

local DialogueRemote = Instance.new("RemoteEvent")
DialogueRemote.Name = "Dialogue"
DialogueRemote.Parent = Remotes

NpcService.SetDialogueSink(function(player, payload)
	DialogueRemote:FireClient(player, payload)
end)

ProgressService.SetPassProvider(GamePassService.Multipliers)
CrewService.SetCrewBonusProvider(function(profile)
	return GamePassService.Multipliers(profile).crew
end)

-- state ---------------------------------------------------------------------
-- "light" pushes skip the unit list; only actions that can change units ask for a
-- full payload, so a mining tick does not ship hundreds of unit records
local dirty: { [number]: string } = {}

local function markDirty(player: Player, full: boolean?)
	local id = player.UserId
	if full then
		dirty[id] = "full"
	elseif dirty[id] == nil then
		dirty[id] = "light"
	end
end

local function rarityRank(rarityId: string): number
	for index, rarity in ipairs(Config.Rarities) do
		if rarity.id == rarityId then
			return index
		end
	end
	return 0
end

local function buildState(player: Player, full: boolean?)
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local bonuses = ResearchService.GetBonuses(profile)
	local combined = ProgressService.Combined(profile)
	local weather = WeatherService.Current()

	local units = full and {} or nil
	local dps = 0
	local equipped = 0
	for _, unit in ipairs(profile.units) do
		if unit.equipped then
			local info = CrewService.UnitInfo(unit, bonuses, combined)
			equipped += 1
			dps += info.dps
			if units then
				units[#units + 1] = info
			end
		elseif units then
			units[#units + 1] = CrewService.UnitInfo(unit, bonuses, combined)
		end
	end

	local zone = Config.Zones[math.clamp(profile.zone, 1, #Config.Zones)]

	profile.stats.bestZone = math.max(profile.stats.bestZone or 0, profile.zone or 1)
	local level = Config.MinerLevel(profile.stats)
	local zoneList = {}
	for _, def in ipairs(Config.Zones) do
		local levelReq = def.levelReq or 1
		local researchReady = bonuses.zonesUnlocked >= def.id
		zoneList[#zoneList + 1] = {
			id = def.id,
			name = def.name,
			levelReq = levelReq,
			researchReady = researchReady,
			levelReady = level >= levelReq,
			unlocked = researchReady and level >= levelReq,
		}
	end

	return {
		coins = profile.coins,
		gems = profile.gems,
		zone = profile.zone,
		zoneName = zone.name,
		units = units,
		pets = PetService.Payload(profile),
		crewSlots = CrewService.CrewSlots(profile, bonuses),
		equipped = equipped,
		dps = dps,
		luck = 1 + bonuses.luck,
		gachaLuck = combined.luck,
		zonesUnlocked = bonuses.zonesUnlocked,
		tradeUnlocked = bonuses.trade,
		research = ResearchService.Nodes(profile),
		weather = weather,
		boosts = ProgressService.ActiveBoosts(profile),
		shop = ProgressService.ShopPayload(profile),
		quests = ProgressService.Quests(profile),
		sideQuests = NpcService.SideQuestLog(profile),
		passes = GamePassService.Payload(profile),
		heroIndex = ProgressService.IndexPayload(profile),
		stats = profile.stats,
		rollCost = Config.RollCost,
		storedUnits = #profile.units,
		tradeIncoming = TradeService.Incoming(player),
		zones = zoneList,
		pickaxe = ProgressService.PickaxeLevel(profile),
		pickaxeCost = ProgressService.PickaxeCost(profile),
		pickaxeMaxed = ProgressService.PickaxeMaxed(profile),
		dailyReady = (os.time() - (profile.lastDaily or 0)) >= 12 * 60 * 60,
		combo = MiningService.Combo(player),
		tutorial = TutorialService.Payload(profile),
		level = level,
		levelProgress = Config.MinerProgress(profile.stats),
		rebirth = ProgressService.RebirthInfo(profile),
		admin = Config.IsAdmin(player),
		settings = profile.settings or { quality = "normal", petsVisible = true, hudVisible = false },
	}
end

local function pushState(player: Player, full: boolean?)
	local state = buildState(player, full)
	if state then
		StateRemote:FireClient(player, state)
	end
	dirty[player.UserId] = nil
end

local function notify(player: Player, text: string, kind: string?)
	NotifyRemote:FireClient(player, text, kind or "info")
end

local function pushAll()
	for _, player in ipairs(Players:GetPlayers()) do
		markDirty(player)
	end
end

local function tutorialEvent(player: Player, profile, key: string)
	local advanced, rewarded = TutorialService.Event(profile, key)
	if advanced then
		markDirty(player)
		if rewarded then
			notify(player, "Tutorial complete: +300 coins, +12 gems", "gacha")
		end
	end
end

-- actions -------------------------------------------------------------------
local handlers = {}

handlers.Roll = function(player, payload)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local count = payload and payload.count == 10 and 10 or 1
	local cost = count == 10 and Config.RollCost.multi or Config.RollCost.single
	if profile.coins < cost then
		notify(player, "Not enough coins (need " .. cost .. ").", "error")
		return
	end
	local bonuses = ResearchService.GetBonuses(profile)
	local combined = ProgressService.Combined(profile)
	profile.coins -= cost
	profile.stats.rolls += count
	local results, err = CrewService.Roll(profile, bonuses, combined, count)
	if err then
		notify(player, err, "error")
	else
		notify(player, "Summoned " .. #results .. " hero(es) for " .. cost .. " coins!", "gacha")
		local best = results[1]
		for _, result in ipairs(results) do
			if rarityRank(result.rarity) > rarityRank(best.rarity) then
				best = result
			end
			if rarityRank(result.rarity) > rarityRank(profile.stats.bestRarity) then
				profile.stats.bestRarity = result.rarity
			end
		end
		if count == 1 then
			notify(player, best.rarity .. ": " .. best.heroName, "roll")
		else
			notify(player, "Best of ten: " .. best.rarity .. " " .. best.heroName, "roll")
		end
	end
	tutorialEvent(player, profile, "summon")
	markDirty(player)
end

handlers.Equip = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local bonuses = ResearchService.GetBonuses(profile)
	local ok, message = CrewService.ToggleEquip(profile, payload.unitId, bonuses)
	notify(player, message, ok and "ok" or "error")
	if ok then
		tutorialEvent(player, profile, "deploy")
	end
	markDirty(player)
end

handlers.LevelUp = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local ok, message = CrewService.LevelUp(profile, payload.unitId)
	notify(player, message, ok and "ok" or "error")
	markDirty(player)
end

handlers.Mutate = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local ok, message = CrewService.Mutate(profile, payload.unitId)
	notify(player, message, ok and "mutation" or "error")
	markDirty(player)
end

handlers.Enchant = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local ok, message = CrewService.Enchant(profile, payload.unitId)
	notify(player, message, ok and "enchant" or "error")
	markDirty(player)
end

handlers.HatchPet = function(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local ok, message = PetService.Hatch(profile)
	notify(player, message, ok and "gacha" or "error")
	markDirty(player)
end

handlers.EquipPet = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local ok, message = PetService.Toggle(profile, payload.petId)
	notify(player, message, ok and "ok" or "error")
	markDirty(player)
end

handlers.Research = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local ok, message = ResearchService.Buy(profile, payload.nodeId)
	notify(player, message, ok and "research" or "error")
	if ok then
		tutorialEvent(player, profile, "research")
	end
	markDirty(player)
end

handlers.Travel = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local ok, message = MiningService.SetZone(player, payload.zoneId)
	notify(player, message, ok and "ok" or "error")
	if ok then
		tutorialEvent(player, profile, "descend")
	end
	markDirty(player)
end

handlers.BuyBoost = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local ok, message = ProgressService.BuyBoost(profile, payload.id)
	notify(player, message, ok and "gacha" or "error")
	markDirty(player)
end

handlers.UpgradePickaxe = function(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local ok, message = ProgressService.BuyPickaxe(profile)
	notify(player, message, ok and "ok" or "error")
	markDirty(player)
end

handlers.Rebirth = function(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local ok, message = ProgressService.Rebirth(profile)
	notify(player, message, ok and "rebirth" or "error")
	if ok then
		MiningService.ClearPlayer(player)
		player:SetAttribute("Zone", profile.zone)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.new(0, 6.5, 42)
		end
		-- write immediately: a crash right after a rebirth must not hand the old
		-- run back on the next join
		DataService.Save(player)
		pushState(player, true)
	end
	markDirty(player, true)
end

handlers.ClaimQuest = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local ok, message = ProgressService.Claim(profile, payload.id)
	notify(player, message, ok and "research" or "error")
	markDirty(player)
end

handlers.TutorialStart = function(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	TutorialService.Start(profile)
	markDirty(player)
end

handlers.TutorialNext = function(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local _, rewarded = TutorialService.Next(profile)
	if rewarded then
		notify(player, "Tutorial complete: +300 coins, +12 gems", "gacha")
	end
	markDirty(player)
end

handlers.TutorialSkip = function(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local _, message = TutorialService.Skip(profile)
	notify(player, message, "ok")
	markDirty(player)
end

handlers.TradeOffer = function(player, payload)
	if not payload then
		return
	end
	local ok, message = TradeService.Offer(player, payload.targetName, payload.unitId)
	notify(player, message, ok and "ok" or "error")
	markDirty(player)
end

handlers.TradeAccept = function(player)
	local ok, message = TradeService.Accept(player)
	notify(player, message, ok and "trade" or "error")
	markDirty(player)
end

handlers.TradeCancel = function(player)
	local ok, message = TradeService.Cancel(player)
	notify(player, message, ok and "ok" or "error")
	markDirty(player)
end

handlers.NpcTalk = function(player, payload)
	if not payload then
		return
	end
	local message, kind = NpcService.Talk(player, payload.npcId, payload.choice, payload.arg)
	if message then
		notify(player, message, kind)
	end
	markDirty(player)
end

-- developer panel ----------------------------------------------------------
handlers.AdminGrant = function(player, payload)
	if not Config.IsAdmin(player) then
		return
	end
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	local kind = payload.kind
	local amount = math.clamp(tonumber(payload.amount) or 0, 0, 1000000)
	if kind == "coins" then
		profile.coins += amount
	elseif kind == "gems" then
		profile.gems += amount
	elseif kind == "xp" then
		profile.stats.blocksMined += amount
	else
		return
	end
	notify(player, "DEV: +" .. amount .. " " .. tostring(kind), "research")
	markDirty(player)
end

handlers.SaveSettings = function(player, payload)
	local profile = DataService.Get(player)
	if not profile or not payload then
		return
	end
	profile.settings = profile.settings or {}
	local quality = payload.quality
	if quality == "low" or quality == "normal" or quality == "high" then
		profile.settings.quality = quality
	end
	if payload.petsVisible ~= nil then
		profile.settings.petsVisible = payload.petsVisible == true
	end
	if payload.hudVisible ~= nil then
		profile.settings.hudVisible = payload.hudVisible == true
	end
	-- no SetAsync here: the normal autosave/leave path writes the profile, so
	-- flipping a toggle cannot eat the DataStore request budget
end

handlers.AdminReset = function(player)
	if not Config.IsAdmin(player) then
		return
	end
	local profile = DataService.Reset(player)
	-- write the empty profile immediately: otherwise a rejoin (or a crash before
	-- the next autosave) loads the old save back over the wipe
	DataService.Save(player)
	MiningService.ClearPlayer(player)
	player:SetAttribute("Zone", profile.zone)
	-- a wiped profile still needs one hero, or the mine cannot be worked at all
	local hero = CrewService.RollHero(0)
	local unit = CrewService.NewUnit(profile, hero)
	unit.equipped = true
	profile.units[#profile.units + 1] = unit
	CrewService.Discover(profile, hero.id)
	DataService.Save(player)
	notify(player, "DEV: progress wiped and saved fresh.", "research")
	pushState(player, true)
end

handlers.RequestState = function(player)
	pushState(player, true)
end

ActionRemote.OnServerEvent:Connect(function(player, action, payload)
	local handler = handlers[action]
	if handler then
		local success, err = pcall(handler, player, payload)
		if success then
			-- an action can change units, so the next flush carries the full roster
			markDirty(player, true)
		else
			warn("[AnimeMiner] action failed: " .. tostring(err))
			notify(player, "Something went wrong: " .. tostring(err), "error")
		end
	end
end)

-- lifecycle -----------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local profile = DataService.Load(player)
	player:SetAttribute("Zone", profile.zone)
	markDirty(player, true)
	task.delay(1, function()
		pushState(player, true)
		-- starter hero so automation is immediately visible
		if #profile.units == 0 then
			local hero = CrewService.RollHero(0)
			local unit = CrewService.NewUnit(profile, hero)
			unit.equipped = true
			profile.units[#profile.units + 1] = unit
			CrewService.Discover(profile, hero.id)
			notify(player, "Starter hero joined: " .. hero.name, "gacha")
			markDirty(player, true)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	MiningService.ClearPlayer(player)
	TradeService.Cleanup(player)
	DataService.Release(player)
	dirty[player.UserId] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- weather broadcasts
WeatherService.Start(function(def)
	for _, player in ipairs(Players:GetPlayers()) do
		notify(player, "WEATHER: " .. def.name, "weather")
		markDirty(player)
	end
end)

-- world + automation
MiningService.Start(markDirty, notify)
local function worldEvent(player: Player, key: string)
	local profile = DataService.Get(player)
	if profile then
		tutorialEvent(player, profile, key)
	end
end
MiningService.SetEventHook(worldEvent)
TreasureService.Start(MiningService.Chests(), notify, markDirty)
StationService.Start(MiningService.World(), notify, markDirty, worldEvent)
GamePassService.Start()
LeaderboardService.Start(MiningService.World())
HeroVisuals.Start()

-- periodic state flush
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local pending = dirty[player.UserId]
			if pending then
				pushState(player, pending == "full")
			end
		end
	end
end)

-- periodic refresh so the client bars tick
task.spawn(function()
	while true do
		task.wait(5)
		pushAll()
	end
end)

-- autosave
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.Save(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		DataService.Save(player)
	end
end)

print("[AnimeMiner] Server online :: " .. Config.TITLE)
