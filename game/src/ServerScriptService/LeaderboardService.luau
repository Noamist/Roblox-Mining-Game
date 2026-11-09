--!strict
-- Anime Miner Tycoon :: global lifetime-ore leaderboard
-- Scores post to an OrderedDataStore every 10 minutes and the visible top ten is
-- rebuilt every 6 hours (a refresh is only a handful of requests). When
-- DataStores are unavailable - Studio without API access - the board quietly
-- falls back to the best miners on the current server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent:WaitForChild("DataService"))

local LeaderboardService = {}

-- a rebirth resets the run's ore, so the visible score is lifetime ore: the
-- current run plus every run banked by a rebirth
local function lifetimeOre(profile): number
	local stats = profile and profile.stats
	return math.floor(((stats and stats.blocksMined) or 0) + ((stats and stats.rebirthBlocks) or 0))
end

local REFRESH_SECONDS = 6 * 60 * 60
local PUBLISH_SECONDS = 10 * 60
local ROWS = 10

local scoreStore = nil
local nameStore = nil

local okScores, scores = pcall(function()
	return DataStoreService:GetOrderedDataStore("AnimeMinerLifetimeOre")
end)
if okScores then
	scoreStore = scores
	local okNames, names = pcall(function()
		return DataStoreService:GetDataStore("AnimeMinerLifetimeNames")
	end)
	if okNames then
		nameStore = names
	end
end

local entries = {}
local rows = {}
local footer = nil
local nextRefresh = 0

local function sessionEntries()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.Get(player)
		if profile then
			list[#list + 1] = {
				name = player.Name,					score = lifetimeOre(profile),
			}
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	return list
end

local function readTop()
	if not scoreStore then
		return sessionEntries()
	end
	local list = {}
	local ok, pages = pcall(function()
		return scoreStore:GetSortedAsync(false, ROWS)
	end)
	if ok and pages then
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		if okPage and page then
			for _, row in ipairs(page) do
				local userId = tonumber(row.key)
				local name = "Miner"
				if nameStore and userId then
					local okName, stored = pcall(function()
						return nameStore:GetAsync(tostring(userId))
					end)
					if okName and type(stored) == "string" and stored ~= "" then
						name = stored
					end
				end
				list[#list + 1] = { name = name, score = math.floor(row.value or 0) }
			end
		end
	end
	if #list == 0 then
		return sessionEntries()
	end
	return list
end

local function publish()
	if not scoreStore then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.Get(player)
		if profile then
			local score = lifetimeOre(profile)
			pcall(function()
				scoreStore:SetAsync(tostring(player.UserId), score)
			end)
			if nameStore then
				pcall(function()
					nameStore:SetAsync(tostring(player.UserId), player.Name)
				end)
			end
		end
	end
end

local function render()
	for index, row in ipairs(rows) do
		local entry = entries[index]
		if entry then
			row.frame.Visible = true
			row.rank.Text = "#" .. index
			row.name.Text = entry.name
			row.score.Text = string.format("%d", entry.score)
			row.frame.BackgroundTransparency = index % 2 == 0 and 0.55 or 0.35
		else
			row.frame.Visible = false
		end
	end
	if footer then
		local remaining = math.max(0, nextRefresh - os.time())
		footer.Text = string.format(
			"lifetime ore  ·  refresh every 6h  ·  next in %dh %02dm",
			math.floor(remaining / 3600),
			math.floor((remaining % 3600) / 60)
		)
	end
end

local function buildBoard(part)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Left
	gui.CanvasSize = Vector2.new(680, 460)
	gui.LightInfluence = 0
	gui.Parent = part

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(13, 17, 29)
	back.BorderSizePixel = 0
	back.Parent = gui

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(1, 0, 0, 4)
	stripe.BackgroundColor3 = Color3.fromRGB(132, 198, 250)
	stripe.BorderSizePixel = 0
	stripe.Parent = back

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -36, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "TOP MINERS"
	title.TextColor3 = Color3.fromRGB(250, 252, 255)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 26
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = back

	local subtitle = Instance.new("TextLabel")
	subtitle.Position = UDim2.fromOffset(18, 42)
	subtitle.Size = UDim2.new(1, -36, 0, 18)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Hall of Records  ·  lifetime ore mined"
	subtitle.TextColor3 = Color3.fromRGB(196, 208, 230)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 14
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = back

	for index = 1, ROWS do
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromOffset(16, 66 + (index - 1) * 32)
		frame.Size = UDim2.new(1, -32, 0, 28)
		frame.BackgroundColor3 = Color3.fromRGB(48, 60, 92)
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = back

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = frame

		local rank = Instance.new("TextLabel")
		rank.Position = UDim2.fromOffset(10, 0)
		rank.Size = UDim2.fromOffset(48, 28)
		rank.BackgroundTransparency = 1
		rank.Text = "#" .. index
		rank.TextColor3 = index == 1 and Color3.fromRGB(255, 216, 134) or Color3.fromRGB(196, 208, 230)
		rank.Font = Enum.Font.GothamBlack
		rank.TextSize = 16
		rank.TextXAlignment = Enum.TextXAlignment.Left
		rank.Parent = frame

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(64, 0)
		name.Size = UDim2.new(1, -190, 0, 28)
		name.BackgroundTransparency = 1
		name.Text = "Miner"
		name.TextColor3 = Color3.fromRGB(250, 252, 255)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 16
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = frame

		local score = Instance.new("TextLabel")
		score.Position = UDim2.new(1, -140, 0, 0)
		score.Size = UDim2.fromOffset(130, 28)
		score.BackgroundTransparency = 1
		score.Text = "0"
		score.TextColor3 = Color3.fromRGB(132, 198, 250)
		score.Font = Enum.Font.GothamBlack
		score.TextSize = 16
		score.TextXAlignment = Enum.TextXAlignment.Right
		score.Parent = frame

		rows[index] = { frame = frame, rank = rank, name = name, score = score }
	end

	footer = Instance.new("TextLabel")
	footer.Position = UDim2.new(0, 18, 1, -30)
	footer.Size = UDim2.new(1, -36, 0, 18)
	footer.BackgroundTransparency = 1
	footer.Text = "lifetime ore"
	footer.TextColor3 = Color3.fromRGB(196, 208, 230)
	footer.Font = Enum.Font.GothamMedium
	footer.TextSize = 13
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.Parent = back
end

function LeaderboardService.Start(world: Instance?)
	local part = nil
	if world then
		part = world:FindFirstChild("LeaderboardBoard", true)
	end
	if part and part:IsA("BasePart") then
		buildBoard(part)
	end

	entries = readTop()
	nextRefresh = os.time() + REFRESH_SECONDS
	render()

	task.spawn(function()
		local lastPublish = os.time()
		while true do
			task.wait(10)
			local now = os.time()
			if now - lastPublish >= PUBLISH_SECONDS then
				lastPublish = now
				task.spawn(publish)
			end
			if now >= nextRefresh then
				task.spawn(function()
					entries = readTop()
					render()
				end)
				nextRefresh = now + REFRESH_SECONDS
			end
			render()
		end
	end)
end

return LeaderboardService
