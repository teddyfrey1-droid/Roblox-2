--!strict
--[[
	BuildingFactory  (le "BuildingModule")
	--------------------------------------
	Génère TOUTE la géométrie du Tycoon par le code (Instance.new) :
	- la base/plot (dalle, bordures néon, mur, panneau-nom)
	- les bâtiments (panneaux solaires, éoliennes, batteries, hydro, nucléaire, VIP)
	- la batterie centrale animée (jauge de charge)
	- le hub de vente
	- les pads d'achat avec BillboardGui (nom + prix en 3D) et détection Touched
	- les câbles électriques néon

	Ce module est PUR (il ne fait que construire et renvoyer des Instances).
	Toute la logique de jeu est gérée par PlotService.

	À placer dans : ServerStorage > Modules > BuildingFactory
]]

local CollectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Format = require(ReplicatedStorage.Shared.Format)

local BuildingFactory = {}

-- Tag utilisé pour faire tourner les pales d'éolienne côté client (gratuit en réseau)
BuildingFactory.ROTOR_TAG = "PT_WindRotor"

-- Couleurs utilitaires
local METAL = Color3.fromRGB(170, 178, 186)
local DARK = Color3.fromRGB(30, 33, 42)
local PANEL_NAVY = Color3.fromRGB(18, 24, 48)

-- =========================================================================
--  HELPERS BAS NIVEAU
-- =========================================================================

