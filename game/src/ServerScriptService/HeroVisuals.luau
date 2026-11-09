--!strict
-- Anime Miner Tycoon :: visible hero rigs
-- Every rig is a jointed model (Motor6D) instead of a pile of welded boxes, so
-- the crew can walk to a block, plant their feet, wind up and actually swing a
-- pickaxe at it. Impacts kick out sparks, dust and floating damage numbers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local CrewService = require(script.Parent:WaitForChild("CrewService"))
local ResearchService = require(script.Parent:WaitForChild("ResearchService"))
local MiningService = require(script.Parent:WaitForChild("MiningService"))

local HeroVisuals = {}

local rigs: { [number]: { [number]: any } } = {}
local zoneFolders: { [number]: Folder } = {}

local SKIN = Color3.fromRGB(255, 224, 202)
local SKIN_SHADE = Color3.fromRGB(238, 190, 168)
local CLOTH = Color3.fromRGB(38, 42, 64)
local BOOT = Color3.fromRGB(22, 24, 36)
local HAIR_DARK = Color3.fromRGB(28, 26, 40)
local WOOD = Color3.fromRGB(124, 86, 52)
local STEEL = Color3.fromRGB(196, 210, 230)

-- building ------------------------------------------------------------------
local function part(model, name, size, cframe, color, material, shape, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function joint(model, name, parentPart, childPart, c0, c1)
	childPart.CFrame = parentPart.CFrame * c0 * (c1 or CFrame.new()):Inverse()
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = parentPart
	motor.Part1 = childPart
	motor.C0 = c0
	motor.C1 = c1 or CFrame.new()
	motor.Parent = parentPart
	return motor
end

local function child(model, parentPart, name, size, relative, color, material, shape, transparency)
	local p = part(model, name, size, parentPart.CFrame * relative, color, material, shape, transparency)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parentPart
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function pyramid(p, scale)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Pyramid
	mesh.Scale = scale
	mesh.Parent = p
	return mesh
end

local function buildPickaxe(model, armJoint, armPart, accent)
	local pivot = part(model, "WeaponPivot", Vector3.new(0.28, 0.28, 0.28), armPart.CFrame * CFrame.new(0, -1.95, 0), Color3.fromRGB(60, 60, 70))
	local weaponJoint = joint(model, "WeaponJoint", armPart, pivot, CFrame.new(0, -1.95, 0) * CFrame.Angles(math.rad(-16), 0, math.rad(6)))

	local handle = child(model, pivot, "Handle", Vector3.new(0.19, 3.3, 0.19), CFrame.new(0, 1.25, 0), WOOD, Enum.Material.Wood)
	child(model, handle, "Grip", Vector3.new(0.26, 0.8, 0.26), CFrame.new(0, -0.55, 0), Color3.fromRGB(48, 34, 26), Enum.Material.Fabric)
	child(model, handle, "Band", Vector3.new(0.28, 0.12, 0.28), CFrame.new(0, 0.45, 0), accent, Enum.Material.Neon)

	local head = child(model, handle, "AxeHead", Vector3.new(0.34, 0.5, 2.1), CFrame.new(0, 1.55, 0), STEEL, Enum.Material.Metal)
	local tip = child(model, head, "AxeEdge", Vector3.new(0.4, 0.26, 0.3), CFrame.new(0, 0, -1.05), accent, Enum.Material.Neon)
	local spike = child(model, head, "AxeSpike", Vector3.new(0.34, 0.34, 0.9), CFrame.new(0, 0, 1.15), STEEL, Enum.Material.Metal)
	pyramid(spike, Vector3.new(1, 1, 1.4))
	spike.CFrame = head.CFrame * CFrame.new(0, 0, 1.15) * CFrame.Angles(0, math.rad(90), 0)

	-- swing trail + flash light follow the blade
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "TrailA"
	attachment0.Position = Vector3.new(0, 0, -1.4)
	attachment0.Parent = head
	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "TrailB"
	attachment1.Position = Vector3.new(0, 0, 1.4)
	attachment1.Parent = head

	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = ColorSequence.new(accent, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.6))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.22
	trail.MinLength = 0.1
	trail.LightEmission = 0.9
	trail.Enabled = false
	trail.Parent = head

	local flash = Instance.new("PointLight")
	flash.Color = accent
	flash.Range = 12
	flash.Brightness = 0
	flash.Shadows = false
	flash.Parent = head

	return weaponJoint, trail, flash, head
