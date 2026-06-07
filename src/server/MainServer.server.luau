--!strict
--[[
	==========================================================================
	  MAIN SERVER SCRIPT — ⚡ POWER TYCOON ⚡
	==========================================================================
	Script serveur CENTRAL. C'est le point d'entrée unique du jeu côté serveur.
	Il :
	  1. charge tous les services (Data, Market, Monetization, Plot)
	  2. les initialise dans le bon ordre (injection de dépendances)
	  3. gère le cycle de vie des joueurs :
	       - connexion  -> chargement des données -> attribution + construction du plot
	       - déconnexion -> sauvegarde + libération du plot
	  4. répond à la requête client "GetData" (config + données initiales pour l'UI)

	Tout le décor (dalle, générateurs, batteries, câbles, pads) est construit
	100% par le code : aucun objet à placer à la main dans Studio.

	À placer dans : ServerScriptService > MainServer  (Script, RunContext = Server)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- ----- Modules partagés -----
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))

-- ----- Services serveur -----
local Modules = ServerStorage:WaitForChild("Modules")
local DataService = require(Modules:WaitForChild("DataService"))
local MarketService = require(Modules:WaitForChild("MarketService"))
local MonetizationService = require(Modules:WaitForChild("MonetizationService"))
local LeaderboardService = require(Modules:WaitForChild("LeaderboardService"))
local EnvironmentService = require(Modules:WaitForChild("EnvironmentService"))
local PlotService = require(Modules:WaitForChild("PlotService"))

-- =========================================================================
--  INITIALISATION DES SERVICES
--  Ordre important : Data et Market n'ont pas de dépendances.
--  Monetization et Plot se référencent mutuellement -> injection de
--  dépendances (les tables de modules existent déjà après require()).
-- =========================================================================
DataService:Init()
MarketService:Init()
EnvironmentService:Init()
LeaderboardService:Init({ Data = DataService })
MonetizationService:Init({ Data = DataService, Plot = PlotService })
PlotService:Init({
	Data = DataService,
	Market = MarketService,
	Monetization = MonetizationService,
	Leaderboard = LeaderboardService,
})

print(string.format("[%s] Serveur initialisé.", GameConfig.Game.Name))

-- Crée les leaderstats natifs (affichés dans la liste des joueurs Roblox)
local function setupLeaderstats(player: Player, data: any)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local money = Instance.new("StringValue")
	money.Name = "Argent"
	money.Value = Format.Money(data.Money)
	money.Parent = ls
	local rebirth = Instance.new("IntValue")
	rebirth.Name = "Rebirth"
	rebirth.Value = data.Rebirths
	rebirth.Parent = ls
	ls.Parent = player
end

-- =========================================================================
--  CYCLE DE VIE DES JOUEURS
-- =========================================================================
local function onPlayerAdded(player: Player)
	-- 1) Données (avec sécurités anti-perte) — peut yield
	local data = DataService:Load(player)
	-- 2) leaderstats natifs + appartenance des gamepasses
	setupLeaderstats(player, data)
	MonetizationService:SetupPlayer(player)
	-- 3) Construction + attribution du plot, puis téléportation du joueur
	local ok, err = pcall(function()
		PlotService:AssignPlot(player, data)
	end)
	if not ok then
		warn("[MainServer] Échec d'attribution du plot pour " .. player.Name .. " : " .. tostring(err))
	end
end

local function onPlayerRemoving(player: Player)
	-- Publie le score final au classement avant de libérer les données
	local data = DataService:Get(player)
	if data then
		LeaderboardService:Report(player.UserId, data.Stats.TotalEarned or 0)
	end
	PlotService:ReleasePlot(player)
	MonetizationService:ClearPlayer(player)
	DataService:Release(player) -- sauvegarde + nettoyage du cache
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Gère les joueurs déjà présents (ex : rejoin/skip pendant un test Studio)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- =========================================================================
--  ÉTAT INITIAL POUR LE CLIENT
--  Le client appelle GetData au démarrage pour construire sa boutique et
--  son interface (liste des bâtiments, prix, infos de monétisation…).
-- =========================================================================
Remotes.Func("GetData").OnServerInvoke = function(player: Player)
	local plot = PlotService.Plots[player.UserId]
	local data = plot and plot.data or DataService:Get(player)

	return {
		Config = {
			GameName = GameConfig.Game.Name,
			Buildings = GameConfig.Buildings,
			VIPBuilding = GameConfig.VIPBuilding,
			Gamepasses = GameConfig.Gamepasses,
			Products = GameConfig.Products,
			Market = GameConfig.Market,
			Rebirth = GameConfig.Rebirth,
			BaseCapacity = GameConfig.Plot.BaseCapacity,
		},
		Data = data and {
			Money = data.Money,
			Watts = data.Watts,
			Rebirths = data.Rebirths,
			Progress = data.Progress,
			OwnedVIP = data.OwnedVIP,
			AutoSell = data.AutoSell,
			Stats = data.Stats,
		} or nil,
	}
end
