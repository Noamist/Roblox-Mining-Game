--!strict
-- Anime Miner Tycoon :: procedural world construction
-- Builds a full map: town hub on the surface, six sealed cavern biomes below,
-- clustered ore models with health bars, treasure caches, props and lighting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local WorldBuilder = {}

local CAVERN = 158
local CAVERN_HEIGHT = 64
local ORE_GRID = 5
local ORE_SPACING = 21

local function basePart(class, props, parent)
	local inst = Instance.new(class)
	inst.Anchored = true
	inst.CanCollide = true
	inst.TopSurface = Enum.SurfaceType.Smooth
	inst.BottomSurface = Enum.SurfaceType.Smooth
	inst.Material = Enum.Material.Slate
	-- geometry-only shadows: the map is decorative and shadow casting here is the
	-- single biggest render cost on low-end devices
	inst.CastShadow = false
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function block(parent, size, cframe, color, material, canCollide)
	return basePart("Part", {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.Slate,
		CanCollide = canCollide ~= false,
	}, parent)
end

local function disc(parent, positionOrY, radius, thickness, color, material)
	local position = positionOrY
	if type(position) == "number" then
		position = Vector3.new(0, positionOrY, 0)
	end
	local p = basePart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		Color = color,
		Material = material or Enum.Material.Neon,
	}, parent)
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

local function cylinderPart(parent, size, cframe, color, material)
	local p = basePart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
	p.CFrame = cframe
	return p
end

local function ballPart(parent, size, cframe, color, material, transparency)
	return basePart("Part", {
		Shape = Enum.PartType.Ball,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
	}, parent)
end

local function spike(parent, size, cframe, color, transparency)
	local p = basePart("Part", {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency or 0.08,
		CanCollide = false,
	}, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Pyramid
	mesh.Parent = p
	return p
end

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = inst
	return c
end

local function addLight(parentPart, color, range, brightness)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range * 0.8
	light.Brightness = brightness * 0.5
	light.Shadows = false
	light.Parent = parentPart
	return light
end

local function sparkles(parentPart, color, rate, speed)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Transparency = NumberSequence.new(0.55, 1)
	emitter.Lifetime = NumberRange.new(0.7, 1.5)
	emitter.Rate = (rate or 6) * 0.55
	emitter.Speed = NumberRange.new(0.5, speed or 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.2
	emitter.Parent = parentPart
	return emitter
end

local function sign(adornee, titleText, subtitleText, width, height, titleColor, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(width or 420, height or 110)
	gui.StudsOffset = Vector3.new(0, offsetY or 6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.Parent = adornee

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, subtitleText and 0.62 or 1, 0)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextColor3 = titleColor or Color3.fromRGB(240, 245, 255)
	title.TextStrokeTransparency = 0.2
	title.TextStrokeColor3 = Color3.fromRGB(10, 14, 30)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Parent = gui

	if subtitleText then
		local sub = Instance.new("TextLabel")
		sub.Position = UDim2.fromScale(0, 0.64)
		sub.Size = UDim2.new(1, 0, 0.34, 0)
		sub.BackgroundTransparency = 1
		sub.Text = subtitleText
		sub.TextColor3 = Color3.fromRGB(190, 210, 240)
		sub.TextStrokeTransparency = 0.6
		sub.Font = Enum.Font.GothamMedium
		sub.Name = "SubLabel"
		sub.TextScaled = true
		sub.Parent = gui
	end
	return gui
end

function WorldBuilder.StyleLighting()
	Lighting.Ambient = Color3.fromRGB(58, 66, 92)
	Lighting.OutdoorAmbient = Color3.fromRGB(74, 84, 112)
	Lighting.Brightness = 1.3
	Lighting.ClockTime = 17.6
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.25
	Lighting.EnvironmentSpecularScale = 0.4

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("ColorCorrectionEffect")
			or child:IsA("SunRaysEffect") or child:IsA("DepthOfFieldEffect") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.44
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(176, 190, 216)
	atmosphere.Decay = Color3.fromRGB(78, 94, 136)
	atmosphere.Glare = 0.12
	atmosphere.Haze = 2.4
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 20
	bloom.Threshold = 1.15
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.12
	color.Contrast = 0.06
	color.Brightness = -0.03
	color.TintColor = Color3.fromRGB(250, 248, 255)
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.04
	rays.Spread = 0.8
	rays.Parent = Lighting
end

-- ore ------------------------------------------------------------------------
local oreMeta: { [Model]: any } = {}

WorldBuilder.OreMeta = oreMeta

local function record(partsList, part)
	partsList[#partsList + 1] = {
		part = part,
		size = part.Size,
		cframe = part.CFrame,
		alpha = part.Transparency,
		collide = part.CanCollide,
	}
	return part
end

local function addHealthBar(core, zone)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(100, 13)
	gui.StudsOffset = Vector3.new(0, 7.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 260
	gui.Enabled = false
	gui.Parent = core

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
	bg.BackgroundTransparency = 0.12
	bg.BorderSizePixel = 0
	bg.Parent = gui
	corner(bg, 5)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = zone.accent
	fill.BorderSizePixel = 0
	fill.Parent = bg
	corner(fill, 5)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Thickness = 1
	stroke.Parent = fill

	return gui, fill
end

local function buildOre(zone, position, name, gemNode)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Zone", zone.id)
	model:SetAttribute("MaxHP", zone.blockHp)
	model:SetAttribute("HP", zone.blockHp)
	model:SetAttribute("Alive", true)
	model:SetAttribute("GemNode", gemNode == true)
	-- rich veins are the mid-session jackpot: a gold node that pays triple and
	-- always drops a couple of gems, so clearing a cavern is worth more than
	-- clicking the nearest rock over and over
	local rich = gemNode ~= true and math.random() < 0.15
	model:SetAttribute("Rich", rich)

	local parts = {}

	local core = basePart("Part", {
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(10.5, 8.4, 10.5),
		CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0),
		Color = zone.blockColor:Lerp(Color3.fromRGB(18, 20, 30), 0.55),
		Material = Enum.Material.Slate,
	}, model)
	core:SetAttribute("Zone", zone.id)
	core:SetAttribute("Alive", true)
	core:SetAttribute("MaxHP", zone.blockHp)
	core:SetAttribute("HP", zone.blockHp)
	record(parts, core)

	-- stone shoulders so the cluster reads as a rock, not a ball
	for index = 1, 3 do
		local angle = math.rad(index * 120 + math.random(-25, 25))
		local rock = basePart("Part", {
			Name = "Rock" .. index,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4.6, 3.2, 4.6),
			CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * 4.4, -0.6 + math.random() * 1.2, math.sin(angle) * 4.4))
				* CFrame.Angles(math.rad(math.random(-20, 20)), angle, math.rad(math.random(-20, 20))),
			Color = zone.blockColor:Lerp(Color3.fromRGB(30, 32, 44), 0.68),
			Material = Enum.Material.Slate,
			CanCollide = false,
		}, model)
		record(parts, rock)
	end

	local shardColor = gemNode and Color3.fromRGB(225, 236, 255) or (rich and Color3.fromRGB(255, 216, 132) or zone.blockColor:Lerp(Color3.fromRGB(255, 255, 255), 0.12))
	local shardCount = gemNode and 6 or 4 + math.random(0, 2)
	for index = 1, shardCount do
		local angle = (index / shardCount) * math.pi * 2 + math.random() * 0.5
		local radius = 2.6 + math.random() * 2.4
		local height = (gemNode and 6.5 or 4.2) + math.random() * 3.4
		local shard = spike(model, Vector3.new(1.9, height, 1.9), CFrame.new(
			position + Vector3.new(math.cos(angle) * radius, 2.1 + height * 0.4, math.sin(angle) * radius)
		) * CFrame.Angles(math.rad(math.random(-18, 18)), angle, math.rad(math.random(-18, 18))), shardColor, 0.26)
		shard.Name = "Shard" .. index
		record(parts, shard)
	end

	if gemNode then
		addLight(core, Color3.fromRGB(255, 245, 255), 18, 0.6)
	end

	if rich then
		local ring = disc(model, Vector3.new(position.x, position.y - 4.3, position.z), 7.6, 0.25, Color3.fromRGB(255, 208, 128), Enum.Material.Neon)
		ring.Name = "RichRing"
		ring.Transparency = 0.3
		ring.CanCollide = false
		addLight(core, Color3.fromRGB(255, 205, 120), 16, 0.45)
		sign(core, "RICH VEIN  x3", nil, 150, 30, Color3.fromRGB(255, 224, 150), 10.2).MaxDistance = 58
	end

	-- idle ore must not simulate particles: gem nodes keep a slow shimmer, plain
	-- ore sparkles only when it is actually hit (MiningService emits on damage)
	local emitter = sparkles(core, zone.blockColor, gemNode and 6 or 0, 3)
	local barGui, barFill = addHealthBar(core, zone)

	local light = core:FindFirstChildOfClass("PointLight")
	-- one invisible hit sphere instead of a detector on every rock and shard: the
	-- click ray meets the sphere first, so mining feels identical with 8x fewer
	-- click detectors to track on every client
	local hitbox = basePart("Part", {
		Name = "Hitbox",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(17, 15, 17),
		CFrame = CFrame.new(position + Vector3.new(0, 2, 0)),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	}, model)
	local detector = Instance.new("ClickDetector")
	detector.Name = "MineClick"
	detector.MaxActivationDistance = 80
	detector.Parent = hitbox

	model.Parent = zone.folder

	oreMeta[model] = {
		parts = parts,
		core = core,
		bar = barGui,
		fill = barFill,
		emitter = emitter,
		light = light,
		zoneId = zone.id,
	}

	return model