end

local function buildRig(parent, hero, mutationColor, level)
	local model = Instance.new("Model")
	model.Name = "Hero_" .. hero.id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1.4, 1.2, 1.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = CFrame.new(0, 0, 0)
	root.Parent = model

	local jacket = hero.color
	local jacketDark = hero.color:Lerp(Color3.fromRGB(10, 12, 22), 0.42)
	local accent = hero.color:Lerp(Color3.fromRGB(255, 255, 255), 0.55)

	-- torso -----------------------------------------------------------------
	local torso = part(model, "Torso", Vector3.new(2.9, 2.7, 1.5), root.CFrame * CFrame.new(0, 1.35, 0), jacket, Enum.Material.Fabric)
	local torsoJoint = joint(model, "TorsoJoint", root, torso, CFrame.new(0, 1.35, 0))

	child(model, torso, "Collar", Vector3.new(2.12, 0.34, 1.62), CFrame.new(0, 1.18, 0), accent, Enum.Material.Fabric)
	child(model, torso, "Belt", Vector3.new(2.98, 0.34, 1.56), CFrame.new(0, -1.26, 0), BOOT, Enum.Material.Fabric)
	local emblem = child(model, torso, "Emblem", Vector3.new(0.82, 0.82, 0.16), CFrame.new(0, 0.24, -0.74) * CFrame.Angles(0, 0, math.rad(45)), accent, Enum.Material.Neon)
	pyramid(emblem, Vector3.new(1, 1, 1))
	local cape = child(model, torso, "Cape", Vector3.new(2.32, 2.9, 0.16), CFrame.new(0, -0.35, 0.8) * CFrame.Angles(math.rad(-7), 0, 0), jacketDark, Enum.Material.Fabric)
	child(model, cape, "CapeTrim", Vector3.new(2.32, 0.18, 0.18), CFrame.new(0, 1.4, 0), accent, Enum.Material.Neon)
	child(model, torso, "ShoulderL", Vector3.new(0.86, 0.4, 1.2), CFrame.new(-1.48, 1.14, 0), jacketDark, Enum.Material.Fabric)
	child(model, torso, "ShoulderR", Vector3.new(0.86, 0.4, 1.2), CFrame.new(1.48, 1.14, 0), jacketDark, Enum.Material.Fabric)

	-- head ------------------------------------------------------------------
	local head = part(model, "Head", Vector3.new(2.2, 2.2, 2.2), torso.CFrame * CFrame.new(0, 2.45, 0), SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local headJoint = joint(model, "NeckJoint", torso, head, CFrame.new(0, 2.45, 0))

	child(model, head, "Hair", Vector3.new(2.44, 2.4, 2.44), CFrame.new(0, 0.24, 0.14), hero.color:Lerp(HAIR_DARK, 0.25), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	child(model, head, "FringeL", Vector3.new(1.0, 0.52, 0.4), CFrame.new(-0.5, 0.66, -0.9) * CFrame.Angles(math.rad(10), math.rad(-6), math.rad(-16)), hero.color:Lerp(HAIR_DARK, 0.15), Enum.Material.SmoothPlastic)
	child(model, head, "FringeR", Vector3.new(1.0, 0.52, 0.4), CFrame.new(0.5, 0.66, -0.9) * CFrame.Angles(math.rad(10), math.rad(6), math.rad(16)), hero.color:Lerp(HAIR_DARK, 0.15), Enum.Material.SmoothPlastic)
	child(model, head, "FringeMid", Vector3.new(0.5, 0.66, 0.42), CFrame.new(0, 0.74, -0.94) * CFrame.Angles(math.rad(14), 0, 0), hero.color, Enum.Material.SmoothPlastic)
	child(model, head, "LockL", Vector3.new(0.34, 1.6, 0.46), CFrame.new(-1.02, -0.04, -0.28), hero.color:Lerp(HAIR_DARK, 0.3), Enum.Material.SmoothPlastic)
	child(model, head, "LockR", Vector3.new(0.34, 1.6, 0.46), CFrame.new(1.02, -0.04, -0.28), hero.color:Lerp(HAIR_DARK, 0.3), Enum.Material.SmoothPlastic)
	child(model, head, "Ponytail", Vector3.new(0.7, 1.5, 0.7), CFrame.new(0, -0.2, 1.18) * CFrame.Angles(math.rad(18), 0, 0), hero.color:Lerp(HAIR_DARK, 0.35), Enum.Material.SmoothPlastic, Enum.PartType.Ball)

	for _, side in ipairs({ -1, 1 }) do
		child(model, head, "Brow" .. side, Vector3.new(0.44, 0.11, 0.12), CFrame.new(side * 0.44, 0.34, -1.02) * CFrame.Angles(0, 0, side * math.rad(-9)), HAIR_DARK)
		child(model, head, "Eye" .. side, Vector3.new(0.32, 0.42, 0.14), CFrame.new(side * 0.42, 0.02, -1.0), Color3.fromRGB(34, 36, 54))
		child(model, head, "Iris" .. side, Vector3.new(0.17, 0.26, 0.12), CFrame.new(side * 0.42, 0.02, -1.06), accent, Enum.Material.Neon)
		child(model, head, "Cheek" .. side, Vector3.new(0.2, 0.1, 0.1), CFrame.new(side * 0.62, -0.34, -0.96), SKIN_SHADE)
	end
	child(model, head, "Mouth", Vector3.new(0.3, 0.08, 0.1), CFrame.new(0, -0.44, -1.0), Color3.fromRGB(120, 62, 72))

	-- arms ------------------------------------------------------------------
	local shoulderY = 0.72
	local armL = part(model, "ArmL", Vector3.new(0.72, 2.25, 0.72), torso.CFrame * CFrame.new(-1.66, shoulderY - 1.06, 0), jacketDark, Enum.Material.Fabric)
	local armLJoint = joint(model, "ShoulderL", torso, armL, CFrame.new(-1.66, shoulderY, 0), CFrame.new(0, 1.06, 0))
	local armR = part(model, "ArmR", Vector3.new(0.72, 2.25, 0.72), torso.CFrame * CFrame.new(1.66, shoulderY - 1.06, 0), jacketDark, Enum.Material.Fabric)
	local armRJoint = joint(model, "ShoulderR", torso, armR, CFrame.new(1.66, shoulderY, 0), CFrame.new(0, 1.06, 0))
	child(model, armL, "HandL", Vector3.new(0.56, 0.5, 0.56), CFrame.new(0, -1.24, 0), SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	child(model, armR, "HandR", Vector3.new(0.56, 0.5, 0.56), CFrame.new(0, -1.24, 0), SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)

	-- legs ------------------------------------------------------------------
	local legL = part(model, "LegL", Vector3.new(0.96, 2.3, 0.96), root.CFrame * CFrame.new(-0.72, -1.25, 0), CLOTH, Enum.Material.Fabric)
	local legLJoint = joint(model, "HipL", root, legL, CFrame.new(-0.72, -0.15, 0), CFrame.new(0, 1.1, 0))
	local legR = part(model, "LegR", Vector3.new(0.96, 2.3, 0.96), root.CFrame * CFrame.new(0.72, -1.25, 0), CLOTH, Enum.Material.Fabric)
	local legRJoint = joint(model, "HipR", root, legR, CFrame.new(0.72, -0.15, 0), CFrame.new(0, 1.1, 0))
	child(model, legL, "BootL", Vector3.new(1.04, 0.5, 1.28), CFrame.new(0, -1.28, -0.12), BOOT, Enum.Material.Fabric)
	child(model, legR, "BootR", Vector3.new(1.04, 0.5, 1.28), CFrame.new(0, -1.28, -0.12), BOOT, Enum.Material.Fabric)

	-- pickaxe ---------------------------------------------------------------
	local weaponJoint, trail, flash, axeHead = buildPickaxe(model, armRJoint, armR, accent)

	-- aura ring -------------------------------------------------------------
	local ring = part(model, "AuraRing", Vector3.new(0.14, 5.4, 5.4), root.CFrame * CFrame.new(0, -2.9, 0), mutationColor, Enum.Material.Neon, Enum.PartType.Cylinder, 0.45)
	local ringJoint = joint(model, "AuraJoint", root, ring, CFrame.new(0, -2.9, 0), CFrame.Angles(0, 0, math.rad(90)))
	ring.CFrame = root.CFrame * CFrame.new(0, -2.9, 0)
	for index = 0, 3 do
		local angle = index * math.pi / 2
		local stud = child(model, ring, "Rune" .. index, Vector3.new(0.34, 0.34, 0.34), CFrame.new(0, math.sin(angle) * 2.5, math.cos(angle) * 2.5), mutationColor, Enum.Material.Neon)
		pyramid(stud, Vector3.new(1, 1, 1))
	end

	local aura = Instance.new("ParticleEmitter")
	aura.Color = ColorSequence.new(mutationColor)
	aura.Size = NumberSequence.new(1.4, 0)
	aura.Transparency = NumberSequence.new(0.2, 1)
	aura.Lifetime = NumberRange.new(0.5, 1.2)
	aura.Rate = 2
	aura.Speed = NumberRange.new(0.6, 2.2)
	aura.SpreadAngle = Vector2.new(20, 20)
	aura.LightEmission = 0.85
	aura.Parent = torso

	local light = Instance.new("PointLight")
	light.Color = mutationColor
	light.Range = 15
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = torso

	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(175, 44)
	gui.StudsOffset = Vector3.new(0, 5.8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 110
	gui.Parent = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.58)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = hero.name
	nameLabel.TextColor3 = hero.color
	nameLabel.TextStrokeColor3 = Color3.fromRGB(8, 10, 18)
	nameLabel.TextStrokeTransparency = 0.25
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.Parent = gui

	local subLabel = Instance.new("TextLabel")
	subLabel.Position = UDim2.fromScale(0, 0.58)
	subLabel.Size = UDim2.fromScale(1, 0.4)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = "Lv " .. level
	subLabel.TextColor3 = mutationColor
	subLabel.TextStrokeColor3 = Color3.fromRGB(8, 10, 18)
	subLabel.TextStrokeTransparency = 0.4
	subLabel.Font = Enum.Font.GothamBold
	subLabel.TextScaled = true
	subLabel.Parent = gui

	model.Parent = parent

	return {
		model = model,
		root = root,
		hero = hero,
		mutationColor = mutationColor,
		level = level,
		torso = torso,
		head = head,
		armL = armL,
		armR = armR,
		legL = legL,
		legR = legR,
		joints = {
			Torso = torsoJoint,
			Head = headJoint,
			ShoulderL = armLJoint,
			ShoulderR = armRJoint,
			HipL = legLJoint,
			HipR = legRJoint,
			Weapon = weaponJoint,
			Aura = ringJoint,
		},
		ring = ring,
		trail = trail,
		flash = flash,
		axeHead = axeHead,
		light = light,
		aura = aura,
		nameLabel = nameLabel,
		subLabel = subLabel,
		tweens = {},
		target = nil,
		striking = false,
		walking = false,
		lastFx = 0,
	}
end

-- effects -------------------------------------------------------------------
local function effectPart(position, color, transparency)
	local p = Instance.new("Part")
	p.Name = "Fx"
	p.Size = Vector3.new(1, 1, 1)
	p.Transparency = transparency or 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.CFrame = CFrame.new(position)
	p.Parent = workspace
	return p
end

local function impactBurst(position, color)
	local holder = effectPart(position, color, 1)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.3, 0.7)
	emitter.Speed = NumberRange.new(9, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -28, 0)
	emitter.Drag = 2
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(12)

	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(color:Lerp(Color3.fromRGB(180, 190, 210), 0.55))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 3.2) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.5, 1.1)
	dust.Speed = NumberRange.new(2, 6)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Acceleration = Vector3.new(0, 6, 0)
	dust.Rate = 0
	dust.Parent = holder
	dust:Emit(6)

	local ring = effectPart(position, color, 0.25)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.12, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(ring, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, 7.5, 7.5),
		Transparency = 1,
	}):Play()

	task.delay(1.6, function()
		if holder.Parent then
			holder:Destroy()
		end
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

local function damageNumber(position, amount, color)
	local holder = effectPart(position, color, 1)
	holder.CFrame = CFrame.new(position + Vector3.new(math.random(-2, 2), 2.4, math.random(-2, 2)))

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(130, 42)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.Parent = holder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "-" .. tostring(math.floor(amount))
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(8, 10, 18)
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 4.4, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.75), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	task.delay(0.85, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

local function dustPuff(position, color)
	local holder = effectPart(position, color, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.4) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.45, 0.9)
	emitter.Speed = NumberRange.new(1, 4)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Acceleration = Vector3.new(0, 5, 0)
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(7)
	task.delay(1.2, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

-- animation -----------------------------------------------------------------
local function stopTween(rig, key)
	local tween = rig.tweens[key]
	if tween then
		tween:Cancel()
		rig.tweens[key] = nil
	end
end

local function ensureIdle(rig)
	if rig.tweens.idle then
		return
	end
	local torso = rig.joints.Torso
	local head = rig.joints.Head
	torso.Transform = CFrame.new()
	head.Transform = CFrame.new()

	local breathe = TweenService:Create(torso, TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transform = CFrame.new(0, 0.055, 0) * CFrame.Angles(math.rad(-1.4), 0, 0),
	})
	breathe:Play()
	rig.tweens.idle = breathe

	local look = TweenService:Create(head, TweenInfo.new(2.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transform = CFrame.Angles(math.rad(2.4), math.rad(3), 0),
	})
	look:Play()
	rig.tweens.idleHead = look
