-- Anime Miner Tycoon :: client HUD, menu and developer panel
-- All artwork is procedural (frames, gradients, strokes) so nothing can fail to
-- load: the only raster image is the player's own avatar thumbnail. Labels all
-- use explicit sizes so text is never clipped to a zero-height row.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("Action")
local StateRemote = Remotes:WaitForChild("State")
local NotifyRemote = Remotes:WaitForChild("Notify")
local DialogueRemote = Remotes:WaitForChild("Dialogue")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- one background for the whole interface, matched to the two cards that read
-- best (profile and descend): every panel, card, sidebar and popup is painted
-- with PALETTE.panel, controls one step up in panelLight, wells one step down in
-- sunken. The whole band stays inside 36-58 brightness, so no screen is a dark
-- hole and no component disappears into its parent. Text clears 3:1 everywhere.
local PALETTE = {
	bg = Color3.fromRGB(40, 46, 63),
	panel = Color3.fromRGB(58, 65, 90),
	panelLight = Color3.fromRGB(72, 80, 106),
	sunken = Color3.fromRGB(48, 55, 74),
	accent = Color3.fromRGB(150, 220, 255),
	gold = Color3.fromRGB(255, 224, 164),
	gem = Color3.fromRGB(176, 246, 255),
	pink = Color3.fromRGB(255, 196, 228),
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(198, 209, 228),
	good = Color3.fromRGB(160, 250, 204),
	bad = Color3.fromRGB(255, 186, 178),
	line = Color3.fromRGB(118, 134, 170),
}

local state = nil
local activeTab = "Summon"
local menuOpen = false
local adminOpen = false
local selectedUnitId = nil
local boostLabels = {}
local crewPage = 1
local lastContentBuild = 0
local lastBoostKey, lastTravelKey
local render
local setMenu
local tourDismissed = false
local lastTabRendered = nil
local lastTutorialStep = nil
local lastZoneSeen = nil
local adminPanel = nil
local adminRefs = {}
local zoneBannerToken = 0

-- helpers --------------------------------------------------------------------
local function create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color or PALETTE.line,
		Thickness = thickness or 1.2,
		Transparency = transparency or 0,
	}, parent)
end

local function gradient(parent, top, bottom, rotation)
	-- flat tone by default (one surface colour everywhere); pass a second colour
	-- only for decorative surfaces such as the start screen card
	local sequence = bottom and ColorSequence.new(top, bottom) or ColorSequence.new(top)
	return create("UIGradient", {
		Color = sequence,
		Rotation = rotation or 90,
	}, parent)
end

local function text(parent, content, size, color, font, props)
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Text = content,
		TextSize = size or 15,
		TextColor3 = color or PALETTE.text,
		Font = font or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
	}, parent)
	for key, value in pairs(props or {}) do
		label[key] = value
	end
	return label
end

local function button(parent, content, color, onClick, height)
	local baseColor = color or PALETTE.panelLight
	local btn = create("TextButton", {
		BackgroundColor3 = baseColor,
		AutoButtonColor = true,
		Text = content,
		TextColor3 = PALETTE.text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height or 32),
	}, parent)
	corner(btn, 8)
	stroke(btn, Color3.fromRGB(255, 255, 255):Lerp(baseColor, 0.78), 1, 0.22)
	if onClick then
		btn.MouseButton1Click:Connect(onClick)
	end
	return btn
end

local function bar(parent, ratio, color, height)
	local holder = create("Frame", {
		BackgroundColor3 = PALETTE.sunken,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height or 6),
	}, parent)
	corner(holder, (height or 6) / 2)
	local fill = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1),
	}, holder)
	corner(fill, (height or 6) / 2)
	return holder, fill
end

local function chip(parent, x, y, width, content, color, height)
	local frame = create("Frame", {
		BackgroundColor3 = PALETTE.sunken,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, height or 18),
		Position = UDim2.fromOffset(x, y),
	}, parent)
	corner(frame, (height or 18) / 2)
	stroke(frame, color, 1, 0.3)
	local label = text(frame, content, 9, color, Enum.Font.GothamBold, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	return frame, label
end

-- clickable feel ---------------------------------------------------------------
-- Flat surfaces stay flat, but they answer the cursor: hover lifts the fill a
-- touch, press deepens it and shrinks the button for a frame. Buttons rebuilt
-- every render inherit this through screen.DescendantAdded, so nothing has to
-- remember to opt in.
local function attachFeel(btn)
	if btn:GetAttribute("FlatFeel") then
		return
	end
	btn:SetAttribute("FlatFeel", true)
	btn.AutoButtonColor = false

	local scale = btn:FindFirstChildOfClass("UIScale")
	local ownsScale = false
	if not scale then
		scale = create("UIScale", { Scale = 1 }, btn)
		ownsScale = true
	end
	local canTint = btn:FindFirstChildOfClass("UIGradient") == nil
	local hoverBase, hoverTint, hovered

	local function tint(color)
		if canTint and color then
			btn.BackgroundColor3 = color
		end
	end
	local function press(amount, duration)
		if ownsScale then
			TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = amount }):Play()
		end
	end

	btn.MouseEnter:Connect(function()
		hovered = true
		hoverBase = btn.BackgroundColor3
		hoverTint = hoverBase:Lerp(PALETTE.text, 0.1)
		tint(hoverTint)
	end)
	btn.MouseLeave:Connect(function()
		hovered = false
		-- only undo our own tint: a re-render may already have set a new base
		if hoverTint and btn.BackgroundColor3 == hoverTint then
			tint(hoverBase)
		end
		hoverTint = nil
		press(1, 0.12)
	end)
	btn.MouseButton1Down:Connect(function()
		tint((hoverBase or btn.BackgroundColor3):Lerp(PALETTE.bg, 0.5))
		press(0.97, 0.06)
	end)
	btn.MouseButton1Up:Connect(function()
		tint(hovered and hoverTint or hoverBase or btn.BackgroundColor3)
		press(1, 0.1)
	end)
end

-- drawn icons ----------------------------------------------------------------
local function iconHolder(parent, box, position, anchor)
	return create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(box, box),
		Position = position,
		AnchorPoint = anchor or Vector2.new(0, 0.5),
	}, parent)
end

local function iconBar(parent, thickness, length, color, rotation, position)
	local item = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(thickness, length),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = rotation or 0,
	}, parent)
	corner(item, thickness / 2)
	return item
end

local function hamburgerIcon(parent, color, box, position, anchor)
	local holder = iconHolder(parent, box, position, anchor)
	local thickness = math.max(2, box * 0.14)
	for index = -1, 1 do
		iconBar(holder, box, thickness, color, 0, UDim2.new(0.5, 0, 0.5, index * box * 0.27))
	end
	return holder
end

local function closeIcon(parent, color, box, position, anchor)
	local holder = iconHolder(parent, box, position, anchor)
	local thickness = math.max(2, box * 0.14)
	iconBar(holder, thickness, box, color, 45, UDim2.fromScale(0.5, 0.5))
	iconBar(holder, thickness, box, color, -45, UDim2.fromScale(0.5, 0.5))
	return holder
end

local function chevronIcon(parent, color, box, position, anchor, thickness)
	local holder = iconHolder(parent, box, position, anchor)
	local length = box * 0.62
	local t = thickness or math.max(2, box * 0.12)
	iconBar(holder, t, length, color, 45, UDim2.new(0.5, box * 0.1, 0.5, -length * 0.32))
	iconBar(holder, t, length, color, -45, UDim2.new(0.5, box * 0.1, 0.5, length * 0.32))
	return holder
end

local function coinIcon(parent, color, box, position, anchor)
	local holder = iconHolder(parent, box, position, anchor)
	local disc = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.82, 0.82),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, holder)
	corner(disc, box)
	local hole = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.34, 0.34),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, holder)
	stroke(hole, PALETTE.bg, 2, 0)
	return holder
end

local function gemIcon(parent, color, box, position, anchor)
	local holder = iconHolder(parent, box, position, anchor)
	local diamond = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.56, 0.56),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
	}, holder)
	corner(diamond, 2)
	return holder
end

local function lockIcon(parent, color, box, position, anchor)
	local holder = iconHolder(parent, box, position, anchor)
	local shackle = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(box * 0.52, box * 0.44),
		Position = UDim2.new(0.5, 0, 0.34, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, holder)
	corner(shackle, box)
	stroke(shackle, color, math.max(1.5, box * 0.14), 0)
	local body = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(box * 0.72, box * 0.5),
		Position = UDim2.new(0.5, 0, 0.66, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, holder)
	corner(body, math.max(2, box * 0.14))
	return holder
end

local function checkIcon(parent, color, box, position, anchor)
	local holder = iconHolder(parent, box, position, anchor)
	iconBar(holder, math.max(2, box * 0.18), box * 0.4, color, -42, UDim2.new(0.36, 0, 0.56, 0))
	iconBar(holder, math.max(2, box * 0.18), box * 0.72, color, 42, UDim2.new(0.62, 0, 0.46, 0))
	return holder
end

-- procedural hero portrait ---------------------------------------------------
local function portrait(parent, size, position, heroColor, rarityColor, level, locked)
	local box = create("Frame", {
		Name = "Portrait",
		BackgroundColor3 = PALETTE.sunken,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(size, size),
		Position = position,
	}, parent)
	corner(box, math.floor(size * 0.26))
	stroke(box, rarityColor or PALETTE.line, 1.6, locked and 0.7 or 0.05)

	local backdrop = create("Frame", {
		BackgroundColor3 = heroColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, box)
	corner(backdrop, math.floor(size * 0.26))
	gradient(backdrop, heroColor:Lerp(Color3.fromRGB(255, 255, 255), 0.14), nil, 90)

	local shoulders = create("Frame", {
		BackgroundColor3 = heroColor:Lerp(Color3.fromRGB(6, 8, 16), 0.52),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.92, 0.32),
		Position = UDim2.fromScale(0.5, 0.98),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, box)
	corner(shoulders, size * 0.24)

	local faceColor = locked and Color3.fromRGB(58, 64, 84) or Color3.fromRGB(255, 226, 205)
	local face = create("Frame", {
		BackgroundColor3 = faceColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.52, 0.52),
		Position = UDim2.fromScale(0.5, 0.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, box)
	corner(face, size)

	local hair = create("Frame", {
		BackgroundColor3 = locked and Color3.fromRGB(44, 49, 66) or heroColor:Lerp(Color3.fromRGB(24, 22, 38), 0.35),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.68, 0.42),
		Position = UDim2.fromScale(0.5, 0.27),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, box)
	corner(hair, size)

	local fringe = create("Frame", {
		BackgroundColor3 = locked and Color3.fromRGB(50, 56, 74) or heroColor:Lerp(Color3.fromRGB(40, 36, 60), 0.2),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.62, 0.16),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -6,
	}, box)
	corner(fringe, 4)

	local eyeY = 0.6
	for _, side in ipairs({ -1, 1 }) do
		local eye = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(30, 32, 48),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(math.max(2, math.floor(size * 0.09)), math.max(3, math.floor(size * 0.13))),
			Position = UDim2.new(0.5, side * size * 0.11, eyeY, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
		}, box)
		corner(eye, 2)
		if not locked then
			create("Frame", {
				BackgroundColor3 = heroColor:Lerp(Color3.fromRGB(255, 255, 255), 0.35),
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(math.max(1, math.floor(size * 0.04)), math.max(2, math.floor(size * 0.06))),
				Position = UDim2.new(0.5, side * size * 0.11, eyeY - size * 0.01, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
			}, box)
		end
	end

	local dot = create("Frame", {
		BackgroundColor3 = rarityColor or PALETTE.line,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(math.max(6, math.floor(size * 0.16)), math.max(6, math.floor(size * 0.16))),
		Position = UDim2.fromOffset(math.floor(size * 0.1), math.floor(size * 0.1)),
		Rotation = 45,
	}, box)
	corner(dot, 2)

	if level then
		local badge = create("Frame", {
			BackgroundColor3 = PALETTE.sunken,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(math.max(26, math.floor(size * 0.4)), math.max(13, math.floor(size * 0.2))),
			Position = UDim2.new(1, -math.floor(size * 0.06), 1, -math.floor(size * 0.06)),
			AnchorPoint = Vector2.new(1, 1),
		}, box)
		corner(badge, 4)
		stroke(badge, rarityColor or PALETTE.line, 1, 0.2)
		text(badge, "Lv " .. tostring(level), math.clamp(math.floor(size * 0.14), 8, 12), PALETTE.text, Enum.Font.GothamBold, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end

	if locked then
		local veil = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(48, 54, 72),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, box)
		corner(veil, math.floor(size * 0.26))
		text(veil, "?", math.clamp(math.floor(size * 0.4), 12, 34), PALETTE.dim, Enum.Font.GothamBlack, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end

	return box
end

local thumbnailCache = {}

local function avatarFrame(parent, size, position)
	local frame = create("Frame", {
		Name = "Avatar",
		BackgroundColor3 = PALETTE.panelLight,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(size, size),
		Position = position,
	}, parent)
	corner(frame, size)
	stroke(frame, PALETTE.gold, 1.6, 0.1)
	gradient(frame, PALETTE.accent, Color3.fromRGB(60, 40, 90), 120)

	local image = create("ImageLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
		Image = "",
	}, frame)
	corner(image, size)

	local cached = thumbnailCache[player.UserId]
	if cached then
		image.Image = cached
	else
		task.spawn(function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			end)
			if ok and content then
				thumbnailCache[player.UserId] = content
				if image.Parent then
					image.Image = content
				end
			end
		end)
	end

	return frame, image
end

local function popLabel(label, baseSize, extra)
	label.TextSize = baseSize + (extra or 2)
	TweenService:Create(label, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = baseSize,
	}):Play()
end

local function send(action, payload)
	Action:FireServer(action, payload)
end

-- player settings -------------------------------------------------------------
-- One store drives render quality, pet visibility and HUD density. The start
-- screen and the in-game panel are the same widget reading the same table, and
-- every choice is written to the profile so it survives a rejoin.
local settings = { quality = "normal", petsVisible = true, hudVisible = false }
local settingsTouched = false
local settingsPanels = {}
local settingsSummaryLabels = {}
local applyPets, applyHud
local refreshSettingsPanels

local QUALITY_PRESETS = {
	low = { label = "LOW", shadows = false, effects = false, emitters = false, lightLimit = 26,
		desc = "Fastest: no post effects, no sparks, fewer lights." },
	normal = { label = "NORMAL", shadows = false, effects = true, emitters = true, lightLimit = 70,
		desc = "Balanced: full colour, sparks and lights, cheap shadows." },
	high = { label = "HIGH", shadows = true, effects = true, emitters = true, lightLimit = math.huge,
		desc = "Everything on: shadows, bloom, sun rays, every light." },
}
local QUALITY_TIERS = { "low", "normal", "high" }

local Lighting = game:GetService("Lighting")