end

-- treasure -------------------------------------------------------------------
local function buildChest(zone, position, index)
	local model = Instance.new("Model")
	model.Name = "Chest_" .. zone.id .. "_" .. index
	model:SetAttribute("Zone", zone.id)

	local base = basePart("Part", {
		Name = "Base",
		Size = Vector3.new(6.4, 3.4, 4.6),
		CFrame = CFrame.new(position),
		Color = Color3.fromRGB(92, 60, 34),
		Material = Enum.Material.WoodPlanks,
	}, model)

	local lid = basePart("Part", {
		Name = "Lid",
		Size = Vector3.new(6.7, 1.4, 4.9),
		CFrame = CFrame.new(position + Vector3.new(0, 2.2, 0)),
		Color = Color3.fromRGB(122, 82, 44),
		Material = Enum.Material.WoodPlanks,
	}, model)

	for side = -1, 1, 2 do
		block(model, Vector3.new(0.22, 3.8, 4.9),
			CFrame.new(position + Vector3.new(side * 3.32, 0.2, 0)),
			Color3.fromRGB(240, 200, 120), Enum.Material.Neon, false)
	end

	local lock = block(model, Vector3.new(1.4, 1.6, 0.5),
		CFrame.new(position + Vector3.new(0, 0.5, 2.56)),
		Color3.fromRGB(255, 226, 150), Enum.Material.Neon, false)
	lock.Name = "Lock"

	addLight(lid, Color3.fromRGB(255, 205, 120), 24, 1.4)
	sparkles(lid, Color3.fromRGB(255, 220, 140), 5, 2)

	local label = sign(base, "CACHE", nil, 100, 28, Color3.fromRGB(255, 224, 150), 4.6)
	label.MaxDistance = 60

	local chestHitbox = basePart("Part", {
		Name = "Hitbox",
		Size = Vector3.new(8, 7, 7),
		CFrame = CFrame.new(position + Vector3.new(0, 1.4, 0)),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	}, model)
	local chestDetector = Instance.new("ClickDetector")
	chestDetector.Name = "ChestClick"
	chestDetector.MaxActivationDistance = 40
	chestDetector.Parent = chestHitbox

	model.Parent = zone.folder

	return {
		model = model,
		zoneId = zone.id,
		base = base,
		lid = lid,
		lock = lock,
		label = label,
	}
end

