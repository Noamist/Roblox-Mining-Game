--!strict
-- Anime Miner Tycoon :: townsfolk dialogue, shops and side quests
-- Every town NPC owns a lore page, one side quest, and (where it fits) a shop
-- that buys into the real progression systems, so talking to people is part of
-- the loop instead of a text box that only says hello.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local ProgressService = require(script.Parent:WaitForChild("ProgressService"))
local CrewService = require(script.Parent:WaitForChild("CrewService"))

local NpcService = {}

local sink = nil

function NpcService.SetDialogueSink(callback)
	sink = callback
end

local NPCS = {
	guildmaster = {
		name = "Master Oro",
		role = "GUILD MASTER",
		accent = Color3.fromRGB(255, 208, 128),
		greeting = "The Guild Hall is open, and every hero you sign is one more shovel in the dark. What do you need?",
		lore = "When the Sundering split the world, the old guilds stayed on the surface and watched the mines swallow their best diggers. We rebuilt this hall over the Starlit Quarry and swore a single oath: no miner descends alone. Every hero you summon signs that same oath. Their power feeds your pick, and your pick keeps the tunnels open.",
		questLine = "The Guild keeps a list of work nobody else will take.",
	},
	merchant = {
		name = "Sable",
		role = "GEM MERCHANT",
		accent = Color3.fromRGB(235, 150, 205),
		greeting = "Gems in, power out. Mind the queue, the counter is older than the town.",
		lore = "Gems are not mined, they are grown. Every shard in a reward cache is a seed of the old sky, and the market buys them at a fair price. Mostly. A Coin Surge is the honest trade: double yield for five minutes. Do the arithmetic before you haggle with me.",
		shop = "boosts",
		shopLabel = "Show me your wares",
		shopLine = "Everything here is a timed buff, so buy it when you are about to dig, not before.",
		questLine = "I move product, I do not move rock. But I do pay for volume.",
	},
	smith = {
		name = "Bran the Forge Master",
		role = "FORGE MASTER",
		accent = Color3.fromRGB(255, 176, 96),
		greeting = "Step up. The anvil is still warm and I do not like waiting.",
		lore = "My family forged picks for four generations. The trick is not the blade, it is the balance: downstroke first, then let the rock answer. Every forge level adds thirty percent to your swing. Bring coins, not excuses.",
		shop = "forge",
		shopLabel = "Forge my pickaxe",
		shopLine = "One level, paid up front. The pick never loses that edge.",
		questLine = "A pick is only proven by the ore it breaks.",
	},
	prospector = {
		name = "Old Rhen",
		role = "PROSPECTOR",
		accent = Color3.fromRGB(150, 220, 255),
		greeting = "New boots? Good. The lower tunnels do not forgive new boots.",
		lore = "Six strata, six rules. The Starlit Quarry is kind. Crystal Caverns lies about its floors. Magma Veins burns the greedy. Frozen Abyss remembers every wrong step. Void Sanctum does not want visitors, and the Celestial Core is where the sky fell in. Chart all six and I will sign your map myself.",
		questLine = "I have been drawing the same map for thirty years. Help me finish it.",
	},
	seer = {
		name = "Seer Yumi",
		role = "TRAIT SEER",
		accent = Color3.fromRGB(212, 168, 255),
		greeting = "Every hero carries a fate rolled before they arrived. I can read it, and for a price, rewrite it.",
		lore = "Traits are older than the Guild. Before the Sundering, every miner was marked at birth: swift hands, a giant's shoulder, a storm in the wrist. The mark does not change who you are, only how the rock answers you. I read marks. I do not invent them, no matter what the merchant tells you.",
		shop = "traits",
		shopLabel = "Read my heroes' traits",
		shopLine = "A reroll picks one deployed hero and rolls a new mark from the old table. Nothing is guaranteed.",
		questLine = "Fate owes nobody a fair roll.",
	},
	villager = {
		name = "Mira",
		role = "TOWNSFOLK",
		accent = Color3.fromRGB(180, 230, 200),
		greeting = "You are the one the guildmaster keeps talking about, aren't you? Sit, the plaza is quiet tonight.",
		lore = "You hear the hum after dark? That is the Deep Shaft breathing. Old miners say the caches above were planted by the first crew to seal it. Open six of them and you will know the whole story. The Guild will not say it out loud, but I will.",
		questLine = "The caches are not just loot. They are a message.",
	},
}