local function applyQuality(tier)
	local preset = QUALITY_PRESETS[tier] or QUALITY_PRESETS.normal
	Lighting.GlobalShadows = preset.shadows
	for _, inst in ipairs(Lighting:GetChildren()) do
		if inst:IsA("PostEffect") then
			inst.Enabled = preset.effects
		elseif inst:IsA("Atmosphere") then
			inst.Density = preset.effects and 0.44 or 0.18
		end
	end
	local world = workspace:FindFirstChild("MineWorld")
	if not world then
		return
	end
	local lights, emitters = {}, {}
	for _, inst in ipairs(world:GetDescendants()) do
		if inst:IsA("Light") then
			lights[#lights + 1] = inst
		elseif inst:IsA("ParticleEmitter") then
			emitters[#emitters + 1] = inst
		end
	end
	for index, light in ipairs(lights) do
		light.Enabled = index <= preset.lightLimit
	end
	for _, emitter in ipairs(emitters) do
		emitter.Enabled = preset.emitters
	end
end

local function saveSettings()
	settingsTouched = true
	Action:FireServer("SaveSettings", {
		quality = settings.quality,
		petsVisible = settings.petsVisible,
		hudVisible = settings.hudVisible,
	})
end

local function setSetting(key, value)
	if settings[key] == value then
		return
	end
	settings[key] = value
	if key == "quality" then
		applyQuality(value)
	elseif key == "petsVisible" and applyPets then
		applyPets()
	elseif key == "hudVisible" and applyHud then
		applyHud()
	end
	if refreshSettingsPanels then
		refreshSettingsPanels()
	end
	saveSettings()
end

local function makeSettingsPanel(parent)
	local card = create("CanvasGroup", {
		Name = "SettingsPanel",
		BackgroundColor3 = PALETTE.panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(430, 330),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		GroupTransparency = 1,
		ZIndex = 60,
	}, parent)
	corner(card, 14)
	stroke(card, PALETTE.line, 1.4, 0.15)

	text(card, "SETTINGS", 15, PALETTE.text, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.fromOffset(220, 20),
	})
	text(card, "Saved to your profile", 8, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 34),
		Size = UDim2.fromOffset(240, 12),
	})

	local closeBtn = create("TextButton", {
		Name = "SettingsClose",
		BackgroundColor3 = PALETTE.sunken,
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -14, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
	}, card)
	corner(closeBtn, 7)
	closeIcon(closeBtn, PALETTE.bad, 10, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

	text(card, "GRAPHICS QUALITY", 9, PALETTE.accent, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 52),
		Size = UDim2.new(1, -36, 0, 12),
	})
	local qualityButtons = {}
	for index, tier in ipairs(QUALITY_TIERS) do
		local btn = button(card, QUALITY_PRESETS[tier].label, PALETTE.panelLight, function()
			setSetting("quality", tier)
		end, 32)
		btn.Size = UDim2.fromOffset(126, 32)
		btn.Position = UDim2.fromOffset(18 + (index - 1) * 132, 68)
		qualityButtons[tier] = btn
	end
	local qualityHint = text(card, "", 8, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 106),
		Size = UDim2.new(1, -36, 0, 12),
	})

	text(card, "PETS", 9, PALETTE.accent, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 128),
		Size = UDim2.new(1, -36, 0, 12),
	})
	local petButtons = {}
	for index, option in ipairs({ { true, "SHOW PETS" }, { false, "HIDE PETS" } }) do
		local btn = button(card, option[2], PALETTE.panelLight, function()
			setSetting("petsVisible", option[1])
		end, 30)
		btn.Size = UDim2.fromOffset(191, 30)
		btn.Position = UDim2.fromOffset(18 + (index - 1) * 197, 146)
		petButtons[index] = btn
	end
	text(card, "Hidden pets keep their bonuses: only the rigs stop drawing.", 8, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 180),
		Size = UDim2.new(1, -36, 0, 12),
	})

	text(card, "HUD", 9, PALETTE.accent, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 202),
		Size = UDim2.new(1, -36, 0, 12),
	})
	local hudButtons = {}
	for index, option in ipairs({ { true, "SHOW HUD" }, { false, "MINIMAL HUD" } }) do
		local btn = button(card, option[2], PALETTE.panelLight, function()
			setSetting("hudVisible", option[1])
		end, 30)
		btn.Size = UDim2.fromOffset(191, 30)
		btn.Position = UDim2.fromOffset(18 + (index - 1) * 197, 220)
		hudButtons[index] = btn
	end
	text(card, "Minimal HUD leaves only Menu, HUD and Settings at the bottom.", 8, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 254),
		Size = UDim2.new(1, -36, 0, 12),
	})
	text(card, "Open this from the start screen or while playing.", 8, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 296),
		Size = UDim2.new(1, -36, 0, 12),
	})

	local function paint(btn, active)
		btn.BackgroundColor3 = active and PALETTE.accent or PALETTE.panelLight
		btn.TextColor3 = active and Color3.fromRGB(12, 16, 28) or PALETTE.text
		btn.BackgroundTransparency = active and 0.05 or 0.18
	end

	local function refresh()
		for tier, btn in pairs(qualityButtons) do
			paint(btn, settings.quality == tier)
		end
		paint(petButtons[1], settings.petsVisible)
		paint(petButtons[2], not settings.petsVisible)
		paint(hudButtons[1], settings.hudVisible)
		paint(hudButtons[2], not settings.hudVisible)
		qualityHint.Text = (QUALITY_PRESETS[settings.quality] or QUALITY_PRESETS.normal).desc
		for _, label in ipairs(settingsSummaryLabels) do
			if label.Parent then
				label.Text = string.format("%s QUALITY  ·  PETS %s  ·  %s HUD",
					QUALITY_PRESETS[settings.quality].label,
					settings.petsVisible and "ON" or "HIDDEN",
					settings.hudVisible and "FULL" or "MINIMAL")
			end
		end
	end

	local function close()
		if not card.Visible then
			return
		end
		TweenService:Create(card, TweenInfo.new(0.14), { GroupTransparency = 1 }):Play()
		task.delay(0.16, function()
			card.Visible = false
		end)
	end

	local function open()
		refresh()
		card.Visible = true
		card.GroupTransparency = 0.6
		TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
	end

	closeBtn.MouseButton1Click:Connect(close)
	local entry = { frame = card, open = open, close = close, refresh = refresh }
	settingsPanels[#settingsPanels + 1] = entry
	refresh()
	return entry
end

refreshSettingsPanels = function()
	for _, panel in ipairs(settingsPanels) do
		panel.refresh()
	end
end

applyQuality(settings.quality)

workspace.ChildAdded:Connect(function(child)
	if child.Name == "MineWorld" then
		task.defer(applyQuality, settings.quality)
	end
end)

-- anything the mine adds while low is selected inherits the ceiling; emitters
-- outside MineWorld (hero auras) stay untouched so HIGH can restore everything
workspace.DescendantAdded:Connect(function(inst)
	if settings.quality ~= "low" then
		return
	end
	if inst:IsA("ParticleEmitter") and inst:FindFirstAncestor("MineWorld") then
		inst.Enabled = false
	end
end)

local function rankFor(stats)
	local mined = (stats and stats.blocksMined) or 0
	if mined >= 25000 then
		return "WORLDBREAKER"
	elseif mined >= 8000 then
		return "DEEP DELVER"
	elseif mined >= 2000 then
		return "CAVERN RUNNER"
	elseif mined >= 400 then
		return "PROSPECTOR"
	elseif mined >= 60 then
		return "APPRENTICE"
	end
	return "ROOKIE"
end

-- loading screen -----------------------------------------------------------
-- This screen only exists while there is real work to do: waiting for the map
-- to replicate, or fetching the assets the world actually references. There is
-- no timer and no minimum display time, so a cached join never sees it.
local ContentProvider = game:GetService("ContentProvider")
local loadingScreen = create("ScreenGui", {
	Name = "AnimeMinerLoading",
	-- inset respected: with it ignored the whole screen was shifted up by the
	-- top-bar inset, which pushed the start card above the display edge
	IgnoreGuiInset = false,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 200,
	Enabled = true,
}, playerGui)

-- the start screen gets the same hover/press feel as the HUD
loadingScreen.DescendantAdded:Connect(function(item)
	if item:IsA("TextButton") then
		attachFeel(item)
	end
end)

local loadingRoot = create("CanvasGroup", {
	Name = "Root",
	BackgroundColor3 = PALETTE.bg,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
}, loadingScreen)
local startGlow = create("Frame", {
	BackgroundColor3 = PALETTE.accent,
	BackgroundTransparency = 0.93,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0.38, 0),
	Position = UDim2.fromScale(0, 0.6),
}, loadingRoot)
local startGlowWarm = create("Frame", {
	BackgroundColor3 = PALETTE.pink,
	BackgroundTransparency = 0.95,
	BorderSizePixel = 0,
	Size = UDim2.new(0.64, 0, 0.16, 0),
	Position = UDim2.fromScale(0.18, 0.54),
}, loadingRoot)
corner(startGlowWarm, 240)
for index = 1, 26 do
	local dot = create("Frame", {
		BackgroundColor3 = index % 3 == 0 and PALETTE.pink or PALETTE.accent,
		BackgroundTransparency = 0.55 + math.random() * 0.3,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(math.random(2, 4), math.random(2, 4)),
		Position = UDim2.fromScale(math.random(), math.random() * 0.8),
	}, loadingRoot)
	corner(dot, 3)
	if index % 4 == 0 then
		TweenService:Create(dot, TweenInfo.new(1.2 + math.random() * 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			BackgroundTransparency = 1,
		}):Play()
	end
end

local START_WIDTH, START_HEIGHT = 660, 440
local loadingCard = create("Frame", {
	Name = "StartCard",
	BackgroundColor3 = PALETTE.panel,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(START_WIDTH, START_HEIGHT),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	ClipsDescendants = true,
}, loadingRoot)
corner(loadingCard, 20)
stroke(loadingCard, PALETTE.line, 1.4, 0.2)
gradient(loadingCard, PALETTE.panelLight, PALETTE.panel, 90)

-- the scale lives on the card, not on the full-screen root (scaling the root
-- pushed the card down-right), and the scaled card is then centred with
-- explicit offsets: a UIScale has no pivot we can rely on between versions,
-- so doing the maths here keeps the start screen dead centre at any size.
local startScale = create("UIScale", { Scale = 1 }, loadingCard)
local function fitStartScreen()
	local viewport = loadingScreen.AbsoluteSize
	if viewport.X < 1 or viewport.Y < 1 then
		return
	end
	local scale = math.clamp(math.min(viewport.X / 720, viewport.Y / 490), 0.5, 1.7)
	startScale.Scale = scale
	loadingCard.AnchorPoint = Vector2.new(0, 0)
	loadingCard.Position = UDim2.fromOffset(
		math.floor((viewport.X - START_WIDTH * scale) / 2),
		math.floor((viewport.Y - START_HEIGHT * scale) / 2)
	)
end
fitStartScreen()
loadingScreen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitStartScreen)

-- accent strip on the top edge, clipped by the card's rounded corners
local startStrip = create("Frame", {
	BackgroundColor3 = PALETTE.accent,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 5),
}, loadingCard)
gradient(startStrip, PALETTE.accent, PALETTE.pink, 0)

-- soft halo + slowly turning ring behind the logo, both procedural
local logoHalo = create("Frame", {
	BackgroundColor3 = PALETTE.accent,
	BackgroundTransparency = 0.94,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(124, 124),
	Position = UDim2.new(0.5, -62, 0, 0),
}, loadingCard)
corner(logoHalo, 62)
local logoRing = create("Frame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(94, 94),
	Position = UDim2.new(0.5, -47, 0, 15),
}, loadingCard)
corner(logoRing, 16)
stroke(logoRing, PALETTE.accent, 1.5, 0.5)
TweenService:Create(logoRing, TweenInfo.new(12, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
	Rotation = 90,
}):Play()

local loadingLogo = create("Frame", {
	BackgroundColor3 = PALETTE.accent,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(66, 66),
	Position = UDim2.new(0.5, 0, 0, 62),
	AnchorPoint = Vector2.new(0.5, 0.5),
}, loadingCard)
corner(loadingLogo, 20)
gradient(loadingLogo, PALETTE.accent, PALETTE.pink, 55)
stroke(loadingLogo, Color3.fromRGB(255, 255, 255), 1.6, 0.35)
text(loadingLogo, "AM", 21, Color3.fromRGB(12, 16, 28), Enum.Font.GothamBlack, {
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
})

-- the page fades up once and the logo pops as it lands: the scale sits on the
-- centred logo, so the pop happens around its middle instead of its corner
local logoScale = create("UIScale", { Scale = 0.55 }, loadingLogo)
loadingRoot.GroupTransparency = 1
TweenService:Create(loadingRoot, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	GroupTransparency = 0,
}):Play()
TweenService:Create(logoScale, TweenInfo.new(0.62, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
	Scale = 1,
}):Play()

local loadingTitle = text(loadingCard, Config.TITLE, 38, PALETTE.text, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(0, 110),
	Size = UDim2.new(1, 0, 0, 46),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0.8,
})
local startDivider = create("Frame", {
	BackgroundColor3 = PALETTE.accent,
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(120, 2),
	Position = UDim2.new(0.5, -60, 0, 160),
}, loadingCard)
corner(startDivider, 2)
text(loadingCard, Config.SUBTITLE, 13, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.fromOffset(0, 170),
	Size = UDim2.new(1, 0, 0, 18),
	TextXAlignment = Enum.TextXAlignment.Center,
})
-- three compact feature chips instead of a single line of small text
chip(loadingCard, 130, 194, 128, "SIX BIOMES", PALETTE.accent, 20)
chip(loadingCard, 266, 194, 128, "150 ORE NODES", PALETTE.gold, 20)
chip(loadingCard, 402, 194, 128, "PET COMPANIONS", PALETTE.pink, 20)

local loadingTrack = create("Frame", {
	BackgroundColor3 = PALETTE.sunken,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(460, 10),
	Position = UDim2.new(0.5, -230, 0, 234),
}, loadingCard)
corner(loadingTrack, 5)
stroke(loadingTrack, PALETTE.line, 1, 0.4)
local loadingFill = create("Frame", {
	BackgroundColor3 = PALETTE.accent,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(0, 1),
	ClipsDescendants = true,
}, loadingTrack)
corner(loadingFill, 4)
gradient(loadingFill, PALETTE.accent, PALETTE.pink, 0)
-- shimmer: a soft white band that sweeps the filled part of the bar forever
local shimmer = create("Frame", {
	Name = "Shimmer",
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(64, 10),
	Position = UDim2.fromOffset(-70, 0),
	ZIndex = 3,
}, loadingFill)
local shimmerGradient = create("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.32),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, shimmer)
task.spawn(function()
	while shimmer.Parent do
		shimmer.Position = UDim2.fromOffset(-70, 0)
		local sweep = TweenService:Create(shimmer, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Position = UDim2.new(1, 10, 0, 0),
		})
		sweep:Play()
		sweep.Completed:Wait()
		task.wait(0.6)
	end
end)
local loadingPercent = text(loadingCard, "0%", 11, PALETTE.gold, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(0, 248),
	Size = UDim2.new(1, 0, 0, 14),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local loadingStatus = text(loadingCard, "Checking for the mine…", 10, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.fromOffset(0, 266),
	Size = UDim2.new(1, 0, 0, 16),
	TextXAlignment = Enum.TextXAlignment.Center,
})

local playButton = create("TextButton", {
	Name = "PlayButton",
	BackgroundColor3 = PALETTE.accent,
	BorderSizePixel = 0,
	Text = "PLAY",
	TextColor3 = Color3.fromRGB(12, 16, 28),
	Font = Enum.Font.GothamBlack,
	TextSize = 18,
	Size = UDim2.fromOffset(300, 52),
	Position = UDim2.new(0.5, -150, 0, 296),
	Visible = false,
	AutoButtonColor = true,
}, loadingCard)
corner(playButton, 13)
gradient(playButton, PALETTE.accent, PALETTE.pink, 0)
stroke(playButton, Color3.fromRGB(255, 255, 255), 1.2, 0.35)

-- settings live on the start screen too, so quality and HUD density are chosen
-- before the mine is ever drawn
local startSettings = makeSettingsPanel(loadingCard)
local startSettingsButton = create("TextButton", {
	Name = "StartSettingsButton",
	BackgroundColor3 = PALETTE.panelLight,
	BorderSizePixel = 0,
	Text = "SETTINGS",
	TextColor3 = PALETTE.text,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	Size = UDim2.fromOffset(160, 34),
	Position = UDim2.new(0.5, -80, 0, 364),
	AutoButtonColor = true,
}, loadingCard)
corner(startSettingsButton, 9)
stroke(startSettingsButton, PALETTE.line, 1, 0.3)
startSettingsButton.MouseButton1Click:Connect(function()
	if startSettings.frame.Visible then
		startSettings.close()
	else
		startSettings.open()
	end
end)

local startSummary = text(loadingCard, "", 9, PALETTE.dim, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(0, 408),
	Size = UDim2.new(1, 0, 0, 14),
	TextXAlignment = Enum.TextXAlignment.Center,
})
settingsSummaryLabels[#settingsSummaryLabels + 1] = startSummary
refreshSettingsPanels()

local loadingReady = false
local function setLoadingProgress(ratio, statusText, percentText)
	local clamped = math.clamp(ratio, 0, 1)
	loadingFill.Size = UDim2.fromScale(clamped, 1)
	loadingPercent.Text = percentText or (math.floor(clamped * 100) .. "%")
	if statusText then
		loadingStatus.Text = statusText
	end
end

local function dismissLoading()
	loadingReady = true
	if not loadingScreen.Parent or not loadingScreen.Enabled then
		return
	end
	startSettings.close()
	TweenService:Create(loadingRoot, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 1,
	}):Play()
	task.delay(0.36, function()
		loadingScreen:Destroy()
	end)
end

playButton.MouseButton1Click:Connect(dismissLoading)

local function revealPlay(message)
	if loadingReady then
		return
	end
	loadingReady = true
	loadingScreen.Enabled = true
	setLoadingProgress(1, message or "Ready. The mine is loaded.", "100%")
	playButton.Visible = true
	playButton.Size = UDim2.fromOffset(300, 52)
	TweenService:Create(playButton, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(322, 58),
	}):Play()
	task.delay(0.34, function()
		if playButton.Parent then
			TweenService:Create(playButton, TweenInfo.new(0.18), { Size = UDim2.fromOffset(300, 52) }):Play()
		end
	end)
end

task.spawn(function()
	local world = workspace:FindFirstChild("MineWorld")
	if not world then
		loadingScreen.Enabled = true
		setLoadingProgress(0.06, "Building the mine…", "…")
		world = workspace:WaitForChild("MineWorld", 20)
	end
	if not world then
		loadingScreen.Enabled = true
		setLoadingProgress(0.5, "The server is still building the map…", "…")
	end

	local list = {}
	if world then
		for _, descendant in ipairs(world:GetDescendants()) do
			if descendant:IsA("Decal") or descendant:IsA("Texture") or descendant:IsA("MeshPart")
				or descendant:IsA("SurfaceAppearance") or descendant:IsA("Sound") then
				list[#list + 1] = descendant
			end
		end
	end

	-- the player's headshot is a genuine remote asset, so the screen has
	-- something honest to fetch even on maps made only of parts
	local avatarProbe = create("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(2, 2),
		Position = UDim2.fromOffset(-10, -10),
		Image = "",
	}, loadingRoot)
	local okThumb, thumbnail = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if okThumb and thumbnail then
		avatarProbe.Image = thumbnail
		list[#list + 1] = avatarProbe
	end

	if #list == 0 then
		-- nothing to load: the start screen is still the start screen
		revealPlay("Ready. The mine is loaded.")
		return
	end

	loadingScreen.Enabled = true
	setLoadingProgress(0.1, "Loading " .. #list .. " asset(s)…")

	local total = #list
	local done = 0
	local finished = false
	local function finish(message)
		if finished then
			return
		end
		finished = true
		revealPlay(message)
	end

	-- safety valve: never trap the player behind a stalled fetch
	task.delay(15, function()
		finish("Some assets are slow — you can enter now.")
	end)

	local ok = pcall(function()
		ContentProvider:PreloadAsync(list, function(_, status)
			done += 1
			setLoadingProgress(0.1 + 0.9 * (done / total), "Loading assets… " .. done .. " / " .. total)
			if status == Enum.AssetFetchStatus.Failure and done >= total then
				finish("Some assets failed to load — entering anyway.")
			end
			if done >= total then
				finish("Ready. The mine is loaded.")
			end
		end)
	end)
	if not ok then
		finish("Asset fetch unavailable — entering anyway.")
	else
		finish("Ready. The mine is loaded.")
	end
end)

-- root -----------------------------------------------------------------------
local screen = create("ScreenGui", {
	Name = "AnimeMinerUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 40,
}, playerGui)

-- every button answers the cursor, including the ones rebuilt on each render
screen.DescendantAdded:Connect(function(item)
	if item:IsA("TextButton") then
		attachFeel(item)
	end
end)

-- responsive canvas -----------------------------------------------------------
-- The HUD is authored against a 1280x720 canvas and the whole layer is scaled to
-- the viewport, so a phone shrinks the layout as a unit instead of letting the
-- fixed offsets collide or run off the edges.
local canvas = create("Frame", {
	Name = "Canvas",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(1280, 720),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	ZIndex = 1,
}, screen)
local canvasScale = create("UIScale", { Scale = 1 }, canvas)
local function fitCanvas()
	local viewport = screen.AbsoluteSize
	if viewport.X < 1 or viewport.Y < 1 then
		return
	end
	canvasScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.5, 3)
end
fitCanvas()
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCanvas)

-- the in-game settings panel rides the same canvas as the HUD
local gameSettings = makeSettingsPanel(canvas)

-- twinkling depth dust behind the HUD
local starLayer = create("Frame", {
	Name = "StarLayer",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 0,
}, screen)
for _ = 1, 34 do
	local dot = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(180, 215, 255),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(math.random(1, 3), math.random(1, 3)),
		Position = UDim2.fromScale(math.random(), math.random()),
	}, starLayer)
	corner(dot, 2)
end

local topBar = create("Frame", {
	Name = "TopBar",
	BackgroundColor3 = PALETTE.panel,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 56),
}, screen)
stroke(topBar, PALETTE.line, 1, 0.55)

local logo = create("Frame", {
	BackgroundColor3 = PALETTE.accent,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(34, 34),
	Position = UDim2.fromOffset(14, 11),
}, topBar)
corner(logo, 10)
gradient(logo, PALETTE.accent, PALETTE.pink, 55)
stroke(logo, Color3.fromRGB(255, 255, 255), 1.2, 0.45)
text(logo, "AM", 12, Color3.fromRGB(12, 16, 28), Enum.Font.GothamBlack, {
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
})