end

local function stopIdle(rig)
	stopTween(rig, "idle")
	stopTween(rig, "idleHead")
	rig.joints.Torso.Transform = CFrame.new()
	rig.joints.Head.Transform = CFrame.new()
end

local function startWalkCycle(rig)
	if rig.tweens.walkLegL then
		return
	end
	local infoL = TweenInfo.new(0.46, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local legL = TweenService:Create(rig.joints.HipL, infoL, { Transform = CFrame.Angles(math.rad(32), 0, 0) })
	legL:Play()
	rig.tweens.walkLegL = legL

	local infoR = TweenInfo.new(0.46, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local legR = TweenService:Create(rig.joints.HipR, infoR, { Transform = CFrame.Angles(math.rad(-32), 0, 0) })
	legR:Play()
	rig.tweens.walkLegR = legR

	local armL = TweenService:Create(rig.joints.ShoulderL, TweenInfo.new(0.46, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transform = CFrame.Angles(math.rad(-26), 0, 0),
	})
	armL:Play()
	rig.tweens.walkArmL = armL
end

local function stopWalkCycle(rig)
	stopTween(rig, "walkLegL")
	stopTween(rig, "walkLegR")
	stopTween(rig, "walkArmL")
	rig.joints.HipL.Transform = CFrame.new()
	rig.joints.HipR.Transform = CFrame.new()
	rig.joints.ShoulderL.Transform = CFrame.new()
end

local function faceTowards(rig, position)
	local delta = position - rig.root.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	local yaw = math.atan2(-flat.X, -flat.Z)
	rig.root.CFrame = CFrame.new(rig.root.Position) * CFrame.Angles(0, yaw, 0)
end

local function walkTo(rig, destination, onArrive)
	if rig.walking or rig.striking then
		return
	end
	local delta = destination - rig.root.Position
	local distance = delta.Magnitude
	if distance < 0.6 then
		if onArrive then
			onArrive()
		end
		return
	end
	rig.walking = true
	stopIdle(rig)
	stopWalkCycle(rig)
	faceTowards(rig, destination)

	local goal = CFrame.new(destination) * (rig.root.CFrame - rig.root.CFrame.Position)
	local duration = math.clamp(distance / 17, 0.25, 4)
	startWalkCycle(rig)

	local walk = TweenService:Create(rig.root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = goal })
	rig.tweens.walk = walk
	walk.Completed:Once(function()
		rig.walking = false
		stopWalkCycle(rig)
		ensureIdle(rig)
		if onArrive then
			onArrive()
		end
	end)
	walk:Play()
end

local function strike(rig, target, power, zoneColor)
	if rig.striking or rig.walking then
		return
	end
	rig.striking = true
	faceTowards(rig, target:GetPivot().Position)
	stopIdle(rig)
	stopWalkCycle(rig)
	rig.joints.ShoulderR.Transform = CFrame.new()
	rig.joints.Torso.Transform = CFrame.new()

	local arm = rig.joints.ShoulderR
	local torso = rig.joints.Torso

	local windup = TweenService:Create(arm, TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transform = CFrame.Angles(math.rad(-128), 0, math.rad(-14)),
	})
	rig.tweens.strikeWindup = windup
	TweenService:Create(rig.joints.Head, TweenInfo.new(0.17), { Transform = CFrame.Angles(math.rad(-6), 0, 0) }):Play()
	windup:Play()

	windup.Completed:Once(function()
		if not rig.model.Parent then
			rig.striking = false
			return
		end
		rig.trail.Enabled = true
		rig.flash.Brightness = 2.4
		dustPuff(rig.root.Position - Vector3.new(0, 2.6, 0), Color3.fromRGB(150, 158, 178))

		local slam = TweenService:Create(arm, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transform = CFrame.Angles(math.rad(38), 0, math.rad(8)),
		})
		rig.tweens.strikeSlam = slam
		TweenService:Create(torso, TweenInfo.new(0.11), { Transform = CFrame.Angles(math.rad(-9), math.rad(4), 0) }):Play()
		slam:Play()

		slam.Completed:Once(function()
			if not rig.model.Parent then
				rig.striking = false
				return
			end
			local pivot = target:GetPivot().Position
			local hit = pivot + Vector3.new(math.random(-2.6, 2.6), math.random(-0.8, 2.2), math.random(-2.6, 2.6))
			impactBurst(hit, zoneColor or Color3.fromRGB(150, 200, 255))
			if os.clock() - rig.lastFx > 0.4 then
				rig.lastFx = os.clock()
				damageNumber(hit, power, zoneColor or Color3.fromRGB(220, 235, 255))
			end

			TweenService:Create(rig.flash, TweenInfo.new(0.2), { Brightness = 0 }):Play()
			rig.trail.Enabled = false

			task.delay(0.09, function()
				if not rig.model.Parent then
					rig.striking = false
					return
				end
				local recover = TweenService:Create(arm, TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Transform = CFrame.new() })
				rig.tweens.strikeRecover = recover
				TweenService:Create(torso, TweenInfo.new(0.28), { Transform = CFrame.new() }):Play()
				TweenService:Create(rig.joints.Head, TweenInfo.new(0.28), { Transform = CFrame.new() }):Play()
				recover:Play()
				recover.Completed:Once(function()
					rig.striking = false
					ensureIdle(rig)
				end)
			end)
		end)
	end)
