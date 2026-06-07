--!strict
--[[
	DataService
	-----------
	Sauvegarde / chargement des données joueur via DataStoreService.

	Sécurités contre la perte de données (demande explicite "séparation des données") :
	- Un DataStore PRINCIPAL + un DataStore de BACKUP (clé séparée). Si le principal
	  est illisible au chargement, on bascule sur le backup.
	- Sonde rapide au démarrage : si l'API DataStore est indisponible (ex : "Studio
	  Access to API Services" désactivé), on passe en mode SESSION-ONLY (le jeu tourne
	  quand même, sans sauvegarde) au lieu de planter.
	- Si le chargement initial d'un joueur échoue, on N'ÉCRASE PAS ses données : la
	  sauvegarde est désactivée pour cette session (on préfère ne rien écrire plutôt
	  que d'écrire des données par défaut par-dessus une sauvegarde existante).
	- Sauvegarde via UpdateAsync (écriture atomique), retries avec backoff exponentiel,
	  autosave périodique et sauvegarde à l'arrêt du serveur (BindToClose).

	À placer dans : ServerStorage > Modules > DataService
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local STORE_MAIN = "PowerTycoon_Main_v1"
local STORE_BACKUP = "PowerTycoon_Backup_v1"

local DataService = {}
DataService.Cache = {} :: { [number]: any } -- userId -> data
DataService.FailedLoad = {} :: { [number]: boolean }
DataService.Enabled = false

local function KEY(userId: number): string
	return "plr_" .. tostring(userId)
end

-- Données par défaut d'un nouveau joueur
local function defaultData(): any
	return {
		Money = GameConfig.Game.StartingMoney,
		Watts = 0,
		Rebirths = 0,
		Progress = 0, -- nombre de bâtiments de la séquence achetés
		OwnedVIP = false,
		AutoSell = false,
		Stats = {
			TotalEarned = 0,
			TotalSold = 0,
			PlayTime = 0,
			Rebirths = 0,
		},
		Version = 1,
	}
end

-- Nettoie/valide les données chargées (anti-corruption + migration douce)
local function sanitize(raw: any): any
	local data = (type(raw) == "table") and raw or {}
	local d = defaultData()
	d.Money = tonumber(data.Money) or d.Money
	d.Watts = math.max(0, tonumber(data.Watts) or 0)
	d.Rebirths = math.max(0, math.floor(tonumber(data.Rebirths) or 0))
	d.Progress = math.clamp(math.floor(tonumber(data.Progress) or 0), 0, #GameConfig.Buildings)
	d.OwnedVIP = data.OwnedVIP == true
	d.AutoSell = data.AutoSell == true
	if type(data.Stats) == "table" then
		d.Stats.TotalEarned = tonumber(data.Stats.TotalEarned) or 0
		d.Stats.TotalSold = tonumber(data.Stats.TotalSold) or 0
		d.Stats.PlayTime = tonumber(data.Stats.PlayTime) or 0
		d.Stats.Rebirths = tonumber(data.Stats.Rebirths) or d.Rebirths
	end
	return d
end

-- Réessaie une opération avec backoff exponentiel (2s, 4s, 8s…)
local function retry(fn: () -> any, tries: number): (boolean, any)
	local ok, res
	for i = 1, tries do
		ok, res = pcall(fn)
		if ok then
			return true, res
		end
		if i < tries then
			task.wait(2 ^ (i - 1))
		end
	end
	return false, res
end

function DataService:Init()
	self.Cache = {}
	self.FailedLoad = {}
	self.Enabled = true

	local storeOk = pcall(function()
		self.Main = DataStoreService:GetDataStore(STORE_MAIN)
		self.Backup = DataStoreService:GetDataStore(STORE_BACKUP)
	end)
	if not storeOk then
		self.Enabled = false
		warn("[DataService] Impossible d'obtenir les DataStores — mode SESSION-ONLY.")
		return
	end

	-- Sonde rapide : un seul GetAsync pour détecter l'absence d'accès API
	local probeOk = pcall(function()
		self.Main:GetAsync("__probe__")
	end)
	if not probeOk then
		self.Enabled = false
		warn("[DataService] API DataStore inaccessible (active 'Studio Access to API Services' ?). Mode SESSION-ONLY : le jeu tourne mais ne sauvegarde pas.")
	end

	-- Autosave périodique
	task.spawn(function()
		while true do
			task.wait(GameConfig.Game.AutoSaveInterval)
			for _, plr in ipairs(Players:GetPlayers()) do
				if self.Cache[plr.UserId] then
					pcall(function()
						self:Save(plr)
					end)
				end
			end
		end
	end)

	-- Sauvegarde de tous les joueurs à l'arrêt du serveur
	game:BindToClose(function()
		for _, plr in ipairs(Players:GetPlayers()) do
			pcall(function()
				self:Save(plr)
			end)
		end
		task.wait(1)
	end)
end

-- Charge (ou crée) les données d'un joueur. Renvoie toujours une table valide.
function DataService:Load(player: Player): any
	local userId = player.UserId
	if self.Cache[userId] then
		return self.Cache[userId]
	end

	local raw: any = nil
	if self.Enabled then
		local ok, result = retry(function()
			return self.Main:GetAsync(KEY(userId))
		end, 4)
		if ok then
			raw = result
		else
			-- Tentative sur le backup
			local okB, backup = retry(function()
				return self.Backup:GetAsync(KEY(userId))
			end, 2)
			if okB and backup ~= nil then
				raw = backup
				warn("[DataService] Données principales illisibles — backup utilisé pour " .. player.Name)
			else
				-- Échec total : on protège la sauvegarde existante (pas d'écrasement)
				self.FailedLoad[userId] = true
				warn("[DataService] Chargement ÉCHOUÉ pour " .. player.Name .. " — sauvegarde désactivée cette session.")
			end
		end
	end

	local data = sanitize(raw)
	self.Cache[userId] = data
	return data
end

-- Renvoie les données en cache (ou nil)
function DataService:Get(player: Player): any
	return self.Cache[player.UserId]
end

-- Sauvegarde les données d'un joueur (principal + backup)
function DataService:Save(player: Player): boolean
	local userId = player.UserId
	local data = self.Cache[userId]
	if not data then
		return false
	end
	if not self.Enabled then
		return false
	end
	if self.FailedLoad[userId] then
		warn("[DataService] Sauvegarde ignorée (chargement initial échoué) pour " .. player.Name)
		return false
	end

	local ok = retry(function()
		self.Main:UpdateAsync(KEY(userId), function()
			return data
		end)
	end, 4)

	if ok then
		-- Backup best-effort (n'influence pas le résultat principal)
		pcall(function()
			self.Backup:SetAsync(KEY(userId), data)
		end)
	else
		warn("[DataService] Échec de sauvegarde pour " .. player.Name)
	end
	return ok
end

-- Sauvegarde puis libère le cache (à la déconnexion)
function DataService:Release(player: Player)
	self:Save(player)
	local userId = player.UserId
	self.Cache[userId] = nil
	self.FailedLoad[userId] = nil
end

return DataService