text(topBar, Config.TITLE, 14, PALETTE.text, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(58, 8),
	Size = UDim2.fromOffset(260, 18),
})
text(topBar, Config.SUBTITLE, 9, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.fromOffset(58, 27),
	Size = UDim2.fromOffset(260, 14),
})

coinIcon(topBar, PALETTE.gold, 16, UDim2.fromOffset(334, 29))
local coinLabel = text(topBar, "0 coins", 16, PALETTE.gold, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(354, 14),
	Size = UDim2.fromOffset(150, 24),
})
gemIcon(topBar, PALETTE.gem, 16, UDim2.fromOffset(506, 29))
local gemLabel = text(topBar, "0 gems", 16, PALETTE.gem, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(526, 14),
	Size = UDim2.fromOffset(140, 24),
})

local levelChip = create("Frame", {
	Name = "LevelChip",
	BackgroundColor3 = PALETTE.panelLight,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(150, 30),
	Position = UDim2.new(1, -572, 0, 13),
}, topBar)
corner(levelChip, 8)
stroke(levelChip, PALETTE.gold, 1, 0.45)
local levelLabel = text(levelChip, "MINER LV 1", 10, PALETTE.gold, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(8, 3),
	Size = UDim2.fromOffset(134, 13),
})
local levelBarHolder = create("Frame", {		BackgroundColor3 = PALETTE.sunken,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -16, 0, 4),
	Position = UDim2.fromOffset(8, 20),
}, levelChip)
corner(levelBarHolder, 2)
local levelFill = create("Frame", {
	BackgroundColor3 = PALETTE.gold,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(0.2, 1),
}, levelBarHolder)
corner(levelFill, 2)

local dpsLabel = text(topBar, "0 DPS  ·  0 heroes", 11, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.new(1, -412, 0, 9),
	Size = UDim2.fromOffset(306, 16),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local luckLabel = text(topBar, "Luck x1.00  ·  Pickaxe Lv 1", 11, PALETTE.pink, Enum.Font.GothamMedium, {
	Position = UDim2.new(1, -412, 0, 29),
	Size = UDim2.fromOffset(306, 16),
	TextXAlignment = Enum.TextXAlignment.Right,
})

local adminButton = create("TextButton", {
	Name = "AdminButton",
	BackgroundColor3 = PALETTE.sunken,
	BorderSizePixel = 0,
	Text = "DEV",
	TextColor3 = PALETTE.pink,
	Font = Enum.Font.GothamBlack,
	TextSize = 10,
	Size = UDim2.fromOffset(46, 30),
	Position = UDim2.new(1, -96, 0, 13),
	Visible = false,
	AutoButtonColor = true,
}, topBar)
corner(adminButton, 8)
stroke(adminButton, PALETTE.pink, 1, 0.3)

local helpButton = create("TextButton", {
	Name = "HelpButton",
	BackgroundColor3 = PALETTE.panelLight,
	BorderSizePixel = 0,
	Text = "?",
	TextColor3 = PALETTE.accent,
	Font = Enum.Font.GothamBlack,
	TextSize = 15,
	Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -46, 0, 13),
}, topBar)
corner(helpButton, 8)
stroke(helpButton, PALETTE.accent, 1, 0.4)

-- weather chip
local weatherChip = create("TextButton", {
	Name = "WeatherChip",
	BackgroundColor3 = PALETTE.panel,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = true,
	Size = UDim2.fromOffset(320, 30),
	Position = UDim2.new(0.5, 0, 0, 64),
	AnchorPoint = Vector2.new(0.5, 0),
}, screen)
corner(weatherChip, 9)
local weatherStroke = stroke(weatherChip, PALETTE.accent, 1, 0.3)	gradient(weatherChip, PALETTE.panelLight, nil, 90)
local weatherDot = create("Frame", {
	BackgroundColor3 = PALETTE.accent,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(8, 8),
	Position = UDim2.fromOffset(12, 11),
	Rotation = 45,
}, weatherChip)
corner(weatherDot, 2)
local weatherLabel = text(weatherChip, "Clear Skies · 100s", 11, PALETTE.text, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(28, 6),
	Size = UDim2.new(1, -40, 0, 18),
	TextXAlignment = Enum.TextXAlignment.Center,
})
text(weatherChip, "CLICK FOR FORECAST", 7, PALETTE.dim, Enum.Font.GothamBold, {
	Position = UDim2.new(1, -130, 0, 9),
	Size = UDim2.fromOffset(118, 12),
	TextXAlignment = Enum.TextXAlignment.Right,
})

-- boost chips
local boostHolder = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(640, 22),
	Position = UDim2.new(0.5, 0, 0, 99),
	AnchorPoint = Vector2.new(0.5, 0),
}, screen)
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, boostHolder)

-- profile card ---------------------------------------------------------------
local profileCard = create("Frame", {
	Name = "ProfileCard",
	BackgroundColor3 = PALETTE.panel,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(272, 208),
	Position = UDim2.fromOffset(16, 132),
}, screen)
corner(profileCard, 12)
stroke(profileCard, PALETTE.line, 1, 0.35)	gradient(profileCard, PALETTE.panelLight, nil, 100)

avatarFrame(profileCard, 56, UDim2.fromOffset(14, 14))
local nameLabel = text(profileCard, player.DisplayName, 14, PALETTE.text, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(80, 14),
	Size = UDim2.fromOffset(178, 18),
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local tagLabel = text(profileCard, "@" .. player.Name, 9, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.fromOffset(80, 33),
	Size = UDim2.fromOffset(178, 13),
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local rankChip = create("Frame", {
	BackgroundColor3 = PALETTE.sunken,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(88, 18),
	Position = UDim2.fromOffset(80, 50),
}, profileCard)
corner(rankChip, 9)
stroke(rankChip, PALETTE.gold, 1, 0.35)
local rankLabel = text(rankChip, "ROOKIE", 9, PALETTE.gold, Enum.Font.GothamBold, {
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
})

local function statCell(x, y, labelText)
	text(profileCard, labelText, 8, PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(118, 11),
	})
	return text(profileCard, "-", 12, PALETTE.text, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(x, y + 12),
		Size = UDim2.fromOffset(118, 16),
	})
end
local zoneStat = statCell(14, 82, "CURRENT ZONE")
local crewStat = statCell(142, 82, "CREW SLOTS")
local blocksStat = statCell(14, 114, "ORE BROKEN")
local bestStat = statCell(142, 114, "BEST PULL")

text(profileCard, "STORAGE", 8, PALETTE.dim, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(14, 148),
	Size = UDim2.fromOffset(120, 11),
})
local storageLabel = text(profileCard, "0 / 60", 10, PALETTE.text, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(180, 147),
	Size = UDim2.fromOffset(78, 13),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local storageHolder, storageFill = bar(profileCard, 0, PALETTE.accent, 5)
storageHolder.Position = UDim2.fromOffset(14, 163)
storageHolder.Size = UDim2.new(1, -28, 0, 5)

local xpHolder, xpFill = bar(profileCard, 0, PALETTE.gold, 5)
xpHolder.Position = UDim2.fromOffset(14, 178)
xpHolder.Size = UDim2.new(1, -28, 0, 5)
local xpLabel = text(profileCard, "0 / 12 ore to Lv 2", 8, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.fromOffset(14, 186),
	Size = UDim2.new(1, -28, 0, 12),
})
local dailyChip = create("Frame", {
	BackgroundColor3 = PALETTE.sunken,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(88, 16),
	Position = UDim2.new(1, -96, 0, 50),
}, profileCard)
corner(dailyChip, 8)
stroke(dailyChip, PALETTE.gold, 1, 0.4)
local dailyLabel = text(dailyChip, "DAILY READY", 7, PALETTE.gold, Enum.Font.GothamBold, {
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
})

-- travel card ----------------------------------------------------------------
local travelCard = create("Frame", {
	Name = "TravelCard",
	BackgroundColor3 = PALETTE.panel,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(272, 196),
	Position = UDim2.fromOffset(16, 350),
}, screen)
corner(travelCard, 12)
stroke(travelCard, PALETTE.line, 1, 0.35)
text(travelCard, "DESCEND", 9, PALETTE.accent, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.fromOffset(120, 12),
})
text(travelCard, "CLICK A BIOME PORTAL", 7, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.fromOffset(14, 24),
	Size = UDim2.fromOffset(180, 10),
})
local zoneList = create("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(12, 40),
	Size = UDim2.new(1, -24, 1, -48),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = PALETTE.accent,
}, travelCard)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, zoneList)

-- quest tracker --------------------------------------------------------------
local questCard = create("Frame", {
	Name = "QuestTracker",
	BackgroundColor3 = PALETTE.panel,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(300, 150),
	Position = UDim2.new(1, -316, 1, -170),
}, screen)
corner(questCard, 12)
stroke(questCard, PALETTE.pink, 1, 0.4)
text(questCard, "QUEST TRACKER", 9, PALETTE.pink, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.fromOffset(160, 12),
})
local questCount = text(questCard, "", 8, PALETTE.gold, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(180, 10),
	Size = UDim2.fromOffset(104, 12),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local questRows = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 28),
	Size = UDim2.new(1, -24, 1, -36),
}, questCard)
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, questRows)

-- combo card -----------------------------------------------------------------
local comboCard = create("Frame", {
	Name = "ComboCard",
	BackgroundColor3 = PALETTE.panel,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(210, 34),
	Position = UDim2.new(0.5, 0, 1, -72),
	AnchorPoint = Vector2.new(0.5, 1),
	Visible = false,
}, screen)
corner(comboCard, 9)
stroke(comboCard, PALETTE.gold, 1.2, 0.2)
local comboLabel = text(comboCard, "COMBO x1.00", 11, PALETTE.gold, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(9, 5),
	Size = UDim2.new(1, -18, 0, 15),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local comboBarHolder = create("Frame", {		BackgroundColor3 = PALETTE.sunken,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -18, 0, 3),
	Position = UDim2.fromOffset(9, 24),
}, comboCard)
corner(comboBarHolder, 2)
local comboFill = create("Frame", {
	BackgroundColor3 = PALETTE.gold,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
}, comboBarHolder)
corner(comboFill, 2)
local comboScale = create("UIScale", { Scale = 1 }, comboCard)

-- toasts ---------------------------------------------------------------------
local toastHolder = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(320, 260),
	Position = UDim2.new(1, -336, 0, 104),
}, screen)
create("UIListLayout", {
	Padding = UDim.new(0, 5),
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
}, toastHolder)

local function toast(message, kind)
	local color = PALETTE.text
	if kind == "error" then
		color = PALETTE.bad
	elseif kind == "gacha" or kind == "mutation" or kind == "enchant" or kind == "trade" then
		color = PALETTE.pink
	elseif kind == "research" or kind == "weather" then
		color = PALETTE.accent
	elseif kind == "roll" then
		color = PALETTE.gold
	end
	local frame = create("Frame", {
		BackgroundColor3 = PALETTE.panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 34),
	}, toastHolder)
	corner(frame, 8)
	stroke(frame, color, 1, 0.3)
	create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(3, 20),
		Position = UDim2.fromOffset(6, 7),
	}, frame)
	local label = text(frame, message, 10, color, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(16, 4),
		Size = UDim2.new(1, -26, 1, -8),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTransparency = 1,
	})
	TweenService:Create(frame, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.02 }):Play()
	TweenService:Create(label, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
	task.delay(5, function()
		if frame and frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			task.delay(0.4, function()
				frame:Destroy()
			end)
		end
	end)
end

-- npc dialogue ---------------------------------------------------------------
local dialogueOpen = false
local dialoguePanel = create("CanvasGroup", {
	Name = "DialoguePanel",
	BackgroundColor3 = PALETTE.panel,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(460, 424),
	Position = UDim2.new(1, -24, 0.5, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	Visible = false,
	GroupTransparency = 1,
}, screen)
corner(dialoguePanel, 14)
local dialogueOutline = stroke(dialoguePanel, PALETTE.accent, 1.6, 0.1)
local dialogueScale = create("UIScale", { Scale = 0.94 }, dialoguePanel)

text(dialoguePanel, "TOWNSFOLK", 9, PALETTE.accent, Enum.Font.GothamBlack, {
	Name = "Role",
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -58, 0, 12),
})
text(dialoguePanel, "", 17, PALETTE.text, Enum.Font.GothamBlack, {
	Name = "Title",
	Position = UDim2.fromOffset(16, 26),
	Size = UDim2.new(1, -58, 0, 22),
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local dialogueCloseButton = create("TextButton", {
	Name = "DialogueClose",
	BackgroundColor3 = PALETTE.sunken,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Text = "",
	Size = UDim2.fromOffset(26, 26),
	Position = UDim2.new(1, -14, 0, 12),
	AnchorPoint = Vector2.new(1, 0),
}, dialoguePanel)
corner(dialogueCloseButton, 7)
closeIcon(dialogueCloseButton, PALETTE.bad, 10, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

local dialogueScroll = create("ScrollingFrame", {
	Name = "DialogueScroll",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(12, 56),
	Size = UDim2.new(1, -24, 1, -68),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = PALETTE.accent,
}, dialoguePanel)
create("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, dialogueScroll)

local dialogueTones = {
	accent = PALETTE.accent,
	gold = PALETTE.gold,
	good = PALETTE.good,
	pink = PALETTE.pink,
	muted = PALETTE.dim,
	bad = PALETTE.bad,
}

local function closeDialogue()
	if not dialogueOpen then
		return
	end
	dialogueOpen = false
	TweenService:Create(dialogueScale, TweenInfo.new(0.16), { Scale = 0.94 }):Play()
	TweenService:Create(dialoguePanel, TweenInfo.new(0.16), { GroupTransparency = 1 }):Play()
	task.delay(0.2, function()
		if not dialogueOpen then
			dialoguePanel.Visible = false
		end
	end)
end

local function clearDialogue()
	for _, child in ipairs(dialogueScroll:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function dialogueChoice(label, tone, onClick)
	local color = dialogueTones[tone] or PALETTE.accent
	local btn = button(dialogueScroll, label, color, onClick, 32)
	btn.TextSize = 11
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.Size = UDim2.new(1, 0, 0, 32)
	create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(3, 16),
		Position = UDim2.fromOffset(0, 8),
	}, btn)
	return btn
end

local function showDialogue(payload)
	if not payload then
		return
	end
	clearDialogue()
	local role = dialoguePanel:FindFirstChild("Role")
	local title = dialoguePanel:FindFirstChild("Title")
	if role and role:IsA("TextLabel") then
		role.Text = payload.role or "TOWNSFOLK"
		role.TextColor3 = payload.accent or PALETTE.accent
	end
	if title and title:IsA("TextLabel") then
		title.Text = payload.name or ""
	end
	dialogueOutline.Color = payload.accent or PALETTE.accent

	text(dialogueScroll, payload.body or "", 13, PALETTE.text, Enum.Font.GothamMedium, {
		Size = UDim2.new(1, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local quest = payload.quest
	if quest then
		local card = create("Frame", {
			BackgroundColor3 = PALETTE.panel,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 70),
		}, dialogueScroll)
		corner(card, 9)
		stroke(card, quest.state == "ready" and PALETTE.good or PALETTE.pink, 1, 0.3)
		text(card, quest.name, 11, quest.state == "ready" and PALETTE.good or PALETTE.pink, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(card, quest.desc, 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(10, 24),
			Size = UDim2.new(1, -20, 0, 12),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local statusText = "SIDE QUEST  ·  not started"
		if quest.state == "active" then
			statusText = "IN PROGRESS  " .. quest.progress .. " / " .. quest.goal
		elseif quest.state == "ready" then
			statusText = "READY  +" .. quest.coins .. "c, +" .. quest.gems .. "g"
		elseif quest.state == "claimed" then
			statusText = "COMPLETED"
		end
		text(card, statusText, 9, quest.state == "ready" and PALETTE.good or PALETTE.gold, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(10, 40),
			Size = UDim2.new(1, -20, 0, 12),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local holder = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 58),
			Size = UDim2.new(1, -20, 0, 5),
		}, card)
		bar(holder, quest.goal > 0 and math.clamp(quest.progress / quest.goal, 0, 1) or 0, quest.state == "ready" and PALETTE.good or PALETTE.pink, 5)
	end

	for _, choice in ipairs(payload.choices or {}) do
		dialogueChoice(choice.label, choice.tone, function()
			if choice.action == "close" then
				closeDialogue()
				return
			end
			send("NpcTalk", { npcId = payload.npcId, choice = choice.action, arg = choice.arg })
		end)
	end

	dialoguePanel.Visible = true
	if dialogueOpen then
		TweenService:Create(dialoguePanel, TweenInfo.new(0.16), { GroupTransparency = 0 }):Play()
		return
	end
	dialogueOpen = true
	dialogueScale.Scale = 0.94
	TweenService:Create(dialogueScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(dialoguePanel, TweenInfo.new(0.16), { GroupTransparency = 0 }):Play()
end

dialogueCloseButton.MouseButton1Click:Connect(closeDialogue)
DialogueRemote.OnClientEvent:Connect(showDialogue)

-- menu -----------------------------------------------------------------------
local panel = create("CanvasGroup", {
	Name = "MenuPanel",
	BackgroundColor3 = PALETTE.panel,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(1000, 520),
	Position = UDim2.new(0.5, 0, 0.5, 8),
	AnchorPoint = Vector2.new(0.5, 0.5),
	ClipsDescendants = true,
	Visible = false,
}, screen)
corner(panel, 16)
stroke(panel, PALETTE.line, 1.4, 0.12)
local panelScale = create("UIScale", { Scale = 1 }, panel)

local sidebar = create("Frame", {
	BackgroundColor3 = PALETTE.panel,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(192, 520),
}, panel)
corner(sidebar, 16)
stroke(sidebar, PALETTE.line, 1, 0.5)

text(sidebar, "CONTROL ROOM", 9, PALETTE.accent, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(16, 14),
	Size = UDim2.fromOffset(140, 12),
})
local sidebarLevel = text(sidebar, "LV 1", 9, PALETTE.gold, Enum.Font.GothamBold, {
	Position = UDim2.new(1, -60, 0, 14),
	Size = UDim2.fromOffset(44, 12),
	TextXAlignment = Enum.TextXAlignment.Right,
})

local tabOrder = {
	{ id = "Summon", color = PALETTE.accent },
	{ id = "Crew", color = PALETTE.good },
	{ id = "Pets", color = Color3.fromRGB(255, 188, 132) },
	{ id = "Research", color = Color3.fromRGB(158, 150, 240) },
	{ id = "Rebirth", color = Color3.fromRGB(255, 150, 186) },
	{ id = "Shop", color = PALETTE.gold },
	{ id = "Quests", color = PALETTE.pink },
	{ id = "Index", color = Color3.fromRGB(240, 188, 132) },
	{ id = "Weather", color = Color3.fromRGB(140, 210, 240) },
	{ id = "Trade", color = Color3.fromRGB(154, 228, 198) },
	{ id = "Guide", color = PALETTE.dim },
}

local tabButtons = {}
for index, tab in ipairs(tabOrder) do
	local btn = create("TextButton", {
		Name = "Tab_" .. tab.id,
		BackgroundColor3 = PALETTE.panelLight,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		Size = UDim2.fromOffset(160, 34),
		Position = UDim2.fromOffset(16, 34 + (index - 1) * 37),
		ClipsDescendants = true,
	}, sidebar)
	corner(btn, 8)
	local btnStroke = stroke(btn, PALETTE.text, 1, 0.85)
	local rail = create("Frame", {
		BackgroundColor3 = tab.color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(3, 14),
		Position = UDim2.fromOffset(0, 10),
	}, btn)
	local label = text(btn, tab.id:upper(), 11, PALETTE.text, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -26, 1, 0),
	})
	local badge = create("Frame", {
		BackgroundColor3 = PALETTE.pink,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(1, -24, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Visible = false,
	}, btn)
	corner(badge, 8)
	local badgeText = text(badge, "", 8, PALETTE.bg, Enum.Font.GothamBlack, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	tabButtons[tab.id] = { button = btn, label = label, color = tab.color, stroke = btnStroke, badge = badge, badgeText = badgeText, rail = rail }
	btn.MouseButton1Click:Connect(function()
		activeTab = tab.id
		render()
	end)
end

local tabArrow = create("Frame", {
	Name = "TabArrow",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(18, 18),
	Position = UDim2.fromOffset(176, 42),
	Visible = false,
}, sidebar)
local tabArrowIcon = chevronIcon(tabArrow, PALETTE.accent, 14, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
TweenService:Create(tabArrowIcon, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = UDim2.new(0.5, 4, 0.5, 0),
}):Play()

local closeSidebar = create("TextButton", {
	BackgroundColor3 = PALETTE.sunken,
	BorderSizePixel = 0,
	Text = "CLOSE  [ESC]",
	TextColor3 = PALETTE.bad,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	Size = UDim2.fromOffset(160, 30),
	Position = UDim2.fromOffset(16, 474),
}, sidebar)
corner(closeSidebar, 8)
closeIcon(closeSidebar, PALETTE.bad, 10, UDim2.new(1, -12, 0.5, 0), Vector2.new(1, 0.5))
closeSidebar.MouseButton1Click:Connect(function()
	setMenu(false)
end)

local contentArea = create("CanvasGroup", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(208, 14),
	Size = UDim2.fromOffset(778, 492),
}, panel)

local contentTitle = text(contentArea, "SUMMON", 15, PALETTE.accent, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(2, 2),
	Size = UDim2.fromOffset(520, 20),
})
local contentSub = text(contentArea, "", 9, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.fromOffset(2, 22),
	Size = UDim2.fromOffset(560, 12),
})

local closeButton = create("TextButton", {
	Name = "CloseButton",
	BackgroundColor3 = PALETTE.sunken,
	BorderSizePixel = 0,
	Text = "",
	Size = UDim2.fromOffset(32, 32),
	Position = UDim2.new(1, -8, 0, 2),
	AnchorPoint = Vector2.new(1, 0),
}, contentArea)
corner(closeButton, 8)
closeIcon(closeButton, PALETTE.bad, 14, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
closeButton.MouseButton1Click:Connect(function()
	setMenu(false)
end)

-- collapse arrow: clipped to the panel's top-right, it folds the control room
-- down to a slim bar and flips to point the other way when it is folded
local MENU_WIDTH, MENU_HEIGHT = 1000, 520
local menuCollapsed = false
local collapseLabel = text(panel, "CONTROL ROOM  ·  PANEL COLLAPSED", 10, PALETTE.accent, Enum.Font.GothamBlack, {
	Name = "CollapsedLabel",
	Position = UDim2.fromOffset(18, 0),
	Size = UDim2.new(1, -70, 0, 52),
	Visible = false,
})
local collapseButton = create("TextButton", {
	Name = "CollapseButton",
	BackgroundColor3 = PALETTE.panelLight,
	BorderSizePixel = 0,
	Text = "",
	Size = UDim2.fromOffset(32, 32),
	Position = UDim2.new(1, -76, 0, 8),
	AutoButtonColor = true,
}, panel)
corner(collapseButton, 8)
stroke(collapseButton, PALETTE.accent, 1, 0.35)
local collapseChevron = chevronIcon(collapseButton, PALETTE.accent, 14, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
collapseChevron.Rotation = -90

local function setMenuCollapsed(collapsed)
	if menuCollapsed == collapsed then
		return
	end
	menuCollapsed = collapsed
	if collapsed then
		sidebar.Visible = false
		contentArea.Visible = false
		collapseLabel.Visible = true
		collapseChevron.Rotation = 90
		TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(MENU_WIDTH, 52),
		}):Play()
	else
		sidebar.Visible = true
		contentArea.Visible = true
		collapseLabel.Visible = false
		collapseChevron.Rotation = -90
		TweenService:Create(panel, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(MENU_WIDTH, MENU_HEIGHT),
		}):Play()
	end
end
collapseButton.MouseButton1Click:Connect(function()
	setMenuCollapsed(not menuCollapsed)
end)

local contentScroll = create("ScrollingFrame", {
	Name = "ContentScroll",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 42),
	Size = UDim2.new(1, -6, 1, -46),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = PALETTE.accent,
}, contentArea)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, contentScroll)