-- props ----------------------------------------------------------------------
local function buildProp(zone, position, parent, index)
	local kind = zone.prop
	local color = zone.propColor
	-- light every other prop: half the point lights, the ring still reads lit
	local lit = ((index or 1) % 2) == 1

	if kind == "crystal" then
		for shardIndex = 1, 4 do
			local height = 6 + math.random() * 9
			spike(parent, Vector3.new(1.6 + math.random(), height, 1.6 + math.random()),
				CFrame.new(position + Vector3.new(math.random(-4, 4), height * 0.42, math.random(-4, 4)))
					* CFrame.Angles(math.rad(math.random(-12, 12)), math.random() * 6, math.rad(math.random(-12, 12))),
				color, 0.25)
		end
		ballPart(parent, Vector3.new(3, 3, 3), CFrame.new(position), color, Enum.Material.Neon, 0.35)
		if lit then
			addLight(ballPart(parent, Vector3.new(1, 1, 1), CFrame.new(position + Vector3.new(0, 6, 0)), color, Enum.Material.Neon, 1), color, 30, 1.2)
		end
	elseif kind == "lava" then
		disc(parent, Vector3.new(position.x, position.y - 0.8, position.z), 9 + math.random() * 2, 1, Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
		local pool = disc(parent, Vector3.new(position.x, position.y - 0.55, position.z), 6.5 + math.random() * 2, 1.1, Color3.fromRGB(255, 170, 70), Enum.Material.Neon)
		if lit then
			addLight(pool, Color3.fromRGB(255, 140, 60), 30, 1.2)
		end
		for rockIndex = 1, 4 do
			local angle = rockIndex / 4 * math.pi * 2
			local rockHeight = 5 + math.random() * 4
			spike(parent, Vector3.new(2.4, rockHeight, 2.4),
				CFrame.new(position + Vector3.new(math.cos(angle) * 11, rockHeight * 0.45, math.sin(angle) * 11))
					* CFrame.Angles(0, angle, 0),
				Color3.fromRGB(70, 34, 32), 0)
		end
	elseif kind == "ice" then
		for shardIndex = 1, 5 do
			local height = 7 + math.random() * 12
			spike(parent, Vector3.new(2 + math.random() * 1.4, height, 2 + math.random() * 1.4),
				CFrame.new(position + Vector3.new(math.random(-6, 6), height * 0.45, math.random(-6, 6)))
					* CFrame.Angles(math.rad(math.random(-16, 16)), math.random() * 6, math.rad(math.random(-16, 16))),
				color, 0.35)
		end
		local glow = ballPart(parent, Vector3.new(2, 2, 2), CFrame.new(position + Vector3.new(0, 1.6, 0)), color, Enum.Material.Neon, 0.5)
		if lit then
			addLight(glow, color, 26, 0.9)
		end
	elseif kind == "void" then
		local obelisk = block(parent, Vector3.new(3.4, 16, 3.4), CFrame.new(position + Vector3.new(0, 7.4, 0)), Color3.fromRGB(38, 24, 60), Enum.Material.Slate, false)
		block(parent, Vector3.new(4.2, 0.8, 4.2), CFrame.new(position + Vector3.new(0, 15.4, 0)), color, Enum.Material.Neon, false)
		local ring = basePart("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 12, 12),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, parent)
		ring.CFrame = CFrame.new(position + Vector3.new(0, 9.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.4
		if lit then
			addLight(obelisk, color, 30, 1.2)
		end
	elseif kind == "gold" then
		local pillar = cylinderPart(parent, Vector3.new(14, 2.6, 2.6), CFrame.new(position + Vector3.new(0, 6.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 96, 54), Enum.Material.Metal)
		pillar.Name = "Pillar"
		local orb = ballPart(parent, Vector3.new(3.4, 3.4, 3.4), CFrame.new(position + Vector3.new(0, 8.8, 0)), color, Enum.Material.Neon, 0.15)
		if lit then
			addLight(orb, color, 34, 1.5)
		end
		sparkles(orb, color, 8, 2)
		disc(parent, Vector3.new(position.x, position.y - 0.55, position.z), 8, 1, color, Enum.Material.Neon)
	end

	-- common base plate so props sit on the floor
	if kind ~= "lava" then
		disc(parent, Vector3.new(position.x, position.y - 0.55, position.z), 6.5, 1, zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.2), Enum.Material.Slate)
	end
end

-- npcs ----------------------------------------------------------------------
local function buildNpc(parent, config)
	local model = Instance.new("Model")
	model.Name = "Npc_" .. config.id
	model:SetAttribute("Role", config.role)
	model.Parent = parent

	local root = basePart("Part", {
		Name = "NpcRoot",
		Size = Vector3.new(1.4, 1, 1.4),
		CFrame = CFrame.new(config.position) * CFrame.Angles(0, math.rad(config.facing or 0), 0),
		Transparency = 1,
		CanCollide = false,
	}, model)

	local accent = config.accent or Color3.fromRGB(255, 205, 130)
	local robe = config.robe or Color3.fromRGB(58, 66, 104)

	local function piece(name, size, rel, color, material, shape)
		local p = basePart("Part", {
			Name = name,
			Size = size,
			CFrame = root.CFrame * rel,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Shape = shape,
			CanCollide = false,
		}, model)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	piece("Skirt", Vector3.new(2.7, 2.6, 1.7), CFrame.new(0, -1.0, 0), robe, Enum.Material.Fabric)
	piece("Torso", Vector3.new(2.9, 2.2, 1.7), CFrame.new(0, 1.35, 0), robe:Lerp(Color3.fromRGB(255, 255, 255), 0.1), Enum.Material.Fabric)
	piece("Sash", Vector3.new(3.0, 0.45, 1.78), CFrame.new(0, 0.75, 0), accent, Enum.Material.Fabric)
	piece("Collar", Vector3.new(2.3, 0.42, 1.6), CFrame.new(0, 2.42, 0), accent:Lerp(Color3.fromRGB(255, 255, 255), 0.25), Enum.Material.Fabric)
	piece("ArmL", Vector3.new(0.72, 2.1, 0.72), CFrame.new(-1.6, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-9)), robe:Lerp(Color3.fromRGB(20, 22, 32), 0.2), Enum.Material.Fabric)
	piece("ArmR", Vector3.new(0.72, 2.1, 0.72), CFrame.new(1.6, 1.3, 0) * CFrame.Angles(0, 0, math.rad(9)), robe:Lerp(Color3.fromRGB(20, 22, 32), 0.2), Enum.Material.Fabric)
	piece("HandL", Vector3.new(0.5, 0.5, 0.5), CFrame.new(-1.68, 0.25, 0), Color3.fromRGB(255, 224, 202), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	piece("HandR", Vector3.new(0.5, 0.5, 0.5), CFrame.new(1.68, 0.25, 0), Color3.fromRGB(255, 224, 202), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	piece("Head", Vector3.new(2.1, 2.1, 2.1), CFrame.new(0, 3.5, 0), Color3.fromRGB(255, 226, 205), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	piece("Hair", Vector3.new(2.3, 1.6, 2.3), CFrame.new(0, 3.95, 0.12), config.hair or Color3.fromRGB(42, 38, 56), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	piece("EyeL", Vector3.new(0.26, 0.34, 0.12), CFrame.new(-0.4, 3.55, -1.02), Color3.fromRGB(32, 34, 50))
	piece("EyeR", Vector3.new(0.26, 0.34, 0.12), CFrame.new(0.4, 3.55, -1.02), Color3.fromRGB(32, 34, 50))
	piece("Mouth", Vector3.new(0.26, 0.07, 0.1), CFrame.new(0, 3.16, -1.02), Color3.fromRGB(130, 78, 84))

	if config.kind == "guild" then
		piece("HatBrim", Vector3.new(3.4, 0.22, 3.4), CFrame.new(0, 4.28, 0), Color3.fromRGB(46, 40, 60), Enum.Material.Fabric)
		piece("HatCrown", Vector3.new(2.0, 1.1, 2.0), CFrame.new(0, 4.8, 0), Color3.fromRGB(58, 50, 78), Enum.Material.Fabric)
	elseif config.kind == "smith" then
		piece("Apron", Vector3.new(2.2, 2.2, 0.2), CFrame.new(0, 0.9, -0.88), Color3.fromRGB(74, 52, 36), Enum.Material.Fabric)
		piece("HammerHandle", Vector3.new(0.16, 1.8, 0.16), CFrame.new(1.9, 0.9, -0.4) * CFrame.Angles(math.rad(20), 0, math.rad(-18)), Color3.fromRGB(120, 84, 52), Enum.Material.Wood)
		piece("HammerHead", Vector3.new(1.0, 0.55, 0.55), CFrame.new(1.78, 1.75, -0.5), Color3.fromRGB(150, 158, 180), Enum.Material.Metal)
	elseif config.kind == "merchant" then
		piece("Cap", Vector3.new(2.2, 0.5, 2.2), CFrame.new(0, 4.3, 0), accent, Enum.Material.Fabric)
		piece("Pack", Vector3.new(1.8, 1.6, 0.9), CFrame.new(0, 1.4, 0.95), Color3.fromRGB(96, 70, 46), Enum.Material.Fabric)
	elseif config.kind == "prospector" then
		piece("Helmet", Vector3.new(2.3, 1.0, 2.3), CFrame.new(0, 4.2, 0), Color3.fromRGB(120, 104, 66), Enum.Material.Metal)
		local lamp = piece("Lamp", Vector3.new(0.55, 0.7, 0.55), CFrame.new(0, 4.7, -1.05), accent, Enum.Material.Neon)
		addLight(lamp, accent, 22, 0.9)
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "NpcTag"
	gui.Size = UDim2.fromOffset(140, 26)
	gui.StudsOffset = Vector3.new(0, 5.0, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 58
	gui.Parent = root

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.56)
	title.BackgroundTransparency = 1
	title.Text = config.role
	title.TextColor3 = accent
	title.TextStrokeColor3 = Color3.fromRGB(8, 10, 18)
	title.TextStrokeTransparency = 0.25
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Parent = gui

	-- one invisible click volume instead of a detector on every limb: the click
	-- ray meets this first, so talking to an NPC is unchanged for the player but
	-- the world carries one detector instead of a couple of dozen
	local npcHitbox = basePart("Part", {
		Name = "NpcHitbox",
		Size = Vector3.new(7.5, 9, 7.5),
		CFrame = root.CFrame * CFrame.new(0, 2.2, 0),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	}, model)
	local detector = Instance.new("ClickDetector")
	detector.Name = "NpcClick"
	detector.MaxActivationDistance = 26
	detector:SetAttribute("Line", config.line)
	detector:SetAttribute("NpcId", config.id)
	detector.Parent = npcHitbox

	return model
end

-- hub ------------------------------------------------------------------------
local function buildHub(root)
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = root

	local plazaColor = Color3.fromRGB(40, 48, 76)
	block(hub, Vector3.new(196, 6, 196), CFrame.new(0, -3, 0), plazaColor, Enum.Material.Slate)
	block(hub, Vector3.new(200, 1.2, 200), CFrame.new(0, -0.4, 0), Color3.fromRGB(90, 130, 210), Enum.Material.SmoothPlastic, false)

	-- glowing plaza inlays
	for _, offset in ipairs({ -60, -20, 20, 60 }) do
		block(hub, Vector3.new(190, 0.5, 1.6), CFrame.new(0, 0.2, offset), Color3.fromRGB(56, 96, 150), Enum.Material.Neon, false)
		block(hub, Vector3.new(1.6, 0.5, 190), CFrame.new(offset, 0.2, 0), Color3.fromRGB(56, 96, 150), Enum.Material.Neon, false)
	end

	-- sunburst paving: twelve slate wedges give the plaza a floor pattern that
	-- reads from spawn without adding collision or a single extra instance kind
	for index = 1, 12 do
		local angle = (index - 1) / 12 * math.pi * 2
		local plate = block(hub, Vector3.new(16, 0.22, 6.4),
			CFrame.new(math.cos(angle) * 32, 0.06, math.sin(angle) * 32) * CFrame.Angles(0, -angle, 0),
			Color3.fromRGB(52, 66, 104), Enum.Material.Slate, false)
		plate.Name = "Paving"
	end

	-- crystal planters and benches soften the plaza corners
	for index, spot in ipairs({ Vector2.new(46, 46), Vector2.new(-46, 46), Vector2.new(46, -46), Vector2.new(-46, -46) }) do
		local planter = Instance.new("Model")
		planter.Name = "Planter"
		planter.Parent = hub
		block(planter, Vector3.new(7, 2, 7), CFrame.new(spot.X, 1, spot.Y), Color3.fromRGB(58, 66, 96), Enum.Material.Slate)
		block(planter, Vector3.new(5.6, 0.5, 5.6), CFrame.new(spot.X, 2.1, spot.Y), Color3.fromRGB(48, 40, 34), Enum.Material.Ground)
		for shard = 1, 3 do
			local height = 4 + shard * 1.4
			spike(planter, Vector3.new(1.3, height, 1.3),
				CFrame.new(spot.X + (shard - 2) * 1.7, 2.4 + height * 0.4, spot.Y + ((shard % 2) * 2 - 1) * 1.2)
					* CFrame.Angles(math.rad(-8), shard * 1.7, math.rad(9)),
				Color3.fromRGB(140, 210, 255), 0.3)
		end
		if index % 2 == 1 then
			local glow = ballPart(planter, Vector3.new(1.2, 1.2, 1.2), CFrame.new(spot.X, 7.4, spot.Y), Color3.fromRGB(170, 225, 255), Enum.Material.Neon, 0.2)
			addLight(glow, Color3.fromRGB(160, 215, 255), 20, 0.7)
		end
	end

	for _, seat in ipairs({ { x = -26, z = 10, facing = 90 }, { x = 26, z = 10, facing = -90 } }) do
		local bench = Instance.new("Model")
		bench.Name = "Bench"
		bench.Parent = hub
		local base = CFrame.new(seat.x, 0.9, seat.z) * CFrame.Angles(0, math.rad(seat.facing), 0)
		block(bench, Vector3.new(8, 0.5, 2.2), base, Color3.fromRGB(96, 70, 48), Enum.Material.WoodPlanks)
		block(bench, Vector3.new(8, 1.6, 0.4), base * CFrame.new(0, 0.9, 0.9), Color3.fromRGB(82, 60, 42), Enum.Material.WoodPlanks)
		for _, side in ipairs({ -3.2, 3.2 }) do
			block(bench, Vector3.new(0.5, 1.0, 2.0), base * CFrame.new(side, -0.6, 0), Color3.fromRGB(60, 62, 82), Enum.Material.Metal)
		end
	end
	disc(hub, 1, 22, 2.4, Color3.fromRGB(70, 84, 128), Enum.Material.Slate)
	disc(hub, 1.6, 16, 1.2, Color3.fromRGB(120, 210, 255), Enum.Material.Neon)
	local fountainPillar = cylinderPart(hub, Vector3.new(10, 3.2, 3.2), CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 92, 138), Enum.Material.Slate)
	local fountainOrb = ballPart(hub, Vector3.new(4.4, 4.4, 4.4), CFrame.new(0, 7.3, 0), Color3.fromRGB(150, 230, 255), Enum.Material.Neon, 0.2)
	fountainOrb.Name = "FountainOrb"
	addLight(fountainPillar, Color3.fromRGB(140, 220, 255), 50, 1.2)

	-- spawn pad
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(26, 1.2, 26)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(140, 225, 255)
	spawn.Position = Vector3.new(0, 0.6, 42)
	spawn.Transparency = 0.15
	spawn.Parent = hub
	sign(spawn, "SPAWN", nil, 150, 36, Color3.fromRGB(190, 240, 255), 6).MaxDistance = 80

	-- gate
	for _, side in ipairs({ -1, 1 }) do
		block(hub, Vector3.new(7, 26, 7), CFrame.new(side * 26, 13, 86), Color3.fromRGB(56, 64, 100), Enum.Material.Slate)
		block(hub, Vector3.new(8, 1.6, 8), CFrame.new(side * 26, 26, 86), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, false)
	end
	block(hub, Vector3.new(60, 3.4, 7), CFrame.new(0, 27, 86), Color3.fromRGB(56, 64, 100), Enum.Material.Slate)
	block(hub, Vector3.new(60, 1, 1), CFrame.new(0, 24.6, 89.6), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, false)
	local gateSign = Instance.new("Part")
	gateSign.Name = "GateSign"
	gateSign.Anchored = true
	gateSign.CanCollide = false
	gateSign.Transparency = 1
	gateSign.Size = Vector3.new(1, 1, 1)
	gateSign.Position = Vector3.new(0, 33, 86)
	gateSign.Parent = hub
	sign(gateSign, Config.TITLE, nil, 360, 78, Color3.fromRGB(255, 240, 250), 0).MaxDistance = 150
	addLight(block(hub, Vector3.new(1, 1, 1), CFrame.new(0, 26, 86), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, false), Color3.fromRGB(120, 200, 255), 60, 1.6)

	-- guild hall (left): a hollow building with a walk-in doorway, not a solid box
	local guild = Instance.new("Folder")
	guild.Name = "GuildHall"
	guild.Parent = hub

	block(guild, Vector3.new(46, 1, 34), CFrame.new(-62, 0.7, -28), Color3.fromRGB(44, 50, 80), Enum.Material.Slate)
	block(guild, Vector3.new(46, 2, 34), CFrame.new(-62, 23.6, -28), Color3.fromRGB(64, 72, 112), Enum.Material.Slate)
	block(guild, Vector3.new(46, 24, 2), CFrame.new(-62, 12, -44), Color3.fromRGB(50, 56, 92), Enum.Material.Slate)
	block(guild, Vector3.new(2, 24, 34), CFrame.new(-84, 12, -28), Color3.fromRGB(50, 56, 92), Enum.Material.Slate)
	block(guild, Vector3.new(2, 24, 34), CFrame.new(-40, 12, -28), Color3.fromRGB(50, 56, 92), Enum.Material.Slate)
	block(guild, Vector3.new(16, 24, 2), CFrame.new(-77, 12, -11), Color3.fromRGB(50, 56, 92), Enum.Material.Slate)
	block(guild, Vector3.new(16, 24, 2), CFrame.new(-47, 12, -11), Color3.fromRGB(50, 56, 92), Enum.Material.Slate)
	block(guild, Vector3.new(14, 7, 2), CFrame.new(-62, 21, -11), Color3.fromRGB(54, 60, 98), Enum.Material.Slate)

	for _, x in ipairs({ -69, -55 }) do
		block(guild, Vector3.new(0.8, 14, 2.6), CFrame.new(x, 7.2, -10.8), Color3.fromRGB(255, 205, 120), Enum.Material.Neon, false)
	end
	block(guild, Vector3.new(14.8, 0.8, 2.6), CFrame.new(-62, 14.4, -10.8), Color3.fromRGB(255, 205, 120), Enum.Material.Neon, false)
	block(guild, Vector3.new(14, 0.3, 6), CFrame.new(-62, 1.15, -7.6), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, false)

	block(guild, Vector3.new(26, 1.4, 6), CFrame.new(-62, 2.4, -38), Color3.fromRGB(70, 60, 96), Enum.Material.WoodPlanks)
	block(guild, Vector3.new(26, 0.5, 6.4), CFrame.new(-62, 3.2, -38), Color3.fromRGB(255, 210, 130), Enum.Material.Neon, false)
	for _, side in ipairs({ -1, 1 }) do
		block(guild, Vector3.new(0.6, 12, 5), CFrame.new(-62 + side * 15, 9, -43), Color3.fromRGB(72, 80, 130), Enum.Material.Fabric, false)
		block(guild, Vector3.new(0.8, 1.4, 5.2), CFrame.new(-62 + side * 15, 14.2, -43), Color3.fromRGB(255, 205, 120), Enum.Material.Neon, false)
		block(guild, Vector3.new(1.2, 7, 1.2), CFrame.new(-62 + side * 19, 3.5, -20), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, false)
	end
	-- roof ridge, finials, lit windows, steps and door braziers
	block(guild, Vector3.new(48, 1.2, 3), CFrame.new(-62, 24.8, -28), Color3.fromRGB(84, 92, 132), Enum.Material.Slate)
	block(guild, Vector3.new(48, 0.5, 0.5), CFrame.new(-62, 24.2, -10.8), Color3.fromRGB(255, 205, 120), Enum.Material.Neon, false)
	for _, side in ipairs({ -1, 1 }) do
		block(guild, Vector3.new(0.9, 2.6, 0.9), CFrame.new(-62 + side * 23.5, 26.9, -28), Color3.fromRGB(255, 205, 120), Enum.Material.Neon, false)
	end
	for _, x in ipairs({ -77, -47 }) do
		block(guild, Vector3.new(6, 9, 0.4), CFrame.new(x, 9, -9.95), Color3.fromRGB(46, 54, 84), Enum.Material.Slate, false)
		local glass = block(guild, Vector3.new(4.6, 7.4, 0.24), CFrame.new(x, 9, -9.8), Color3.fromRGB(255, 214, 150), Enum.Material.Neon, false)
		glass.Name = "Window"
		glass.Transparency = 0.25
		block(guild, Vector3.new(0.3, 7.4, 0.3), CFrame.new(x, 9, -9.7), Color3.fromRGB(46, 54, 84), Enum.Material.Slate, false)
	end
	for step = 1, 2 do
		block(guild, Vector3.new(18, 0.6, 2.4), CFrame.new(-62, 0.3 + (3 - step) * 0.4, -9 + step * 1.5), Color3.fromRGB(64, 72, 104), Enum.Material.Slate)
	end
	for _, side in ipairs({ -1, 1 }) do
		cylinderPart(guild, Vector3.new(1.8, 1.2, 1.2), CFrame.new(-62 + side * 8, 2.2, -8.4) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(84, 74, 60), Enum.Material.Metal)
		local flame = ballPart(guild, Vector3.new(1.6, 2.2, 1.6), CFrame.new(-62 + side * 8, 3.7, -8.4), Color3.fromRGB(255, 180, 110), Enum.Material.Neon, 0.15)
		flame.Name = "BrazierFlame"
		addLight(flame, Color3.fromRGB(255, 180, 110), 26, 1)
	end

	local guildLight = block(guild, Vector3.new(1, 1, 1), CFrame.new(-62, 12, -28), Color3.fromRGB(255, 210, 140), Enum.Material.Neon, false)
	guildLight.Transparency = 1
	addLight(guildLight, Color3.fromRGB(255, 210, 140), 46, 1.4)
	local guildSignPart = block(guild, Vector3.new(1, 1, 1), CFrame.new(-62, 28.5, -9), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, false)
	guildSignPart.Transparency = 1
	sign(guildSignPart, "HERO GUILD", nil, 220, 52, Color3.fromRGB(255, 220, 150), 0).MaxDistance = 100

	-- market (right): open-front arcade you can walk into
	local market = Instance.new("Folder")
	market.Name = "Market"
	market.Parent = hub

	block(market, Vector3.new(42, 1, 30), CFrame.new(62, 0.7, -30), Color3.fromRGB(48, 52, 78), Enum.Material.WoodPlanks)
	block(market, Vector3.new(46, 1.6, 34), CFrame.new(62, 18.6, -30), Color3.fromRGB(84, 96, 134), Enum.Material.Slate)
	block(market, Vector3.new(42, 18, 2), CFrame.new(62, 9, -44), Color3.fromRGB(56, 66, 96), Enum.Material.Slate)
	block(market, Vector3.new(2, 18, 30), CFrame.new(42, 9, -30), Color3.fromRGB(56, 66, 96), Enum.Material.Slate)
	block(market, Vector3.new(2, 18, 30), CFrame.new(82, 9, -30), Color3.fromRGB(56, 66, 96), Enum.Material.Slate)
	for _, x in ipairs({ 45, 56, 68, 79 }) do
		block(market, Vector3.new(2.2, 18, 2.2), CFrame.new(x, 9, -15.5), Color3.fromRGB(66, 76, 112), Enum.Material.Slate)
	end
	block(market, Vector3.new(42, 1, 3), CFrame.new(62, 17.6, -15), Color3.fromRGB(255, 190, 120), Enum.Material.Neon, false)
	block(market, Vector3.new(38, 1.2, 8), CFrame.new(62, 2.4, -38), Color3.fromRGB(92, 66, 44), Enum.Material.WoodPlanks)
	block(market, Vector3.new(38, 0.4, 8.4), CFrame.new(62, 3.2, -38), Color3.fromRGB(255, 200, 130), Enum.Material.Neon, false)
	local marketLight = block(market, Vector3.new(1, 1, 1), CFrame.new(62, 10, -30), Color3.fromRGB(255, 220, 170), Enum.Material.Neon, false)
	marketLight.Transparency = 1
	addLight(marketLight, Color3.fromRGB(255, 214, 160), 44, 1.3)

	-- kiosks flank the entrance so the doorway stays clear
	for _, x in ipairs({ 50, 74 }) do
		block(market, Vector3.new(10, 3.4, 4), CFrame.new(x, 1.7, -9), Color3.fromRGB(120, 84, 48), Enum.Material.WoodPlanks)
		block(market, Vector3.new(0.4, 5.8, 0.4), CFrame.new(x - 4.6, 2.9, -11), Color3.fromRGB(96, 74, 50), Enum.Material.Wood)
		block(market, Vector3.new(0.4, 5.8, 0.4), CFrame.new(x + 4.6, 2.9, -11), Color3.fromRGB(96, 74, 50), Enum.Material.Wood)
		block(market, Vector3.new(11, 0.4, 5), CFrame.new(x, 5.8, -9.3), Color3.fromRGB(255, 190, 120), Enum.Material.Neon, false)
	end

	-- striped awnings, hanging lanterns and stock crates dress the arcade front
	for index, x in ipairs({ 50.5, 62, 73.5 }) do
		local awningColor = index % 2 == 1 and Color3.fromRGB(255, 196, 132) or Color3.fromRGB(196, 226, 255)
		local awning = block(market, Vector3.new(10.6, 0.4, 7.4), CFrame.new(x, 16.2, -12.4) * CFrame.Angles(math.rad(14), 0, 0), awningColor, Enum.Material.Fabric, false)
		awning.Name = "Awning"
	end
	for _, x in ipairs({ 50, 62, 74 }) do
		local lantern = ballPart(market, Vector3.new(1.6, 1.6, 1.6), CFrame.new(x, 15.2, -15), Color3.fromRGB(255, 206, 148), Enum.Material.Neon, 0.2)
		lantern.Name = "MarketLantern"
		addLight(lantern, Color3.fromRGB(255, 200, 140), 20, 0.7)
	end
	for _, spot in ipairs({ { x = 47, z = -6 }, { x = 77, z = -6 }, { x = 57, z = -20 } }) do
		local crate = block(market, Vector3.new(2.4, 2.4, 2.4), CFrame.new(spot.x, 1.2, spot.z), Color3.fromRGB(112, 80, 48), Enum.Material.WoodPlanks)
		crate.Name = "Crate"
		if spot.z == -6 then
			local barrel = cylinderPart(market, Vector3.new(2.6, 2.2, 2.2), CFrame.new(spot.x + 2.2, 1.1, spot.z + 1.4) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(96, 68, 44), Enum.Material.WoodPlanks)
			barrel.Name = "Barrel"
		end
	end
	-- roof ridge and vents so the hall reads as a building from the plaza
	block(market, Vector3.new(47, 0.8, 2.4), CFrame.new(62, 19.8, -30), Color3.fromRGB(96, 108, 150), Enum.Material.Slate)
	for _, spot in ipairs({ { x = 50, z = -40 }, { x = 74, z = -24 } }) do
		block(market, Vector3.new(2.4, 4, 2.4), CFrame.new(spot.x, 21.4, spot.z), Color3.fromRGB(70, 78, 110), Enum.Material.Slate)
		block(market, Vector3.new(3, 0.6, 3), CFrame.new(spot.x, 23.6, spot.z), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, false)
	end
	local marketSignPart = block(market, Vector3.new(1, 1, 1), CFrame.new(62, 22, -13), Color3.fromRGB(255, 240, 220), Enum.Material.Neon, false)
	marketSignPart.Transparency = 1
	sign(marketSignPart, "GEM MARKET", nil, 210, 50, Color3.fromRGB(255, 200, 220), 0).MaxDistance = 100

	-- statues around the plaza
	for index, config in ipairs({
		{ x = -34, z = 26, color = Color3.fromRGB(255, 140, 90) },
		{ x = 34, z = 26, color = Color3.fromRGB(120, 200, 255) },
		{ x = -34, z = -56, color = Color3.fromRGB(180, 130, 255) },
		{ x = 34, z = -56, color = Color3.fromRGB(255, 220, 130) },
	}) do
		block(hub, Vector3.new(10, 3, 10), CFrame.new(config.x, 1.5, config.z), Color3.fromRGB(62, 70, 106), Enum.Material.Slate)
		block(hub, Vector3.new(4.4, 5.4, 2.8), CFrame.new(config.x, 5.6, config.z), Color3.fromRGB(84, 92, 132), Enum.Material.Slate)
		block(hub, Vector3.new(7, 1.1, 2.8), CFrame.new(config.x, 8.5, config.z), Color3.fromRGB(78, 86, 124), Enum.Material.Slate)
		block(hub, Vector3.new(1.8, 3.2, 1.8), CFrame.new(config.x, 3.1, config.z), Color3.fromRGB(84, 92, 132), Enum.Material.Slate)
		ballPart(hub, Vector3.new(3.4, 3.4, 3.4), CFrame.new(config.x, 10.4, config.z), Color3.fromRGB(190, 196, 214), Enum.Material.SmoothPlastic, 0)
		block(hub, Vector3.new(0.9, 10, 0.9), CFrame.new(config.x + 5.8, 5, config.z), Color3.fromRGB(70, 78, 112), Enum.Material.Metal)
		local statueLight = ballPart(hub, Vector3.new(1.6, 1.6, 1.6), CFrame.new(config.x + 5.8, 10.2, config.z), config.color, Enum.Material.Neon, 0.15)
		statueLight.Name = "StatueOrb"
		addLight(statueLight, config.color, 24, 0.6)
	end

	-- lampposts, with the portal row's skyline deliberately left clear
	for lampIndex = 1, 8 do
		local angle = (lampIndex / 8) * math.pi * 2
		local degrees = math.deg(angle) % 360
		local x = math.cos(angle) * 88
		local z = math.sin(angle) * 88
		-- skip the arc that would put a lamp inside the Hall of Records, which
		-- fills the east side of the plaza
		local clearOfHall = not (x > 60 and z > -12 and z < 46)
		if (degrees <= 28 or degrees >= 152) and clearOfHall then
			block(hub, Vector3.new(1.6, 16, 1.6), CFrame.new(x, 8, z), Color3.fromRGB(64, 72, 110), Enum.Material.Metal)
			local lamp = ballPart(hub, Vector3.new(3.4, 3.4, 3.4), CFrame.new(x, 17, z), Color3.fromRGB(180, 225, 255), Enum.Material.Neon, 0.1)
			addLight(lamp, Color3.fromRGB(170, 220, 255), 34, 1.1)
		end
	end

	-- crystal trees, kept clear of the gate, buildings and lamps
	for _, spot in ipairs({
		Vector2.new(92, 62),
		Vector2.new(-92, 62),
		Vector2.new(92, -62),
		Vector2.new(-92, -62),
		Vector2.new(45, -90),
		Vector2.new(-45, -90),
	}) do
		local trunk = cylinderPart(hub, Vector3.new(13, 2.2, 2.2), CFrame.new(spot.X, 6.5, spot.Y) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(82, 62, 48), Enum.Material.Wood)
		trunk.Name = "TreeTrunk"
		local crown = ballPart(hub, Vector3.new(8.4, 6.4, 8.4), CFrame.new(spot.X, 15, spot.Y), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, 0.45)
		crown.Name = "TreeTop"
		local inner = ballPart(hub, Vector3.new(5.4, 4.6, 5.4), CFrame.new(spot.X + 2, 18.4, spot.Y - 1), Color3.fromRGB(150, 230, 255), Enum.Material.Neon, 0.6)
		inner.Name = "TreeTop"
	end

	-- depth shaft monument (cosmetic descent beacon)
	disc(hub, 0.6, 20, 1.6, Color3.fromRGB(90, 200, 255), Enum.Material.Neon)
	local beacon = block(hub, Vector3.new(9, 34, 9), CFrame.new(0, 17, -58), Color3.fromRGB(46, 52, 84), Enum.Material.Slate, true)
	beacon.Name = "ShaftBeacon"
	for ring = 1, 6 do
		local ringPart = block(hub, Vector3.new(11, 0.8, 11), CFrame.new(0, ring * 5, -58), Color3.fromRGB(120, 210, 255), Enum.Material.Neon, false)
		ringPart.Name = "BeaconRing"
	end
	ballPart(hub, Vector3.new(5, 5, 5), CFrame.new(0, 36, -58), Color3.fromRGB(160, 235, 255), Enum.Material.Neon, 0.2)
	addLight(ballPart(hub, Vector3.new(1, 1, 1), CFrame.new(0, 30, -58), Color3.fromRGB(140, 220, 255), Enum.Material.Neon, 1), Color3.fromRGB(140, 220, 255), 70, 2)
	sign(beacon, "THE DEEP SHAFT", nil, 190, 46, Color3.fromRGB(190, 235, 255), 24).MaxDistance = 120

	-- depth board listing every biome
	local board = block(hub, Vector3.new(30, 16, 1.2), CFrame.new(0, 8, -30), Color3.fromRGB(30, 36, 60), Enum.Material.Slate)
	board.Name = "DepthBoard"
	sign(board, "BIOME CHART", nil, 180, 44, Color3.fromRGB(255, 240, 200), 10).MaxDistance = 95

	-- townsfolk, one in each building plus two on the plaza ---------------------
	buildNpc(hub, {
		id = "guildmaster", kind = "guild", role = "GUILD MASTER",
		position = Vector3.new(-62, 2.55, -34), facing = 180,
		accent = Color3.fromRGB(255, 208, 128), robe = Color3.fromRGB(62, 56, 108),
		hair = Color3.fromRGB(226, 214, 190),
		line = "GUILD MASTER: Summon heroes, deploy the best ones, then let them dig while you explore.",
	})
	buildNpc(hub, {
		id = "merchant", kind = "merchant", role = "GEM MERCHANT",
		position = Vector3.new(62, 2.55, -35), facing = 180,
		accent = Color3.fromRGB(235, 150, 205), robe = Color3.fromRGB(64, 78, 108),
		line = "GEM MERCHANT: Gems buy boosts and mutation dice. A Coin Surge pays itself back fast.",
	})
	buildNpc(hub, {
		id = "smith", kind = "smith", role = "FORGE MASTER",
		position = Vector3.new(-64, 2.55, 24), facing = 135,
		accent = Color3.fromRGB(255, 176, 96), robe = Color3.fromRGB(70, 56, 46),
		line = "FORGE MASTER: Every pickaxe level is +30% swing damage. Click the anvil behind me.",
	})
	buildNpc(hub, {
		id = "prospector", kind = "prospector", role = "PROSPECTOR",
		position = Vector3.new(26, 2.55, 50), facing = 180,
		accent = Color3.fromRGB(150, 220, 255), robe = Color3.fromRGB(52, 70, 96),
		line = "PROSPECTOR: Each gate asks for a Miner Lv. Break ore to level up, then walk through.",
	})
	-- hall of records (global leaderboard) --------------------------------------
	-- The display panel is the front-most surface of the whole model: the support
	-- posts stand behind it so the board never sits inside a pillar.
	local records = Instance.new("Model")
	records.Name = "HallOfRecords"
	records.Parent = hub
	block(records, Vector3.new(22, 2, 46), CFrame.new(86, 1, 18), Color3.fromRGB(44, 52, 82), Enum.Material.Slate)
	block(records, Vector3.new(24, 0.6, 46), CFrame.new(86, 2.2, 18), Color3.fromRGB(96, 148, 214), Enum.Material.Neon, false)
	for _, offset in ipairs({ -21, 21 }) do
		local post = block(records, Vector3.new(2.6, 22, 2.6), CFrame.new(90.6, 13, 18 + offset), Color3.fromRGB(62, 72, 110), Enum.Material.Slate)
		post.Name = "RecordPost"
		block(records, Vector3.new(2.9, 1, 2.9), CFrame.new(90.6, 24.4, 18 + offset), Color3.fromRGB(132, 198, 250), Enum.Material.Neon, false)
	end
	block(records, Vector3.new(7.6, 2, 48), CFrame.new(90.4, 25.6, 18), Color3.fromRGB(56, 64, 100), Enum.Material.Slate)
	block(records, Vector3.new(0.8, 0.8, 48), CFrame.new(86.4, 24.6, 18), Color3.fromRGB(132, 198, 250), Enum.Material.Neon, false)
	local board = block(records, Vector3.new(1.4, 21, 40), CFrame.new(87.6, 13.6, 18), Color3.fromRGB(16, 20, 34), Enum.Material.Slate)
	board.Name = "LeaderboardBoard"
	block(records, Vector3.new(3.4, 1.6, 42), CFrame.new(87.6, 2.6, 18), Color3.fromRGB(62, 72, 110), Enum.Material.Slate)
	for _, zOffset in ipairs({ -2, 38 }) do
		block(records, Vector3.new(0.8, 6, 0.8), CFrame.new(75.8, 5, zOffset), Color3.fromRGB(64, 72, 110), Enum.Material.Metal)
		local lamp = ballPart(records, Vector3.new(2.2, 2.2, 2.2), CFrame.new(75.8, 8.6, zOffset), Color3.fromRGB(132, 198, 250), Enum.Material.Neon, 0.15)
		lamp.Name = "RecordLantern"
		addLight(lamp, Color3.fromRGB(132, 198, 250), 22, 0.8)
	end
	local boardLight = block(records, Vector3.new(1, 1, 1), CFrame.new(84, 14, 18), Color3.fromRGB(132, 198, 250), Enum.Material.Neon, false)
	boardLight.Transparency = 1
	addLight(boardLight, Color3.fromRGB(132, 198, 250), 46, 1.2)

	-- trait shrine ---------------------------------------------------------------
	local shrine = Instance.new("Model")
	shrine.Name = "TraitShrine"
	shrine.Parent = hub
	block(shrine, Vector3.new(24, 2, 26), CFrame.new(-86, 1, 18), Color3.fromRGB(46, 42, 72), Enum.Material.Slate)
	disc(shrine, Vector3.new(-86, 2.4, 18), 9, 0.7, Color3.fromRGB(150, 110, 220), Enum.Material.Neon)
	for _, offset in ipairs({ { -9, -10 }, { 9, -10 }, { -9, 10 }, { 9, 10 } }) do
		block(shrine, Vector3.new(1.8, 15, 1.8), CFrame.new(-86 + offset[1], 9, 18 + offset[2]), Color3.fromRGB(64, 58, 104), Enum.Material.Slate)
		local cap = block(shrine, Vector3.new(2.3, 1, 2.3), CFrame.new(-86 + offset[1], 16.8, 18 + offset[2]), Color3.fromRGB(212, 168, 255), Enum.Material.Neon, false)
		cap.Name = "ShrineCap"
	end
	block(shrine, Vector3.new(24, 1.6, 26), CFrame.new(-86, 18.4, 18), Color3.fromRGB(58, 50, 96), Enum.Material.Slate)
	local shrineOrb = ballPart(shrine, Vector3.new(4, 4, 4), CFrame.new(-86, 14, 18), Color3.fromRGB(212, 168, 255), Enum.Material.Neon, 0.15)
	shrineOrb.Name = "ShrineOrb"
	addLight(shrineOrb, Color3.fromRGB(212, 168, 255), 40, 1.4)
	sparkles(shrineOrb, Color3.fromRGB(212, 168, 255), 7, 2)

	buildNpc(hub, {
		id = "seer", kind = "guild", role = "TRAIT SEER",
		position = Vector3.new(-86, 2.55, 12), facing = 0,
		accent = Color3.fromRGB(212, 168, 255), robe = Color3.fromRGB(66, 54, 104),
		hair = Color3.fromRGB(232, 226, 255),
		line = "TRAIT SEER: Every hero carries a fate rolled before they arrived.",
	})

	buildNpc(hub, {
		id = "villager", kind = "villager", role = "TOWNSFOLK",
		position = Vector3.new(30, 2.55, 34), facing = 41,
		accent = Color3.fromRGB(180, 230, 200), robe = Color3.fromRGB(58, 84, 78),
		line = "TOWNSFOLK: Deeper ore pays more. Every biome has a descend pad at the far end.",
	})

	return hub
end

-- portals -------------------------------------------------------------------
-- One gate per biome, lined up in front of spawn. Each gate keeps its own
-- orbiting rune ring so the row reads as six working portals, and the label
-- states the miner level the server will check on click.
local function buildGate(folder, zone, x, z)
	local gate = Instance.new("Folder")
	gate.Name = "Gate_" .. zone.id
	gate:SetAttribute("Zone", zone.id)
	gate:SetAttribute("LevelReq", zone.levelReq or 1)
	gate.Parent = folder

	disc(gate, Vector3.new(x, 0.8, z), 12.4, 1.4, zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.12), Enum.Material.Slate)
	disc(gate, Vector3.new(x, 1.55, z), 9.6, 0.35, zone.accent, Enum.Material.Neon)

	for side = -1, 1, 2 do
		block(gate, Vector3.new(3.2, 20, 3.2), CFrame.new(x + side * 9.8, 11, z), zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.08), Enum.Material.Slate)
		block(gate, Vector3.new(3.5, 1.2, 3.5), CFrame.new(x + side * 9.8, 21.4, z), zone.accent, Enum.Material.Neon, false)
	end
	block(gate, Vector3.new(23, 2.4, 3.2), CFrame.new(x, 22, z), zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.08), Enum.Material.Slate)

	local plane = block(gate, Vector3.new(17.6, 18.4, 0.7), CFrame.new(x, 11.4, z), zone.blockColor:Lerp(Color3.fromRGB(18, 22, 36), 0.4), Enum.Material.Neon, false)
	plane.Name = "PortalPlane"
	plane.Transparency = 0.55
	addLight(plane, zone.accent, 32, 1.1)
	sparkles(plane, zone.accent, 9, 2.4)

	-- orbiting rune ring: runes are welded to a pivot, the pivot is animated
	local pivot = basePart("Part", {
		Name = "PortalPivot",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(x, 11.4, z - 1.4),
		Transparency = 1,
		CanCollide = false,
	}, gate)
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		local rune = basePart("Part", {
			Name = "PortalRune",
			Size = Vector3.new(0.9, 0.9, 0.4),				CFrame = pivot.CFrame * CFrame.new(math.cos(angle) * 6.4, math.sin(angle) * 6.7, 0) * CFrame.Angles(0, 0, angle),
			Color = zone.accent,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			CanCollide = false,
		}, gate)
		rune.Parent = pivot
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pivot
		weld.Part1 = rune
		weld.Parent = rune
	end

	local labelPart = basePart("Part", {
		Name = "GateLabel",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(x, 27.4, z),
		Transparency = 1,
		CanCollide = false,
	}, gate)
	sign(labelPart, zone.name:upper(), nil, 160, 36, zone.accent, 0).MaxDistance = 90

	-- a single click volume over the arch; the detector name and the target zone
	-- are unchanged, so the click travel path in MiningService stays the same
	local gateHitbox = basePart("Part", {
		Name = "GateHitbox",
		Size = Vector3.new(17, 30, 9),
		CFrame = CFrame.new(x, 14, z),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	}, gate)
	gateHitbox:SetAttribute("Zone", zone.id)
	local detector = Instance.new("ClickDetector")
	detector.Name = "DescendClick"
	detector.MaxActivationDistance = 50
	detector.Parent = gateHitbox

	return gate
end

local function buildPortal(root)
	local folder = Instance.new("Folder")
	folder.Name = "Portal"
	folder.Parent = root

	local count = #Config.Zones
	local spacing = 26
	for index, zone in ipairs(Config.Zones) do
		buildGate(folder, zone, (index - (count + 1) / 2) * spacing, 62)
	end

	return folder
end

-- stations ------------------------------------------------------------------
local function buildStations(root)
	local folder = Instance.new("Folder")
	folder.Name = "Stations"
	folder.Parent = root

	-- pickaxe forge
	local forgeBase = block(folder, Vector3.new(15, 3, 15), CFrame.new(-70, 1.5, 30), Color3.fromRGB(54, 60, 92), Enum.Material.Slate)
	block(folder, Vector3.new(15, 0.6, 15), CFrame.new(-70, 3.2, 30), Color3.fromRGB(70, 88, 130), Enum.Material.Neon, false)
	local anvil = block(folder, Vector3.new(9, 3.2, 4.4), CFrame.new(-70, 4.6, 30), Color3.fromRGB(74, 82, 112), Enum.Material.Metal)
	block(folder, Vector3.new(2.4, 1.2, 4.4), CFrame.new(-70, 6.8, 30), Color3.fromRGB(96, 104, 138), Enum.Material.Metal)
	block(folder, Vector3.new(1.2, 9, 1.2), CFrame.new(-63.5, 4.5, 25), Color3.fromRGB(96, 74, 50), Enum.Material.Wood)
	local hammerHead = block(folder, Vector3.new(3.6, 2.8, 3.6), CFrame.new(-63.5, 9.9, 25), Color3.fromRGB(226, 178, 100), Enum.Material.Neon, false)
	hammerHead.Name = "ForgeHammer"
	addLight(anvil, Color3.fromRGB(255, 170, 90), 34, 1.4)
	sign(forgeBase, "PICKAXE FORGE", nil, 190, 46, Color3.fromRGB(255, 205, 130), 9).MaxDistance = 90
	local forgeHitbox = basePart("Part", {
		Name = "ForgeHitbox",
		Size = Vector3.new(18, 11, 18),
		CFrame = CFrame.new(-70, 4.5, 30),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	}, folder)
	local forgeDetector = Instance.new("ClickDetector")
	forgeDetector.Name = "ForgeClick"
	forgeDetector.MaxActivationDistance = 35
	forgeDetector.Parent = forgeHitbox

	-- daily cache
	local dailyBase = block(folder, Vector3.new(9, 4, 6.4), CFrame.new(70, 2, 30), Color3.fromRGB(84, 56, 32), Enum.Material.WoodPlanks)
	block(folder, Vector3.new(9.4, 1.4, 6.8), CFrame.new(70, 4.7, 30), Color3.fromRGB(112, 76, 42), Enum.Material.WoodPlanks)
	for offset = -1, 1, 2 do
		block(folder, Vector3.new(9.6, 0.8, 0.8), CFrame.new(70, 2.4, 30 + offset * 2.6), Color3.fromRGB(236, 196, 110), Enum.Material.Neon, false)
	end
	local orb = ballPart(folder, Vector3.new(3, 3, 3), CFrame.new(70, 6.9, 30), Color3.fromRGB(255, 220, 140), Enum.Material.Neon, 0.25)
	orb.Name = "DailyOrb"
	addLight(orb, Color3.fromRGB(255, 210, 130), 30, 1.1)
	sparkles(orb, Color3.fromRGB(255, 220, 150), 6, 2)
	sign(dailyBase, "DAILY CACHE", nil, 170, 42, Color3.fromRGB(255, 220, 150), 6).MaxDistance = 90
	local dailyHitbox = basePart("Part", {
		Name = "DailyHitbox",
		Size = Vector3.new(14, 11, 12),
		CFrame = CFrame.new(70, 4.5, 30),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	}, folder)
	local dailyDetector = Instance.new("ClickDetector")
	dailyDetector.Name = "DailyClick"
	dailyDetector.MaxActivationDistance = 35
	dailyDetector.Parent = dailyHitbox

	return folder
end

-- return portal --------------------------------------------------------------
-- Mirror of the town gates, mirrored on the far side of every biome pad so you
-- can always walk back to spawn.
local function buildReturnGate(parent, zone, baseY)
	local gate = Instance.new("Model")
	gate.Name = "ReturnGate"
	gate:SetAttribute("Zone", 0)
	gate.Parent = parent

	local x, z = -48, -56
	local accent = Color3.fromRGB(150, 222, 255)

	disc(gate, Vector3.new(x, baseY + 4.4, z), 9.6, 1.2, zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.12), Enum.Material.Slate)
	disc(gate, Vector3.new(x, baseY + 5.0, z), 7.4, 0.3, accent, Enum.Material.Neon)

	for _, side in ipairs({ -1, 1 }) do
		block(gate, Vector3.new(2.6, 16, 2.6), CFrame.new(x + side * 7.6, baseY + 13.4, z), zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.05), Enum.Material.Slate)
		block(gate, Vector3.new(2.9, 1, 2.9), CFrame.new(x + side * 7.6, baseY + 21.6, z), accent, Enum.Material.Neon, false)
	end
	block(gate, Vector3.new(18.4, 2, 2.6), CFrame.new(x, baseY + 22.4, z), zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.05), Enum.Material.Slate)

	local plane = block(gate, Vector3.new(13.6, 14.8, 0.6), CFrame.new(x, baseY + 12.8, z), Color3.fromRGB(92, 164, 222), Enum.Material.Neon, false)
	plane.Name = "PortalPlane"
	plane.Transparency = 0.5
	addLight(plane, accent, 28, 1.1)
	sparkles(plane, accent, 8, 2.2)

	local pivot = basePart("Part", {
		Name = "PortalPivot",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(x, baseY + 12.8, z - 1.2),
		Transparency = 1,
		CanCollide = false,
	}, gate)
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		local rune = basePart("Part", {
			Name = "PortalRune",
			Size = Vector3.new(0.8, 0.8, 0.35),
			CFrame = pivot.CFrame * CFrame.new(math.cos(angle) * 5.2, math.sin(angle) * 5.5, 0) * CFrame.Angles(0, 0, angle),
			Color = accent,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			CanCollide = false,
		}, pivot)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pivot
		weld.Part1 = rune
		weld.Parent = rune
	end

	local labelPart = basePart("Part", {
		Name = "ReturnLabel",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(x, baseY + 27.4, z),
		Transparency = 1,
		CanCollide = false,
	}, gate)
	sign(labelPart, "TO TOWN", nil, 130, 34, accent, 0).MaxDistance = 80

	local returnHitbox = basePart("Part", {
		Name = "ReturnHitbox",
		Size = Vector3.new(17, 30, 9),
		CFrame = CFrame.new(x, baseY + 14, z),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	}, gate)
	returnHitbox:SetAttribute("Zone", 0)
	local detector = Instance.new("ClickDetector")
	detector.Name = "ReturnClick"
	detector.MaxActivationDistance = 40
	detector.Parent = returnHitbox

	return gate
