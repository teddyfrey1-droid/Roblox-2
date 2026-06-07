--!strict
--[[
	PlotService
	-----------
	Cœur du gameplay côté serveur. Responsable de :
	- attribuer un plot (base) à chaque joueur et le CONSTRUIRE par code
	  (via BuildingFactory), puis téléporter le joueur dessus
	- la boucle de production : Production (Watts) -> Stockage (Batteries) -> Vente ($)
	- la gestion des pads d'achat (détection Touched, anti-spam, achat séquentiel)
	- la vente (manuelle ou automatique), le rebirth, l'auto-sell
	- la mise à jour des visuels (jauge de la batterie centrale) et de l'interface (HUD)

	Dépendances injectées dans :Init({ Data, Market, Monetization }).

	À placer dans : ServerStorage > Modules > PlotService
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modules = ServerStorage:WaitForChild("Modules")
local BuildingFactory = require(Modules:WaitForChild("BuildingFactory"))

-- Disposition de la grille des bâtiments sur le plot
local GRID_COLS = 4
local GRID_CELL = 30

local PlotService = {}
PlotService.Plots = {} :: { [number]: any }
PlotService.UsedOrigins = {} :: { [number]: boolean }

-- =========================================================================
--  POSITIONNEMENT
-- =========================================================================

-- Origine (surface marchable, Y = GroundY) du plot n°index
function PlotService:_computeOrigin(index: number): Vector3
	return Vector3.new(index * GameConfig.Plot.Spacing, GameConfig.Plot.GroundY, 0)
end

-- Réserve le prochain emplacement de plot libre
function PlotService:_nextFreeOrigin(): number
	local i = 0
	while self.UsedOrigins[i] do
		i += 1
	end
	self.UsedOrigins[i] = true
	return i
end

-- CFrame (au sol) de la cellule du bâtiment n°index1 (1-based)
function PlotService:_cellCFrame(plot: any, index1: number): CFrame
	local i = index1 - 1
	local col = i % GRID_COLS
	local row = math.floor(i / GRID_COLS)
	local x = (col - (GRID_COLS - 1) / 2) * GRID_CELL -- -45 .. 45
	local z = (row - 1.5) * GRID_CELL -- -45 .. 45 (lignes 0..3)
	return CFrame.new(plot.origin + Vector3.new(x, 0, z))
end

-- =========================================================================
--  CONSTRUCTION DU PLOT
-- =========================================================================

function PlotService:_buildPlot(plot: any)
	local folder = Instance.new("Model")
	folder.Name = "Plot_" .. tostring(plot.userId)
	folder.Parent = self.PlotsFolder
	plot.folder = folder

	-- Base (dalle + bordures + mur + panneau-nom)
	local baseModel = BuildingFactory.CreatePlotBase(plot.origin, plot.player.DisplayName)
	baseModel.Parent = folder

	-- Jumbotron / classement mondial (mis à jour par LeaderboardService)
	local lbModel, lbContent = BuildingFactory.CreateLeaderboard(CFrame.new(plot.origin + Vector3.new(0, 0, -90)))
	lbModel.Parent = folder
	if self.Leaderboard then
		self.Leaderboard:Register(plot.userId, lbContent)
	end

	-- Batterie centrale animée (jauge de charge) — à droite
	local batBase = plot.origin + Vector3.new(42, 0, 70)
	plot.batteryPos = batBase + Vector3.new(0, 9, 0)
	local batModel, fill = BuildingFactory.CreateCentralBattery(CFrame.new(batBase))
	batModel.Parent = folder
	plot.batteryModel = batModel
	plot.batteryFill = fill
	plot.batteryBottomY = fill.Position.Y - fill.Size.Y / 2
	local casing = batModel.PrimaryPart
	if casing then
		local info = casing:FindFirstChild("Info")
		local frame = info and info:FindFirstChildOfClass("Frame")
		plot.batteryPercentLabel = frame and frame:FindFirstChild("Price")
	end

	-- Hub de vente — au centre devant
	local hubModel, sellPart = BuildingFactory.CreateSellHub(CFrame.new(plot.origin + Vector3.new(0, 0, 72)))
	hubModel.Parent = folder
	plot.sellPart = sellPart
	self:_connectPad(plot, sellPart)

	-- Pad VIP — à gauche devant (si pas encore possédé)
	plot.vipCF = CFrame.new(plot.origin + Vector3.new(-45, 0, 70))
	if not plot.data.OwnedVIP then
		local vipModel, vipPad = BuildingFactory.CreatePad(GameConfig.VIPBuilding, plot.vipCF, "VIP", 0)
		vipModel.Parent = folder
		plot.vipPadModel = vipModel
		self:_connectPad(plot, vipPad)
	end
end

-- Construit instantanément tous les bâtiments déjà possédés (au chargement / rebirth)
function PlotService:_buildOwned(plot: any)
	for i = 1, plot.data.Progress do
		self:_placeBuilding(plot, i, false)
	end
	if plot.data.OwnedVIP then
		self:_placeVIPBuilding(plot, false)
	end
end

-- Anime un Model qui « sort de terre » jusqu'à sa position finale
function PlotService:_riseIn(model: Model)
	if not model.PrimaryPart then
		return
	end
	local target = model:GetPivot()
	model:PivotTo(target + Vector3.new(0, -14, 0))
	task.spawn(function()
		local steps = 22
		for s = 1, steps do
			if not model.Parent then
				return
			end
			local a = s / steps
			local ease = 1 - (1 - a) ^ 3 -- ease-out cubique
			model:PivotTo(target + Vector3.new(0, -14 * (1 - ease), 0))
			task.wait(0.018)
		end
		if model.Parent then
			model:PivotTo(target)
		end
	end)
end

-- Place un bâtiment de la séquence (index1) sur sa cellule
function PlotService:_placeBuilding(plot: any, index1: number, animate: boolean)
	if plot.buildings[index1] then
		return
	end
	local bcfg = GameConfig.Buildings[index1]
	if not bcfg then
		return
	end
	local cf = self:_cellCFrame(plot, index1)
	local model = BuildingFactory.Build(bcfg, cf)
	model.Parent = plot.folder
	plot.buildings[index1] = model
	-- Câble électrique vers la batterie centrale
	BuildingFactory.CreateCable(plot.folder, cf.Position + Vector3.new(0, 1, 0), plot.batteryPos, bcfg.Color)
	if animate then
		self:_riseIn(model)
	end
end

-- Place le réacteur VIP
function PlotService:_placeVIPBuilding(plot: any, animate: boolean)
	if plot.vipBuilding then
		return
	end
	local model = BuildingFactory.Build(GameConfig.VIPBuilding, plot.vipCF)
	model.Parent = plot.folder
	plot.vipBuilding = model
	BuildingFactory.CreateCable(plot.folder, plot.vipCF.Position + Vector3.new(0, 1, 0), plot.batteryPos, GameConfig.VIPBuilding.Color)
	if plot.vipPadModel then
		plot.vipPadModel:Destroy()
		plot.vipPadModel = nil
	end
	if animate then
		self:_riseIn(model)
	end
end

-- =========================================================================
--  PADS
-- =========================================================================

function PlotService:_clearActivePad(plot: any)
	if plot.activePad then
		plot.activePad:Destroy()
		plot.activePad = nil
	end
end

-- Fait apparaître le pad du prochain bâtiment à acheter (s'il en reste)
function PlotService:_spawnActivePad(plot: any)
	local nextIndex = plot.data.Progress + 1
	local bcfg = GameConfig.Buildings[nextIndex]
	if not bcfg then
		plot.activePad = nil -- tout est acheté
		return
	end
	local cf = self:_cellCFrame(plot, nextIndex)
	local model, pad = BuildingFactory.CreatePad(bcfg, cf, "BUY", nextIndex)
	model.Parent = plot.folder
	plot.activePad = model
	self:_connectPad(plot, pad)
end

-- Connecte le Touched d'un pad (achat / vente / VIP) avec anti-spam
function PlotService:_connectPad(plot: any, pad: BasePart)
	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or player.UserId ~= plot.userId then
			return
		end
		local kind = pad:GetAttribute("Kind")
		local index = pad:GetAttribute("Index")
		local now = os.clock()
		local key = tostring(kind) .. ":" .. tostring(index)
		if plot.padCooldown[key] and (now - plot.padCooldown[key]) < 0.8 then
			return
		end
		plot.padCooldown[key] = now

		if kind == "SELL" then
			self:Sell(plot)
		elseif kind == "VIP" then
			self:BuyVIP(plot)
		elseif kind == "BUY" then
			self:Buy(plot, index)
		end
	end)
end

-- =========================================================================
--  ÉCONOMIE
-- =========================================================================

-- Production en Watts/seconde (base + gamepass Double Énergie)
function PlotService:_productionPerSecond(plot: any): number
	local data = plot.data
	local prod = (GameConfig.ComputeStats(data.Progress, data.OwnedVIP))
	if self.Monetization:OwnsGamepass(plot.player, "DoubleEnergy") then
		prod *= GameConfig.Gamepasses.DoubleEnergy.Multiplier
	end
	return prod
end

-- Convertit l'énergie stockée en argent. Renvoie le gain (0 si rien).
function PlotService:_doSell(plot: any): number
	local data = plot.data
	local amount = math.floor(data.Watts)
	if amount <= 0 then
		return 0
	end
	local price = self.Market:GetPrice()
	local mult = GameConfig.RebirthMultiplier(data.Rebirths)
	local earnings = math.floor(amount * price * mult)
	if earnings <= 0 then
		return 0
	end
	data.Money += earnings
	data.Watts -= amount
	data.Stats.TotalEarned += earnings
	data.Stats.TotalSold += amount
	return earnings
end

-- Vente manuelle (bouton UI ou pad de vente)
function PlotService:Sell(plot: any)
	local earnings = self:_doSell(plot)
	if earnings > 0 then
		Remotes.Event("Notify"):FireClient(plot.player, { Kind = "cash", Amount = earnings })
	else
		Remotes.Event("Notify"):FireClient(plot.player, { Kind = "info", Text = "Batterie vide" })
	end
	self:PushHUD(plot)
end

-- Achat séquentiel d'un bâtiment
function PlotService:Buy(plot: any, index1: number)
	local data = plot.data
	if index1 ~= data.Progress + 1 then
		return -- on ne peut acheter que le prochain de la séquence
	end
	local bcfg = GameConfig.Buildings[index1]
	if not bcfg then
		return
	end
	if data.Money < bcfg.Price then
		Remotes.Event("Notify"):FireClient(plot.player, {
			Kind = "error",
			Text = "Pas assez d'argent (" .. Format.Money(bcfg.Price) .. ")",
		})
		return
	end

	data.Money -= bcfg.Price
	data.Progress = index1
	self:_placeBuilding(plot, index1, true)
	Remotes.Event("BuildFX"):FireClient(plot.player, { Pos = self:_cellCFrame(plot, index1).Position })
	Remotes.Event("Notify"):FireClient(plot.player, { Kind = "build", Text = "Construit : " .. bcfg.Name })
	self:_clearActivePad(plot)
	self:_spawnActivePad(plot)
	self:PushHUD(plot)
end

-- Achat / activation du réacteur VIP (nécessite le gamepass VIP)
function PlotService:BuyVIP(plot: any)
	local data = plot.data
	if data.OwnedVIP then
		Remotes.Event("Notify"):FireClient(plot.player, { Kind = "info", Text = "Réacteur VIP déjà actif" })
		return
	end
	if not self.Monetization:OwnsGamepass(plot.player, "VIP") then
		self.Monetization:PromptGamepass(plot.player, "VIP")
		return
	end
	data.OwnedVIP = true
	self:_placeVIPBuilding(plot, true)
	Remotes.Event("Notify"):FireClient(plot.player, { Kind = "build", Text = "Réacteur à Fusion VIP activé !" })
	self:PushHUD(plot)
end

-- Accordé par MonetizationService quand le gamepass VIP est acheté en jeu
function PlotService:GrantVIP(player: Player)
	local plot = self.Plots[player.UserId]
	if not plot or plot.data.OwnedVIP then
		return
	end
	plot.data.OwnedVIP = true
	self:_placeVIPBuilding(plot, true)
	self:PushHUD(plot)
end

-- Rebirth (prestige) : reset de la progression contre un multiplicateur permanent
function PlotService:Rebirth(plot: any)
	local data = plot.data
	local cost = GameConfig.RebirthCost(data.Rebirths)
	if data.Money < cost then
		Remotes.Event("Notify"):FireClient(plot.player, {
			Kind = "error",
			Text = "Rebirth : il te faut " .. Format.Money(cost),
		})
		return
	end

	data.Rebirths += 1
	data.Money = GameConfig.Game.StartingMoney
	data.Watts = 0
	data.Progress = 0
	data.Stats.Rebirths = data.Rebirths

	-- Reconstruit la séquence depuis zéro (le réacteur VIP est conservé)
	for _, model in pairs(plot.buildings) do
		model:Destroy()
	end
	plot.buildings = {}
	self:_clearActivePad(plot)
	self:_spawnActivePad(plot)

	local mult = GameConfig.RebirthMultiplier(data.Rebirths)
	Remotes.Event("Notify"):FireClient(plot.player, {
		Kind = "build",
		Text = string.format("⭐ REBIRTH ! Gains ×%.2f", mult),
	})
	self:PushHUD(plot)
end

-- Active/désactive la vente automatique
function PlotService:ToggleAutoSell(plot: any)
	if self.Monetization:OwnsGamepass(plot.player, "AutoSell") then
		plot.data.AutoSell = true -- verrouillé ON par le gamepass
	else
		plot.data.AutoSell = not plot.data.AutoSell
	end
	self:PushHUD(plot)
end

-- Donne de l'argent (Developer Products)
function PlotService:GiveMoney(player: Player, amount: number)
	local plot = self.Plots[player.UserId]
	if not plot then
		return
	end
	plot.data.Money += amount
	Remotes.Event("Notify"):FireClient(player, { Kind = "cash", Amount = amount })
	self:PushHUD(plot)
end

-- Remplit instantanément la batterie (Developer Product)
function PlotService:FillBattery(player: Player)
	local plot = self.Plots[player.UserId]
	if not plot then
		return
	end
	plot.data.Watts = GameConfig.MaxWatts(plot.data.Progress, plot.data.OwnedVIP)
	Remotes.Event("Notify"):FireClient(player, { Kind = "info", Text = "Batterie rechargée à 100% !" })
	self:PushHUD(plot)
end

-- =========================================================================
--  VISUELS & HUD
-- =========================================================================

-- Met à jour la jauge 3D de la batterie centrale (hauteur + couleur)
function PlotService:_updateBatteryVisual(plot: any, maxW: number)
	local fill = plot.batteryFill
	if not fill or not fill.Parent then
		return
	end
	local ratio = (maxW > 0) and math.clamp(plot.data.Watts / maxW, 0, 1) or 0
	local maxH = 16
	local h = math.max(0.2, ratio * maxH)
	local goalCF = CFrame.new(fill.Position.X, plot.batteryBottomY + h / 2, fill.Position.Z)
	local color = Color3.fromRGB(231, 76, 60):Lerp(Color3.fromRGB(46, 204, 113), ratio)

	TweenService:Create(fill, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		Size = Vector3.new(6.5, h, 6.5),
		CFrame = goalCF,
		Color = color,
	}):Play()

	if plot.batteryPercentLabel then
		plot.batteryPercentLabel.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
		plot.batteryPercentLabel.TextColor3 = color
	end
end

-- Envoie l'état complet au client (interface)
function PlotService:PushHUD(plot: any)
	local data = plot.data
	local maxW = GameConfig.MaxWatts(data.Progress, data.OwnedVIP)
	local prod = self:_productionPerSecond(plot)
	local ownsAuto = self.Monetization:OwnsGamepass(plot.player, "AutoSell")

	-- leaderstats natifs (liste des joueurs Roblox)
	local ls = plot.player:FindFirstChild("leaderstats")
	if ls then
		local m = ls:FindFirstChild("Argent")
		if m then
			(m :: StringValue).Value = Format.Money(data.Money)
		end
		local r = ls:FindFirstChild("Rebirth")
		if r then
			(r :: IntValue).Value = data.Rebirths
		end
	end
	Remotes.Event("UpdateHUD"):FireClient(plot.player, {
		Money = data.Money,
		Watts = data.Watts,
		MaxWatts = maxW,
		Production = prod,
		Rebirths = data.Rebirths,
		RebirthCost = GameConfig.RebirthCost(data.Rebirths),
		RebirthMult = GameConfig.RebirthMultiplier(data.Rebirths),
		AutoSell = data.AutoSell or ownsAuto,
		AutoSellLocked = ownsAuto,
		Price = self.Market:GetPrice(),
		Progress = data.Progress,
		OwnedVIP = data.OwnedVIP,
		Stats = data.Stats,
	})
end

-- =========================================================================
--  BOUCLE DE PRODUCTION
-- =========================================================================

function PlotService:Tick(plot: any, dt: number)
	local data = plot.data
	local maxW = GameConfig.MaxWatts(data.Progress, data.OwnedVIP)
	local prod = self:_productionPerSecond(plot)

	data.Watts = math.min(maxW, data.Watts + prod * dt)
	data.Stats.PlayTime += dt

	local autoOn = data.AutoSell or self.Monetization:OwnsGamepass(plot.player, "AutoSell")
	if autoOn then
		local earnings = self:_doSell(plot)
		if earnings > 0 then
			local now = os.clock()
			if (now - (plot.lastCashNotify or 0)) >= 0.9 then
				plot.lastCashNotify = now
				Remotes.Event("Notify"):FireClient(plot.player, { Kind = "cash", Amount = earnings })
			end
		end
	end

	self:_updateBatteryVisual(plot, maxW)
	self:PushHUD(plot)
end

-- =========================================================================
--  CYCLE DE VIE JOUEUR
-- =========================================================================

-- Téléporte le personnage (présent et futurs) sur le plot du joueur
function PlotService:_bindCharacter(plot: any)
	local spawnCF = CFrame.new(plot.origin + Vector3.new(0, 5, 90)) * CFrame.Angles(0, math.rad(180), 0)
	local function place(character: Model)
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		if hrp then
			task.wait(0.1)
			character:PivotTo(spawnCF)
		end
	end
	if plot.player.Character then
		task.spawn(place, plot.player.Character)
	end
	plot._charConn = plot.player.CharacterAdded:Connect(place)
end

function PlotService:AssignPlot(player: Player, data: any): any
	local index = self:_nextFreeOrigin()
	local plot = {
		player = player,
		userId = player.UserId,
		data = data,
		originIndex = index,
		origin = self:_computeOrigin(index),
		buildings = {},
		padCooldown = {},
		lastCashNotify = 0,
	}
	self.Plots[player.UserId] = plot

	self:_buildPlot(plot)
	self:_buildOwned(plot)
	self:_spawnActivePad(plot)
	self:_bindCharacter(plot)
	self:PushHUD(plot)
	return plot
end

function PlotService:ReleasePlot(player: Player)
	local plot = self.Plots[player.UserId]
	if not plot then
		return
	end
	if plot._charConn then
		plot._charConn:Disconnect()
	end
	if self.Leaderboard then
		self.Leaderboard:Unregister(player.UserId)
	end
	if plot.folder then
		plot.folder:Destroy()
	end
	self.UsedOrigins[plot.originIndex] = nil
	self.Plots[player.UserId] = nil
end

-- =========================================================================
--  INITIALISATION
-- =========================================================================

function PlotService:Init(deps: { Data: any, Market: any, Monetization: any, Leaderboard: any })
	self.Data = deps.Data
	self.Market = deps.Market
	self.Monetization = deps.Monetization
	self.Leaderboard = deps.Leaderboard
	self.Plots = {}
	self.UsedOrigins = {}

	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	folder.Parent = workspace
	self.PlotsFolder = folder

	-- Remotes pilotés par le client
	Remotes.Event("RequestSell").OnServerEvent:Connect(function(plr)
		local plot = self.Plots[plr.UserId]
		if plot then
			self:Sell(plot)
		end
	end)
	Remotes.Event("RequestBuy").OnServerEvent:Connect(function(plr)
		local plot = self.Plots[plr.UserId]
		if plot then
			self:Buy(plot, plot.data.Progress + 1)
		end
	end)
	Remotes.Event("RequestRebirth").OnServerEvent:Connect(function(plr)
		local plot = self.Plots[plr.UserId]
		if plot then
			self:Rebirth(plot)
		end
	end)
	Remotes.Event("ToggleAutoSell").OnServerEvent:Connect(function(plr)
		local plot = self.Plots[plr.UserId]
		if plot then
			self:ToggleAutoSell(plot)
		end
	end)

	-- Boucle de production globale (un seul thread pour tous les plots)
	task.spawn(function()
		while true do
			local dt = GameConfig.Game.TickRate
			for _, plot in pairs(self.Plots) do
				local ok, err = pcall(function()
					self:Tick(plot, dt)
				end)
				if not ok then
					warn("[PlotService] Erreur de tick : " .. tostring(err))
				end
			end
			task.wait(dt)
		end
	end)
end

return PlotService