-- tutorial card --------------------------------------------------------------
local tutorialCard = create("CanvasGroup", {
	Name = "TutorialCard",
	BackgroundColor3 = PALETTE.panel,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(356, 138),
	Position = UDim2.new(0, 16, 1, -14),
	AnchorPoint = Vector2.new(0, 1),
}, screen)
corner(tutorialCard, 12)
stroke(tutorialCard, PALETTE.accent, 1.4, 0.2)
local tutorialStep = text(tutorialCard, "GUIDED TOUR", 9, PALETTE.accent, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.fromOffset(200, 12),
})
local tutorialTitle = text(tutorialCard, "Welcome, miner", 14, PALETTE.text, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(14, 26),
	Size = UDim2.fromOffset(328, 18),
})
local tutorialText = text(tutorialCard, "A short tour shows you the loop. It takes a minute.", 10, PALETTE.dim, Enum.Font.GothamMedium, {
	Position = UDim2.fromOffset(14, 46),
	Size = UDim2.fromOffset(328, 34),
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
})
local tutorialNext = button(tutorialCard, "START TOUR", PALETTE.accent, function()
	if state and state.tutorial and state.tutorial.started then
		send("TutorialNext")
	else
		send("TutorialStart")
	end
end, 28)
tutorialNext.Size = UDim2.fromOffset(104, 28)
tutorialNext.Position = UDim2.fromOffset(14, 100)
local tutorialShow = button(tutorialCard, "SHOW ME", PALETTE.panelLight, function()
	if state and state.tutorial and state.tutorial.target and tabButtons[state.tutorial.target] then
		activeTab = state.tutorial.target
		setMenu(true)
		render()
	end
end, 28)
tutorialShow.Size = UDim2.fromOffset(96, 28)
tutorialShow.Position = UDim2.fromOffset(124, 100)
local tutorialSkip = button(tutorialCard, "LATER", PALETTE.panelLight, function()
	if state and state.tutorial and state.tutorial.started then
		send("TutorialSkip")
	else
		tourDismissed = true
		tutorialCard.Visible = false
	end
end, 28)
tutorialSkip.Size = UDim2.fromOffset(88, 28)
tutorialSkip.Position = UDim2.fromOffset(226, 100)
tutorialSkip.TextColor3 = PALETTE.dim

-- guide arrow ----------------------------------------------------------------
local guideArrow = create("Frame", {
	Name = "GuideArrow",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(46, 46),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Visible = false,
	ZIndex = 60,
}, screen)
chevronIcon(guideArrow, PALETTE.accent, 46, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), 6)
local guideArrowHint = text(screen, "", 10, PALETTE.accent, Enum.Font.GothamBold, {
	Size = UDim2.fromOffset(220, 14),
	AnchorPoint = Vector2.new(0.5, 0.5),
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	ZIndex = 60,
	TextStrokeTransparency = 0.3,
})

-- open button ----------------------------------------------------------------
local openButton = create("TextButton", {
	Name = "OpenMenuButton",
	BackgroundColor3 = PALETTE.panelLight,
	BorderSizePixel = 0,
	Text = "",
	Size = UDim2.fromOffset(196, 42),
	Position = UDim2.new(0.5, 0, 1, -16),
	AnchorPoint = Vector2.new(0.5, 1),
}, screen)
corner(openButton, 10)
stroke(openButton, PALETTE.accent, 1.2, 0.3)	gradient(openButton, PALETTE.panelLight, nil, 90)
hamburgerIcon(openButton, PALETTE.accent, 16, UDim2.fromOffset(16, 21))
text(openButton, "MENU  [M]", 12, PALETTE.text, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(38, 0),
	Size = UDim2.new(1, -66, 1, 0),
})
chevronIcon(openButton, PALETTE.accent, 14, UDim2.new(1, -14, 0.5, 0), Vector2.new(1, 0.5))
openButton.MouseButton1Click:Connect(function()
	setMenu(true)
end)

-- density controls: the rest of the HUD is opt-in through Settings or HUD
local hudToggle = create("TextButton", {
	Name = "HudToggle",
	BackgroundColor3 = PALETTE.panelLight,
	BorderSizePixel = 0,
	Text = "HUD OFF",
	TextColor3 = PALETTE.dim,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	Size = UDim2.fromOffset(96, 42),
	Position = UDim2.new(0.5, -160, 1, -16),
	AnchorPoint = Vector2.new(0.5, 1),
}, screen)
corner(hudToggle, 10)
stroke(hudToggle, PALETTE.line, 1, 0.3)
hudToggle.MouseButton1Click:Connect(function()
	setSetting("hudVisible", not settings.hudVisible)
end)

local settingsButton = create("TextButton", {
	Name = "SettingsButton",
	BackgroundColor3 = PALETTE.panelLight,
	BorderSizePixel = 0,
	Text = "SETTINGS",
	TextColor3 = PALETTE.accent,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	Size = UDim2.fromOffset(112, 42),
	Position = UDim2.new(0.5, 160, 1, -16),
	AnchorPoint = Vector2.new(0.5, 1),
}, screen)
corner(settingsButton, 10)
stroke(settingsButton, PALETTE.accent, 1, 0.35)
settingsButton.MouseButton1Click:Connect(function()
	if gameSettings.frame.Visible then
		gameSettings.close()
	else
		gameSettings.open()
	end
end)

-- zone entry banner ----------------------------------------------------------
local zoneBanner = create("CanvasGroup", {
	Name = "ZoneBanner",
	BackgroundColor3 = PALETTE.panel,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(430, 62),
	Position = UDim2.new(0.5, 0, 0, 132),
	AnchorPoint = Vector2.new(0.5, 0),
	Visible = false,
	ZIndex = 70,
}, screen)
corner(zoneBanner, 12)
local zoneBannerStroke = stroke(zoneBanner, PALETTE.accent, 1.4, 0.1)
local zoneBannerTitle = text(zoneBanner, "STARLIT QUARRY", 20, PALETTE.text, Enum.Font.GothamBlack, {
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.new(1, -32, 0, 24),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local zoneBannerSub = text(zoneBanner, "DEPTH 1 · 14 HP ORE", 9, PALETTE.accent, Enum.Font.GothamBold, {
	Position = UDim2.fromOffset(16, 34),
	Size = UDim2.new(1, -32, 0, 14),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local bannerScale = create("UIScale", { Scale = 0.9 }, zoneBanner)

local fadeOverlay = create("Frame", {
	Name = "TravelFade",
	BackgroundColor3 = PALETTE.bg,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 90,
}, screen)

-- developer panel ------------------------------------------------------------
local function sectionLabel(parent, y, content, color)
	text(parent, content, 9, color or PALETTE.dim, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, y),
		Size = UDim2.new(1, -36, 0, 12),
	})
end

local function devButton(parent, x, y, width, content, color, amount, kind)
	local btn = button(parent, content, color, function()
		send("AdminGrant", { kind = kind, amount = amount })
	end, 30)
	btn.Size = UDim2.fromOffset(width, 30)
	btn.Position = UDim2.fromOffset(x, y)
	return btn
end

local function buildAdminPanel()
	if adminPanel then
		return
	end
	adminPanel = create("CanvasGroup", {
		Name = "AdminPanel",
		BackgroundColor3 = PALETTE.panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(470, 470),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
	}, canvas)
	corner(adminPanel, 14)
	stroke(adminPanel, PALETTE.pink, 1.6, 0.12)

	text(adminPanel, "DEVELOPER PANEL", 16, PALETTE.pink, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.fromOffset(300, 20),
	})
	local tag = create("Frame", {
		BackgroundColor3 = PALETTE.sunken,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(86, 18),
		Position = UDim2.fromOffset(286, 16),
	}, adminPanel)
	corner(tag, 9)
	stroke(tag, PALETTE.pink, 1, 0.4)
	text(tag, "ADMIN ONLY", 7, PALETTE.pink, Enum.Font.GothamBold, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	adminRefs.coins = text(adminPanel, "0 coins", 10, PALETTE.gold, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(18, 42),
		Size = UDim2.fromOffset(150, 14),
	})
	adminRefs.gems = text(adminPanel, "0 gems", 10, PALETTE.gem, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(170, 42),
		Size = UDim2.fromOffset(150, 14),
	})
	adminRefs.level = text(adminPanel, "Miner Lv 1", 10, PALETTE.accent, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(320, 42),
		Size = UDim2.fromOffset(130, 14),
	})

	local adminClose = create("TextButton", {
		BackgroundColor3 = PALETTE.sunken,
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -12, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
	}, adminPanel)
	corner(adminClose, 7)
	closeIcon(adminClose, PALETTE.bad, 12, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	adminClose.MouseButton1Click:Connect(function()
		adminOpen = false
		adminPanel.Visible = false
	end)

	sectionLabel(adminPanel, 68, "CURRENCY")
	devButton(adminPanel, 18, 86, 104, "+10K COINS", PALETTE.gold, 10000, "coins")
	devButton(adminPanel, 130, 86, 104, "+100K COINS", PALETTE.gold, 100000, "coins")
	devButton(adminPanel, 242, 86, 96, "+50 GEMS", PALETTE.gem, 50, "gems")
	devButton(adminPanel, 346, 86, 106, "+500 GEMS", PALETTE.gem, 500, "gems")

	sectionLabel(adminPanel, 126, "MINER LEVEL (ORE BROKEN)")
	devButton(adminPanel, 18, 144, 140, "+1,000 ORE", PALETTE.accent, 1000, "xp")
	devButton(adminPanel, 166, 144, 140, "+10,000 ORE", PALETTE.accent, 10000, "xp")
	devButton(adminPanel, 314, 144, 138, "+100,000 ORE", PALETTE.accent, 100000, "xp")

	sectionLabel(adminPanel, 184, "ZONE ACCESS")
	text(adminPanel, "Travel is gated on Miner Lv and research. Use the ore buttons to jump levels, then click a portal in town.", 9, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 200),
		Size = UDim2.fromOffset(434, 26),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	sectionLabel(adminPanel, 236, "DANGER ZONE")
	text(adminPanel, "Wipes coins, gems, heroes, pets, research, pickaxe and miner level, then rewrites the save.", 9, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 252),
		Size = UDim2.fromOffset(434, 24),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local resetBtn = button(adminPanel, "RESET PROGRESS", PALETTE.bad, nil, 34)
	resetBtn.Size = UDim2.fromOffset(200, 34)
	resetBtn.Position = UDim2.fromOffset(18, 282)

	local confirmRow = create("Frame", {
		Name = "ResetConfirm",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(434, 34),
		Position = UDim2.fromOffset(18, 324),
		Visible = false,
	}, adminPanel)
	local wipeBtn = button(confirmRow, "YES, WIPE EVERYTHING", PALETTE.bad, function()
		send("AdminReset")
		confirmRow.Visible = false
		adminRefs.resetStatus.Text = "Wipe sent — the server is rewriting your save."
		adminRefs.resetStatus.TextColor3 = PALETTE.gold
	end, 34)
	wipeBtn.Size = UDim2.fromOffset(232, 34)
	wipeBtn.Position = UDim2.fromOffset(0, 0)
	local cancelBtn = button(confirmRow, "CANCEL", PALETTE.panelLight, function()
		confirmRow.Visible = false
		adminRefs.resetStatus.Text = "Nothing was changed."
		adminRefs.resetStatus.TextColor3 = PALETTE.dim
	end, 34)
	cancelBtn.Size = UDim2.fromOffset(190, 34)
	cancelBtn.Position = UDim2.fromOffset(244, 0)

	resetBtn.MouseButton1Click:Connect(function()
		confirmRow.Visible = true
		adminRefs.resetStatus.Text = "This cannot be undone. Confirm to wipe."
		adminRefs.resetStatus.TextColor3 = PALETTE.bad
	end)

	adminRefs.resetStatus = text(adminPanel, "", 9, PALETTE.dim, Enum.Font.GothamBold, {
		Name = "ResetStatus",
		Position = UDim2.fromOffset(18, 364),
		Size = UDim2.fromOffset(434, 14),
	})

	local note = text(adminPanel, "Server re-checks admin rights on every developer action.", 8, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 398),
		Size = UDim2.fromOffset(434, 12),
	})
	text(adminPanel, "DEV BUILD", 8, PALETTE.pink, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(18, 436),
		Size = UDim2.fromOffset(120, 12),
	})
end

adminButton.MouseButton1Click:Connect(function()
	if not state or not state.admin then
		return
	end
	buildAdminPanel()
	adminOpen = not adminOpen
	adminPanel.Visible = adminOpen
	if adminOpen then
		adminRefs.coins.Text = tostring(state.coins) .. " coins"
		adminRefs.gems.Text = tostring(state.gems) .. " gems"
		adminRefs.level.Text = "Miner Lv " .. tostring(state.level or 1)
	end
end)

-- hud density ----------------------------------------------------------------
-- On launch the mine is the whole screen: only Menu, HUD and Settings are up.
-- The profile, currency, travel and quest chrome is opt-in, and the choice is
-- saved with the profile.
local hudWidgets = { topBar, weatherChip, boostHolder, profileCard, travelCard, questCard }
applyHud = function()
	local show = settings.hudVisible and not menuOpen
	for _, widget in ipairs(hudWidgets) do
		widget.Visible = show
	end
	hudToggle.Text = settings.hudVisible and "HUD ON" or "HUD OFF"
	hudToggle.TextColor3 = settings.hudVisible and PALETTE.good or PALETTE.dim
	hudToggle.Visible = not menuOpen
	settingsButton.Visible = not menuOpen
end
applyHud()

