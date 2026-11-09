--!strict
-- Anime Miner Tycoon :: optional guided tour

local TutorialService = {}

local Steps = {
	{ key = "summon", title = "Summon a hero", text = "Open SUMMON and press SUMMON once.", target = "Summon", world = nil },
	{ key = "deploy", title = "Deploy your crew", text = "In CREW, press DEPLOY on your best hero.", target = "Crew", world = nil },
	{ key = "descend", title = "Enter the mine", text = "Click the glowing portal in town.", target = nil, world = "portal" },
	{ key = "mine", title = "Break some ore", text = "Click any glowing ore block.", target = nil, world = "ore" },
	{ key = "research", title = "Buy an upgrade", text = "Open RESEARCH and buy Reinforced Picks.", target = "Research", world = nil },
	{ key = "done", title = "Tour complete", text = "Deeper biomes pay more. Keep digging.", target = nil, world = nil },
}

TutorialService.Steps = Steps

function TutorialService.Index(profile): number
	return math.clamp(profile.tutorial or 1, 1, #Steps)
end

local function grantReward(profile)
	if profile.tutorialRewarded then
		return false
	end
	profile.tutorialRewarded = true
	profile.coins += 300
	profile.gems += 12
	return true
end

function TutorialService.Payload(profile)
	local index = TutorialService.Index(profile)
	local step = Steps[index]
	return {
		started = profile.tutorialStarted == true,
		index = index,
		total = #Steps,
		title = step.title,
		text = step.text,
		target = step.target,
		world = step.world,
		done = profile.tutorialDone == true,
	}
end

function TutorialService.Start(profile)
	if profile.tutorialDone then
		return false
	end
	profile.tutorialStarted = true
	profile.tutorial = math.clamp(profile.tutorial or 1, 1, #Steps)
	return true
end

function TutorialService.Event(profile, key: string)
	if profile.tutorialDone or profile.tutorialStarted ~= true then
		return false, false
	end
	local index = TutorialService.Index(profile)
	if Steps[index].key ~= key then
		return false, false
	end
	profile.tutorial = math.min(index + 1, #Steps)
	local rewarded = false
	if profile.tutorial == #Steps then
		rewarded = grantReward(profile)
	end
	return true, rewarded
end

function TutorialService.Next(profile)
	if profile.tutorialDone or profile.tutorialStarted ~= true then
		return false, false
	end
	local index = TutorialService.Index(profile)
	if index >= #Steps then
		profile.tutorialDone = true
		return true, false
	end
	profile.tutorial = index + 1
	local rewarded = false
	if profile.tutorial == #Steps then
		rewarded = grantReward(profile)
	end
	return true, rewarded
end

function TutorialService.Skip(profile)
	profile.tutorialStarted = true
	profile.tutorialDone = true
	return true, "Tour skipped. Open GUIDE any time."
end

return TutorialService