-- Crée une Part ancrée avec des valeurs par défaut propres, puis applique props
local function newPart(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Crée un coin arrondi (UICorner-like) pour une frame de BillboardGui
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

-- Construit une BillboardGui (titre + sous-titre + prix) au-dessus d'une part
local function makeBillboard(adornee: BasePart, title: string, subtitle: string, accent: Color3): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "Info"
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(220, 96)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 220
	bb.LightInfluence = 0

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.Parent = bb
	corner(bg, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = accent
	stroke.Transparency = 0.1
	stroke.Parent = bg

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 2)
	layout.Parent = bg

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Title"
	nameLabel.Size = UDim2.new(1, -10, 0, 28)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = title
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = bg

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.new(1, -10, 0, 30)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.GothamBlack
	priceLabel.Text = subtitle
	priceLabel.TextColor3 = accent
	priceLabel.TextScaled = true
	priceLabel.TextStrokeTransparency = 0.4
	priceLabel.LayoutOrder = 2
	priceLabel.Parent = bg

	bb.Parent = adornee
	return bb
end

-- Câble électrique néon entre deux points du monde
function BuildingFactory.CreateCable(parent: Instance, fromPos: Vector3, toPos: Vector3, color: Color3): Part
	local dist = (toPos - fromPos).Magnitude
	local mid = (fromPos + toPos) / 2
	return newPart(parent, {
		Name = "Cable",
		Size = Vector3.new(0.3, 0.3, math.max(dist, 0.1)),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.25,
		CFrame = CFrame.lookAt(mid, toPos),
	})
end

-- =========================================================================
--  BÂTIMENTS
-- =========================================================================

-- Panneau solaire : pied métal + panneau incliné + grille néon
local function buildSolar(model: Model, base: CFrame, color: Color3)
	local stand = newPart(model, {
		Name = "Stand",
		Size = Vector3.new(1.2, 4, 1.2),
		Material = Enum.Material.Metal,
		Color = METAL,
		CFrame = base * CFrame.new(0, 2, 0),
	})
	local panelCF = base * CFrame.new(0, 4.6, 0) * CFrame.Angles(math.rad(-32), 0, 0)
	newPart(model, {
		Name = "Panel",
		Size = Vector3.new(11, 0.4, 7.5),
		Material = Enum.Material.SmoothPlastic,
		Color = PANEL_NAVY,
		CFrame = panelCF,
	})
	newPart(model, {
		Name = "Cells",
		Size = Vector3.new(10.2, 0.18, 6.8),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.12,
		CFrame = panelCF * CFrame.new(0, 0.32, 0),
	})
	-- Lignes de séparation des cellules (esthétique)
	for i = -2, 2 do
		newPart(model, {
			Name = "Grid",
			Size = Vector3.new(0.18, 0.22, 6.8),
			Material = Enum.Material.SmoothPlastic,
			Color = DARK,
			CFrame = panelCF * CFrame.new(i * 1.9, 0.34, 0),
		})
	end
	model.PrimaryPart = stand
end

-- Éolienne : mât + nacelle + rotor à 3 pales (tag pour rotation côté client)
local function buildWind(model: Model, base: CFrame, color: Color3)
	local tower = newPart(model, {
		Name = "Tower",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(22, 2.2, 2.2),
		Material = Enum.Material.Metal,
		Color = color,
		CastShadow = true,
		CFrame = base * CFrame.new(0, 11, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	newPart(model, {
		Name = "Nacelle",
		Size = Vector3.new(4, 2.4, 2.4),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(210, 214, 220),
		CFrame = base * CFrame.new(0, 22, 0.8),
	})

	-- Rotor : moyeu + 3 pales, regroupés dans un sous-Model pour la rotation.
	-- Le moyeu est un Block d'orientation identité : le pivot du rotor vaut donc
	-- exactement hubCF (axe de rotation = Z monde au repos).
	local rotor = Instance.new("Model")
	rotor.Name = "Rotor"
	local hubCF = base * CFrame.new(0, 22, 2.2)
	local hub = newPart(rotor, {
		Name = "Hub",
		Size = Vector3.new(1.6, 1.6, 1.2),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(120, 124, 130),
		CFrame = hubCF,
	})
	for i = 0, 2 do
		local bladeCF = hubCF * CFrame.Angles(0, 0, math.rad(i * 120)) * CFrame.new(0, 6, 0)
		newPart(rotor, {
			Name = "Blade",
			Size = Vector3.new(0.5, 11, 1.4),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(245, 247, 250),
			CFrame = bladeCF,
		})
	end
	rotor.PrimaryPart = hub
	rotor:SetAttribute("SpinSpeed", 2.2) -- rad/s, lu par le spinner client
	-- Axe de rotation exprimé RELATIVEMENT à la tour (PrimaryPart du bâtiment).
	-- La tour ne tourne jamais : le client reconstruit l'axe = tower.CFrame * RestOffset,
	-- ce qui reste correct même pendant l'animation de sortie de terre.
	rotor:SetAttribute("RestOffset", tower.CFrame:Inverse() * hubCF)
	rotor.Parent = model
	CollectionService:AddTag(rotor, BuildingFactory.ROTOR_TAG)

	model.PrimaryPart = tower
end

-- Batterie décorative : boîtier + bornes + bandes néon
local function buildBattery(model: Model, base: CFrame, color: Color3)
	local casing = newPart(model, {
		Name = "Casing",
		Size = Vector3.new(6, 8, 6),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(34, 38, 48),
		CastShadow = true,
		CFrame = base * CFrame.new(0, 4, 0),
	})
	newPart(model, {
		Name = "Terminal",
		Size = Vector3.new(2.4, 1, 2.4),
		Material = Enum.Material.Metal,
		Color = METAL,
		CFrame = base * CFrame.new(0, 8.4, 0),
	})
	for i = -1, 1 do
		newPart(model, {
			Name = "Strip",
			Size = Vector3.new(6.2, 0.6, 0.4),
			Material = Enum.Material.Neon,
			Color = color,
			CFrame = base * CFrame.new(0, 4 + i * 2, 3.05),
		})
		newPart(model, {
			Name = "Strip",
			Size = Vector3.new(0.4, 0.6, 6.2),
			Material = Enum.Material.Neon,
			Color = color,
			CFrame = base * CFrame.new(3.05, 4 + i * 2, 0),
		})
	end
	model.PrimaryPart = casing
end

-- Centrale hydroélectrique : socle béton + turbines néon + déversoir
local function buildHydro(model: Model, base: CFrame, color: Color3)
	local slab = newPart(model, {
		Name = "Block",
		Size = Vector3.new(15, 6, 11),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(120, 126, 134),
		CastShadow = true,
		CFrame = base * CFrame.new(0, 3, 0),
	})
	for i = -1, 1, 2 do
		newPart(model, {
			Name = "Turbine",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2, 4.5, 4.5),
			Material = Enum.Material.Neon,
			Color = color,
			CFrame = base * CFrame.new(i * 4, 4, 5.6) * CFrame.Angles(0, 0, math.rad(90)),
		})
	end
	newPart(model, {
		Name = "Spillway",
		Size = Vector3.new(13, 0.4, 6),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 200, 255),
		Transparency = 0.35,
		CFrame = base * CFrame.new(0, 6.1, 2) * CFrame.Angles(math.rad(-12), 0, 0),
	})
	model.PrimaryPart = slab
end

-- Réacteur nucléaire : tour de refroidissement + cœur néon
local function buildNuclear(model: Model, base: CFrame, color: Color3)
	local towerBottom = newPart(model, {
		Name = "TowerBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7, 13, 13),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(206, 210, 214),
		CastShadow = true,
		CFrame = base * CFrame.new(0, 3.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	newPart(model, {
		Name = "TowerTop",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 16, 16),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(224, 228, 232),
		CFrame = base * CFrame.new(0, 11.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	newPart(model, {
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6, 6, 6),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.1,
		CFrame = base * CFrame.new(0, 4, 0),
	})
	-- Vapeur (semi-transparente) au sommet
	for i = 1, 3 do
		newPart(model, {
			Name = "Steam",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(7, 7, 7),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(235, 238, 242),
			Transparency = 0.7,
			CFrame = base * CFrame.new(math.sin(i) * 2, 19 + i * 2.5, math.cos(i) * 2),
		})
	end
	model.PrimaryPart = towerBottom
end

-- Réacteur à Fusion VIP : socle + cœur néon + anneaux croisés
local function buildVIP(model: Model, base: CFrame, color: Color3)
	local pedestal = newPart(model, {
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 9, 9),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(60, 45, 80),
		CastShadow = true,
		CFrame = base * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	newPart(model, {
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(7, 7, 7),
		Material = Enum.Material.Neon,
		Color = color,
		CFrame = base * CFrame.new(0, 8, 0),
	})
	for i = 0, 2 do
		newPart(model, {
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 11, 11),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(220, 180, 255),
			Transparency = 0.2,
			CFrame = base * CFrame.new(0, 8, 0) * CFrame.Angles(math.rad(i * 60), 0, math.rad(90)),
		})
	end
	model.PrimaryPart = pedestal
end

-- Dispatcher : construit le bâtiment correspondant au type demandé
local BUILDERS: { [string]: (Model, CFrame, Color3) -> () } = {
	Solar = buildSolar,
	Wind = buildWind,
	Battery = buildBattery,
	Hydro = buildHydro,
	Nuclear = buildNuclear,
	VIP = buildVIP,
}

-- Construit un bâtiment d'après sa config et le renvoie (Model non parenté)
function BuildingFactory.Build(buildingConfig: any, baseCFrame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = buildingConfig.Name or "Building"
	local builder = BUILDERS[buildingConfig.Type] or buildSolar
	builder(model, baseCFrame, buildingConfig.Color or Color3.fromRGB(80, 200, 255))
	return model
end

-- =========================================================================
--  BATTERIE CENTRALE (jauge de charge animée)
--  Renvoie le Model + la part "fill" (cœur néon) à mettre à jour.
-- =========================================================================
function BuildingFactory.CreateCentralBattery(baseCFrame: CFrame): (Model, Part)
	local model = Instance.new("Model")
	model.Name = "CentralBattery"

	local casing = newPart(model, {
		Name = "Casing",
		Size = Vector3.new(9, 18, 9),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(210, 230, 245),
		Transparency = 0.62,
		Reflectance = 0.1,
		CastShadow = true,
		CFrame = baseCFrame * CFrame.new(0, 9, 0),
	})
	newPart(model, {
		Name = "Cap",
		Size = Vector3.new(10, 1, 10),
		Material = Enum.Material.Metal,
		Color = METAL,
		CFrame = baseCFrame * CFrame.new(0, 18.5, 0),
	})
	newPart(model, {
		Name = "Foot",
		Size = Vector3.new(10, 1, 10),
		Material = Enum.Material.Metal,
		Color = METAL,
		CFrame = baseCFrame * CFrame.new(0, 0.5, 0),
	})

	-- Cœur néon : sa hauteur représente la charge (0 -> 16 studs)
	local fill = newPart(model, {
		Name = "Fill",
		Size = Vector3.new(6.5, 0.2, 6.5),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(46, 204, 113),
		CFrame = baseCFrame * CFrame.new(0, 1.2, 0),
	})

	makeBillboard(casing, "BATTERIE", "0%", Color3.fromRGB(46, 204, 113))
	model.PrimaryPart = casing
	return model, fill
end

-- =========================================================================
--  HUB DE VENTE (pad tactile + visuel)
--  Renvoie le Model + la part tactile (Touched).
-- =========================================================================
function BuildingFactory.CreateSellHub(baseCFrame: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "SellHub"

	local disc = newPart(model, {
		Name = "SellPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 16, 16),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(46, 204, 113),
		Transparency = 0.15,
		CanTouch = true,
		CFrame = baseCFrame * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	disc:SetAttribute("Kind", "SELL")

	newPart(model, {
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 18, 18),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 215, 0),
		Transparency = 0.4,
		CFrame = baseCFrame * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	-- Faisceau lumineux vertical
	newPart(model, {
		Name = "Beam",
		Size = Vector3.new(14, 40, 14),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(46, 204, 113),
		Transparency = 0.92,
		CFrame = baseCFrame * CFrame.new(0, 20, 0),
	})

	local sign = newPart(model, {
		Name = "Sign",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = baseCFrame * CFrame.new(0, 6, 0),
	})
	makeBillboard(sign, "💰 VENDRE 💰", "Marche dessus", Color3.fromRGB(255, 215, 0))

	model.PrimaryPart = disc
	return model, disc
end

-- =========================================================================
--  PAD D'ACHAT (le bouton au sol avec prix en 3D et détection Touched)
--  kind = "BUY" (séquence) ou "VIP"
--  Renvoie le Model + la part tactile.
-- =========================================================================
function BuildingFactory.CreatePad(buildingConfig: any, baseCFrame: CFrame, kind: string, index: number): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Pad_" .. tostring(buildingConfig.Name)
	local accent = buildingConfig.Color or Color3.fromRGB(80, 200, 255)

	local pad = newPart(model, {
		Name = "BuyPad",
		Size = Vector3.new(9, 0.5, 9),
		Material = Enum.Material.Neon,
		Color = accent,
		Transparency = 0.2,
		CanTouch = true,
		CFrame = baseCFrame * CFrame.new(0, 0.25, 0),
	})
	pad:SetAttribute("Kind", kind)
	pad:SetAttribute("Index", index)

	-- Bordure du pad
	newPart(model, {
		Name = "PadBorder",
		Size = Vector3.new(9.8, 0.3, 9.8),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.5,
		CFrame = baseCFrame * CFrame.new(0, 0.15, 0),
	})
	-- Faisceau vertical pour repérer le pad de loin
	newPart(model, {
		Name = "Beam",
		Size = Vector3.new(9, 26, 9),
		Material = Enum.Material.Neon,
		Color = accent,
		Transparency = 0.93,
		CFrame = baseCFrame * CFrame.new(0, 13, 0),
	})

	-- Sous-titre du panneau : prix + effet
	local subtitle: string
	if kind == "VIP" then
		subtitle = "GAMEPASS VIP"
	elseif (buildingConfig.Price or 0) <= 0 then
		subtitle = "GRATUIT"
	else
		subtitle = Format.Money(buildingConfig.Price)
	end

	local effect: string
	if (buildingConfig.Capacity or 0) > 0 then
		effect = "+" .. Format.Watts(buildingConfig.Capacity) .. " stockage"
	else
		effect = "+" .. Format.Watts(buildingConfig.Production) .. "/s"
	end

	-- BillboardGui spécifique avec une 3e ligne (effet)
	local bb = makeBillboard(pad, buildingConfig.Name, subtitle, accent)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.Size = UDim2.fromOffset(230, 120)
	local bg = bb:FindFirstChildOfClass("Frame")
	if bg then
		local effectLabel = Instance.new("TextLabel")
		effectLabel.Name = "Effect"
		effectLabel.Size = UDim2.new(1, -10, 0, 22)
		effectLabel.BackgroundTransparency = 1
		effectLabel.Font = Enum.Font.GothamMedium
		effectLabel.Text = effect
		effectLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
		effectLabel.TextScaled = true
		effectLabel.LayoutOrder = 3
		effectLabel.Parent = bg
	end

	model.PrimaryPart = pad
	return model, pad
end

-- =========================================================================
--  BASE DU PLOT (dalle + bordures néon + mur + panneau-nom)
--  Renvoie le Model + la dalle (surface marchable).
-- =========================================================================
function BuildingFactory.CreatePlotBase(origin: Vector3, ownerName: string): (Model, BasePart)
	local cfg = GameConfig.Plot
	local model = Instance.new("Model")
	model.Name = "PlotBase"

	local size = cfg.SlabSize
	-- La surface marchable est à Y = origin.Y ; le centre de la dalle est donc dessous
	local slab = newPart(model, {
		Name = "Slab",
		Size = size,
		Material = Enum.Material.SmoothPlastic,
		Color = cfg.SlabColor,
		CanCollide = true,
		CastShadow = true,
		CFrame = CFrame.new(origin - Vector3.new(0, size.Y / 2, 0)),
	})

	-- Bordures néon le long des 4 arêtes supérieures
	local halfX, halfZ = size.X / 2, size.Z / 2
	local borderDefs = {
		{ Vector3.new(size.X, 0.6, 2), Vector3.new(0, 0, -halfZ) },
		{ Vector3.new(size.X, 0.6, 2), Vector3.new(0, 0, halfZ) },
		{ Vector3.new(2, 0.6, size.Z), Vector3.new(-halfX, 0, 0) },
		{ Vector3.new(2, 0.6, size.Z), Vector3.new(halfX, 0, 0) },
	}
	for _, def in ipairs(borderDefs) do
		newPart(model, {
			Name = "Border",
			Size = def[1],
			Material = Enum.Material.Neon,
			Color = cfg.BorderColor,
			CFrame = CFrame.new(origin + def[2] + Vector3.new(0, 0.3, 0)),
		})
	end

	-- Mur du fond
	newPart(model, {
		Name = "BackWall",
		Size = Vector3.new(size.X, 14, 2),
		Material = Enum.Material.SmoothPlastic,
		Color = cfg.WallColor,
		CanCollide = true,
		CastShadow = true,
		CFrame = CFrame.new(origin + Vector3.new(0, 7, -halfZ + 1)),
	})

	-- Panneau-nom du joueur (au-dessus du mur)
	local signPost = newPart(model, {
		Name = "SignPost",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(origin + Vector3.new(0, 16, -halfZ + 1)),
	})
	makeBillboard(signPost, "🏭 " .. ownerName, "Power Plant", cfg.BorderColor)

	model.PrimaryPart = slab
	return model, slab
end

-- =========================================================================
--  JUMBOTRON / TABLEAU DES SCORES (écran 3D avec SurfaceGui)
--  Renvoie le Model + le Frame "Content" où LeaderboardService écrit les lignes.
-- =========================================================================
function BuildingFactory.CreateLeaderboard(baseCFrame: CFrame): (Model, Frame)
	local model = Instance.new("Model")
	model.Name = "Leaderboard"
	local accent = Color3.fromRGB(0, 200, 255)

	local screen = newPart(model, {
		Name = "Screen",
		Size = Vector3.new(40, 18, 1),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(10, 12, 18),
		CastShadow = true,
		CFrame = baseCFrame * CFrame.new(0, 14, 0),
	})
	newPart(model, {
		Name = "ScreenFrame",
		Size = Vector3.new(41.5, 19.5, 0.6),
		Material = Enum.Material.Neon,
		Color = accent,
		Transparency = 0.2,
		CFrame = baseCFrame * CFrame.new(0, 14, 0.4),
	})
	for _, sx in ipairs({ -16, 16 }) do
		newPart(model, {
			Name = "Pillar",
			Size = Vector3.new(1.4, 14, 1.4),
			Material = Enum.Material.Metal,
			Color = METAL,
			CastShadow = true,
			CFrame = baseCFrame * CFrame.new(sx, 7, 0),
		})
	end

	-- SurfaceGui sur la face arrière (+Z) : tournée vers le joueur qui regarde sa base
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Board"
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 22
	sg.LightInfluence = 0
	sg.Parent = screen

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 70)
	title.BackgroundColor3 = accent
	title.BorderSizePixel = 0
	title.Text = "🏆  TOP VENDEURS MONDIAL"
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(10, 12, 18)
	title.Parent = sg

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.new(0, 0, 0, 78)
	content.Size = UDim2.new(1, 0, 1, -78)
	content.BackgroundTransparency = 1
	content.Parent = sg
	local lpad = Instance.new("UIPadding")
	lpad.PaddingLeft = UDim.new(0, 12)
	lpad.PaddingRight = UDim.new(0, 12)
	lpad.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	model.PrimaryPart = screen
	return model, content
end

return BuildingFactory