NpcService.Npcs = NPCS

local QUESTS = {
	{
		id = "guild_trial", npc = "guildmaster", name = "A Place in the Guild",
		desc = "Summon 15 heroes for the guild roster",
		metric = "rolls", goal = 15, coins = 750, gems = 25,
	},
	{
		id = "supply_run", npc = "merchant", name = "Supply Run",
		desc = "Mine 200 ore blocks so the market stays stocked",
		metric = "blocksMined", goal = 200, coins = 900, gems = 20,
	},
	{
		id = "forge_oath", npc = "smith", name = "The Forge Oath",
		desc = "Break 450 ore blocks with a forged pick",
		metric = "blocksMined", goal = 450, coins = 1400, gems = 30,
	},
	{
		id = "deep_chart", npc = "prospector", name = "Chart the Depths",
		desc = "Reach the Crystal Caverns (biome 2)",
		metric = "zone", goal = 2, coins = 600, gems = 18,
	},
	{
		id = "cache_hunt", npc = "villager", name = "Cache Hunter",
		desc = "Open 6 reward caches",
		metric = "chestsOpened", goal = 6, coins = 800, gems = 22,
	},
}

NpcService.Quests = QUESTS

local questByNpc: { [string]: any } = {}
for _, quest in ipairs(QUESTS) do
	questByNpc[quest.npc] = quest
end

local function metricValue(profile, metric: string): number
	if metric == "zone" then
		return profile.zone or 1
	end
	return ProgressService.StatValue(profile, metric)
end

local function questEntry(profile, questId: string)
	profile.sideQuests = profile.sideQuests or {}
	return profile.sideQuests[questId]
end

local function questProgress(profile, quest, entry): number
	local current = metricValue(profile, quest.metric)
	if quest.metric == "zone" then
		return math.min(current, quest.goal)
	end
	return math.clamp(current - (entry.start or 0), 0, quest.goal)
end

local function questState(profile, quest): (string, number)
	local entry = questEntry(profile, quest.id)
	if not entry then
		return "available", 0
	end
	local progress = questProgress(profile, quest, entry)
	if entry.claimed then
		return "claimed", progress
	end
	if progress >= quest.goal then
		return "ready", progress
	end
	return "active", progress
end

-- Accepting stores a snapshot of the stat so progress only counts from now on.
local function acceptQuest(profile, quest): (boolean, string)
	profile.sideQuests = profile.sideQuests or {}
	if profile.sideQuests[quest.id] then
		return false, "You already took that job."
	end
	profile.sideQuests[quest.id] = { start = metricValue(profile, quest.metric), claimed = false }
	return true, "Accepted: " .. quest.name
end

local function claimQuest(profile, quest): (boolean, string)
	local entry = questEntry(profile, quest.id)
	if not entry then
		return false, "You never accepted that job."
	end
	if entry.claimed then
		return false, "That reward is already paid."
	end
	local status = questState(profile, quest)
	if status ~= "ready" then
		return false, "Not finished yet."
	end
	entry.claimed = true
	profile.coins += quest.coins
	profile.gems += quest.gems
	profile.stats.coinsEarned += quest.coins
	return true, quest.name .. " complete! +" .. quest.coins .. " coins, +" .. quest.gems .. " gems"
end