end

-- world helpers -------------------------------------------------------------
local function heroFolder(zoneId: number): Folder
	local folder = zoneFolders[zoneId]
	if folder and folder.Parent then
		return folder
	end
	local world = workspace:FindFirstChild("MineWorld")
	local zones = world and world:FindFirstChild("Zones")
	local zoneFolder = zones and zones:FindFirstChild("Zone_" .. zoneId)
	folder = Instance.new("Folder")
	folder.Name = "Heroes"
	folder.Parent = zoneFolder or workspace
	zoneFolders[zoneId] = folder
	return folder
end

local function nearestOre(rig, zoneId)
	local world = workspace:FindFirstChild("MineWorld")
	local zones = world and world:FindFirstChild("Zones")
	local folder = zones and zones:FindFirstChild("Zone_" .. zoneId)
	if not folder then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, inst in ipairs(folder:GetChildren()) do
		if inst:IsA("Model") and inst.Name:match("^Ore_") and inst:GetAttribute("Alive") then
			local distance = (inst:GetPivot().Position - rig.root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = inst, distance
			end
		end
	end
	return best
end

local function standPosition(target, rig, zoneId)
	local pivot = target:GetPivot().Position
	local away = rig.root.Position - pivot
	local flat = Vector3.new(away.X, 0, away.Z)
	if flat.Magnitude < 2 then
		flat = Vector3.new(0, 0, 1)
	end
	flat = flat.Unit * 5.4
	local pad = MiningService.PadFor(zoneId)
	local floorY = pad and pad.Y + 3.15 or pivot.Y - 1.4
	return Vector3.new(pivot.X + flat.X, floorY, pivot.Z + flat.Z)
end

-- rig bookkeeping -----------------------------------------------------------
local function sync(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local bonuses = ResearchService.GetBonuses(profile)
	local zoneId = math.min(profile.zone, bonuses.zonesUnlocked)
	local pad = MiningService.PadFor(zoneId) or MiningService.PadFor(1) or Vector3.new(0, 0, 0)

	local owned = rigs[player.UserId] or {}
	rigs[player.UserId] = owned

	local equipped = {}
	for _, unit in ipairs(profile.units) do
		if unit.equipped then
			equipped[#equipped + 1] = unit
		end
	end

	local rank = 0
	for playerIndex, other in ipairs(Players:GetPlayers()) do
		if other == player then
			rank = playerIndex - 1
			break
		end
	end

	local seen = {}
	for index, unit in ipairs(equipped) do
		seen[unit.id] = true
		local hero = CrewService.HeroById[unit.heroId]
		local mutation = CrewService.MutationById[unit.mutation] or CrewService.MutationById.none
		if hero then
			local rig = owned[unit.id]
			if not rig or not rig.model.Parent then
				rig = buildRig(heroFolder(zoneId), hero, mutation.color, unit.level)
				rig.model:SetAttribute("UnitId", unit.id)
				rig.zoneId = zoneId
				local count = #equipped
				local offsetX = (index - (count + 1) / 2) * 6
				rig.root.CFrame = CFrame.new(pad + Vector3.new(offsetX + rank * 34, 3.2, 13))
					* CFrame.Angles(0, math.rad(180), 0)
				rig.home = rig.root.CFrame
				ensureIdle(rig)
				local spin = TweenService:Create(rig.joints.Aura, TweenInfo.new(4.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
					Transform = CFrame.Angles(0, math.rad(360), 0),
				})
				spin:Play()
				rig.tweens.aura = spin
				owned[unit.id] = rig
			end

			if rig.zoneId ~= zoneId then
				rig.zoneId = zoneId
				rig.target = nil
				stopTween(rig, "walk")
				rig.walking = false
				stopWalkCycle(rig)
				rig.model.Parent = heroFolder(zoneId)
				rig.root.CFrame = CFrame.new(pad + Vector3.new((index - (#equipped + 1) / 2) * 6 + rank * 34, 3.2, 13))
					* CFrame.Angles(0, math.rad(180), 0)
				ensureIdle(rig)
			end

			if rig.level ~= unit.level or rig.mutationColor ~= mutation.color then
				rig.level = unit.level
				rig.mutationColor = mutation.color
				rig.subLabel.Text = "Lv " .. unit.level .. "  •  " .. mutation.name
				rig.subLabel.TextColor3 = mutation.color
				rig.ring.Color = mutation.color
				rig.light.Color = mutation.color
				rig.aura.Color = ColorSequence.new(mutation.color)
				for _, rune in ipairs(rig.ring:GetChildren()) do
					if rune:IsA("BasePart") then
						rune.Color = mutation.color
					end
				end
			end
		end
	end

	for unitId, rig in pairs(owned) do
		if not seen[unitId] then
			rig.model:Destroy()
			owned[unitId] = nil
		end
	end
end

local function cleanupPlayer(userId: number)
	local owned = rigs[userId]
	if owned then
		for _, rig in pairs(owned) do
			rig.model:Destroy()
		end
	end
	rigs[userId] = nil
end

local function workLoop()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local owned = rigs[player.UserId]
			if owned then
				for _, rig in pairs(owned) do
					if rig.model.Parent and not rig.striking and not rig.walking then
						local zoneId = rig.zoneId or 1
						local target = rig.target
						if not target or not target.Parent or not target:GetAttribute("Alive") then
							target = nearestOre(rig, zoneId)
							rig.target = target
						end
						if target then
							local stand = standPosition(target, rig, zoneId)
							if (rig.root.Position - stand).Magnitude > 1.4 then
								walkTo(rig, stand)
							else
								faceTowards(rig, target:GetPivot().Position)
							end
						end
					end
				end
			end
		end
		task.wait(1)
	end
end

function HeroVisuals.Start()
	Players.PlayerRemoving:Connect(function(player)
		cleanupPlayer(player.UserId)
	end)

	MiningService.SetHeroTargetProvider(function(player, unitId, zoneId)
		local owned = rigs[player.UserId]
		local rig = owned and owned[unitId]
		if not rig or not rig.model.Parent then
			return nil
		end
		local target = rig.target
		if target and target.Parent and target:GetAttribute("Alive") then
			return target
		end
		return nil
	end)

	MiningService.SetHeroHitHook(function(player, unitId, target, power)
		local owned = rigs[player.UserId]
		local rig = owned and owned[unitId]
		if not rig or not rig.model.Parent then
			return
		end
		if rig.target ~= target then
			rig.target = target
			if not rig.walking then
				local stand = standPosition(target, rig, rig.zoneId or 1)
				if (rig.root.Position - stand).Magnitude > 1.8 then
					walkTo(rig, stand)
					return
				end
			end
		end
		local zone = Config.ZoneById(target:GetAttribute("Zone"))
		strike(rig, target, power, zone and zone.blockColor or nil)
	end)

	task.spawn(function()
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(sync, player)
				if not ok then
					warn("[AnimeMiner] hero rig sync failed: " .. tostring(err))
				end
			end
			task.wait(0.8)
		end
	end)

	task.spawn(workLoop)
end

return HeroVisuals
