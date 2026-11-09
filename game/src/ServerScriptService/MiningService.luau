--!strict
-- Anime Miner Tycoon :: block breaking, rewards and hero automation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CrewService = require(script.Parent:WaitForChild("CrewService"))
local ResearchService = require(script.Parent:WaitForChild("ResearchService"))
local ProgressService = require(script.Parent:WaitForChild("ProgressService"))
local PetService = require(script.Parent:WaitForChild("PetService"))

local MiningService = {}

local world: any = nil
local blocksByZone: { [number]: { Model } } = {}
local pads: { [number]: BasePart } = {}
local oreMeta: { [Model]: any } = {}
local chests = {}
local lastHit: { [number]: { [number]: number } } = {}
local aliveCache: { [number]: { Model } } = {}
local notifyDirty = nil
local notifyPlayer = nil
local eventHook = nil
local heroTargetProvider = nil
local heroHitHook = nil
local comboState: { [number]: any } = {}
local COMBO_WINDOW = 2.4

local function zoneConfig(zoneId: number)
	return Config.ZoneById(zoneId)
end

local function unlocked(profile, zoneId: number): boolean
	local zone = zoneConfig(zoneId)
	if not zone then
		return false
	end
	if zone.research == nil then
		return true
	end
	return profile.research[zone.research] == true
end

