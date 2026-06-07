--!strict
--[[
	GameConfig
	----------
	Configuration centrale et UNIQUE source de vérité du jeu.
	Ce ModuleScript est partagé entre le serveur et le client (ReplicatedStorage.Shared).

	Tu peux régler ici TOUT l'équilibrage du jeu :
	- la liste des bâtiments achetables (générateurs, batteries…)
	- les prix, la production, la capacité
	- le marché de l'énergie
	- le rebirth (prestige)
	- les IDs de monétisation (Gamepass / Developer Products)

	IMPORTANT : la seule chose que tu DOIS remplir manuellement, ce sont les
	IDs des Gamepasses et Developer Products (champs `.Id`). Ces IDs sont créés
	sur le site Roblox (Creator Hub) et ne peuvent pas être générés par le code.
	Tant qu'un Id vaut 0, le code l'ignore proprement (aucune erreur).
]]

local GameConfig = {}

-- =========================================================================
--  RÉGLAGES GÉNÉRAUX
-- =========================================================================
GameConfig.Game = {
	Name = "⚡ POWER TYCOON ⚡",
	TickRate = 1, -- secondes entre chaque tick de production/vente
	AutoSaveInterval = 60, -- sauvegarde automatique (secondes)
	StartingMoney = 250, -- argent de départ d'un nouveau joueur
}

-- =========================================================================
--  PLOT (la base de chaque joueur)
-- =========================================================================
GameConfig.Plot = {
	SlabSize = Vector3.new(150, 2, 200), -- taille de la dalle de base
	Spacing = 240, -- distance entre deux plots de joueurs
	BaseCapacity = 150, -- capacité de batterie de départ (Watts)
	GroundY = 0, -- la surface marchable est à Y = 0
	-- Couleurs d'ambiance de la base
	SlabColor = Color3.fromRGB(38, 42, 54),
	BorderColor = Color3.fromRGB(0, 200, 255),
	WallColor = Color3.fromRGB(28, 31, 40),
}

-- =========================================================================
--  MARCHÉ DE L'ÉNERGIE (prix fluctuant)
-- =========================================================================
GameConfig.Market = {
	BasePrice = 0.12, -- $ par Watt (valeur de référence)
	MinPrice = 0.05,
	MaxPrice = 0.45,
	UpdateInterval = 60, -- le prix change toutes les 60 secondes
	WavePeriod = 140, -- période (s) de la composante sinusoïdale lente
	Volatility = 0.05, -- amplitude du bruit aléatoire ajouté
}

-- =========================================================================
--  REBIRTH (Prestige)
-- =========================================================================
GameConfig.Rebirth = {
	BaseCost = 250000, -- coût du 1er rebirth
	CostMultiplier = 5, -- le coût est multiplié par 5 à chaque rebirth
	BonusPerRebirth = 0.30, -- +30% sur la valeur de vente par rebirth
}

-- =========================================================================
--  BÂTIMENTS ACHETABLES (séquence linéaire : un pad débloque le suivant)
--  Type : "Solar" | "Wind" | "Battery" | "Hydro" | "Nuclear"
--  Production : Watts par seconde produits
--  Capacity  : Watts de capacité de batterie ajoutés
-- =========================================================================
GameConfig.Buildings = {
	{ Name = "Panneau Solaire I",   Type = "Solar",   Price = 0,        Production = 3,    Capacity = 0,      Color = Color3.fromRGB(52, 152, 219) },
	{ Name = "Batterie I",          Type = "Battery", Price = 200,      Production = 0,    Capacity = 250,    Color = Color3.fromRGB(46, 204, 113) },
	{ Name = "Panneau Solaire II",  Type = "Solar",   Price = 600,      Production = 8,    Capacity = 0,      Color = Color3.fromRGB(52, 152, 219) },
	{ Name = "Éolienne I",          Type = "Wind",    Price = 1800,     Production = 20,   Capacity = 0,      Color = Color3.fromRGB(236, 240, 241) },
	{ Name = "Batterie II",         Type = "Battery", Price = 4000,     Production = 0,    Capacity = 1200,   Color = Color3.fromRGB(46, 204, 113) },
	{ Name = "Éolienne II",         Type = "Wind",    Price = 9000,     Production = 55,   Capacity = 0,      Color = Color3.fromRGB(236, 240, 241) },
	{ Name = "Panneau Solaire III", Type = "Solar",   Price = 20000,    Production = 130,  Capacity = 0,      Color = Color3.fromRGB(52, 152, 219) },
	{ Name = "Batterie III",        Type = "Battery", Price = 45000,    Production = 0,    Capacity = 6000,   Color = Color3.fromRGB(46, 204, 113) },
	{ Name = "Centrale Hydro I",    Type = "Hydro",   Price = 90000,    Production = 300,  Capacity = 0,      Color = Color3.fromRGB(26, 188, 156) },
	{ Name = "Éolienne III",        Type = "Wind",    Price = 200000,   Production = 650,  Capacity = 0,      Color = Color3.fromRGB(236, 240, 241) },
	{ Name = "Batterie IV",         Type = "Battery", Price = 450000,   Production = 0,    Capacity = 30000,  Color = Color3.fromRGB(46, 204, 113) },
	{ Name = "Centrale Hydro II",   Type = "Hydro",   Price = 900000,   Production = 1400, Capacity = 0,      Color = Color3.fromRGB(26, 188, 156) },
	{ Name = "Réacteur Nucléaire I", Type = "Nuclear", Price = 2000000, Production = 3200, Capacity = 0,      Color = Color3.fromRGB(241, 196, 15) },
	{ Name = "Batterie V",          Type = "Battery", Price = 4500000,  Production = 0,    Capacity = 150000, Color = Color3.fromRGB(46, 204, 113) },
	{ Name = "Réacteur Nucléaire II", Type = "Nuclear", Price = 9000000, Production = 7000, Capacity = 0,     Color = Color3.fromRGB(241, 196, 15) },
}