local function shopPayload(profile, npc)
	if npc.shop == "boosts" then
		local items = {}
		for _, item in ipairs(ProgressService.ShopPayload(profile)) do
			items[#items + 1] = {
				id = item.id, name = item.name, desc = item.desc,
				cost = item.cost, currency = "gems", color = item.color,
			}
		end
		return { kind = "boosts", items = items }
	elseif npc.shop == "traits" then
		return {
			kind = "traits",
			items = {
				{
					id = "trait",
					name = "Trait reroll",
					desc = "Reroll the trait of one deployed hero",
					cost = Config.TraitRerollCost,
					currency = "gems",
					color = Color3.fromRGB(212, 168, 255),
				},
			},
		}
	elseif npc.shop == "forge" then
		local level = ProgressService.PickaxeLevel(profile)
		local maxed = ProgressService.PickaxeMaxed(profile)
		return {
			kind = "forge",
			items = {
				{
					id = "pickaxe",
					name = maxed and ("Pickaxe Lv " .. level .. " (max)") or ("Pickaxe Lv " .. (level + 1)),
					desc = maxed and "Fully forged - nothing left to temper" or "+30% swing damage, permanently",
					cost = ProgressService.PickaxeCost(profile),
					currency = "coins",
					color = Color3.fromRGB(255, 205, 130),
					maxed = maxed,
				},
			},
		}
	end
	return nil
end

local TONES = { accent = "accent", gold = "gold", good = "good", muted = "muted", pink = "pink", bad = "bad" }