end

-- zones ----------------------------------------------------------------------
local function buildZone(zone, zonesFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Zone_" .. zone.id
	folder.Parent = zonesFolder
	zone.folder = folder

	local baseY = zone.y

	-- floor and ceiling
	block(folder, Vector3.new(CAVERN, 8, CAVERN), CFrame.new(0, baseY, 0), zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.3), Enum.Material.Slate)
	block(folder, Vector3.new(CAVERN, 6, CAVERN), CFrame.new(0, baseY + CAVERN_HEIGHT, 0), zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.45), Enum.Material.Slate)

	-- walls
	local wallColor = zone.wallColor
	block(folder, Vector3.new(CAVERN, CAVERN_HEIGHT, 8), CFrame.new(0, baseY + CAVERN_HEIGHT / 2, -CAVERN / 2), wallColor, Enum.Material.Slate)
	block(folder, Vector3.new(CAVERN, CAVERN_HEIGHT, 8), CFrame.new(0, baseY + CAVERN_HEIGHT / 2, CAVERN / 2), wallColor, Enum.Material.Slate)
	block(folder, Vector3.new(8, CAVERN_HEIGHT, CAVERN), CFrame.new(-CAVERN / 2, baseY + CAVERN_HEIGHT / 2, 0), wallColor, Enum.Material.Slate)
	block(folder, Vector3.new(8, CAVERN_HEIGHT, CAVERN), CFrame.new(CAVERN / 2, baseY + CAVERN_HEIGHT / 2, 0), wallColor, Enum.Material.Slate)

	-- corner pillars
	for _, cornerPos in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
		block(folder, Vector3.new(10, CAVERN_HEIGHT, 10),
			CFrame.new(cornerPos[1] * (CAVERN / 2 - 14), baseY + CAVERN_HEIGHT / 2, cornerPos[2] * (CAVERN / 2 - 14)),
			wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.15), Enum.Material.Slate)
		block(folder, Vector3.new(11, 1.2, 11),
			CFrame.new(cornerPos[1] * (CAVERN / 2 - 14), baseY + 4.6, cornerPos[2] * (CAVERN / 2 - 14)),
			zone.accent, Enum.Material.Neon, false)
	end

	-- floor inlays
	block(folder, Vector3.new(CAVERN - 26, 0.8, 3), CFrame.new(0, baseY + 4.2, 0), zone.accent:Lerp(Color3.fromRGB(0, 0, 0), 0.45), Enum.Material.Neon, false)
	block(folder, Vector3.new(3, 0.8, CAVERN - 26), CFrame.new(0, baseY + 4.2, 0), zone.accent:Lerp(Color3.fromRGB(0, 0, 0), 0.45), Enum.Material.Neon, false)

	-- ceiling stalactites
	for stalactite = 1, 10 do
		local x = math.random(-CAVERN / 2 + 20, CAVERN / 2 - 20)
		local z = math.random(-CAVERN / 2 + 20, CAVERN / 2 - 20)
		local height = math.random(6, 14)
		spike(folder, Vector3.new(3.4, height, 3.4),
			CFrame.new(x, baseY + CAVERN_HEIGHT - height * 0.45, z) * CFrame.Angles(math.rad(180), 0, 0),
			wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.1), 0)
	end

	-- ambient dust
	local dustHolder = block(folder, Vector3.new(1, 1, 1), CFrame.new(0, baseY + 26, 0), zone.accent, Enum.Material.Neon, false)
	dustHolder.Transparency = 1
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(zone.accent)
	dust.Size = NumberSequence.new(0.22, 0)
	dust.Transparency = NumberSequence.new(0.5, 1)
	dust.Lifetime = NumberRange.new(3, 6)
	dust.Rate = 6
	dust.Speed = NumberRange.new(0.4, 1.4)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Acceleration = Vector3.new(0, -0.35, 0)
	dust.Parent = dustHolder

	-- main zone light
	local lightHolder = block(folder, Vector3.new(1, 1, 1), CFrame.new(0, baseY + 34, 0), zone.accent, Enum.Material.Neon, false)
	lightHolder.Transparency = 1
	addLight(lightHolder, zone.accent, 150, 1.5)

	-- arch + teleport pad
	local padZ = -CAVERN / 2 + 16
	local pad = basePart("Part", {
		Name = "Pad_" .. zone.id,
		Size = Vector3.new(18, 0.8, 18),
		CFrame = CFrame.new(0, baseY + 4.6, padZ),
		Color = zone.accent,
		Material = Enum.Material.Neon,
		CanCollide = true,
	}, folder)
	disc(folder, baseY + 4.4, 15, 0.8, zone.accent:Lerp(Color3.fromRGB(0, 0, 0), 0.35), Enum.Material.Neon)
	addLight(pad, zone.accent, 44, 1.4)

	-- descend pad to the next biome
	local descend = basePart("Part", {
		Name = "DescendPad_" .. zone.id,
		Size = Vector3.new(12, 0.6, 12),
		CFrame = CFrame.new(48, baseY + 4.4, -56),
		Color = zone.accent,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = true,
	}, folder)
	descend:SetAttribute("Zone", zone.id)
	local descendSign = basePart("Part", {
		Name = "DescendSign",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(48, baseY + 14, -56),
		Transparency = 1,
		CanCollide = false,
		Material = Enum.Material.SmoothPlastic,
	}, folder)
	sign(descendSign, "DESCEND", nil, 120, 32, zone.accent, 0).MaxDistance = 75
	local descendDetector = Instance.new("ClickDetector")
	descendDetector.Name = "DescendPadClick"
	descendDetector.MaxActivationDistance = 40
	descendDetector.Parent = descend

	for side = -1, 1, 2 do
		block(folder, Vector3.new(4, 20, 4), CFrame.new(side * 13, baseY + 14, padZ - 13), zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.2), Enum.Material.Slate)
	end
	block(folder, Vector3.new(30, 3, 4), CFrame.new(0, baseY + 25.5, padZ - 13), zone.wallColor:Lerp(Color3.fromRGB(0, 0, 0), 0.2), Enum.Material.Slate)
	local archStrip = block(folder, Vector3.new(30, 0.8, 0.8), CFrame.new(0, baseY + 24.1, padZ - 11.2), zone.accent:Lerp(Color3.fromRGB(0, 0, 0), 0.35), Enum.Material.Neon, false)
	archStrip.Name = "ArchStrip"
	local padSign = basePart("Part", {
		Name = "ZoneSign",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, baseY + 32, padZ - 13),
		Transparency = 1,
		CanCollide = false,
		Material = Enum.Material.SmoothPlastic,
	}, folder)
	sign(padSign, zone.name:upper(), nil, 190, 46, zone.accent, 0).MaxDistance = 110

	buildReturnGate(folder, zone, baseY)

	-- ore grid
	local oreList = {}
	local gemCount = 0
	for row = 1, ORE_GRID do
		for column = 1, ORE_GRID do
			local x = (column - (ORE_GRID + 1) / 2) * ORE_SPACING
			local z = (row - (ORE_GRID + 1) / 2) * ORE_SPACING + 10
			local isGem = (row * 3 + column) % 11 == 0
			if isGem then
				gemCount += 1
			end
			local ore = buildOre(zone, Vector3.new(x, baseY + 8.6, z), "Ore_" .. zone.id .. "_" .. row .. "_" .. column, isGem)
			oreList[#oreList + 1] = ore
		end
	end

	-- props ring around the mine floor, skipping anything that would clip an
	-- ore cluster, the landing pad or a chest
	local chestSpots = {
		Vector3.new(-64, baseY + 5.8, 0),
		Vector3.new(64, baseY + 5.8, 0),
	}
	local placed = 0
	for attempt = 1, 26 do
		if placed >= 8 then
			break
		end
		local angle = (placed / 8) * math.pi * 2 + 0.35 + attempt * 0.17
		local radius = 66 + math.random(-2, 2)
		local position = Vector3.new(math.cos(angle) * radius, baseY + 4.6, math.sin(angle) * radius)
		local clear = (position - Vector3.new(0, baseY + 4.6, -63)).Magnitude > 22
		if clear then
			for _, ore in ipairs(oreList) do
				if (position - ore:GetPivot().Position).Magnitude < 17 then
					clear = false
					break
				end
			end
		end
		if clear then
			for _, spot in ipairs(chestSpots) do
				if (position - spot).Magnitude < 16 then
					clear = false
					break
				end
			end
		end
		if clear then
			buildProp(zone, position, folder, placed + 1)
			placed += 1
		end
	end

	return folder, oreList, pad
end

function WorldBuilder.Animate(root: Instance)
	local portal = root:FindFirstChild("Portal")
	if portal then
		for _, gate in ipairs(portal:GetChildren()) do
			local plane = gate:FindFirstChild("PortalPlane")
			if plane and plane:IsA("BasePart") then
				local zoneId = gate:GetAttribute("Zone") or 1
				TweenService:Create(plane, TweenInfo.new(2 + zoneId * 0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					Transparency = 0.24,
				}):Play()
			end
			local pivot = gate:FindFirstChild("PortalPivot")
			if pivot and pivot:IsA("BasePart") then
				TweenService:Create(pivot, TweenInfo.new(11, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
					CFrame = pivot.CFrame * CFrame.Angles(0, 0, math.rad(360)),
				}):Play()
			end
		end
	end

	local fountainOrb = root:FindFirstChild("FountainOrb", true)
	if fountainOrb and fountainOrb:IsA("BasePart") then
		local home = fountainOrb.CFrame
		TweenService:Create(fountainOrb, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = home * CFrame.new(0, 0.55, 0) }):Play()
	end

	local hammer = root:FindFirstChild("ForgeHammer", true)
	if hammer and hammer:IsA("BasePart") then
		local home = hammer.CFrame
		TweenService:Create(hammer, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { CFrame = home * CFrame.Angles(0, math.rad(360), 0) }):Play()
	end

	local dailyOrb = root:FindFirstChild("DailyOrb", true)
	if dailyOrb and dailyOrb:IsA("BasePart") then
		local home = dailyOrb.CFrame
		TweenService:Create(dailyOrb, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = home * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, math.rad(180), 0) }):Play()
	end

	local zonesFolder = root:FindFirstChild("Zones")
	if zonesFolder then
		for _, folder in ipairs(zonesFolder:GetChildren()) do
			if folder:IsA("Folder") and folder.Name:match("^Zone_") then
				local zoneId = tonumber(folder.Name:match("%d+") or "")
				local pad = zoneId and folder:FindFirstChild("Pad_" .. zoneId)
				if pad and pad:IsA("BasePart") then
					TweenService:Create(pad, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.45 }):Play()
				end
			end
		end
	end

	-- townsfolk breathe and sway so the plaza never looks frozen
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "NpcRoot" then
			local home = descendant.CFrame
			TweenService:Create(descendant, TweenInfo.new(2.6 + math.abs(home.Position.X % 4) * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				CFrame = home * CFrame.new(0, 0.22, 0) * CFrame.Angles(0, 0, math.rad(1.6)),
			}):Play()
		end
	end

	-- ambient motion: rotates and gentle glow pulses on existing parts only,
	-- so the instance count and light count stay exactly the same
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Name == "BeaconRing" then
				TweenService:Create(part, TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					CFrame = part.CFrame * CFrame.Angles(0, math.rad(180), 0),
				}):Play()
			elseif part.Name == "TreeTop" or part.Name == "StatueOrb" or part.Name == "Lock" or part.Name == "ArchStrip" or part.Name == "RichRing" then
				local base = part.Transparency
				TweenService:Create(part, TweenInfo.new(1.7 + math.abs(part.Position.X % 5) * 0.11, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					Transparency = math.clamp(base + 0.34, 0, 0.85),
				}):Play()
			elseif part.Name:match("^DescendPad_") then
				TweenService:Create(part, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					Transparency = 0.5,
				}):Play()
			end
		end
	end