-- menu helpers ---------------------------------------------------------------
setMenu = function(open)
	if menuOpen == open and panel.Visible == open then
		return
	end
	menuOpen = open
	profileCard.Visible = settings.hudVisible and not open
	travelCard.Visible = settings.hudVisible and not open
	questCard.Visible = settings.hudVisible and not open
	openButton.Visible = not open
	applyHud()
	if open then
		panel.Visible = true
		panel.GroupTransparency = 0.7
		panelScale.Scale = 0.94
		TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			GroupTransparency = 0,
		}):Play()
		TweenService:Create(panelScale, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	else
		if not panel.Visible then
			return
		end
		local tween = TweenService:Create(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			if not menuOpen then
				panel.Visible = false
			end
		end)
	end
	if render and state then
		render(open)
	end
end

local function clearScroll()
	for _, child in ipairs(contentScroll:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function row(height)
	local frame = create("Frame", {
		BackgroundColor3 = PALETTE.panelLight,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
	}, contentScroll)
	corner(frame, 9)
	-- a crisp edge instead of a value jump keeps cards legible now that every
	-- surface sits in the same light band
	stroke(frame, PALETTE.line, 1, 0.22)
	return frame
end

local function unitById(id)
	if not state then
		return nil
	end
	for _, unit in ipairs(state.units) do
		if unit.id == id then
			return unit
		end
	end
	return nil
end

local function heroById(id)
	for _, hero in ipairs(Config.Heroes) do
		if hero.id == id then
			return hero
		end
	end
	return nil
end

local function zoneColor(zoneId)
	local zone = Config.ZoneById(zoneId)
	return zone and zone.blockColor or PALETTE.accent
end

-- tabs -----------------------------------------------------------------------
local function renderSummon()
	local featured = Config.Heroes[(math.floor(os.time() / 600) % #Config.Heroes) + 1]
	local banner = row(128)
	gradient(banner, featured.color:Lerp(PALETTE.panel, 0.55), nil, 20)
	stroke(banner, featured.color, 1.2, 0.2)
	portrait(banner, 96, UDim2.fromOffset(16, 16), featured.color, Config.RarityColor(featured.rarity))
	text(banner, "FEATURED HERO", 8, featured.color, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(126, 16),
		Size = UDim2.fromOffset(300, 12),
	})
	text(banner, featured.name, 18, PALETTE.text, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(126, 28),
		Size = UDim2.fromOffset(420, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	text(banner, '"' .. featured.quote .. '"', 10, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(126, 54),
		Size = UDim2.fromOffset(420, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	chip(banner, 126, 76, 92, featured.rarity:upper(), Config.RarityColor(featured.rarity), 18)
	chip(banner, 226, 76, 104, featured.power .. " BASE POWER", PALETTE.gold, 18)
	chip(banner, 338, 76, 104, featured.speed .. "x SPEED", PALETTE.good, 18)

	local odds = row(76)
	text(odds, "SUMMON ODDS", 9, PALETTE.accent, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(200, 12),
	})
	local totalWeight = 0
	for _, rarity in ipairs(Config.Rarities) do
		totalWeight += rarity.weight
	end
	local te = text(odds, "", 9, PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 0, 12),
	})
	local parts = {}
	for _, rarity in ipairs(Config.Rarities) do
		parts[#parts + 1] = rarity.id .. " " .. math.floor(rarity.weight / totalWeight * 100 + 0.5) .. "%"
	end
	te.Text = table.concat(parts, "   ·   ")
	local barHolder = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 26),
		Size = UDim2.new(1, -24, 0, 10),
	}, odds)
	for _, rarity in ipairs(Config.Rarities) do
		create("Frame", {
			BackgroundColor3 = rarity.color,
			BorderSizePixel = 0,
			Size = UDim2.new(rarity.weight / totalWeight, -2, 1, 0),
			Position = UDim2.new((function()
				local before = 0
				for _, other in ipairs(Config.Rarities) do
					if other.id == rarity.id then
						break
					end
					before += other.weight
				end
				return before / totalWeight
			end)(), 0, 0, 0),
		}, barHolder)
	end

	local single = row(78)
	portrait(single, 52, UDim2.fromOffset(12, 13), PALETTE.accent, PALETTE.accent)
	text(single, "Single Summon", 14, PALETTE.text, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(76, 14),
		Size = UDim2.fromOffset(240, 18),
	})
	text(single, Config.RollCost.single .. " coins  ·  one hero, instant", 10, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(76, 34),
		Size = UDim2.fromOffset(300, 14),
	})
	text(single, "Storage " .. state.storedUnits .. " / " .. Config.MaxUnits, 9, state.storedUnits >= Config.MaxUnits and PALETTE.bad or PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(76, 52),
		Size = UDim2.fromOffset(220, 12),
	})
	local canAfford = state.coins >= Config.RollCost.single
	local summonBtn = button(single, canAfford and "SUMMON" or "NEED COINS", canAfford and PALETTE.accent or PALETTE.panelLight, function()
		send("Roll", { count = 1 })
	end, 34)
	summonBtn.Size = UDim2.fromOffset(140, 34)
	summonBtn.Position = UDim2.new(1, -152, 0, 22)

	local multi = row(78)
	portrait(multi, 52, UDim2.fromOffset(12, 13), PALETTE.pink, PALETTE.pink)
	text(multi, "Tenfold Summon", 14, PALETTE.text, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(76, 14),
		Size = UDim2.fromOffset(240, 18),
	})
	text(multi, Config.RollCost.multi .. " coins  ·  ten heroes, best pull shown", 10, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(76, 34),
		Size = UDim2.fromOffset(320, 14),
	})
	text(multi, "Luck x" .. string.format("%.2f", state.gachaLuck or 1) .. "  ·  " .. tostring(state.stats.rolls) .. " summons", 9, PALETTE.pink, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(76, 52),
		Size = UDim2.fromOffset(240, 12),
	})
	local canAffordMulti = state.coins >= Config.RollCost.multi
	local multiBtn = button(multi, canAffordMulti and "SUMMON x10" or "NEED COINS", canAffordMulti and PALETTE.pink or PALETTE.panelLight, function()
		send("Roll", { count = 10 })
	end, 34)
	multiBtn.Size = UDim2.fromOffset(140, 34)
	multiBtn.Position = UDim2.new(1, -152, 0, 22)

	local stats = row(62)
	text(stats, "Best pull: " .. tostring(state.stats.bestRarity) .. "   ·   coins earned: " .. tostring(state.stats.coinsEarned), 10, PALETTE.good, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 14),
	})
	text(stats, "Chests opened: " .. tostring(state.stats.chestsOpened) .. "   ·   crew slots: " .. state.equipped .. "/" .. state.crewSlots, 10, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(1, -24, 0, 14),
	})
end

local function renderCrew()
	local summary = row(36)
	text(summary, "Crew " .. state.equipped .. "/" .. state.crewSlots .. "   ·   " .. string.format("%.0f", state.dps) .. " DPS   ·   Storage " .. state.storedUnits .. "/" .. Config.MaxUnits, 10, PALETTE.accent, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 14),
	})

	if #state.units == 0 then
		local empty = row(58)
		text(empty, "No heroes yet. Open Summon to recruit your first crew.", 11, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(12, 20),
			Size = UDim2.new(1, -24, 16),
		})
		return
	end

	local sorted = table.clone(state.units)
	table.sort(sorted, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		return a.dps > b.dps
	end)

	-- paged so a big collection never builds hundreds of cards at once
	local perPage = 20
	local pageCount = math.max(1, math.ceil(#sorted / perPage))
	if crewPage > pageCount then
		crewPage = pageCount
	end
	if pageCount > 1 then
		local pager = row(34)
		text(pager, "PAGE " .. crewPage .. " / " .. pageCount .. "   ·   " .. #sorted .. " heroes", 9, PALETTE.dim, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(12, 11),
			Size = UDim2.fromOffset(240, 14),
		})
		local prev = button(pager, "PREV", crewPage > 1 and PALETTE.panelLight or PALETTE.bg, function()
			crewPage = math.max(1, crewPage - 1)
			render(true)
		end, 24)
		prev.Size = UDim2.fromOffset(70, 24)
		prev.Position = UDim2.new(1, -164, 0, 5)
		local nxt = button(pager, "NEXT", crewPage < pageCount and PALETTE.panelLight or PALETTE.bg, function()
			crewPage = math.min(pageCount, crewPage + 1)
			render(true)
		end, 24)
		nxt.Size = UDim2.fromOffset(70, 24)
		nxt.Position = UDim2.new(1, -86, 0, 5)
	end
	local firstIndex = (crewPage - 1) * perPage + 1
	for index = firstIndex, math.min(#sorted, firstIndex + perPage - 1) do
		local unit = sorted[index]
		local card = row(106)
		stroke(card, unit.color, 1, 0.35)
		portrait(card, 64, UDim2.fromOffset(12, 12), unit.color, Config.RarityColor(unit.rarity), unit.level)

		text(card, unit.heroName, 13, unit.color, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(88, 10),
			Size = UDim2.new(1, -330, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(card, unit.rarity .. "  ·  " .. (unit.trait and unit.trait.name or "Untempered") .. "  ·  " .. string.format("%.0f", unit.dps) .. " DPS  ·  " .. string.format("%.1f", unit.power) .. " power  ·  " .. string.format("%.2f", unit.speed) .. "x swing", 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(88, 30),
			Size = UDim2.new(1, -330, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		chip(card, 88, 50, 116, unit.mutation.name .. " x" .. unit.mutation.mult, unit.mutation.color, 18)
		chip(card, 212, 50, 108, unit.enchant.name .. " x" .. unit.enchant.power, unit.enchant.color, 18)
		if unit.trait then
			chip(card, 326, 50, 120, unit.trait.name, unit.trait.color, 18)
		end
		text(card, '"' .. unit.quote .. '"', 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(88, 76),
			Size = UDim2.new(1, -330, 0, 12),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})

		local equipBtn = button(card, unit.equipped and "BENCH" or "DEPLOY", unit.equipped and PALETTE.bad or PALETTE.good, function()
			send("Equip", { unitId = unit.id })
		end, 26)
		equipBtn.Size = UDim2.fromOffset(96, 26)
		equipBtn.Position = UDim2.new(1, -108, 0, 10)

		local levelBtn = button(card, "LEVEL  " .. unit.levelCost, state.coins >= unit.levelCost and PALETTE.accent or PALETTE.panelLight, function()
			send("LevelUp", { unitId = unit.id })
		end, 26)
		levelBtn.Size = UDim2.fromOffset(96, 26)
		levelBtn.Position = UDim2.new(1, -108, 0, 42)

		local pickBtn = button(card, selectedUnitId == unit.id and "PICKED" or "SELECT", selectedUnitId == unit.id and PALETTE.pink or PALETTE.panelLight, function()
			selectedUnitId = unit.id
			render(true)
		end, 26)
		pickBtn.Size = UDim2.fromOffset(96, 26)
		pickBtn.Position = UDim2.new(1, -108, 0, 74)

		local mutBtn = button(card, "MUTATE  " .. Config.MutationCost .. "g", PALETTE.pink, function()
			send("Mutate", { unitId = unit.id })
		end, 22)
		mutBtn.Size = UDim2.fromOffset(116, 22)
		mutBtn.Position = UDim2.fromOffset(88, 76)

		local enchBtn = button(card, "ENCHANT  " .. Config.EnchantCost .. "g", PALETTE.gold, function()
			send("Enchant", { unitId = unit.id })
		end, 22)
		enchBtn.Size = UDim2.fromOffset(120, 22)
		enchBtn.Position = UDim2.fromOffset(212, 76)
	end
end

local function petIcon(parent, size, position, pet)
	local box = create("Frame", {
		BackgroundColor3 = PALETTE.sunken,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Position = position,
	}, parent)
	corner(box, math.floor(size * 0.28))
	stroke(box, pet.color, 1.4, 0.2)
	local tail = create("Frame", {
		BackgroundColor3 = pet.color:Lerp(Color3.fromRGB(255, 255, 255), 0.25),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.16, 0.26),
		Position = UDim2.fromScale(0.74, 0.46),
		Rotation = -24,
	}, box)
	corner(tail, 4)
	local body = create("Frame", {
		BackgroundColor3 = pet.color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.54, 0.42),
		Position = UDim2.fromScale(0.46, 0.66),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, box)
	corner(body, math.floor(size * 0.22))
	local head = create("Frame", {
		BackgroundColor3 = pet.color:Lerp(Color3.fromRGB(255, 255, 255), 0.16),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.42, 0.36),
		Position = UDim2.fromScale(0.44, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, box)
	corner(head, math.floor(size * 0.18))
	for side = -1, 1, 2 do
		local ear = create("Frame", {
			BackgroundColor3 = pet.color,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0.11, 0.16),
			Position = UDim2.fromScale(0.44 + side * 0.13, 0.18),
			Rotation = side * 16,
		}, box)
		corner(ear, 3)
		local eye = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(38, 44, 62),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0.055, 0.075),
			Position = UDim2.fromScale(0.44 + side * 0.09, 0.35),
		}, box)
		corner(eye, 3)
	end
	return box
end

local function renderPets()
	local pets = state.pets
	if not pets then
		return
	end
	local header = row(66)
	stroke(header, PALETTE.gold, 1, 0.4)
	text(header, "COMPANIONS", 12, PALETTE.gold, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.fromOffset(220, 16),
	})
	text(header, string.format("%d owned  ·  %d slots  ·  +%d%% coins  ·  +%d%% gems", pets.total, pets.slots, math.floor(pets.coin * 100 + 0.5), math.floor(pets.gem * 100 + 0.5)), 9, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.fromOffset(440, 14),
	})
	text(header, "duplicates bond: +5% bonus per level, cap Lv " .. pets.maxLevel, 8, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(12, 45),
		Size = UDim2.fromOffset(440, 12),
	})
	local hatch = button(header, "HATCH  " .. pets.cost .. "g", state.gems >= pets.cost and PALETTE.pink or PALETTE.panelLight, function()
		send("HatchPet")
	end, 30)
	hatch.Size = UDim2.fromOffset(148, 30)
	hatch.Position = UDim2.new(1, -160, 0.5, 0)
	hatch.AnchorPoint = Vector2.new(0, 0.5)

	if pets.total == 0 then
		local empty = row(110)
		petIcon(empty, 62, UDim2.fromOffset(18, 22), { color = PALETTE.panelLight })
		text(empty, "NO COMPANIONS YET", 14, PALETTE.text, Enum.Font.GothamBlack, {
			Position = UDim2.fromOffset(96, 26),
			Size = UDim2.fromOffset(320, 18),
		})
		text(empty, "Hatch an egg for " .. pets.cost .. " gems. Pets follow you and add small, capped yield bonuses.", 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(96, 48),
			Size = UDim2.new(1, -120, 0, 14),
		})
		return
	end

	for _, pet in ipairs(pets.list) do
		local card = row(80)
		stroke(card, pet.color, 1, pet.equipped and 0.15 or 0.5)
		petIcon(card, 56, UDim2.fromOffset(12, 12), pet)
		text(card, pet.name, 13, PALETTE.text, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(82, 12),
			Size = UDim2.new(1, -240, 0, 16),
		})
		text(card, pet.rarity .. "  ·  Lv " .. pet.level .. string.format("  ·  +%d%% coins  ·  +%d%% gems", math.floor(pet.coin * 100 + 0.5), math.floor(pet.gem * 100 + 0.5)), 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(82, 30),
			Size = UDim2.new(1, -240, 0, 14),
		})
		chip(card, 82, 48, 92, pet.equipped and "FOLLOWING" or "BENCHED", pet.equipped and PALETTE.good or PALETTE.dim, 18)
		local toggle = button(card, pet.equipped and "BENCH" or "EQUIP", pet.equipped and PALETTE.bad or PALETTE.good, function()
			send("EquipPet", { petId = pet.id })
		end, 28)
		toggle.Size = UDim2.fromOffset(96, 28)
		toggle.Position = UDim2.new(1, -108, 0.5, 0)
		toggle.AnchorPoint = Vector2.new(0, 0.5)
	end
end

