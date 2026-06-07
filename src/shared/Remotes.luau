--!strict
--[[
	Remotes
	-------
	Crée et expose tous les RemoteEvents / RemoteFunctions du jeu.
	- Côté serveur : crée le dossier ReplicatedStorage/Remotes et les instances.
	- Côté client  : attend que le serveur les ait créées.

	Utilisation :
		local Remotes = require(ReplicatedStorage.Shared.Remotes)
		Remotes.Event("UpdateHUD"):FireClient(player, data)
		Remotes.Func("GetData").OnServerInvoke = function(plr) ... end
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

-- Liste des événements et fonctions distantes du jeu
local EVENTS = {
	"UpdateHUD", -- Serveur -> Client : rafraîchit l'interface (argent, watts…)
	"MarketUpdate", -- Serveur -> Client : nouveau prix de l'énergie
	"Notify", -- Serveur -> Client : popup ("+150$", message…)
	"BuildFX", -- Serveur -> Client : effet sonore/visuel lors d'une construction
	"RequestSell", -- Client -> Serveur : vendre l'énergie stockée
	"RequestBuy", -- Client -> Serveur : acheter le prochain bâtiment (depuis la boutique)
	"RequestRebirth", -- Client -> Serveur : effectuer un rebirth
	"ToggleAutoSell", -- Client -> Serveur : activer/désactiver la vente auto
	"PromptPurchase", -- Client -> Serveur : ouvrir l'achat d'un gamepass/produit
}

local FUNCTIONS = {
	"GetData", -- Client -> Serveur : récupère l'état initial (config + données joueur)
}

local Remotes = {}

local folder: Folder

if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	for _, name in ipairs(EVENTS) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in ipairs(FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

-- Récupère un RemoteEvent par son nom
function Remotes.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Récupère une RemoteFunction par son nom
function Remotes.Func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