end

function WorldBuilder.Build()
	WorldBuilder.StyleLighting()

	local old = workspace:FindFirstChild("MineWorld")
	if old then
		old:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "MineWorld"

	buildHub(root)
	buildPortal(root)
	buildStations(root)

	local zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "Zones"
	zonesFolder.Parent = root

	local blocksByZone: { [number]: { Model } } = {}
	local pads: { [number]: BasePart } = {}
	local chests = {}

	for _, zone in ipairs(Config.Zones) do
		local folder, oreList, pad = buildZone(zone, zonesFolder)
		blocksByZone[zone.id] = oreList
		pads[zone.id] = pad

		local chestPositions = {
			Vector3.new(-64, zone.y + 5.8, 0),
			Vector3.new(64, zone.y + 5.8, 0),
		}
		for index, position in ipairs(chestPositions) do
			local chest = buildChest(zone, position, index)
			chest.folder = folder
			chests[#chests + 1] = chest
		end
	end

	root.Parent = workspace
	WorldBuilder.Animate(root)

	return {
		root = root,
		blocksByZone = blocksByZone,
		oreMeta = oreMeta,
		pads = pads,
		chests = chests,
	}
end

function WorldBuilder.PadPosition(pads, zoneId: number)
	local pad = pads[zoneId]
	if pad then
		return pad.Position + Vector3.new(0, 6, 6)
	end
	return Vector3.new(0, 6, 42)
end

return WorldBuilder