local function burst(position: Vector3, color: Color3, amount: number)
	local holder = Instance.new("Part")
	holder.Name = "OreBurst"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = CFrame.new(position)
	holder.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(1.4, 0)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(8, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.8
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(amount)

	task.delay(1.5, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

local function applyOreVisual(model: Model, alive: boolean, ratio: number)
	local meta = oreMeta[model]
	if not meta then
		return
	end
	-- 24 visual steps instead of a property write per swing: the client sees the
	-- same shrinking block, the server sends ~4x fewer part updates
	local bucket = alive and math.clamp(math.ceil(ratio * 24), 1, 24) or 0
	if meta.bucket == bucket then
		return
	end
	meta.bucket = bucket
	if alive and meta.emitter then
		-- a couple of sparks per visible damage step replaces a constant emitter
		meta.emitter:Emit(2)
	end
	for _, entry in ipairs(meta.parts) do
		local piece = entry.part
		if piece and piece.Parent then
			if alive then
				piece.Size = entry.size * (0.74 + 0.26 * ratio)
				piece.Transparency = entry.alpha
				piece.CanCollide = entry.collide
			else
				piece.Transparency = 1
				piece.CanCollide = false
			end
		end
	end
	if meta.core then
		meta.core:SetAttribute("Alive", alive)
		meta.core:SetAttribute("HP", math.floor((meta.core:GetAttribute("MaxHP") or 0) * math.clamp(ratio, 0, 1)))
	end
	if meta.bar then
		meta.bar.Enabled = alive and ratio < 0.999
	end
	if meta.fill then
		local zone = zoneConfig(meta.zoneId)
		local accent = zone and zone.accent or Color3.fromRGB(150, 200, 255)
		meta.fill.Size = UDim2.fromScale(math.clamp(ratio, 0.02, 1), 1)
		meta.fill.BackgroundColor3 = accent:Lerp(Color3.fromRGB(255, 90, 90), math.clamp(1 - ratio, 0, 1) * 0.75)
	end
	if meta.emitter then
		meta.emitter.Enabled = alive
	end
	if meta.light then
		meta.light.Enabled = alive
	end
end

local function indexAlive(zoneId: number): { Model }
	local list = {}
	for _, model in ipairs(blocksByZone[zoneId] or {}) do
		if model:GetAttribute("Alive") then
			list[#list + 1] = model
		end
	end
	aliveCache[zoneId] = list
	return list
end

local function aliveBlocks(zoneId: number): { Model }
	return aliveCache[zoneId] or indexAlive(zoneId)
end

local function markDead(zoneId: number, model: Model)
	local list = aliveCache[zoneId]
	if not list then
		return
	end
	for index = #list, 1, -1 do
		if list[index] == model then
			table.remove(list, index)
			return
		end
	end
end

local function markAlive(zoneId: number, model: Model)
	local list = aliveCache[zoneId]
	if not list then
		return
	end
	for _, existing in ipairs(list) do
		if existing == model then
			return
		end
	end
	list[#list + 1] = model
end

local function collectReward(player, profile, zone, gemNode, bonus, rich)
	-- equipped pets add a small capped yield bonus on top of research/boosts
	local pets = PetService.Bonuses(profile)
	local richMult = rich and 3 or 1
	local coins = math.floor(zone.value * richMult * (ProgressService.Combined(profile).coin) * (1 + ResearchService.GetBonuses(profile).coin) * (1 + pets.coin) * (bonus or 1) + 0.5)
	profile.coins += coins
	profile.stats.coinsEarned += coins
	profile.stats.blocksMined += 1

	local gems = 0
	if gemNode then
		gems = 2 + math.random(0, 2)
	elseif math.random() < zone.gemChance then
		gems = 1
	end
	if rich then
		gems = math.max(gems, 3)
	end
	if gems > 0 then
		gems = math.floor(gems * (1 + pets.gem) + 0.5)
		profile.gems += gems
	end

	if notifyDirty then
		notifyDirty(player)
	end
	if gems > 0 and notifyPlayer then
		notifyPlayer(player, (gemNode and "GEM NODE! +" or "Gem found! +") .. gems .. " gems", "gacha")
	end
	return coins, gems
end

local function respawnBlock(model: Model)
	local zoneId = model:GetAttribute("Zone")
	local zone = zoneConfig(zoneId)
	if not zone then
		return
	end
	model:SetAttribute("HP", zone.blockHp)
	model:SetAttribute("MaxHP", zone.blockHp)
	model:SetAttribute("Alive", true)
	applyOreVisual(model, true, 1)
	markAlive(zoneId, model)
end

function MiningService.BumpCombo(player: Player): number
	local now = os.clock()
	local entry = comboState[player.UserId]
	if not entry or now - entry.last > COMBO_WINDOW then
		entry = { count = 0, last = now }
		comboState[player.UserId] = entry
	end
	entry.count = math.min(entry.count + 1, 10)
	entry.last = now
	return entry.count
end

function MiningService.Combo(player: Player)
	local entry = comboState[player.UserId]
	if not entry then
		return { count = 0, mult = 1, timeLeft = 0 }
	end
	local elapsed = os.clock() - entry.last
	if elapsed > COMBO_WINDOW then
		comboState[player.UserId] = nil
		return { count = 0, mult = 1, timeLeft = 0 }
	end
	return { count = entry.count, mult = 1 + 0.06 * (entry.count - 1), timeLeft = COMBO_WINDOW - elapsed }
end

function MiningService.ClearPlayer(player: Player)
	comboState[player.UserId] = nil
end

function MiningService.Damage(target: Instance, amount: number, player: Player, bonus: number?)
	local model: Model? = nil
	if target:IsA("Model") then
		model = target
	elseif target:IsA("BasePart") then
		model = target:FindFirstAncestorOfClass("Model")
	end
	if not model then
		return
	end
	local zoneId = model:GetAttribute("Zone")
	local profile = DataService.Get(player)
	if not profile or not zoneId then
		return
	end
	if not unlocked(profile, zoneId) then
		return
	end
	if not model:GetAttribute("Alive") then
		return
	end

	local maxHp = model:GetAttribute("MaxHP") or 1
	-- catch-up floor: 1% of max HP per hit, so a biome that out-scales a weak crew
	-- still falls after at most 100 swings instead of becoming a hard wall
	amount = math.max(amount, maxHp * 0.01)
	local hp = (model:GetAttribute("HP") or 0) - amount
	if hp > 0 then
		model:SetAttribute("HP", hp)
		applyOreVisual(model, true, math.clamp(hp / maxHp, 0, 1))
		return
	end

	model:SetAttribute("Alive", false)
	model:SetAttribute("HP", 0)
	applyOreVisual(model, false, 0)
	markDead(zoneId, model)

	local pivot = model:GetPivot().Position
	local zone = zoneConfig(zoneId)
	if zone then
		burst(pivot, zone.blockColor, 22)
	end

	local gemNode = model:GetAttribute("GemNode") == true
	local rich = model:GetAttribute("Rich") == true
	local coins = collectReward(player, profile, zone, gemNode, bonus, rich)
	if rich and notifyPlayer then
		notifyPlayer(player, "RICH VEIN! +" .. coins .. " coins", "gacha")
	end
	if notifyDirty then
		notifyDirty(player)
	end
end

-- the player's own pickaxe click
local function onBlockClicked(instance: Instance, player: Player)
	local model = instance:IsA("Model") and instance or instance:FindFirstAncestorOfClass("Model")
	if not model then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local zoneId = model:GetAttribute("Zone")
	if not zoneId or not unlocked(profile, zoneId) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if (root.Position - model:GetPivot().Position).Magnitude > 110 then
		return
	end
	local zone = zoneConfig(zoneId)
	local damage = math.max(2, zone.value * 0.6)
		* ProgressService.Combined(profile).power
		* ProgressService.PickaxePower(profile)
	local comboCount = MiningService.BumpCombo(player)
	local comboMult = 1 + 0.06 * (comboCount - 1)
	MiningService.Damage(model, damage, player, comboMult)
	if eventHook then
		eventHook(player, "mine")
	end
	if notifyDirty then
		notifyDirty(player)
	end
end

-- heroes dig automatically, even while the player is away
local function heroLoop()
	while true do
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			if profile then
				local bonuses = ResearchService.GetBonuses(profile)
				local combined = ProgressService.Combined(profile)
				local playerHits = lastHit[player.UserId] or {}
				lastHit[player.UserId] = playerHits

				for _, unit in ipairs(profile.units) do
					if unit.equipped then
						local interval = CrewService.UnitInterval(unit, combined)
						if now >= (playerHits[unit.id] or 0) then
							playerHits[unit.id] = now + interval
							local zoneId = math.min(profile.zone, bonuses.zonesUnlocked)
							local list = aliveBlocks(zoneId)
							if #list == 0 then
								zoneId = math.max(1, zoneId - 1)
								list = aliveBlocks(zoneId)
							end
							if #list > 0 then
								local target = nil
								if heroTargetProvider then
									local ok, provided = pcall(heroTargetProvider, player, unit.id, zoneId)
									if ok and provided and provided:GetAttribute("Alive") then
										target = provided
									end
								end
								target = target or list[math.random(1, #list)]
								local power = CrewService.UnitPower(unit, bonuses, combined)
								MiningService.Damage(target, power, player)
								if heroHitHook then
									heroHitHook(player, unit.id, target, power)
								end
							end
						end
					end
				end
			end
		end
		task.wait(0.25)
	end
end

function MiningService.SetZone(player: Player, zoneId: number)
	local profile = DataService.Get(player)
	if not profile then
		return false, "No profile."
	end
	local bonuses = ResearchService.GetBonuses(profile)
	local zone = Config.ZoneById(zoneId)
	if not zone then
		return false, "Unknown biome."
	end
	if zoneId > bonuses.zonesUnlocked then
		return false, "Research " .. tostring(zone.research) .. " required to reach " .. zone.name .. "."
	end
	local level = Config.MinerLevel(profile.stats)
	if level < (zone.levelReq or 1) then
		return false, "Miner Lv " .. (zone.levelReq or 1) .. " required for " .. zone.name .. " (you are Lv " .. level .. ")."
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "No character."
	end
	profile.zone = zoneId
	player:SetAttribute("Zone", zoneId)
	root.CFrame = CFrame.new(WorldBuilder.PadPosition(pads, zoneId))
	return true, "Travelled to " .. Config.Zones[zoneId].name .. "."
end

function MiningService.PadFor(zoneId: number): Vector3?
	local pad = pads[zoneId]
	if pad then
		return pad.Position
	end
	return nil
end

-- the return gates in each biome send you back to the town spawn
function MiningService.ReturnToHub(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return false, "No profile."
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "No character."
	end
	profile.stats.bestZone = math.max(profile.stats.bestZone or 0, profile.zone or 1)
	profile.zone = 1
	player:SetAttribute("Zone", 1)
	root.CFrame = CFrame.new(0, 6.5, 42)
	if notifyDirty then
		notifyDirty(player)
	end
	return true, "Returned to Miner Town."
end

function MiningService.Chests()
	return chests
end

function MiningService.SetEventHook(fn)
	eventHook = fn
end

-- the visible rigs own which block their hero is working on, so the damage the
-- server applies and the swing the player sees always hit the same ore
function MiningService.SetHeroTargetProvider(fn)
	heroTargetProvider = fn
end

function MiningService.SetHeroHitHook(fn)
	heroHitHook = fn
end

function MiningService.Start(dirtyCallback, playerNotify)
	notifyDirty = dirtyCallback
	notifyPlayer = playerNotify
	local built = WorldBuilder.Build()
	world = built.root
	blocksByZone = built.blocksByZone
	oreMeta = built.oreMeta
	pads = built.pads
	chests = built.chests
	aliveCache = {}
	for zoneId in pairs(blocksByZone) do
		indexAlive(zoneId)
	end

	for _, list in pairs(blocksByZone) do
		for _, model in ipairs(list) do
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("ClickDetector") then
					descendant.MouseClick:Connect(function(player)
						onBlockClicked(model, player)
					end)
				end
			end
		end
	end

	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("ClickDetector") and descendant.Name == "ReturnClick" then
			descendant.MouseClick:Connect(function(player)
				local ok, message = MiningService.ReturnToHub(player)
				if notifyPlayer then
					notifyPlayer(player, message, ok and "ok" or "error")
				end
			end)
		end
	end

	local portal = world:FindFirstChild("Portal")
	if portal then
		for _, descendant in ipairs(portal:GetDescendants()) do
			if descendant:IsA("ClickDetector") then
				descendant.MouseClick:Connect(function(player)
					local gate = descendant.Parent
					local targetZone = gate and gate:GetAttribute("Zone") or 1
					local ok, message = MiningService.SetZone(player, targetZone)
					if notifyPlayer then
						notifyPlayer(player, message, ok and "ok" or "error")
					end
					if notifyDirty then
						notifyDirty(player)
					end
					if ok and eventHook then
						eventHook(player, "descend")
					end
				end)
			end
		end
	end

	-- walking into a portal plane travels too: same level/research checks as the click
	local touchGuard: { [Player]: number } = {}
	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "PortalPlane" then
			local gate = descendant.Parent
			descendant.Touched:Connect(function(hit)
				local character = hit.Parent
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player then
					return
				end
				local now = os.clock()
				local last = touchGuard[player]
				if last and now - last < 2 then
					return
				end
				touchGuard[player] = now
				local ok, message
				if gate and gate.Name == "ReturnGate" then
					ok, message = MiningService.ReturnToHub(player)
				else
					local zoneId = gate and gate:GetAttribute("Zone") or 1
					ok, message = MiningService.SetZone(player, zoneId)
				end
				if notifyPlayer then
					notifyPlayer(player, message, ok and "ok" or "error")
				end
				if notifyDirty then
					notifyDirty(player)
				end
				if ok and eventHook then
					eventHook(player, "descend")
				end
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		touchGuard[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.BlockRespawn)
			for zoneId, list in pairs(blocksByZone) do
				for _, model in ipairs(list) do
					if not model:GetAttribute("Alive") then
						respawnBlock(model)
					end
				end
			end
		end
	end)

	task.spawn(heroLoop)
end

function MiningService.World()
	return world
end

function MiningService.RefreshLocks()
	for zoneId, list in pairs(blocksByZone) do
		local zone = zoneConfig(zoneId)
		for _, model in ipairs(list) do
			model:SetAttribute("MaxHP", zone.blockHp)
		end
	end
end

return MiningService
