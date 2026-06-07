--!strict
--[[
	LeaderboardService
	------------------
	Classement mondial des plus gros vendeurs (Total gagné) via OrderedDataStore.
	- Toutes les ~45 s : publie le score des joueurs en ligne, récupère le TOP 10,
	  puis le rend sur TOUS les jumbotrons enregistrés (un par base de joueur).
	- Fallback : si l'API DataStore est indisponible (Studio sans accès API), le
	  classement se base sur les joueurs en ligne (pour que ça marche quand même).

	Les jumbotrons 3D sont construits par BuildingFactory et enregistrés par
	PlotService via Register / Unregister.

	À placer dans : ServerStorage > Modules > LeaderboardService
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local MEDALS = { "🥇", "🥈", "🥉" }

local LeaderboardService = {}
LeaderboardService.Boards = {} :: { [number]: Frame } -- userId -> content frame du jumbotron
LeaderboardService.Top = {} :: { any }
LeaderboardService._names = {} :: { [number]: string }
LeaderboardService.Enabled = false

-- ---------- Enregistrement des jumbotrons ----------
function LeaderboardService:Register(userId: number, contentFrame: Frame)
	self.Boards[userId] = contentFrame
	self:RenderInto(contentFrame)
end

function LeaderboardService:Unregister(userId: number)
	self.Boards[userId] = nil
end

-- ---------- Rendu ----------
function LeaderboardService:RenderInto(frame: Frame)
	-- Nettoie l'ancien contenu (on garde la mise en page)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end

	if #self.Top == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.BackgroundTransparency = 1
		empty.Text = "En attente de données…"
		empty.Font = Enum.Font.GothamMedium
		empty.TextScaled = true
		empty.TextColor3 = Color3.fromRGB(170, 178, 190)
		empty.Parent = frame
		return
	end

	for rank, entry in ipairs(self.Top) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundColor3 = (rank % 2 == 0) and Color3.fromRGB(30, 34, 46) or Color3.fromRGB(38, 43, 58)
		row.BorderSizePixel = 0
		row.LayoutOrder = rank
		row.Parent = frame

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = row

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0, 50, 1, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Text = MEDALS[rank] or ("#" .. rank)
		rankLabel.Font = Enum.Font.GothamBlack
		rankLabel.TextScaled = true
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Position = UDim2.new(0, 58, 0, 0)
		nameLabel.Size = UDim2.new(1, -210, 1, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = entry.name
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = Color3.fromRGB(240, 244, 250)
		nameLabel.Parent = row

		local scoreLabel = Instance.new("TextLabel")
		scoreLabel.AnchorPoint = Vector2.new(1, 0)
		scoreLabel.Position = UDim2.new(1, 0, 0, 0)
		scoreLabel.Size = UDim2.new(0, 150, 1, 0)
		scoreLabel.BackgroundTransparency = 1
		scoreLabel.Text = Format.Money(entry.score)
		scoreLabel.Font = Enum.Font.GothamBlack
		scoreLabel.TextScaled = true
		scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
		scoreLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
		scoreLabel.Parent = row
	end
end

function LeaderboardService:RenderAll()
	for _, frame in pairs(self.Boards) do
		if frame.Parent then
			self:RenderInto(frame)
		end
	end
end

-- ---------- Données ----------
function LeaderboardService:_nameFor(userId: number): string
	if self._names[userId] then
		return self._names[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		self._names[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local final = (ok and name) or ("Joueur " .. userId)
	self._names[userId] = final
	return final
end

-- Classement de secours basé sur les joueurs en ligne
function LeaderboardService:_buildOnlineTop()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local data = self.Data:Get(plr)
		if data then
			table.insert(list, {
				userId = plr.UserId,
				name = plr.DisplayName,
				score = math.floor(data.Stats.TotalEarned or 0),
			})
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	self.Top = list
end

function LeaderboardService:Refresh()
	if self.Enabled then
		-- 1) Publie le score des joueurs en ligne
		for _, plr in ipairs(Players:GetPlayers()) do
			local data = self.Data:Get(plr)
			if data then
				local score = math.floor(math.clamp(data.Stats.TotalEarned or 0, 0, 9e15))
				self._names[plr.UserId] = plr.DisplayName
				pcall(function()
					self.Store:SetAsync(tostring(plr.UserId), score)
				end)
			end
		end

		-- 2) Récupère le TOP 10 trié décroissant
		local ok, pages = pcall(function()
			return self.Store:GetSortedAsync(false, 10)
		end)
		if ok then
			local top = {}
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(entry.key) or 0
				table.insert(top, { userId = uid, name = self:_nameFor(uid), score = entry.value })
			end
			self.Top = top
		else
			self:_buildOnlineTop()
		end
	else
		self:_buildOnlineTop()
	end

	self:RenderAll()
end

-- Publie immédiatement le score d'un joueur (ex : à la déconnexion)
function LeaderboardService:Report(userId: number, score: number)
	if not self.Enabled then
		return
	end
	local clamped = math.floor(math.clamp(score, 0, 9e15))
	task.spawn(function()
		pcall(function()
			self.Store:SetAsync(tostring(userId), clamped)
		end)
	end)
end

function LeaderboardService:Init(deps: { Data: any })
	self.Data = deps.Data
	self.Boards = {}
	self.Top = {}
	self._names = {}

	local ok = pcall(function()
		self.Store = DataStoreService:GetOrderedDataStore("PowerTycoon_TopEarners_v1")
	end)
	self.Enabled = ok
	if not ok then
		warn("[LeaderboardService] OrderedDataStore indisponible — classement basé sur les joueurs en ligne.")
	end

	task.spawn(function()
		while true do
			local success, err = pcall(function()
				self:Refresh()
			end)
			if not success then
				warn("[LeaderboardService] Refresh: " .. tostring(err))
			end
			task.wait(45)
		end
	end)
end

return LeaderboardService