local function buildChoices(npc, page, profile, quest, status)
	local choices = {}

	if page == "shop" then
		local shop = shopPayload(profile, npc)
		for _, item in ipairs(shop and shop.items or {}) do
			local affordable = item.currency == "gems" and profile.gems >= item.cost or profile.coins >= item.cost
			if not item.maxed then
				choices[#choices + 1] = {
					label = item.name .. "  ·  " .. item.cost .. (item.currency == "gems" and " gems" or " coins"),
					action = "buy",
					arg = item.id,
					tone = affordable and TONES.gold or TONES.muted,
				}
			end
		end
		choices[#choices + 1] = { label = "Never mind", action = "greet", tone = TONES.muted }
	else
		if npc.shop then
			choices[#choices + 1] = { label = npc.shopLabel, action = "shop", tone = TONES.gold }
		end
		choices[#choices + 1] = { label = "Tell me about this place", action = "lore", tone = TONES.accent }
		if quest then
			if status == "available" then
				choices[#choices + 1] = { label = "Do you have work for me?", action = "quest", tone = TONES.pink }
			elseif status == "active" then
				choices[#choices + 1] = { label = "About that job...", action = "quest", tone = TONES.pink }
			elseif status == "ready" then
				choices[#choices + 1] = { label = "I finished the job", action = "quest", tone = TONES.good }
			else
				choices[#choices + 1] = { label = "Anything else?", action = "quest", tone = TONES.muted }
			end
		end
	end

	choices[#choices + 1] = { label = "Farewell", action = "close", tone = TONES.muted }
	return choices
end

local function bodyFor(npc, page, profile, quest, status, progress)
	if page == "lore" then
		return npc.lore
	end
	if page == "shop" then
		local shop = shopPayload(profile, npc)
		local lines = { npc.shopLine }
		for _, item in ipairs(shop and shop.items or {}) do
			lines[#lines + 1] = item.name .. " - " .. item.desc
		end
		lines[#lines + 1] = "You carry " .. profile.coins .. " coins and " .. profile.gems .. " gems."
		return table.concat(lines, "\n")
	end
	if page == "quest" and quest then
		if status == "available" then
			return npc.questLine .. "\n\n" .. quest.desc .. ".\n\nPay: " .. quest.coins .. " coins and " .. quest.gems .. " gems."
		elseif status == "active" then
			return "Still open: " .. quest.desc .. ".\n\nYou are at " .. progress .. " of " .. quest.goal .. ". Come back when it is done."
		elseif status == "ready" then
			return "That is the job done. Hand over the tally and collect your pay: " .. quest.coins .. " coins and " .. quest.gems .. " gems."
		end
		return "That job is settled. The ledger is clean, and the Guild remembers who helped."
	end
	return npc.greeting
end

local function questPayload(profile, npc, page)
	local quest = questByNpc[npc.id or ""]
	if not quest then
		return nil
	end
	local status, progress = questState(profile, quest)
	return {
		id = quest.id,
		npcId = quest.npc,
		name = quest.name,
		desc = quest.desc,
		goal = quest.goal,
		progress = progress,
		coins = quest.coins,
		gems = quest.gems,
		state = status,
	}
end

function NpcService.Payload(profile, npcId: string, page: string?)
	local npc = NPCS[npcId]
	if not npc then
		return nil
	end
	-- give the npc a stable id for the quest lookup
	local withId = npc :: any
	withId.id = npcId
	page = page or "greet"
	local quest = questByNpc[npcId]
	local status, progress = "available", 0
	if quest then
		status, progress = questState(profile, quest)
	end
	local questInfo = questPayload(profile, withId, page)

	return {
		npcId = npcId,
		name = npc.name,
		role = npc.role,
		accent = npc.accent,
		page = page,
		body = bodyFor(npc, page, profile, quest, status, progress),
		choices = buildChoices(npc, page, profile, quest, status),
		quest = questInfo,
		shop = shopPayload(profile, npc),
		coins = profile.coins,
		gems = profile.gems,
	}
end

-- Log shown in the Quests tab: only jobs the player actually took.
function NpcService.SideQuestLog(profile)
	profile.sideQuests = profile.sideQuests or {}
	local list = {}
	for _, quest in ipairs(QUESTS) do
		local entry = profile.sideQuests[quest.id]
		if entry then
			local status, progress = questState(profile, quest)
			local npc = NPCS[quest.npc]
			list[#list + 1] = {
				id = quest.id,
				npcId = quest.npc,
				npcName = npc and npc.name or quest.npc,
				role = npc and npc.role or "TOWNSFOLK",
				name = quest.name,
				desc = quest.desc,
				goal = quest.goal,
				progress = progress,
				coins = quest.coins,
				gems = quest.gems,
				state = status,
			}
		end
	end
	return list
end

local function buy(player, profile, npc, itemId): (boolean, string)
	if npc.shop == "boosts" then
		return ProgressService.BuyBoost(profile, itemId)
	elseif npc.shop == "forge" then
		return ProgressService.BuyPickaxe(profile)
	elseif npc.shop == "traits" then
		return CrewService.RerollTrait(profile)
	end
	return false, "Nothing for sale here."
end

-- Single entry point used by both the world click detectors and the client panel.
function NpcService.Talk(player: Player, npcId: string?, choice: string?, argument: string?)
	local profile = DataService.Get(player)
	local npc = npcId and NPCS[npcId]
	if not profile or not npc then
		return nil, nil
	end
	local quest = questByNpc[npcId]
	local page = "greet"
	local message, kind = nil, nil

	if choice == "lore" then
		page = "lore"
	elseif choice == "shop" and npc.shop then
		page = "shop"
	elseif choice == "quest" and quest then
		page = "quest"
	elseif choice == "accept" and quest then
		local ok, text = acceptQuest(profile, quest)
		page = "quest"
		message, kind = text, ok and "ok" or "error"
	elseif choice == "claim" and quest then
		local ok, text = claimQuest(profile, quest)
		page = "quest"
		message, kind = text, ok and "gacha" or "error"
	elseif choice == "buy" then
		local ok, text = buy(player, profile, npc, argument or "")
		page = "shop"
		message, kind = text, ok and "ok" or "error"
	end

	local payload = NpcService.Payload(profile, npcId, page)
	if payload and sink then
		sink(player, payload)
	end
	return message, kind
end

return NpcService