-- Bâtiment spécial VIP (hors séquence, débloqué via le Gamepass VIP)
GameConfig.VIPBuilding = {
	Name = "Réacteur à Fusion VIP",
	Type = "VIP",
	Production = 5000,
	Color = Color3.fromRGB(155, 89, 182),
}

-- =========================================================================
--  MONÉTISATION
--  Remplace les `Id = 0` par tes vrais IDs (Creator Hub > Monetization).
--  Tant que l'Id vaut 0, la fonctionnalité est désactivée proprement.
-- =========================================================================
GameConfig.Gamepasses = {
	DoubleEnergy = { Id = 0, Name = "Double Énergie", Desc = "Production ×2 en permanence", Multiplier = 2 },
	AutoSell     = { Id = 0, Name = "Auto-Sell",      Desc = "Vend ton énergie automatiquement" },
	VIP          = { Id = 0, Name = "Générateur VIP",  Desc = "Débloque le Réacteur à Fusion VIP" },
}

GameConfig.Products = {
	Cash10k     = { Id = 0, Name = "+10 000 $",   Desc = "Reçois 10 000 $ instantanément", Amount = 10000 },
	Cash100k    = { Id = 0, Name = "+100 000 $",  Desc = "Reçois 100 000 $ instantanément", Amount = 100000 },
	FullBattery = { Id = 0, Name = "Recharge Pleine", Desc = "Remplit instantanément ta batterie" },
}

-- =========================================================================
--  SONS (côté client)
--  On utilise un asset MOTEUR garanti présent (rbxasset, aucun téléchargement,
--  aucune modération) et on varie le rendu par PlaybackSpeed/Volume selon
--  l'action. Tu peux remplacer chaque Id par un asset perso (rbxassetid://...).
-- =========================================================================
GameConfig.Sounds = {
	Click   = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 1.70, Volume = 0.20 },
	Buy     = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 0.85, Volume = 0.45 },
	Build   = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 0.70, Volume = 0.55 },
	Cash    = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 1.25, Volume = 0.30 },
	Error   = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 0.55, Volume = 0.40 },
	Rebirth = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 0.50, Volume = 0.60 },
	Market  = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 1.45, Volume = 0.30 },
	Open    = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 1.50, Volume = 0.28 },
}

-- =========================================================================
--  ENVIRONNEMENT (cycle jour/nuit dynamique)
-- =========================================================================
GameConfig.Environment = {
	DayLength = 480, -- durée (s) d'un cycle de 24h complet
	DayBrightness = 2.6,
	NightBrightness = 0.7,
}

-- =========================================================================
--  HELPERS DÉRIVÉS (purs : utilisables côté serveur ET client)
-- =========================================================================

-- Coût du prochain rebirth en fonction du nombre de rebirths déjà effectués
function GameConfig.RebirthCost(rebirths: number): number
	local r = GameConfig.Rebirth
	return math.floor(r.BaseCost * (r.CostMultiplier ^ rebirths))
end

-- Multiplicateur de gains lié au rebirth (1 + 0.30 par rebirth)
function GameConfig.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * GameConfig.Rebirth.BonusPerRebirth
end

-- Production de base (Watts/s) et capacité (Watts) cumulées pour un avancement donné
function GameConfig.ComputeStats(progress: number, ownedVIP: boolean): (number, number)
	local prod, cap = 0, 0
	local count = math.min(progress, #GameConfig.Buildings)
	for i = 1, count do
		local b = GameConfig.Buildings[i]
		prod += (b.Production or 0)
		cap += (b.Capacity or 0)
	end
	if ownedVIP then
		prod += GameConfig.VIPBuilding.Production
	end
	return prod, cap
end

-- Capacité maximale de batterie (Watts) pour un avancement donné
function GameConfig.MaxWatts(progress: number, ownedVIP: boolean): number
	local _, cap = GameConfig.ComputeStats(progress, ownedVIP)
	return GameConfig.Plot.BaseCapacity + cap
end

return GameConfig