local function renderResearch()
	local bonuses = row(34)
	text(bonuses, state.zonesUnlocked .. " / " .. #Config.Zones .. " biomes reachable   ·   " .. state.level .. " miner level", 10, PALETTE.accent, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.new(1, -24, 0, 14),
	})
	for _, node in ipairs(state.research) do
		local card = row(72)
		local headerColor = node.bought and PALETTE.good or (node.canBuy and PALETTE.accent or PALETTE.dim)
		local badge = create("Frame", {
			BackgroundColor3 = node.bought and PALETTE.panelLight or PALETTE.sunken,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(12, 12),
		}, card)
		corner(badge, 8)
		stroke(badge, headerColor, 1, 0.3)
		if node.bought then
			checkIcon(badge, PALETTE.good, 14, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		else
			lockIcon(badge, node.canBuy and PALETTE.accent or PALETTE.dim, 14, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		end

		text(card, node.name, 12, headerColor, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(50, 10),
			Size = UDim2.new(1, -172, 0, 16),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(card, node.desc, 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(50, 28),
			Size = UDim2.new(1, -172, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(card, node.bought and "RESEARCHED" or node.requiresText, 8, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(50, 46),
			Size = UDim2.new(1, -172, 0, 12),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local costColor = state.coins >= node.cost and PALETTE.gold or PALETTE.bad
		text(card, node.bought and "—" or (node.cost .. " coins"), 9, costColor, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(50, 58),
			Size = UDim2.fromOffset(220, 12),
		})

		local buyBtn = button(card, node.bought and "DONE" or (node.canBuy and "BUY" or "LOCKED"), node.bought and PALETTE.good or (node.canBuy and PALETTE.accent or PALETTE.panelLight), function()
			if not node.bought then
				send("Research", { nodeId = node.id })
			end
		end, 28)
		buyBtn.Size = UDim2.fromOffset(104, 28)
		buyBtn.Position = UDim2.new(1, -116, 0, 22)
	end
end

local function renderRebirth()
	local info = state.rebirth
	if not info then
		local missing = row(64)
		text(missing, "Rebirth data is unavailable right now.", 10, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(16, 24),
			Size = UDim2.new(1, -32, 0, 16),
		})
		return
	end

	local head = row(126)
	gradient(head, PALETTE.pink:Lerp(PALETTE.panel, 0.6), nil, 20)
	stroke(head, PALETTE.pink, 1.4, 0.16)
	text(head, "REBIRTH " .. info.count, 20, PALETTE.pink, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.fromOffset(320, 26),
	})
	text(head, "Restart the run. The multiplier never resets.", 10, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 38),
		Size = UDim2.new(1, -36, 0, 14),
	})
	chip(head, 18, 60, 160, string.format("COINS  x%.2f", info.coinMult), PALETTE.gold, 22)
	chip(head, 188, 60, 160, string.format("POWER  x%.2f", info.powerMult), PALETTE.accent, 22)
	text(head, string.format("Next rebirth:  coins x%.2f  ·  power x%.2f", info.nextCoinMult, info.nextPowerMult), 9, PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(18, 94),
		Size = UDim2.new(1, -36, 0, 14),
	})

	local requirement = row(100)
	text(requirement, "REQUIREMENT", 9, PALETTE.dim, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.new(1, -36, 0, 12),
	})
	text(requirement, string.format("Miner Lv %d  /  %d", info.level, info.levelReq), 15, info.canRebirth and PALETTE.good or PALETTE.text, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(18, 26),
		Size = UDim2.new(1, -36, 0, 20),
	})
	local track = bar(requirement, info.ratio, info.canRebirth and PALETTE.good or PALETTE.accent, 6)
	track.Position = UDim2.fromOffset(18, 52)
	track.Size = UDim2.new(1, -36, 0, 6)
	text(requirement, string.format("%d / %d ore this run", info.blocks, info.blocksReq), 9, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 66),
		Size = UDim2.new(1, -36, 0, 14),
	})

	local action = row(92)
	local status = text(action, "", 9, PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(260, 24),
		Size = UDim2.new(1, -278, 0, 14),
	})
	local confirmRow = create("Frame", {
		Name = "RebirthConfirm",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -36, 0, 34),
		Position = UDim2.fromOffset(18, 50),
		Visible = false,
	}, action)
	local reborn = button(action, info.canRebirth and "REBIRTH NOW" or ("MINER LV " .. info.levelReq .. " REQUIRED"), info.canRebirth and PALETTE.pink or PALETTE.panelLight, function()
		if not info.canRebirth then
			toast("Rebirth needs Miner Lv " .. info.levelReq .. ".", "error")
			return
		end
		confirmRow.Visible = true
		status.Text = "This wipes the run. Confirm below."
		status.TextColor3 = PALETTE.bad
	end, 34)
	reborn.Size = UDim2.fromOffset(230, 34)
	reborn.Position = UDim2.fromOffset(18, 10)

	local confirmBtn = button(confirmRow, "YES, REBIRTH", PALETTE.pink, function()
		confirmRow.Visible = false
		status.Text = "Rebirthing..."
		status.TextColor3 = PALETTE.gold
		send("Rebirth")
	end, 34)
	confirmBtn.Size = UDim2.fromOffset(160, 34)
	confirmBtn.Position = UDim2.fromOffset(0, 0)
	local cancelBtn = button(confirmRow, "NOT YET", PALETTE.panelLight, function()
		confirmRow.Visible = false
		status.Text = ""
	end, 34)
	cancelBtn.Size = UDim2.fromOffset(120, 34)
	cancelBtn.Position = UDim2.fromOffset(172, 0)

	local resets = row(78)
	stroke(resets, PALETTE.bad, 1, 0.5)
	text(resets, "RESETS", 9, PALETTE.bad, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -36, 0, 12),
	})
	text(resets, "Coins, pickaxe level, the whole research tree, miner level and your current biome.", 10, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 30),
		Size = UDim2.new(1, -36, 0, 30),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local keeps = row(78)
	stroke(keeps, PALETTE.good, 1, 0.5)
	text(keeps, "KEEPS", 9, PALETTE.good, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -36, 0, 12),
	})
	text(keeps, "Every hero, pet, gem, boost, quest claim and all rebirth multipliers earned so far.", 10, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(18, 30),
		Size = UDim2.new(1, -36, 0, 30),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
end

local function renderShop()
	local pick = row(92)
	stroke(pick, PALETTE.gold, 1, 0.4)
	text(pick, "Pickaxe  ·  Level " .. state.pickaxe .. " / 25", 13, PALETTE.gold, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -180, 0, 18),
	})
	text(pick, "+30% swing damage per level. Also sold at the town forge.", 9, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -180, 0, 14),
	})
	local pickBar, pickFill = bar(pick, (state.pickaxe - 1) / 24, PALETTE.gold, 5)
	pickBar.Position = UDim2.fromOffset(12, 56)
	pickBar.Size = UDim2.new(1, -204, 0, 5)
	text(pick, state.pickaxeMaxed and "Maxed out" or ("Next level " .. state.pickaxeCost .. " coins"), 9, state.pickaxeMaxed and PALETTE.good or PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.fromOffset(260, 12),
	})
	local forgeBtn = button(pick, state.pickaxeMaxed and "MAXED" or ("FORGE  " .. state.pickaxeCost .. "c"), PALETTE.gold, function()
		if not state.pickaxeMaxed then
			send("UpgradePickaxe")
		end
	end, 32)
	forgeBtn.Size = UDim2.fromOffset(140, 32)
	forgeBtn.Position = UDim2.new(1, -152, 0, 30)

	for _, boost in ipairs(state.shop) do
		local card = row(92)
		stroke(card, boost.color, 1, 0.4)
		local active = boost.timeLeft > 0
		text(card, boost.name, 13, boost.color, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -200, 0, 18),
		})
		if active then
			chip(card, 300, 12, 70, "ACTIVE", PALETTE.good, 16)
		end
		text(card, boost.desc, 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(12, 32),
			Size = UDim2.new(1, -200, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local timeText = active and ("Running  " .. math.ceil(boost.timeLeft) .. "s") or ("Duration  " .. math.floor(boost.duration / 60) .. " min")
		text(card, timeText, 9, active and PALETTE.good or PALETTE.dim, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(12, 50),
			Size = UDim2.fromOffset(240, 12),
		})
		local ratio = active and math.clamp(boost.timeLeft / boost.duration, 0, 1) or 0
		local holder, fill = bar(card, ratio, boost.color, 4)
		holder.Position = UDim2.fromOffset(12, 70)
		holder.Size = UDim2.new(1, -204, 0, 4)
		local buyBtn = button(card, (active and "EXTEND" or "BUY") .. "  " .. boost.cost .. "g", boost.color, function()
			send("BuyBoost", { id = boost.id })
		end, 32)
		buyBtn.Size = UDim2.fromOffset(140, 32)
		buyBtn.Position = UDim2.new(1, -152, 0, 30)
	end

	local passes = state.passes or {}
	if #passes > 0 then
		local header = row(30)
		text(header, "GAMEPASSES  ·  permanent", 10, PALETTE.accent, Enum.Font.GothamBlack, {
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 0, 14),
		})
		for _, pass in ipairs(passes) do
			local card = row(90)
			stroke(card, pass.color, 1, 0.35)
			text(card, pass.name, 13, pass.color, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(12, 10),
				Size = UDim2.new(1, -180, 0, 18),
			})
			text(card, pass.desc, 9, PALETTE.dim, Enum.Font.GothamMedium, {
				Position = UDim2.fromOffset(12, 31),
				Size = UDim2.new(1, -180, 0, 14),
				TextWrapped = true,
			})
			if pass.owned then
				chip(card, 12, 62, 92, "OWNED", PALETTE.good, 18)
			elseif not pass.configured then
				chip(card, 12, 62, 132, "NOT SET UP YET", PALETTE.dim, 18)
			end
			local label = pass.owned and "OWNED" or (pass.configured and "BUY" or "UNAVAILABLE")
			local btn = button(card, label, pass.owned and PALETTE.good or (pass.configured and pass.color or PALETTE.panelLight), function()
				if pass.owned then
					return
				end
				if pass.configured then
					MarketplaceService:PromptGamePassPurchase(player, pass.passId)
				else
					toast("This pass has no id yet - add it on the Game Passes page.", "error")
				end
			end, 32)
			btn.Size = UDim2.fromOffset(140, 32)
			btn.Position = UDim2.new(1, -152, 0, 30)
		end
	end
end

local function renderQuests()
	local claimable = 0
	for _, quest in ipairs(state.quests or {}) do
		if quest.claimable then
			claimable += 1
		end
	end
	local header = row(34)
	text(header, claimable > 0 and (claimable .. " reward(s) ready to claim") or "Rewards unlock as you play", 10, claimable > 0 and PALETTE.good or PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.new(1, -24, 0, 14),
	})
	for _, quest in ipairs(state.quests) do
		local card = row(84)
		local color = quest.claimed and PALETTE.dim or (quest.claimable and PALETTE.good or PALETTE.text)
		gemIcon(card, PALETTE.gem, 16, UDim2.fromOffset(12, 18))
		text(card, quest.name, 12, color, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(38, 10),
			Size = UDim2.new(1, -180, 0, 16),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(card, quest.desc, 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(38, 28),
			Size = UDim2.new(1, -180, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(card, quest.progress .. " / " .. quest.goal .. "   ·   +" .. quest.reward .. " gems", 9, PALETTE.gold, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(38, 48),
			Size = UDim2.new(1, -200, 0, 12),
		})
		local holder = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(38, 68),
			Size = UDim2.new(1, -200, 0, 5),
		}, card)
		bar(holder, quest.progress / quest.goal, quest.claimable and PALETTE.good or PALETTE.accent, 5)
		local status = quest.claimed and "CLAIMED" or (quest.claimable and ("CLAIM +" .. quest.reward) or "IN PROGRESS")
		local claimBtn = button(card, status, quest.claimable and PALETTE.good or PALETTE.panelLight, function()
			if quest.claimable then
				send("ClaimQuest", { id = quest.id })
			end
		end, 30)
		claimBtn.Size = UDim2.fromOffset(130, 30)
		claimBtn.Position = UDim2.new(1, -142, 0, 28)
	end

	local sideQuests = state.sideQuests or {}
	if #sideQuests > 0 then
		local header = row(30)
		text(header, "SIDE QUESTS", 10, PALETTE.pink, Enum.Font.GothamBlack, {
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 0, 14),
		})
		for _, quest in ipairs(sideQuests) do
			local card = row(80)
			local color = quest.state == "claimed" and PALETTE.dim or (quest.state == "ready" and PALETTE.good or PALETTE.text)
			text(card, quest.name, 12, color, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(12, 9),
				Size = UDim2.new(1, -130, 0, 16),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			text(card, quest.role .. "  ·  " .. quest.desc, 9, PALETTE.dim, Enum.Font.GothamMedium, {
				Position = UDim2.fromOffset(12, 27),
				Size = UDim2.new(1, -130, 0, 13),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			text(card, quest.progress .. " / " .. quest.goal .. "   ·   +" .. quest.coins .. " coins, +" .. quest.gems .. " gems", 9, PALETTE.gold, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(12, 44),
				Size = UDim2.new(1, -130, 0, 12),
			})
			local holder = create("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 62),
				Size = UDim2.new(1, -142, 0, 5),
			}, card)
			bar(holder, math.clamp(quest.progress / quest.goal, 0, 1), quest.state == "ready" and PALETTE.good or PALETTE.pink, 5)
			local label = quest.state == "claimed" and "DONE" or (quest.state == "ready" and "CLAIM" or "VISIT")
			local actionBtn = button(card, label, quest.state == "ready" and PALETTE.good or PALETTE.panelLight, function()
				if quest.state == "claimed" then
					return
				end
				send("NpcTalk", { npcId = quest.npcId, choice = quest.state == "ready" and "claim" or "greet" })
			end, 30)
			actionBtn.Size = UDim2.fromOffset(104, 30)
			actionBtn.Position = UDim2.new(1, -116, 0, 24)
		end
	end
end

local function renderIndex()
	local discovered = 0
	for _, hero in ipairs(state.heroIndex) do
		if hero.count > 0 then
			discovered += 1
		end
	end
	local header = row(34)
	text(header, "Discovered " .. discovered .. " / " .. #state.heroIndex .. "  ·  every hero you have ever summoned", 10, PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.new(1, -24, 0, 14),
	})

	local columns = 5
	local cellW, cellH, pad = 146, 168, 6
	local rows = math.ceil(#state.heroIndex / columns)
	local container = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, rows * (cellH + pad)),
	}, contentScroll)
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellW, cellH),
		CellPadding = UDim2.fromOffset(pad, pad),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}, container)

	for index, hero in ipairs(state.heroIndex) do
		local known = hero.count > 0
		local cell = create("Frame", {
			BackgroundColor3 = PALETTE.panelLight,
			BackgroundTransparency = known and 0.25 or 0.5,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(cellW, cellH),
			LayoutOrder = index,
		}, container)
		corner(cell, 10)
		stroke(cell, known and Config.RarityColor(hero.rarity) or PALETTE.line, 1, known and 0.35 or 0.7)
		portrait(cell, 72, UDim2.new(0.5, -36, 0, 10), hero.color, Config.RarityColor(hero.rarity), nil, not known)
		text(cell, known and hero.name or "???", 9, known and PALETTE.text or PALETTE.dim, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(8, 92),
			Size = UDim2.new(1, -16, 0, 24),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		text(cell, hero.rarity, 8, Config.RarityColor(hero.rarity), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(8, 122),
			Size = UDim2.new(1, -16, 0, 12),
		})
		text(cell, known and ("Owned x" .. hero.count) or "Not summoned", 8, known and PALETTE.good or PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(8, 136),
			Size = UDim2.new(1, -16, 0, 12),
		})
	end
end

local function weatherGlyph(parent, size, position, id, color)
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = position,
	}, parent)
	local core = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.44, 0.44),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, holder)
	corner(core, size)
	if id == "meteor" then
		for index = 1, 3 do
			iconBar(holder, math.max(2, size * 0.06), size * 0.5, color, 40, UDim2.new(0.2 + index * 0.24, 0, 0.2 + index * 0.12, 0))
		end
	elseif id == "storm" then
		iconBar(holder, math.max(2, size * 0.08), size * 0.3, Color3.fromRGB(255, 240, 180), 24, UDim2.fromScale(0.52, 0.62))
	elseif id == "aurora" then
		for index = 1, 3 do
			iconBar(holder, math.max(2, size * 0.07), size * 0.6, color, -20 + index * 14, UDim2.new(0.5, 0, 0.12 * index, 0))
		end
	elseif id == "golden" then
		for index = 1, 3 do
			iconBar(holder, math.max(2, size * 0.05), size * 0.66, Color3.fromRGB(255, 230, 170), 0, UDim2.new(0.5, 0, 0.24 * index + 0.1, 0))
		end
	else
		for index = 0, 3 do
			iconBar(holder, math.max(2, size * 0.05), size * 0.26, color, index * 45, UDim2.new(0.5, 0, 0.5, -size * 0.3))
		end
	end
	return holder
end

