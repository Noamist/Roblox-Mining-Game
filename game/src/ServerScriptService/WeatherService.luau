--!strict
-- Anime Miner Tycoon :: server-wide weather events

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local WeatherService = {}

local current = {
	def = Config.Weather[1],
	endsAt = os.clock() + Config.Weather[1].duration,
}
local running = false

function WeatherService.Current()
	local def = current.def
	local timeLeft = math.max(0, current.endsAt - os.clock())
	return {
		id = def.id,
		name = def.name,
		desc = def.desc,
		color = def.color,
		mult = def.mult,
		timeLeft = timeLeft,
		duration = def.duration,
	}
end

function WeatherService.Multipliers()
	return current.def.mult
end

function WeatherService.RollWeather()
	local def = Config.WeightedPick(Config.Weather)
	current = { def = def, endsAt = os.clock() + def.duration }
	return def
end

function WeatherService.Start(onChange)
	if running then
		return
	end
	running = true
	task.spawn(function()
		task.wait(2)
		while true do
			local def = WeatherService.RollWeather()
			if onChange then
				onChange(def)
			end
			task.wait(def.duration)
		end
	end)
end

return WeatherService
