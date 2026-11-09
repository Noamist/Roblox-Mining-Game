--!strict
-- Anime Miner Tycoon :: clickable reward caches scattered through every biome

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local ProgressService = require(script.Parent:WaitForChild("ProgressService"))

local TreasureService = {}

local readyAt: { [Model]: number } = {}
local chestsList = {}
local notifyPlayer = nil
local markDirty = nil

local function labelText(chest)
	local remaining = math.max(0, math.ceil((readyAt[chest.model] or 0) - os.clock()))
	if remaining <= 0 then
		return "REWARD CACHE", "click to open"
	end
	return "REWARD CACHE", "restocking... " .. remaining .. "s"
end

local function refreshLabel(chest)
	local label = chest.label
	if not label or not label.Parent then
		return
	end
	local titleText, subText = labelText(chest)
	-- only touch the labels when the text actually changes: writing an identical
	-- string still replicates a property to every client
	local title = label:FindFirstChildOfClass("TextLabel")
	if title and title.Text ~= titleText then
		title.Text = titleText
	end
	if label:FindFirstChild("Sign") then
		return
	end
	for _, child in ipairs(label:GetChildren()) do
		if child:IsA("TextLabel") and child.Position.Y.Scale > 0.5 and child.Text ~= subText then
			child.Text = subText
		end
	end
end

local function openChest(chest, player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local current = os.clock()
	if current < (readyAt[chest.model] or 0) then
		if notifyPlayer then
			notifyPlayer(player, "That cache is still restocking.", "error")
		end
		return
	end
	if profile.zone ~= chest.zoneId then
		if notifyPlayer then
			notifyPlayer(player, "You must be in this biome to open its cache.", "error")
		end
		return
	end

	local zone = Config.ZoneById(chest.zoneId)
	local coins = math.floor((zone.value * 9 + 25) * ProgressService.Combined(profile).coin + 0.5)
	local gems = 0
	if math.random() < 0.65 then
		gems = 1 + math.random(0, 2)
	end
	profile.coins += coins
	profile.gems += gems
	profile.stats.coinsEarned += coins
	profile.stats.chestsOpened = (profile.stats.chestsOpened or 0) + 1
	readyAt[chest.model] = current + Config.ChestCooldown

	if markDirty then
		markDirty(player)
	end
	if notifyPlayer then
		notifyPlayer(player, "Cache opened: +" .. coins .. " coins" .. (gems > 0 and (" and +" .. gems .. " gems") or ""), "gacha")
	end

	-- lid pops open and settles back down
	local lid = chest.lid
	if lid then
		local home = lid.CFrame
		local tween = TweenService:Create(lid, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			CFrame = home * CFrame.Angles(math.rad(-55), 0, 0),
		})
		tween:Play()
		task.delay(1.2, function()
			if lid.Parent then
				TweenService:Create(lid, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { CFrame = home }):Play()
			end
		end)
	end
end

function TreasureService.Start(chests, notify, dirty)
	chestsList = chests or {}
	notifyPlayer = notify
	markDirty = dirty

	for _, chest in ipairs(chestsList) do
		readyAt[chest.model] = 0
		for _, descendant in ipairs(chest.model:GetDescendants()) do
			if descendant:IsA("ClickDetector") then
				descendant.MouseClick:Connect(function(player)
					openChest(chest, player)
				end)
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(1)
			for _, chest in ipairs(chestsList) do
				refreshLabel(chest)
			end
		end
	end)
end

return TreasureService