local function renderWeather()
	local current = state.weather
	local hero = row(112)
	stroke(hero, current.color, 1.4, 0.2)
	weatherGlyph(hero, 62, UDim2.fromOffset(16, 16), current.id, current.color)
	text(hero, current.name, 17, current.color, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(92, 14),
		Size = UDim2.new(1, -110, 0, 22),
	})
	text(hero, current.desc, 10, PALETTE.dim, Enum.Font.GothamMedium, {
		Position = UDim2.fromOffset(92, 38),
		Size = UDim2.new(1, -110, 0, 14),
		TextWrapped = true,
	})
	text(hero, string.format("Power x%.2f   Luck x%.2f   Coins x%.2f   Speed x%.2f", current.mult.power, current.mult.luck, current.mult.coin, current.mult.speed), 9, PALETTE.gold, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(92, 62),
		Size = UDim2.new(1, -110, 0, 12),
	})
	local remaining = math.floor(current.timeLeft)
	local holder, fill = bar(hero, current.duration and (remaining / current.duration) or 0, current.color, 4)
	holder.Position = UDim2.fromOffset(92, 84)
	holder.Size = UDim2.new(1, -110, 0, 4)
	text(hero, "Ends in " .. remaining .. "s", 9, PALETTE.accent, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(92, 90),
		Size = UDim2.fromOffset(200, 12),
	})

	for _, weather in ipairs(Config.Weather) do
		if weather.id ~= current.id then
			local card = row(66)
			weatherGlyph(card, 40, UDim2.fromOffset(12, 12), weather.id, weather.color)
			text(card, weather.name, 11, weather.color, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(64, 10),
				Size = UDim2.new(1, -80, 0, 16),
			})
			text(card, weather.desc, 9, PALETTE.dim, Enum.Font.GothamMedium, {
				Position = UDim2.fromOffset(64, 28),
				Size = UDim2.new(1, -80, 0, 14),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			text(card, string.format("x%.2f power  ·  x%.2f luck  ·  x%.2f coins  ·  x%.2f speed", weather.mult.power, weather.mult.luck, weather.mult.coin, weather.mult.speed), 8, PALETTE.gold, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(64, 46),
				Size = UDim2.new(1, -80, 0, 12),
			})
		end
	end
end

local function renderTrade()
	if not state.tradeUnlocked then
		local locked = row(84)
		lockIcon(locked, PALETTE.bad, 26, UDim2.fromOffset(16, 26))
		text(locked, "Trading locked", 13, PALETTE.bad, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(58, 14),
			Size = UDim2.new(1, -74, 0, 18),
		})
		text(locked, "Research Guild Charter to trade heroes with other miners.", 10, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(58, 38),
			Size = UDim2.new(1, -74, 0, 20),
			TextWrapped = true,
		})
		return
	end

	local selected = selectedUnitId and unitById(selectedUnitId)
	local selectionCard = row(52)
	portrait(selectionCard, 34, UDim2.fromOffset(12, 9), selected and selected.color or PALETTE.dim, PALETTE.line, nil, not selected)
	text(selectionCard, selected and ("Offering: " .. selected.heroName .. "  ·  Lv " .. selected.level) or "Pick a hero in Crew first", 11, selected and selected.color or PALETTE.dim, Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(56, 16),
		Size = UDim2.new(1, -70, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local others = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			others += 1
			local card = row(58)
			local thumb = avatarFrame(card, 34, UDim2.fromOffset(12, 12))
			thumb.BorderSizePixel = 0
			text(card, other.DisplayName, 11, PALETTE.text, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(56, 12),
				Size = UDim2.new(1, -180, 0, 16),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			text(card, "Offer your picked hero, then they accept.", 9, PALETTE.dim, Enum.Font.GothamMedium, {
				Position = UDim2.fromOffset(56, 32),
				Size = UDim2.new(1, -180, 0, 14),
			})
			local offerBtn = button(card, "OFFER", PALETTE.accent, function()
				if selectedUnitId then
					send("TradeOffer", { targetName = other.Name, unitId = selectedUnitId })
				else
					toast("Pick a hero in Crew first.", "error")
				end
			end, 28)
			offerBtn.Size = UDim2.fromOffset(96, 28)
			offerBtn.Position = UDim2.new(1, -108, 0, 15)
		end
	end
	if others == 0 then
		local solo = row(44)
		text(solo, "No other miners online right now.", 10, PALETTE.dim, Enum.Font.GothamMedium, {
			Position = UDim2.fromOffset(12, 14),
			Size = UDim2.new(1, -24, 16),
		})
	end

	if #state.tradeIncoming > 0 then
		text(contentScroll, "INCOMING OFFERS", 9, PALETTE.pink, Enum.Font.GothamBlack, {
			Size = UDim2.new(1, 0, 0, 14),
		})
		for _, offer in ipairs(state.tradeIncoming) do
			local card = row(58)
			text(card, offer.fromName .. "  →  " .. offer.unitName, 10, PALETTE.text, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.new(1, -150, 0, 16),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			text(card, "Offer one back, then accept.", 9, PALETTE.dim, Enum.Font.GothamMedium, {
				Position = UDim2.fromOffset(12, 32),
				Size = UDim2.new(1, -150, 0, 14),
			})
			local acceptBtn = button(card, "ACCEPT", PALETTE.good, function()
				send("TradeAccept")
			end, 28)
			acceptBtn.Size = UDim2.fromOffset(96, 28)
			acceptBtn.Position = UDim2.new(1, -108, 0, 15)
		end
	end
end

local function renderGuide()
	local tourLine = "Tour: not started"
	if state.tutorial then
		if state.tutorial.done then
			tourLine = "Tour: complete"
		elseif state.tutorial.started then
			tourLine = "Tour: step " .. state.tutorial.index .. " of " .. state.tutorial.total
		end
	end
	local sections = {
		{ title = "THE LOOP", color = PALETTE.accent, lines = {
			"Click a portal in town to enter a biome (Miner Lv gates each one).",
			"Click ore to swing. Deployed heroes swing on their own, even offline.",
			"Deeper biomes pay far more but the ore takes more hits.",
		} },
		{ title = "CURRENCIES", color = PALETTE.gold, lines = {
			"Coins: summons, hero levels, research, pickaxe, forge.",
			"Gems: mutations, enchant dice, boosts and quest rewards.",
		} },
		{ title = "GETTING STRONGER", color = PALETTE.good, lines = {
			"More crew slots come from Research (Recruit Board, Guild Hall).",
			"Mutate and enchant your best hero before pushing a new biome.",
			"Weather multiplies everything: check the forecast chip up top.",
		} },
		{ title = "ON THE MAP", color = PALETTE.pink, lines = {
			"Forge: pickaxe upgrades. Daily cache: free coins and gems.",
			"Chests restock in every biome. Descend pads go one biome deeper.",
		} },
		{ title = "REBIRTH", color = PALETTE.pink, lines = {
			"At Miner Lv 24 the Rebirth tab can restart the run for good.",
			"Each rebirth is +40% coins and +12% hero power, permanently.",
			"Rich veins glow gold and pay triple. Gem nodes glow white.",
		} },
		{ title = tourLine, color = PALETTE.dim, lines = {
			"Mining fast builds a combo that adds bonus coins.",
			"Press M for the menu, ESC to close. DEV opens the developer panel.",
		} },
	}
	for _, section in ipairs(sections) do
		local card = row(88)
		create("Frame", {
			BackgroundColor3 = section.color,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(3, 68),
			Position = UDim2.fromOffset(0, 10),
		}, card)
		text(card, section.title, 9, PALETTE.text, Enum.Font.GothamBlack, {
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -28, 0, 12),
		})
		for index, line in ipairs(section.lines) do
			create("Frame", {
				BackgroundColor3 = section.color,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(4, 4),
				Position = UDim2.fromOffset(16, 30 + (index - 1) * 18),
				Rotation = 45,
			}, card)
			text(card, line, 9, PALETTE.dim, Enum.Font.GothamMedium, {
				Position = UDim2.fromOffset(28, 24 + (index - 1) * 18),
				Size = UDim2.new(1, -42, 0, 16),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
		end
	end
end

-- guide arrow helpers --------------------------------------------------------
local function worldTargetPosition(): (Vector3?, string?)
	if not state or not state.tutorial or state.tutorial.done or not state.tutorial.started then
		return nil, nil
	end
	local world = workspace:FindFirstChild("MineWorld")
	if not world then
		return nil, nil
	end
	if state.tutorial.world == "portal" then
		local portal = world:FindFirstChild("Portal")
		local plane = portal and portal:FindFirstChild("PortalPlane", true)
		if plane and plane:IsA("BasePart") then
			return plane.Position + Vector3.new(0, 20, 0), "ENTER THE MINES"
		end
	elseif state.tutorial.world == "ore" then
		local zones = world:FindFirstChild("Zones")
		local zone = zones and zones:FindFirstChild("Zone_" .. tostring(state.zone or 1))
		if zone then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local best: Model? = nil
			local bestDistance = math.huge
			for _, model in ipairs(zone:GetChildren()) do
				if model:IsA("Model") and model.Name:match("^Ore_") and model:GetAttribute("Alive") then
					local position = model:GetPivot().Position
					local distance = root and (position - root.Position).Magnitude or 0
					if distance < bestDistance then
						best = model
						bestDistance = distance
					end
				end
			end
			if best then
				return best:GetPivot().Position + Vector3.new(0, 7, 0), "BREAK THIS ORE"
			end
		end
	end
	return nil, nil
end

local function updateGuideArrow()
	if not camera then
		camera = workspace.CurrentCamera
	end
	local targetPosition, hintText = worldTargetPosition()
	if not targetPosition or not camera then
		guideArrow.Visible = false
		guideArrowHint.Visible = false
		return
	end

	local viewport = camera.ViewportSize
	local projected, onScreen = camera:WorldToViewportPoint(targetPosition)
	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local direction = Vector2.new(projected.X, projected.Y) - center
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, 1)
	end
	direction = direction.Unit

	local x, y, rotation
	if onScreen then
		x = projected.X
		y = projected.Y - 34
		rotation = 90
	else
		local margin = 90
		local scaleX = (viewport.X / 2 - margin) / math.max(math.abs(direction.X), 1e-3)
		local scaleY = (viewport.Y / 2 - margin) / math.max(math.abs(direction.Y), 1e-3)
		local distance = math.min(scaleX, scaleY)
		x = center.X + direction.X * distance
		y = center.Y + direction.Y * distance
		rotation = math.deg(math.atan2(direction.Y, direction.X))
	end

	-- screen pixels map inward onto the scaled canvas
	local fit = canvasScale.Scale
	local canvasX = 640 + (x - viewport.X / 2) / fit
	local canvasY = 360 + (y - viewport.Y / 2) / fit
	guideArrow.Position = UDim2.fromOffset(math.floor(canvasX), math.floor(canvasY))
	guideArrow.Rotation = rotation
	guideArrow.Visible = true
	guideArrowHint.Position = UDim2.fromOffset(math.floor(canvasX), math.floor(canvasY) + 30)
	guideArrowHint.Text = hintText or ""
	guideArrowHint.Visible = true
end

-- zone presentation ----------------------------------------------------------
local function showZoneBanner(zoneName, zoneId, color)
	zoneBannerToken += 1
	local token = zoneBannerToken
	zoneBanner.Visible = true
	-- the zone tint stays on the border; the labels keep the standard readable
	-- white/dim pair so the banner matches every other surface
	zoneBannerTitle.Text = string.upper(zoneName)
	zoneBannerTitle.TextColor3 = PALETTE.text
	zoneBannerStroke.Color = color
	zoneBannerSub.Text = "DEPTH " .. zoneId .. "  ·  BIOME " .. zoneId .. " OF " .. #Config.Zones
	zoneBannerSub.TextColor3 = PALETTE.dim
	bannerScale.Scale = 0.9
	zoneBanner.GroupTransparency = 1
	TweenService:Create(zoneBanner, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	}):Play()
	TweenService:Create(bannerScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(3.2, function()
		if token ~= zoneBannerToken then
			return
		end
		TweenService:Create(zoneBanner, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
		task.delay(0.45, function()
			if token == zoneBannerToken then
				zoneBanner.Visible = false
			end
		end)
	end)
end

local function flashTravel(zoneName, zoneId, color)
	fadeOverlay.Visible = true
	fadeOverlay.BackgroundTransparency = 0.4
	TweenService:Create(fadeOverlay, TweenInfo.new(0.45), { BackgroundTransparency = 0.85 }):Play()
	task.delay(0.5, function()
		TweenService:Create(fadeOverlay, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		task.delay(0.55, function()
			fadeOverlay.Visible = false
		end)
	end)
	showZoneBanner(zoneName, zoneId, color)
end

-- world labels: cache the instances once and only write a property when it
-- actually changed, so this can run on every payload without touching the scene
local labelCache = { signs = nil, gates = nil }

local function buildLabelCache(world)
	labelCache.signs = {}
	local zonesFolder = world:FindFirstChild("Zones")
	if zonesFolder then
		for _, folder in ipairs(zonesFolder:GetChildren()) do
			local zoneId = tonumber(folder.Name:match("%d+") or "")
			local signPart = folder:FindFirstChild("ZoneSign")
			local gui = signPart and signPart:FindFirstChild("Sign")
			if zoneId and gui and gui:IsA("BillboardGui") then
				labelCache.signs[#labelCache.signs + 1] = { zone = zoneId, gui = gui }
			end
		end
	end
	labelCache.gates = {}
	local portal = world:FindFirstChild("Portal")
	if portal then
		for _, gate in ipairs(portal:GetChildren()) do
			local zoneId = gate:GetAttribute("Zone")
			local zone = zoneId and Config.ZoneById(zoneId)
			if zone then
				local sign = gate:FindFirstChild("Sign", true)
				labelCache.gates[#labelCache.gates + 1] = {
					zone = zone,
					plane = gate:FindFirstChild("PortalPlane", true),
					title = sign and sign:FindFirstChild("TextLabel"),
					sub = sign and sign:FindFirstChild("SubLabel"),
				}
			end
		end
	end
end

local function syncWorldLabels()
	if not state then
		return
	end
	local world = workspace:FindFirstChild("MineWorld")
	if not world then
		return
	end
	-- zone folders replicate one by one; keep rebuilding until every sign is known
	local zonesFolder = world:FindFirstChild("Zones")
	local zoneCount = zonesFolder and #zonesFolder:GetChildren() or 0
	if not labelCache.signs or #labelCache.signs < zoneCount or not labelCache.gates or #labelCache.gates == 0 then
		buildLabelCache(world)
	end

	-- zone titles are only shown inside their own biome
	for _, entry in ipairs(labelCache.signs) do
		local inside = entry.zone == state.zone
		if entry.gui.Enabled ~= inside then
			entry.gui.Enabled = inside
		end
	end

	-- portal gates tint per player: locked ones read red with a LV tag
	for _, entry in ipairs(labelCache.gates) do
		local zone = entry.zone
		local unlocked = state.level >= (zone.levelReq or 1) and state.zonesUnlocked >= zone.id
		local plane = entry.plane
		if plane and plane:IsA("BasePart") then
			local color = unlocked and zone.blockColor or PALETTE.bad
			if plane.Color ~= color then
				plane.Color = color
			end
		end
		local title = entry.title
		if title and title:IsA("TextLabel") then
			local nameText = string.upper(zone.name)
			if title.Text ~= nameText then
				title.Text = nameText
					title.TextColor3 = unlocked and PALETTE.text or PALETTE.bad
			end
		end
		local sub = entry.sub
		if sub and sub:IsA("TextLabel") then
			local subText = unlocked and ("MINER LV " .. (zone.levelReq or 1) .. " · OPEN")
				or ("LOCKED · MINER LV " .. (zone.levelReq or 1) .. " REQUIRED")
			if sub.Text ~= subText then
				sub.Text = subText
				sub.TextColor3 = unlocked and PALETTE.good or PALETTE.bad
			end
		end
	end
end

-- main render ----------------------------------------------------------------
render = function(immediate)
	if not state then
		return
	end

	coinLabel.Text = tostring(state.coins) .. " coins"
	gemLabel.Text = tostring(state.gems) .. " gems"
	dpsLabel.Text = string.format("%.0f DPS  ·  %d hero(es)", state.dps, state.equipped)
	luckLabel.Text = string.format("Luck x%.2f  ·  Pickaxe Lv %d", state.gachaLuck or 1, state.pickaxe or 1)

	local level = state.level or 1
	levelLabel.Text = "MINER LV " .. level
	levelFill.Size = UDim2.fromScale((state.levelProgress and state.levelProgress.ratio) or 0, 1)
	xpLabel.Text = string.format("%d / %d ore to Lv %d", state.levelProgress and state.levelProgress.blocks or 0, state.levelProgress and state.levelProgress.next or 0, level + 1)
	xpFill.Size = UDim2.fromScale((state.levelProgress and state.levelProgress.ratio) or 0, 1)

	weatherLabel.Text = state.weather.name .. "  ·  " .. math.floor(state.weather.timeLeft) .. "s"
	-- weather tint lives on the border and dot only: the label keeps the shared
	-- white so it stays readable on the panel tone
	weatherStroke.Color = state.weather.color
	weatherDot.BackgroundColor3 = state.weather.color
	weatherLabel.TextColor3 = PALETTE.text

	zoneStat.Text = state.zoneName
	crewStat.Text = "Crew " .. state.equipped .. "/" .. state.crewSlots
	blocksStat.Text = tostring(state.stats.blocksMined)
	bestStat.Text = tostring(state.stats.bestRarity) .. "  ·  x" .. tostring(state.stats.rolls)
	storageLabel.Text = state.storedUnits .. " / " .. Config.MaxUnits
	storageFill.Size = UDim2.fromScale(math.clamp(state.storedUnits / Config.MaxUnits, 0, 1), 1)
	storageFill.BackgroundColor3 = state.storedUnits >= Config.MaxUnits and PALETTE.bad or PALETTE.accent
	rankLabel.Text = rankFor(state.stats)
	dailyLabel.Text = state.dailyReady and "DAILY READY" or "DAILY USED"
	dailyLabel.TextColor3 = state.dailyReady and PALETTE.gold or PALETTE.dim
	sidebarLevel.Text = "LV " .. level

	adminButton.Visible = state.admin == true
	if adminOpen and adminPanel then
		adminRefs.coins.Text = tostring(state.coins) .. " coins"
		adminRefs.gems.Text = tostring(state.gems) .. " gems"
		adminRefs.level.Text = "Miner Lv " .. level
	end

	local combo = state.combo
	if combo and combo.count >= 2 and combo.timeLeft > 0 and not menuOpen then
		comboCard.Visible = true
		comboLabel.Text = "COMBO  x" .. string.format("%.2f", combo.mult) .. "  ·  " .. combo.count
		TweenService:Create(comboFill, TweenInfo.new(0.2), {
			Size = UDim2.fromScale(math.clamp(combo.timeLeft / 2.4, 0, 1), 1),
		}):Play()
	else
		comboCard.Visible = false
	end

	-- boost chips: the set changes rarely, so build the chips once and let the
	-- one-second timer loop update their labels
	local boostKey = ""
	for _, boost in ipairs(state.boosts or {}) do
		boostKey = boostKey .. boost.id .. ","
	end
	if boostKey ~= lastBoostKey then
		lastBoostKey = boostKey
		for _, child in ipairs(boostHolder:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		boostLabels = {}
		for _, boost in ipairs(state.boosts or {}) do
			local chipFrame = create("Frame", {
				BackgroundColor3 = PALETTE.panel,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(152, 22),
			}, boostHolder)
			corner(chipFrame, 6)
			stroke(chipFrame, boost.color, 1, 0.3)
			text(chipFrame, boost.name, 9, boost.color, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(8, 3),
				Size = UDim2.fromOffset(96, 16),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local timerLabel = text(chipFrame, math.ceil(boost.timeLeft) .. "s", 9, PALETTE.text, Enum.Font.GothamBold, {
				Position = UDim2.new(1, -52, 0, 3),
				Size = UDim2.fromOffset(44, 16),
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			boostLabels[boost.id] = timerLabel
		end
	end

	-- travel list: rebuilt only when the unlock state, biome or current zone changes
	local travelKey = tostring(state.zone) .. "|" .. tostring(state.level) .. "|" .. tostring(state.zonesUnlocked) .. "|" .. tostring(#(state.zones or {}))
	if travelKey ~= lastTravelKey then
		lastTravelKey = travelKey
		for _, child in ipairs(zoneList:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for _, zone in ipairs(state.zones or {}) do
			local isHere = zone.id == state.zone
			local rowBtn = create("TextButton", {
				BackgroundColor3 = isHere and PALETTE.panelLight or PALETTE.sunken,
				BackgroundTransparency = isHere and 0.05 or 0.3,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = true,
				Size = UDim2.new(1, 0, 0, 40),
			}, zoneList)
			corner(rowBtn, 8)
			stroke(rowBtn, isHere and PALETTE.accent or PALETTE.line, 1, isHere and 0.15 or 0.6)
			local swatch = create("Frame", {
				BackgroundColor3 = zoneColor(zone.id),
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(5, 26),
				Position = UDim2.fromOffset(8, 7),
			}, rowBtn)
			corner(swatch, 3)
			text(rowBtn, zone.name, 9, zone.unlocked and PALETTE.text or PALETTE.dim, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(20, 5),
				Size = UDim2.new(1, -50, 0, 14),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local statusText = zone.unlocked and (isHere and "HERE" or "OPEN")
				or ("LV " .. (zone.levelReq or 1) .. (zone.researchReady and "" or " + RESEARCH"))
			text(rowBtn, statusText, 8, zone.unlocked and (isHere and PALETTE.text or PALETTE.good) or PALETTE.bad, Enum.Font.GothamBold, {
				Position = UDim2.fromOffset(20, 22),
				Size = UDim2.new(1, -50, 0, 12),
			})
			if not zone.unlocked then
				lockIcon(rowBtn, PALETTE.bad, 14, UDim2.new(1, -12, 0.5, 0), Vector2.new(1, 0.5))
			end
			rowBtn.MouseButton1Click:Connect(function()
				if zone.unlocked then
					send("Travel", { zoneId = zone.id })
				elseif not zone.levelReady then
					toast("Miner Lv " .. (zone.levelReq or 1) .. " required for " .. zone.name .. ".", "error")
				else
					toast("Research required for " .. zone.name .. ".", "error")
				end
			end)
		end
	end

	-- quest tracker
	for _, child in ipairs(questRows:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local claimable = 0
	local tracked = {}
	for _, quest in ipairs(state.quests or {}) do
		if quest.claimable then
			claimable += 1
		end
		if not quest.claimed then
			tracked[#tracked + 1] = quest
		end
	end
	table.sort(tracked, function(a, b)
		local ra = a.progress / math.max(1, a.goal)
		local rb = b.progress / math.max(1, b.goal)
		if ra ~= rb then
			return ra > rb
		end
		return a.reward > b.reward
	end)
	questCount.Text = claimable > 0 and (claimable .. " READY") or (tostring(#tracked) .. " ACTIVE")
	for index = 1, math.min(3, #tracked) do
		local quest = tracked[index]
		local rowFrame = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
		}, questRows)
		text(rowFrame, quest.name, 9, quest.claimable and PALETTE.good or PALETTE.text, Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, -76, 0, 12),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(rowFrame, quest.progress .. "/" .. quest.goal, 8, PALETTE.dim, Enum.Font.GothamBold, {
			Position = UDim2.new(1, -72, 0, 0),
			Size = UDim2.fromOffset(72, 12),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local holder = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 4),
		}, rowFrame)
		bar(holder, quest.progress / math.max(1, quest.goal), quest.claimable and PALETTE.good or PALETTE.pink, 4)
		if quest.claimable then
			local claim = create("TextButton", {
				BackgroundColor3 = PALETTE.sunken,
				BorderSizePixel = 0,
				Text = "CLAIM",
				TextColor3 = PALETTE.good,
				Font = Enum.Font.GothamBold,
				TextSize = 8,
				Size = UDim2.fromOffset(48, 16),
				Position = UDim2.new(1, -48, 0, 20),
			}, rowFrame)
			corner(claim, 4)
			claim.MouseButton1Click:Connect(function()
				send("ClaimQuest", { id = quest.id })
			end)
		end
	end
	if #tracked == 0 then
		text(questRows, "All quests claimed. Go break more ore.", 9, PALETTE.dim, Enum.Font.GothamMedium, {
			Size = UDim2.new(1, 0, 0, 30),
			TextWrapped = true,
		})
	end

	-- tutorial
	local tutorial = state.tutorial
	local targetTab = nil
	if tutorial and tutorial.started and not tutorial.done then
		targetTab = tutorial.target
	end
	if tutorial then
		if tutorial.done then
			tutorialCard.Visible = false
		elseif not tutorial.started then
			tutorialCard.Visible = settings.hudVisible and not tourDismissed and not menuOpen
			tutorialStep.Text = "GUIDED TOUR"
			tutorialTitle.Text = "Welcome, miner"
			tutorialText.Text = "A short tour shows you the loop and pays 300 coins + 12 gems."
			tutorialNext.Text = "START TOUR"
			tutorialShow.Visible = false
			tutorialSkip.Text = "LATER"
		else
			tourDismissed = false
			tutorialCard.Visible = settings.hudVisible and not menuOpen
			tutorialStep.Text = "TUTORIAL " .. tutorial.index .. " / " .. tutorial.total
			tutorialTitle.Text = tutorial.title
			tutorialText.Text = tutorial.text
			tutorialNext.Text = "GOT IT"
			tutorialShow.Visible = tutorial.target ~= nil and tabButtons[tutorial.target] ~= nil
			tutorialSkip.Text = "SKIP"
			if lastTutorialStep ~= tutorial.index then
				lastTutorialStep = tutorial.index
				tutorialCard.GroupTransparency = 0.4
				TweenService:Create(tutorialCard, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					GroupTransparency = 0,
				}):Play()
			end
		end
	end

	if targetTab and tabButtons[targetTab] then
		local targetIndex = 1
		for index, tab in ipairs(tabOrder) do
			if tab.id == targetTab then
				targetIndex = index
				break
			end
		end
		tabArrow.Position = UDim2.fromOffset(176, 34 + (targetIndex - 1) * 37 + 8)
		tabArrow.Visible = true
	else
		tabArrow.Visible = false
	end

	for id, entry in pairs(tabButtons) do
		local active = id == activeTab
		entry.button.BackgroundColor3 = active and entry.color or PALETTE.panelLight
		entry.button.BackgroundTransparency = active and 0.05 or 0.12
		entry.label.TextColor3 = active and Color3.fromRGB(14, 16, 26) or PALETTE.text
		-- selection reads by shape, not by brightness: the rail fills the row, the
		-- outline closes around it and the label steps in
		entry.rail.Size = active and UDim2.fromOffset(4, 34) or UDim2.fromOffset(3, 14)
		entry.rail.Position = active and UDim2.fromOffset(0, 0) or UDim2.fromOffset(0, 10)
		entry.rail.BackgroundTransparency = active and 0 or 0.25
		entry.label.Position = active and UDim2.fromOffset(18, 0) or UDim2.fromOffset(14, 0)
		entry.stroke.Color = id == targetTab and PALETTE.accent or (active and PALETTE.bg or PALETTE.text)
		entry.stroke.Thickness = id == targetTab and 1.8 or (active and 1.6 or 1)
		entry.stroke.Transparency = id == targetTab and 0.05 or (active and 0.25 or 0.85)
		entry.label.Text = id:upper()
		local badgeCount = 0
		if id == "Quests" then
			badgeCount = claimable
		elseif id == "Research" then
			for _, node in ipairs(state.research or {}) do
				if node.canBuy then
					badgeCount += 1
				end
			end
		elseif id == "Shop" then
			badgeCount = #(state.boosts or {})
		end
		entry.badge.Visible = badgeCount > 0
		entry.badgeText.Text = tostring(badgeCount)
	end

	-- zone presentation reacts to travel, not to every payload
	if state.zone and state.zone ~= lastZoneSeen then
		local firstView = lastZoneSeen ~= nil
		lastZoneSeen = state.zone
		if firstView then
			flashTravel(state.zoneName, state.zone, zoneColor(state.zone))
		else
			showZoneBanner(state.zoneName, state.zone, zoneColor(state.zone))
		end
	end
	-- cheap now: the object references are cached and unchanged values are skipped
	syncWorldLabels()

	if not menuOpen then
		return
	end
	-- a payload every half second must not rebuild 200 labels: refresh the open tab
	-- at most about twice a second, and always right after the player acts
	if not immediate and activeTab == lastTabRendered and os.clock() - lastContentBuild < 1.2 then
		return
	end
	lastContentBuild = os.clock()

	local scrollY = contentScroll.CanvasPosition.Y
	clearScroll()
	contentTitle.Text = string.upper(activeTab)
	contentTitle.TextColor3 = (tabButtons[activeTab] and tabButtons[activeTab].color) or PALETTE.accent
	contentSub.Text = ""

	if activeTab == "Summon" then
		renderSummon()
	elseif activeTab == "Crew" then
		renderCrew()
	elseif activeTab == "Pets" then
		renderPets()
	elseif activeTab == "Research" then
		renderResearch()
	elseif activeTab == "Rebirth" then
		renderRebirth()
	elseif activeTab == "Shop" then
		renderShop()
	elseif activeTab == "Quests" then
		renderQuests()
	elseif activeTab == "Index" then
		renderIndex()
	elseif activeTab == "Weather" then
		renderWeather()
	elseif activeTab == "Trade" then
		renderTrade()
	elseif activeTab == "Guide" then
		renderGuide()
	end
	contentScroll.CanvasPosition = Vector2.new(0, scrollY)

	if activeTab ~= lastTabRendered then
		lastTabRendered = activeTab
		if menuOpen then
			contentArea.GroupTransparency = 0.5
			TweenService:Create(contentArea, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
		end
	end

end

-- companion rigs + movement toggle -------------------------------------------
-- Pets are owner-only: the client builds a couple of anchored parts per pet and
-- moves each rig with a single PivotTo per frame, so they cost no replication.
local petFolder = create("Folder", { Name = "LocalPets" }, workspace)
local petRigs = {}
local petBuildKey = nil

local function petPart(parent, size, cframe, color)
	return create("Part", {
		Anchored = true,
		CanCollide = false,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
		Color = color,
		Size = size,
		CFrame = cframe,
	}, parent)
end

local function buildPetRig(pet)
	local model = Instance.new("Model")
	model.Name = "Pet_" .. pet.id
	local color = pet.color
	local body = petPart(model, Vector3.new(1.7, 1.5, 2.0), CFrame.new(0, 0, 0), color)
	model.PrimaryPart = body
	petPart(model, Vector3.new(1.4, 1.2, 1.2), CFrame.new(0, 0.62, -1.15), color:Lerp(Color3.fromRGB(255, 255, 255), 0.18))
	petPart(model, Vector3.new(0.45, 0.45, 1.3), CFrame.new(0, 0.28, 1.34) * CFrame.Angles(math.rad(12), 0, 0), color:Lerp(Color3.fromRGB(255, 255, 255), 0.08))
	for side = -1, 1, 2 do
		petPart(model, Vector3.new(0.5, 0.7, 0.4), CFrame.new(side * 0.72, -0.55, -0.5), color:Lerp(Color3.fromRGB(0, 0, 0), 0.16))
		petPart(model, Vector3.new(0.16, 0.16, 0.08), CFrame.new(side * 0.34, 0.72, -1.72), Color3.fromRGB(30, 34, 50))
	end
	local shape = pet.shape
	if shape == "cat" or shape == "fox" or shape == "beast" or shape == "dragon" then
		for side = -1, 1, 2 do
			petPart(model, Vector3.new(0.26, 0.55, 0.14), CFrame.new(side * 0.38, 1.28, -1.08) * CFrame.Angles(0, 0, math.rad(side * 14)), color)
		end
	end
	if shape == "bird" or shape == "dragon" or shape == "celestial" then
		for side = -1, 1, 2 do
			petPart(model, Vector3.new(0.9, 0.1, 0.7), CFrame.new(side * 1.25, 0.45, -0.1) * CFrame.Angles(0, 0, math.rad(side * 22)), color:Lerp(Color3.fromRGB(255, 255, 255), 0.32))
		end
	end
	if shape == "celestial" or shape == "moon" then
		petPart(model, Vector3.new(1.1, 0.1, 1.1), CFrame.new(0, 1.38, -1.15), Color3.fromRGB(255, 236, 170))
	end
	return model
end

local function syncPets()
	if not settings.petsVisible then
		if petBuildKey ~= "" then
			petBuildKey = ""
			petRigs = {}
			for _, model in ipairs(petFolder:GetChildren()) do
				model:Destroy()
			end
		end
		return
	end
	local pets = state and state.pets
	if not pets then
		return
	end
	local equipped = {}
	local key = ""
	for _, pet in ipairs(pets.list) do
		if pet.equipped then
			equipped[#equipped + 1] = pet
			key ..= pet.id .. ":" .. pet.level .. ","
		end
	end
	if key == petBuildKey then
		return
	end
	petBuildKey = key
	for _, model in ipairs(petFolder:GetChildren()) do
		model:Destroy()
	end
	petRigs = {}
	local count = #equipped
	for index, pet in ipairs(equipped) do
		local model = buildPetRig(pet)
		model.Parent = petFolder
		petRigs[#petRigs + 1] = {
			model = model,
			side = (index - 1) - (count - 1) / 2,
			phase = index * 1.7,
			current = nil,
		}
	end
end

applyPets = function()
	petBuildKey = nil
	syncPets()
end

player.CharacterAdded:Connect(function()
	for _, rig in ipairs(petRigs) do
		rig.current = nil
	end
end)

RunService.Heartbeat:Connect(function(delta)
	if not settings.petsVisible or #petRigs == 0 then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local clock = os.clock()
	-- 5.2/s gives roughly a fifth of a second of trail: the pet is always a step
	-- behind the player, never welded to the hip
	local follow = 1 - math.exp(-delta * 5.2)
	for _, rig in ipairs(petRigs) do
		if rig.model.Parent then
			local bob = math.sin(clock * 1.9 + rig.phase) * 0.22
			local drift = math.sin(clock * 0.85 + rig.phase) * 0.55
			-- +Z is behind the character: its body faces -Z
			local target = root.CFrame * CFrame.new(
				rig.side * 2.7 + drift,
				-0.55 + bob,
				4.6 + math.cos(clock * 1.1 + rig.phase) * 0.35
			) * CFrame.Angles(0, math.sin(clock * 1.2 + rig.phase) * 0.14, 0)
			if rig.current then
				rig.current = rig.current:Lerp(target, follow)
			else
				rig.current = target
			end
			rig.model:PivotTo(rig.current)
		end
	end
end)

local RUN_SPEED, WALK_SPEED = 20, 8
local running = true
local speedChip = create("TextButton", {
	Name = "SpeedChip",
	BackgroundColor3 = PALETTE.panel,
	BorderSizePixel = 0,
	Text = "RUN  [X]",
	TextColor3 = PALETTE.good,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	Size = UDim2.fromOffset(104, 26),
	Position = UDim2.fromOffset(16, 64),
	AnchorPoint = Vector2.new(0, 0),
}, screen)
corner(speedChip, 8)
stroke(speedChip, PALETTE.good, 1, 0.45)

local function applySpeed()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = running and RUN_SPEED or WALK_SPEED
	end
	speedChip.Text = running and "RUN  [X]" or "WALK  [X]"
	speedChip.TextColor3 = running and PALETTE.good or PALETTE.accent
end

local function toggleSpeed()
	running = not running
	applySpeed()
	toast(running and "Running" or "Walking", "ok")
end

hudWidgets[#hudWidgets + 1] = speedChip
speedChip.Visible = settings.hudVisible and not menuOpen
speedChip.MouseButton1Click:Connect(toggleSpeed)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.X then
		toggleSpeed()
	end
end)
player.CharacterAdded:Connect(function()
	task.wait(0.4)
	applySpeed()
end)
applySpeed()

-- events ---------------------------------------------------------------------
weatherChip.MouseButton1Click:Connect(function()
	activeTab = "Weather"
	setMenu(true)
	render()
end)

helpButton.MouseButton1Click:Connect(function()
	activeTab = "Guide"
	setMenu(true)
	render()
end)

local lastComboCount = 0
local shakeAmount = 0

StateRemote.OnClientEvent:Connect(function(newState)
	local count = (newState.combo and newState.combo.count) or 0
	-- light pushes omit the roster; keep the one already on screen
	if newState.units == nil then
		newState.units = (state and state.units) or {}
	end
	state = newState
	-- a saved settings block only applies on the first payload: after that the
	-- local panel is the source of truth so a push cannot undo a click
	if not settingsTouched and newState.settings then
		local saved = newState.settings
		if QUALITY_PRESETS[saved.quality] then
			settings.quality = saved.quality
		end
		settings.petsVisible = saved.petsVisible ~= false
		settings.hudVisible = saved.hudVisible == true
		applyQuality(settings.quality)
		refreshSettingsPanels()
		if applyHud then
			applyHud()
		end
	end
	syncPets()
	render()
	if count > lastComboCount and count >= 2 then
		shakeAmount = math.min(1, shakeAmount + 0.45)
		popLabel(comboLabel, 11, 2)
		comboScale.Scale = 1.14
		TweenService:Create(comboScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	lastComboCount = count
end)

NotifyRemote.OnClientEvent:Connect(function(message, kind)
	toast(message, kind)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, _, purchased)
	if purchased then
		send("RequestState")
		toast("Gamepass activated - perks are live.", "gacha")
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		setMenu(not menuOpen)
	elseif input.KeyCode == Enum.KeyCode.Escape then
		if dialogueOpen then
			closeDialogue()
		elseif gameSettings.frame.Visible then
			gameSettings.close()
		elseif adminOpen and adminPanel then
			adminOpen = false
			adminPanel.Visible = false
		elseif menuOpen then
			setMenu(false)
		end
	end
end)

-- camera nudge on combo build, decays on its own
RunService:BindToRenderStep("MineFeedback", Enum.RenderPriority.Camera.Value + 1, function(delta)
	if shakeAmount <= 0.001 then
		return
	end
	shakeAmount = math.max(0, shakeAmount - delta * 3.4)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local amount = shakeAmount * 0.5
		humanoid.CameraOffset = Vector3.new(
			(math.random() - 0.5) * amount,
			(math.random() - 0.5) * amount,
			0
		)
		if shakeAmount <= 0.001 then
			humanoid.CameraOffset = Vector3.new(0, 0, 0)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.15)
		updateGuideArrow()
	end
end)

-- the map can replicate after the first payload, so retry the label pass
-- occasionally; it is a handful of comparisons now, not a scene walk
task.spawn(function()
	while true do
		task.wait(3)
		syncWorldLabels()
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if state and state.weather then
			state.weather.timeLeft = math.max(0, state.weather.timeLeft - 1)
			weatherLabel.Text = state.weather.name .. "  ·  " .. math.floor(state.weather.timeLeft) .. "s"
		end
		if state and state.boosts then
			for _, boost in ipairs(state.boosts) do
				boost.timeLeft = math.max(0, boost.timeLeft - 1)
				local label = boostLabels[boost.id]
				if label and label.Parent then
					label.Text = math.ceil(boost.timeLeft) .. "s"
				end
			end
		end
		if state and state.combo and state.combo.timeLeft > 0 then
			state.combo.timeLeft = math.max(0, state.combo.timeLeft - 1)
			if state.combo.timeLeft <= 0 or state.combo.count < 2 then
				comboCard.Visible = false
			end
		end
	end
end)

-- move the finished HUD onto the canvas; full-screen layers and the automation
-- hooks stay on the ScreenGui so they keep covering the whole viewport
local fullScreenLayers = { StarLayer = true, TravelFade = true }
for _, child in ipairs(screen:GetChildren()) do
	if child ~= canvas and not fullScreenLayers[child.Name] and not child:IsA("BindableEvent") and not child:IsA("BindableFunction") then
		child.Parent = canvas
	end
end

-- automation hooks: let the playtest drive the same code paths as clicks
local menuControl = create("BindableEvent", { Name = "MenuControl" }, screen)
menuControl.Event:Connect(function(open)
	setMenu(open == true)
end)

local tabControl = create("BindableFunction", { Name = "TabControl" }, screen)
tabControl.OnInvoke = function(tabName)
	if tabButtons[tabName] then
		activeTab = tabName
		render()
		return true
	end
	return false
end

-- collapse hook for automation: fold/unfold the control room and read it back
local collapseControl = create("BindableFunction", { Name = "CollapseControl" }, screen)
collapseControl.OnInvoke = function(collapsed)
	setMenuCollapsed(collapsed ~= false)
	return tostring(menuCollapsed) .. "|" .. tostring(math.floor(panel.Size.Y.Offset)) .. "|" .. tostring(sidebar.Visible) .. "|" .. tostring(contentArea.Visible)
end

-- settings hook for automation: set a tier/toggle and read the effect back
local settingsControl = create("BindableFunction", { Name = "SettingsControl" }, screen)
settingsControl.OnInvoke = function(action, value)
	if action == "quality" and QUALITY_PRESETS[value] then
		setSetting("quality", value)
	elseif action == "pets" then
		setSetting("petsVisible", value ~= false)
	elseif action == "hud" then
		setSetting("hudVisible", value ~= false)
	end
	local emittersOff, lightsOff = 0, 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ParticleEmitter") and not inst.Enabled then
			emittersOff += 1
		elseif inst:IsA("Light") and not inst.Enabled then
			lightsOff += 1
		end
	end
	return string.format("quality=%s pets=%s hud=%s shadows=%s emittersOff=%d lightsOff=%d",
		settings.quality, tostring(settings.petsVisible), tostring(settings.hudVisible),
		tostring(Lighting.GlobalShadows), emittersOff, lightsOff)
end

-- dev panel hook for automation: builds the panel so its reset flow can be
-- checked without a mouse, and can close it again
local adminControl = create("BindableFunction", { Name = "AdminControl" }, screen)
adminControl.OnInvoke = function(action)
	buildAdminPanel()
	if action == "open" then
		adminOpen = true
		adminPanel.Visible = true
		if state then
			adminRefs.coins.Text = tostring(state.coins) .. " coins"
			adminRefs.gems.Text = tostring(state.gems) .. " gems"
			adminRefs.level.Text = "Miner Lv " .. tostring(state.level or 1)
		end
	elseif action == "close" then
		adminOpen = false
		adminPanel.Visible = false
	end
	return adminOpen and "open" or "closed"
end

task.delay(3, function()
	if not state then
		send("RequestState")
	end
end)

print("[AnimeMiner] Client UI ready")
