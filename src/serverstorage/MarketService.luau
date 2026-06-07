--!strict
--[[
	MarketService
	-------------
	Gère le PRIX DU MARCHÉ de l'énergie ($ par Watt), partagé par tous les joueurs.
	Le prix fluctue de manière algorithmique toutes les 60 secondes :
	- une composante sinusoïdale LENTE (tendance de fond)
	- un BRUIT aléatoire (volatilité court terme)
	Le tout est borné entre MinPrice et MaxPrice.

	À chaque mise à jour, le nouveau prix + la tendance (hausse/baisse) sont diffusés
	à tous les clients via le remote "MarketUpdate" (pour l'affichage et les pop-ups).

	À placer dans : ServerStorage > Modules > MarketService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MarketService = {}
MarketService.Price = GameConfig.Market.BasePrice
MarketService.Trend = 0 -- +1 = hausse, -1 = baisse, 0 = stable
MarketService.History = {} :: { number }

-- Calcule le nouveau prix
function MarketService:Fluctuate()
	local cfg = GameConfig.Market
	local t = os.clock()

	-- Onde lente (0..1) -> tendance de fond
	local wave = (math.sin(t / cfg.WavePeriod * math.pi * 2) * 0.5) + 0.5
	-- Bruit aléatoire centré
	local noise = (math.random() - 0.5) * 2 * cfg.Volatility

	local span = cfg.MaxPrice - cfg.MinPrice
	local target = cfg.MinPrice + span * wave + noise
	local newPrice = math.clamp(target, cfg.MinPrice, cfg.MaxPrice)

	if newPrice > self.Price + 0.0001 then
		self.Trend = 1
	elseif newPrice < self.Price - 0.0001 then
		self.Trend = -1
	else
		self.Trend = 0
	end

	self.Price = newPrice
	table.insert(self.History, newPrice)
	if #self.History > 30 then
		table.remove(self.History, 1)
	end
end

-- Diffuse le prix actuel à tous les clients
function MarketService:Broadcast()
	Remotes.Event("MarketUpdate"):FireAllClients({
		Price = self.Price,
		Trend = self.Trend,
		Min = GameConfig.Market.MinPrice,
		Max = GameConfig.Market.MaxPrice,
	})
end

function MarketService:GetPrice(): number
	return self.Price
end

function MarketService:Init()
	-- Prix initial diffusé immédiatement, puis boucle de fluctuation
	self:Fluctuate()
	self:Broadcast()
	task.spawn(function()
		while true do
			task.wait(GameConfig.Market.UpdateInterval)
			self:Fluctuate()
			self:Broadcast()
		end
	end)
end

return MarketService
