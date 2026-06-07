--!strict
--[[
	MonetizationService
	-------------------
	Gère TOUTE la monétisation via MarketplaceService :
	- Gamepasses : Double Énergie (×2 prod), Auto-Sell (vente auto), VIP (réacteur VIP)
	- Developer Products (consommables) : +10k $, +100k $, Recharge Pleine

	Détails techniques :
	- Le cache d'appartenance des gamepasses (self._owns) évite les appels réseau
	  répétés ; il est mis à jour à la connexion et après chaque achat.
	- ProcessReceipt traite les Developer Products et renvoie un
	  Enum.ProductPurchaseDecision (PurchaseGranted / NotProcessedYet).
	- Si un Id vaut 0 (non configuré), les fonctions le gèrent proprement : aucun
	  prompt n'est lancé et une notification "non configuré" est envoyée.

	Dépendances injectées dans :Init({ Data, Plot }).

	À placer dans : ServerStorage > Modules > MonetizationService
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MonetizationService = {}
MonetizationService._owns = {} :: { [number]: { [string]: boolean } }

-- ---------- Cache d'appartenance ----------
function MonetizationService:_setOwns(player: Player, key: string, value: boolean)
	local t = self._owns[player.UserId]
	if not t then
		t = {}
		self._owns[player.UserId] = t
	end
	t[key] = value
end

function MonetizationService:OwnsGamepass(player: Player, key: string): boolean
	local t = self._owns[player.UserId]
	return (t ~= nil and t[key]) == true
end

-- Interroge l'API pour tous les gamepasses configurés (appelé à la connexion)
function MonetizationService:SetupPlayer(player: Player)
	self._owns[player.UserId] = self._owns[player.UserId] or {}
	for key, gp in pairs(GameConfig.Gamepasses) do
		if gp.Id and gp.Id > 0 then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gp.Id)
				end)
				if ok then
					self:_setOwns(player, key, owns)
					if owns and key == "AutoSell" then
						local plot = self.Plot.Plots[player.UserId]
						if plot then
							plot.data.AutoSell = true
						end
					end
				end
			end)
		else
			self:_setOwns(player, key, false)
		end
	end
end

function MonetizationService:ClearPlayer(player: Player)
	self._owns[player.UserId] = nil
end

-- ---------- Prompts d'achat ----------
function MonetizationService:PromptGamepass(player: Player, key: string)
	local gp = GameConfig.Gamepasses[key]
	if not gp or not gp.Id or gp.Id <= 0 then
		Remotes.Event("Notify"):FireClient(player, {
			Kind = "error",
			Text = "« " .. (gp and gp.Name or key) .. " » : Id non configuré",
		})
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, gp.Id)
end

function MonetizationService:PromptProduct(player: Player, key: string)
	local p = GameConfig.Products[key]
	if not p or not p.Id or p.Id <= 0 then
		Remotes.Event("Notify"):FireClient(player, {
			Kind = "error",
			Text = "« " .. (p and p.Name or key) .. " » : Id non configuré",
		})
		return
	end
	MarketplaceService:PromptProductPurchase(player, p.Id)
end

-- ---------- Application des effets ----------
function MonetizationService:_applyProduct(key: string, player: Player): boolean
	local p = GameConfig.Products[key]
	if not p then
		return false
	end
	if key == "Cash10k" or key == "Cash100k" then
		self.Plot:GiveMoney(player, p.Amount)
		return true
	elseif key == "FullBattery" then
		self.Plot:FillBattery(player)
		return true
	end
	return false
end

function MonetizationService:_processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local handler = self._productHandlers[receiptInfo.ProductId]
	if not handler then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Le joueur est parti : on réessaiera quand il reviendra
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, player)
	if ok and granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService:Init(deps: { Data: any, Plot: any })
	self.Data = deps.Data
	self.Plot = deps.Plot
	self._owns = {}

	-- Table productId -> handler (uniquement pour les Ids configurés)
	self._productHandlers = {} :: { [number]: (Player) -> boolean }
	for key, p in pairs(GameConfig.Products) do
		if p.Id and p.Id > 0 then
			self._productHandlers[p.Id] = function(player: Player)
				return self:_applyProduct(key, player)
			end
		end
	end

	-- Traitement des Developer Products
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:_processReceipt(receiptInfo)
	end

	-- Mise à jour du cache après l'achat d'un gamepass
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, purchased)
		if not purchased then
			return
		end
		for key, gp in pairs(GameConfig.Gamepasses) do
			if gp.Id == gamepassId then
				self:_setOwns(player, key, true)
				Remotes.Event("Notify"):FireClient(player, { Kind = "build", Text = gp.Name .. " activé !" })
				local plot = self.Plot.Plots[player.UserId]
				if key == "VIP" then
					self.Plot:GrantVIP(player)
				elseif key == "AutoSell" and plot then
					plot.data.AutoSell = true
				end
				if plot then
					self.Plot:PushHUD(plot)
				end
			end
		end
	end)

	-- Demande d'achat venant du client (boutons UI)
	Remotes.Event("PromptPurchase").OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.Kind == "gamepass" then
			self:PromptGamepass(player, payload.Key)
		elseif payload.Kind == "product" then
			self:PromptProduct(player, payload.Key)
		end
	end)
end

return MonetizationService
