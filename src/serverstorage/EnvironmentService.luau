--!strict
--[[
	EnvironmentService
	------------------
	Cycle jour/nuit dynamique. Fait avancer Lighting.ClockTime en continu et
	ajuste la luminosité (pleine le jour, faible la nuit) avec une transition
	douce. L'Atmosphere / Bloom configurés via Rojo donnent le rendu "premium".

	À placer dans : ServerStorage > Modules > EnvironmentService
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local EnvironmentService = {}

function EnvironmentService:Init()
	local cfg = GameConfig.Environment
	Lighting.ClockTime = 14

	-- On met à jour Lighting ~10 fois/seconde (fluide et léger pour le réseau)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		local step = accumulator
		accumulator = 0

		-- Avance de l'horloge (24h sur DayLength secondes)
		Lighting.ClockTime = (Lighting.ClockTime + (24 / cfg.DayLength) * step) % 24

		-- Facteur jour 0..1 (1 = midi, 0 = minuit) via une sinusoïde
		local t = Lighting.ClockTime
		local dayFactor = math.sin((t / 24) * 2 * math.pi - math.pi / 2) * 0.5 + 0.5
		Lighting.Brightness = cfg.NightBrightness + (cfg.DayBrightness - cfg.NightBrightness) * dayFactor
	end)
end

return EnvironmentService
