--!strict
--[[
	==========================================================================
	  CLIENT MAIN — ⚡ POWER TYCOON ⚡  (UI/UX + effets)
	==========================================================================
	Construit TOUTE l'interface par le code (aucun élément à placer à la main) :
	  - HUD : argent, jauge de batterie animée, production, prix du marché, rebirths
	  - Boutons : Boutique, Stats, Rebirth, Vente, Auto-Sell
	  - Panneaux modaux animés (TweenService) : Boutique (avec section Premium /
	    monétisation), Statistiques, Rebirth
	  - Notifications : pop-ups de gains « +150 $ » et toasts de messages
	  - Effets : rotation des pales d'éolienne (côté client = 0 coût réseau),
	    flash lumineux lors d'une construction

	À placer dans : StarterPlayer > StarterPlayerScripts > ClientMain  (LocalScript)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================================================================
--  SONS — un asset moteur garanti, varié par PlaybackSpeed/Volume selon l'action
-- =========================================================================
local SoundService = game:GetService("SoundService")
local Sounds: { [string]: Sound } = {}
for soundName, scfg in pairs(GameConfig.Sounds) do
	local s = Instance.new("Sound")
	s.Name = soundName
	s.SoundId = scfg.Id
	s.Volume = scfg.Volume
	s.PlaybackSpeed = scfg.Speed
	s.Parent = SoundService
	Sounds[soundName] = s
end
local function playSound(name: string)
	local s = Sounds[name]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

-- =========================================================================
--  THÈME
-- =========================================================================
local Theme = {
	Bg = Color3.fromRGB(16, 18, 26),
	Backdrop = Color3.fromRGB(0, 0, 0),
	Panel = Color3.fromRGB(26, 29, 40),
	Panel2 = Color3.fromRGB(34, 38, 52),
	Row = Color3.fromRGB(40, 45, 60),
	Accent = Color3.fromRGB(0, 200, 255),
	Money = Color3.fromRGB(46, 204, 113),
	Energy = Color3.fromRGB(255, 196, 0),
	Danger = Color3.fromRGB(231, 76, 60),
	VIP = Color3.fromRGB(170, 110, 230),
	Text = Color3.fromRGB(240, 244, 250),
	Sub = Color3.fromRGB(165, 174, 190),
	Lock = Color3.fromRGB(70, 76, 92),
}
local FONT = Enum.Font.GothamBold
local FONT_BLACK = Enum.Font.GothamBlack
local FONT_MED = Enum.Font.GothamMedium

-- =========================================================================
--  HELPERS DE CRÉATION D'INSTANCES
-- =========================================================================
local function new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function gradient(parent: Instance, c1: Color3, c2: Color3, rotation: number)
	new("UIGradient", {
		Color = ColorSequence.new(c1, c2),
		Rotation = rotation,
		Parent = parent,
	})
end

local function padding(parent: Instance, all: number)
	new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
		Parent = parent,
	})
end

-- Petit effet de survol/clic sur un bouton
local function makeInteractive(button: GuiButton, baseColor: Color3)
	local hover = baseColor:Lerp(Color3.new(1, 1, 1), 0.15)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = baseColor }):Play()
	end)
	-- Petit « flash » + son au clic
	button.MouseButton1Down:Connect(function()
		playSound("Click")
		button.BackgroundColor3 = baseColor:Lerp(Color3.new(0, 0, 0), 0.15)
		TweenService:Create(button, TweenInfo.new(0.18), { BackgroundColor3 = hover }):Play()
	end)
end

-- =========================================================================
--  RACINE
-- =========================================================================
local gui = new("ScreenGui", {
	Name = "PowerTycoonUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
	Parent = playerGui,
})

-- État local (dernier payload HUD reçu)
local State = {
	Money = 0,
	Watts = 0,
	MaxWatts = 1,
	Production = 0,
	Rebirths = 0,
	RebirthCost = 0,
	RebirthMult = 1,
	AutoSell = false,
	AutoSellLocked = false,
	Price = 0.12,
	Progress = 0,
	OwnedVIP = false,
	Stats = { TotalEarned = 0, TotalSold = 0, PlayTime = 0, Rebirths = 0 },
}
local Cfg: any = nil -- config reçue via GetData

-- Références d'UI mises à jour dynamiquement
local Refs: any = {}
local shopRows: { [number]: any } = {}
local vipRow: any = nil

-- =========================================================================
--  HUD : BARRE SUPÉRIEURE
-- =========================================================================
local topBar = new("Frame", {
	Name = "TopBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.new(1, -20, 0, 76),
	BackgroundTransparency = 1,
	Parent = gui,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 10),
	Parent = topBar,
})

-- Fabrique une « pilule » d'info (icône + titre + valeur)
local function makePill(width: number, icon: string, title: string, valueColor: Color3, order: number): (Frame, TextLabel)
	local pill = new("Frame", {
		Size = UDim2.new(0, width, 1, 0),
		BackgroundColor3 = Theme.Panel,
		LayoutOrder = order,
	})
	corner(pill, 14)
	stroke(pill, Color3.fromRGB(255, 255, 255), 1, 0.85)
	padding(pill, 10)

	new("TextLabel", {
		Name = "Icon",
		Size = UDim2.new(0, 40, 1, 0),
		BackgroundTransparency = 1,
		Text = icon,
		TextScaled = true,
		Font = FONT,
		TextColor3 = valueColor,
		Parent = pill,
	})
	local textCol = new("Frame", {
		Position = UDim2.new(0, 46, 0, 0),
		Size = UDim2.new(1, -46, 1, 0),
		BackgroundTransparency = 1,
		Parent = pill,
	})
	new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0.4, 0),
		BackgroundTransparency = 1,
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT_MED,
		TextColor3 = Theme.Sub,
		Parent = textCol,
	})
	local value = new("TextLabel", {
		Name = "Value",
		Position = UDim2.new(0, 0, 0.38, 0),
		Size = UDim2.new(1, 0, 0.62, 0),
		BackgroundTransparency = 1,
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = valueColor,
		Parent = textCol,
	})
	pill.Parent = topBar
	return pill, value
end

local _, moneyValue = makePill(200, "💰", "ARGENT", Theme.Money, 1)
Refs.MoneyValue = moneyValue

-- Pilule batterie (jauge animée)
local batteryPill = new("Frame", {
	Size = UDim2.new(0, 260, 1, 0),
	BackgroundColor3 = Theme.Panel,
	LayoutOrder = 2,
})
corner(batteryPill, 14)
stroke(batteryPill, Color3.fromRGB(255, 255, 255), 1, 0.85)
padding(batteryPill, 10)
new("TextLabel", {
	Name = "Title",
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Text = "🔋 BATTERIE",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextScaled = true,
	Font = FONT_MED,
	TextColor3 = Theme.Sub,
	Parent = batteryPill,
})
local barBg = new("Frame", {
	Name = "BarBg",
	Position = UDim2.new(0, 0, 0, 22),
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundColor3 = Color3.fromRGB(18, 20, 28),
	Parent = batteryPill,
})
corner(barBg, 8)
local barFill = new("Frame", {
	Name = "BarFill",
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Theme.Energy,
	Parent = barBg,
})
corner(barFill, 8)
gradient(barFill, Theme.Energy, Color3.fromRGB(255, 120, 0), 0)
local barText = new("TextLabel", {
	Name = "BarText",
	Position = UDim2.new(0, 0, 0, 40),
	Size = UDim2.new(1, 0, 0, 14),
	BackgroundTransparency = 1,
	Text = "0 / 0 W",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextScaled = true,
	Font = FONT,
	TextColor3 = Theme.Text,
	Parent = batteryPill,
})
batteryPill.Parent = topBar
Refs.BarFill = barFill
Refs.BarText = barText

local _, prodValue = makePill(170, "⚡", "PRODUCTION", Theme.Accent, 3)
Refs.ProdValue = prodValue

local _, marketValue = makePill(190, "📈", "MARCHÉ", Theme.Text, 4)
Refs.MarketValue = marketValue

local rebirthPill, rebirthValue = makePill(150, "⭐", "REBIRTH", Theme.VIP, 5)
Refs.RebirthValue = rebirthValue
rebirthPill.Active = true

-- =========================================================================
--  HUD : BOUTONS LATÉRAUX (droite)
-- =========================================================================
local sideBar = new("Frame", {
	Name = "SideBar",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.new(0, 76, 0, 280),
	BackgroundTransparency = 1,
	Parent = gui,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 12),
	Parent = sideBar,
})

local function makeSideButton(icon: string, label: string, color: Color3, order: number): TextButton
	local btn = new("TextButton", {
		Size = UDim2.new(0, 76, 0, 76),
		BackgroundColor3 = Theme.Panel,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
	})
	corner(btn, 18)
	stroke(btn, color, 2, 0.2)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0.6, 0),
		BackgroundTransparency = 1,
		Text = icon,
		TextScaled = true,
		Font = FONT,
		TextColor3 = color,
		Parent = btn,
	})
	new("TextLabel", {
		Position = UDim2.new(0, 0, 0.62, 0),
		Size = UDim2.new(1, 0, 0.32, 0),
		BackgroundTransparency = 1,
		Text = label,
		TextScaled = true,
		Font = FONT,
		TextColor3 = Theme.Text,
		Parent = btn,
	})
	makeInteractive(btn, Theme.Panel)
	btn.Parent = sideBar
	return btn
end

local shopBtn = makeSideButton("🛒", "BOUTIQUE", Theme.Accent, 1)
local statsBtn = makeSideButton("📊", "STATS", Theme.Energy, 2)
local rebirthBtn = makeSideButton("⭐", "REBIRTH", Theme.VIP, 3)

-- =========================================================================
--  HUD : BAS (Vendre + Auto-Sell)
-- =========================================================================
local bottomBar = new("Frame", {
	Name = "BottomBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(0, 360, 0, 64),
	BackgroundTransparency = 1,
	Parent = gui,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 12),
	Parent = bottomBar,
})

local sellBtn = new("TextButton", {
	Size = UDim2.new(0, 230, 1, 0),
	BackgroundColor3 = Theme.Money,
	Text = "💰  VENDRE",
	TextScaled = true,
	Font = FONT_BLACK,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	AutoButtonColor = false,
	LayoutOrder = 1,
})
corner(sellBtn, 16)
stroke(sellBtn, Color3.fromRGB(255, 255, 255), 1.5, 0.6)
padding(sellBtn, 8)
makeInteractive(sellBtn, Theme.Money)
sellBtn.Parent = bottomBar

local autoBtn = new("TextButton", {
	Size = UDim2.new(0, 118, 1, 0),
	BackgroundColor3 = Theme.Panel,
	Text = "AUTO\nOFF",
	TextScaled = true,
	Font = FONT,
	TextColor3 = Theme.Sub,
	AutoButtonColor = false,
	LayoutOrder = 2,
})
corner(autoBtn, 16)
stroke(autoBtn, Theme.Money, 2, 0.2)
padding(autoBtn, 8)
makeInteractive(autoBtn, Theme.Panel)
autoBtn.Parent = bottomBar
Refs.AutoBtn = autoBtn

-- =========================================================================
--  SYSTÈME DE PANNEAUX MODAUX (animés)
-- =========================================================================
local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Theme.Backdrop,
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
})

local openPanel: Frame? = nil

local function closePanel()
	if not openPanel then
		return
	end
	local panel = openPanel
	openPanel = nil
	TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	local tween = TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromScale(panel:GetAttribute("BaseW") * 0.85, panel:GetAttribute("BaseH") * 0.85),
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		panel.Visible = false
		backdrop.Visible = false
	end)
end

local function openPanelFn(panel: Frame)
	if openPanel == panel then
		closePanel()
		return
	end
	if openPanel then
		openPanel.Visible = false
	end
	openPanel = panel
	playSound("Open")
	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	local baseW = panel:GetAttribute("BaseW")
	local baseH = panel:GetAttribute("BaseH")
	panel.Visible = true
	panel.BackgroundTransparency = 1
	panel.Size = UDim2.fromScale(baseW * 0.85, baseH * 0.85)
	TweenService:Create(panel, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(baseW, baseH),
		BackgroundTransparency = 0,
	}):Play()
end

backdrop.MouseButton1Click:Connect(closePanel)

-- Crée un panneau modal vide (titre + bouton fermer + zone de contenu)
local function makePanel(title: string, widthScale: number, heightScale: number, accent: Color3): (Frame, Instance)
	local panel = new("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(widthScale, heightScale),
		BackgroundColor3 = Theme.Bg,
		Visible = false,
		ZIndex = 21,
		Parent = gui,
	})
	panel:SetAttribute("BaseW", widthScale)
	panel:SetAttribute("BaseH", heightScale)
	corner(panel, 18)
	stroke(panel, accent, 2.5, 0.1)

	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = Theme.Panel,
		ZIndex = 22,
		Parent = panel,
	})
	corner(header, 18)
	new("Frame", { -- masque les coins arrondis du bas du header
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -18),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = header,
	})
	new("TextLabel", {
		Position = UDim2.new(0, 18, 0, 0),
		Size = UDim2.new(1, -80, 1, 0),
		BackgroundTransparency = 1,
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = accent,
		ZIndex = 23,
		Parent = header,
	})
	local closeBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = Theme.Danger,
		Text = "✕",
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = false,
		ZIndex = 23,
		Parent = header,
	})
	corner(closeBtn, 10)
	padding(closeBtn, 6)
	makeInteractive(closeBtn, Theme.Danger)
	closeBtn.MouseButton1Click:Connect(closePanel)

	local body = new("Frame", {
		Name = "Body",
		Position = UDim2.new(0, 0, 0, 54),
		Size = UDim2.new(1, 0, 1, -54),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = panel,
	})
	return panel, body
end

-- =========================================================================
--  PANNEAU BOUTIQUE
-- =========================================================================
local shopPanel, shopBody = makePanel("🛒  BOUTIQUE", 0.62, 0.78, Theme.Accent)
local shopScroll = new("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = Theme.Accent,
	ZIndex = 22,
	Parent = shopBody,
})
padding(shopScroll, 14)
new("UIListLayout", {
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = shopScroll,
})

local function sectionTitle(parent: Instance, text: string, color: Color3, order: number)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = color,
		LayoutOrder = order,
		ZIndex = 22,
		Parent = parent,
	})
end

-- Crée une ligne de bâtiment dans la boutique
local function makeShopRow(index: number, bcfg: any, order: number): any
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Theme.Row,
		LayoutOrder = order,
		ZIndex = 22,
	})
	corner(row, 12)
	stroke(row, bcfg.Color, 1.5, 0.4)
	padding(row, 8)

	new("Frame", {
		Name = "Swatch",
		Size = UDim2.new(0, 8, 1, 0),
		BackgroundColor3 = bcfg.Color,
		ZIndex = 22,
		Parent = row,
	})
	local info = new("Frame", {
		Position = UDim2.new(0, 20, 0, 0),
		Size = UDim2.new(1, -180, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = row,
	})
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Text = bcfg.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT,
		TextColor3 = Theme.Text,
		ZIndex = 22,
		Parent = info,
	})
	local effect = (bcfg.Capacity and bcfg.Capacity > 0)
			and ("🔋 +" .. Format.Watts(bcfg.Capacity) .. " stockage")
		or ("⚡ +" .. Format.Watts(bcfg.Production) .. "/s")
	new("TextLabel", {
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundTransparency = 1,
		Text = effect,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT_MED,
		TextColor3 = Theme.Sub,
		ZIndex = 22,
		Parent = info,
	})
	local buyBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 46),
		BackgroundColor3 = Theme.Money,
		Text = "ACHETER",
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = false,
		ZIndex = 22,
		Parent = row,
	})
	corner(buyBtn, 10)
	padding(buyBtn, 8)
	makeInteractive(buyBtn, Theme.Money)
	buyBtn.MouseButton1Click:Connect(function()
		Remotes.Event("RequestBuy"):FireServer()
	end)

	row.Parent = shopScroll
	return { Row = row, BuyBtn = buyBtn, Cfg = bcfg, Index = index }
end

-- Bouton d'achat « premium » (gamepass ou produit)
local function makePremiumRow(name: string, desc: string, badge: string, color: Color3, order: number, onBuy: () -> ())
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Theme.Row,
		LayoutOrder = order,
		ZIndex = 22,
	})
	corner(row, 12)
	stroke(row, color, 1.5, 0.3)
	padding(row, 8)
	local info = new("Frame", {
		Size = UDim2.new(1, -160, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = row,
	})
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT,
		TextColor3 = color,
		ZIndex = 22,
		Parent = info,
	})
	new("TextLabel", {
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundTransparency = 1,
		Text = desc,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT_MED,
		TextColor3 = Theme.Sub,
		ZIndex = 22,
		Parent = info,
	})
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 46),
		BackgroundColor3 = color,
		Text = badge,
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = false,
		ZIndex = 22,
		Parent = row,
	})
	corner(btn, 10)
	padding(btn, 8)
	makeInteractive(btn, color)
	btn.MouseButton1Click:Connect(onBuy)
	row.Parent = shopScroll
end

-- Construit le contenu de la boutique à partir de la config (appelé après GetData)
local function buildShopContent()
	sectionTitle(shopScroll, "⚙️  GÉNÉRATEURS & BATTERIES", Theme.Accent, 1)
	for i, bcfg in ipairs(Cfg.Buildings) do
		shopRows[i] = makeShopRow(i, bcfg, 1 + i)
	end

	-- Ligne VIP
	local vipCfg = Cfg.VIPBuilding
	local vrow = new("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Theme.Row,
		LayoutOrder = 200,
		ZIndex = 22,
	})
	corner(vrow, 12)
	stroke(vrow, Theme.VIP, 1.5, 0.2)
	padding(vrow, 8)
	new("TextLabel", {
		Size = UDim2.new(1, -160, 0.5, 0),
		BackgroundTransparency = 1,
		Text = "👑 " .. vipCfg.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT,
		TextColor3 = Theme.VIP,
		ZIndex = 22,
		Parent = vrow,
	})
	new("TextLabel", {
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, -160, 0.45, 0),
		BackgroundTransparency = 1,
		Text = "⚡ +" .. Format.Watts(vipCfg.Production) .. "/s — exclusif VIP",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT_MED,
		TextColor3 = Theme.Sub,
		ZIndex = 22,
		Parent = vrow,
	})
	local vbtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 46),
		BackgroundColor3 = Theme.VIP,
		Text = "DÉBLOQUER",
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = false,
		ZIndex = 22,
		Parent = vrow,
	})
	corner(vbtn, 10)
	padding(vbtn, 8)
	makeInteractive(vbtn, Theme.VIP)
	vbtn.MouseButton1Click:Connect(function()
		Remotes.Event("PromptPurchase"):FireServer({ Kind = "gamepass", Key = "VIP" })
	end)
	vrow.Parent = shopScroll
	vipRow = { Row = vrow, BuyBtn = vbtn }

	-- Section Premium (monétisation)
	sectionTitle(shopScroll, "✨  PREMIUM", Theme.Energy, 300)
	local gp = Cfg.Gamepasses
	makePremiumRow(gp.DoubleEnergy.Name, gp.DoubleEnergy.Desc, "ACHETER", Theme.Energy, 301, function()
		Remotes.Event("PromptPurchase"):FireServer({ Kind = "gamepass", Key = "DoubleEnergy" })
	end)
	makePremiumRow(gp.AutoSell.Name, gp.AutoSell.Desc, "ACHETER", Theme.Energy, 302, function()
		Remotes.Event("PromptPurchase"):FireServer({ Kind = "gamepass", Key = "AutoSell" })
	end)
	local pr = Cfg.Products
	makePremiumRow(pr.Cash10k.Name, pr.Cash10k.Desc, "ROBUX", Theme.Money, 303, function()
		Remotes.Event("PromptPurchase"):FireServer({ Kind = "product", Key = "Cash10k" })
	end)
	makePremiumRow(pr.Cash100k.Name, pr.Cash100k.Desc, "ROBUX", Theme.Money, 304, function()
		Remotes.Event("PromptPurchase"):FireServer({ Kind = "product", Key = "Cash100k" })
	end)
	makePremiumRow(pr.FullBattery.Name, pr.FullBattery.Desc, "ROBUX", Theme.Money, 305, function()
		Remotes.Event("PromptPurchase"):FireServer({ Kind = "product", Key = "FullBattery" })
	end)
end

-- Met à jour l'état des lignes (possédé / disponible / verrouillé)
local function refreshShop()
	for i, ctrl in pairs(shopRows) do
		local btn = ctrl.BuyBtn
		if i <= State.Progress then
			btn.Text = "✓ POSSÉDÉ"
			btn.BackgroundColor3 = Theme.Lock
			btn.Active = false
			stroke(ctrl.Row, Theme.Money, 1.5, 0.5)
		elseif i == State.Progress + 1 then
			local affordable = State.Money >= ctrl.Cfg.Price
			btn.Text = (ctrl.Cfg.Price <= 0) and "GRATUIT" or Format.Money(ctrl.Cfg.Price)
			btn.BackgroundColor3 = affordable and Theme.Money or Theme.Danger
			btn.Active = true
		else
			btn.Text = "🔒 " .. Format.Money(ctrl.Cfg.Price)
			btn.BackgroundColor3 = Theme.Lock
			btn.Active = false
		end
	end
	if vipRow then
		if State.OwnedVIP then
			vipRow.BuyBtn.Text = "✓ ACTIF"
			vipRow.BuyBtn.BackgroundColor3 = Theme.Lock
		else
			vipRow.BuyBtn.Text = "DÉBLOQUER"
			vipRow.BuyBtn.BackgroundColor3 = Theme.VIP
		end
	end
end

-- =========================================================================
--  PANNEAU STATISTIQUES
-- =========================================================================
local statsPanel, statsBody = makePanel("📊  STATISTIQUES", 0.5, 0.66, Theme.Energy)
local statsList = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 22,
	Parent = statsBody,
})
padding(statsList, 16)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = statsList })

local statRefs: { [string]: TextLabel } = {}
local function makeStatLine(key: string, label: string, order: number)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Row,
		LayoutOrder = order,
		ZIndex = 22,
	})
	corner(row, 10)
	padding(row, 10)
	new("TextLabel", {
		Size = UDim2.new(0.6, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = FONT_MED,
		TextColor3 = Theme.Sub,
		ZIndex = 22,
		Parent = row,
	})
	local val = new("TextLabel", {
		Position = UDim2.new(0.6, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "—",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = Theme.Text,
		ZIndex = 22,
		Parent = row,
	})
	row.Parent = statsList
	statRefs[key] = val
end

makeStatLine("Money", "💰 Argent actuel", 1)
makeStatLine("Prod", "⚡ Production / s", 2)
makeStatLine("Stored", "🔋 Énergie stockée", 3)
makeStatLine("Price", "📈 Prix du marché", 4)
makeStatLine("Rebirths", "⭐ Rebirths", 5)
makeStatLine("Mult", "✖️ Multiplicateur gains", 6)
makeStatLine("Earned", "🏦 Total gagné", 7)
makeStatLine("Sold", "🔌 Énergie totale vendue", 8)
makeStatLine("Time", "⏱️ Temps de jeu", 9)

local function formatTime(sec: number): string
	sec = math.floor(sec)
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

local function refreshStats()
	statRefs.Money.Text = Format.Money(State.Money)
	statRefs.Prod.Text = Format.Watts(State.Production)
	statRefs.Stored.Text = Format.Watts(math.floor(State.Watts)) .. " / " .. Format.Watts(State.MaxWatts)
	statRefs.Price.Text = string.format("$%.3f /W", State.Price)
	statRefs.Rebirths.Text = tostring(State.Rebirths)
	statRefs.Mult.Text = string.format("×%.2f", State.RebirthMult)
	statRefs.Earned.Text = Format.Money(State.Stats.TotalEarned or 0)
	statRefs.Sold.Text = Format.Watts(State.Stats.TotalSold or 0)
	statRefs.Time.Text = formatTime(State.Stats.PlayTime or 0)
end

-- =========================================================================
--  PANNEAU REBIRTH
-- =========================================================================
local rebirthPanel, rebirthBody = makePanel("⭐  REBIRTH", 0.46, 0.6, Theme.VIP)
local rbContent = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 22,
	Parent = rebirthBody,
})
padding(rbContent, 20)
new("UIListLayout", {
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = rbContent,
})

new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 60),
	BackgroundTransparency = 1,
	Text = "♻️",
	TextScaled = true,
	Font = FONT,
	LayoutOrder = 1,
	ZIndex = 22,
	Parent = rbContent,
})
local rbDesc = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 70),
	BackgroundTransparency = 1,
	Text = "",
	TextWrapped = true,
	TextScaled = true,
	Font = FONT_MED,
	TextColor3 = Theme.Sub,
	LayoutOrder = 2,
	ZIndex = 22,
	Parent = rbContent,
})
local rbMultLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundTransparency = 1,
	Text = "",
	TextScaled = true,
	Font = FONT_BLACK,
	TextColor3 = Theme.VIP,
	LayoutOrder = 3,
	ZIndex = 22,
	Parent = rbContent,
})
local rebirthConfirm = new("TextButton", {
	Size = UDim2.new(0, 280, 0, 64),
	BackgroundColor3 = Theme.VIP,
	Text = "REBIRTH",
	TextScaled = true,
	Font = FONT_BLACK,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	AutoButtonColor = false,
	LayoutOrder = 4,
	ZIndex = 22,
})
corner(rebirthConfirm, 14)
padding(rebirthConfirm, 12)
stroke(rebirthConfirm, Color3.fromRGB(255, 255, 255), 1.5, 0.6)
makeInteractive(rebirthConfirm, Theme.VIP)
rebirthConfirm.MouseButton1Click:Connect(function()
	Remotes.Event("RequestRebirth"):FireServer()
end)
rebirthConfirm.Parent = rbContent

local function refreshRebirth()
	local nextMult = 1 + (State.Rebirths + 1) * (Cfg and Cfg.Rebirth.BonusPerRebirth or 0.30)
	rbDesc.Text = string.format(
		"Recommence à zéro (bâtiments + argent)\nmais gagne un BONUS PERMANENT sur tes ventes.\n\nMultiplicateur actuel : ×%.2f",
		State.RebirthMult
	)
	rbMultLabel.Text = string.format("Prochain : ×%.2f", nextMult)
	local affordable = State.Money >= State.RebirthCost
	rebirthConfirm.Text = affordable and ("REBIRTH (" .. Format.Money(State.RebirthCost) .. ")")
		or ("🔒 " .. Format.Money(State.RebirthCost))
	rebirthConfirm.BackgroundColor3 = affordable and Theme.VIP or Theme.Lock
end

-- =========================================================================
--  NOTIFICATIONS
-- =========================================================================
-- Pop-ups de gains "+$X"
local cashLayer = new("Frame", {
	Name = "CashLayer",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.new(0, 300, 0, 200),
	BackgroundTransparency = 1,
	ZIndex = 50,
	Parent = gui,
})

local function spawnCashPopup(amount: number)
	local label = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, math.random(-40, 40), 1, 0),
		Size = UDim2.new(0, 200, 0, 44),
		BackgroundTransparency = 1,
		Text = "+" .. Format.Money(amount),
		TextScaled = true,
		Font = FONT_BLACK,
		TextColor3 = Theme.Money,
		TextStrokeTransparency = 0.4,
		ZIndex = 51,
		Parent = cashLayer,
	})
	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad), {
		Position = label.Position - UDim2.fromOffset(0, 110),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.15, function()
		label:Destroy()
	end)
end

-- Toasts de messages (haut-centre)
local toastLayer = new("Frame", {
	Name = "ToastLayer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.new(0, 460, 0, 200),
	BackgroundTransparency = 1,
	ZIndex = 50,
	Parent = gui,
})
new("UIListLayout", {
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = UDim.new(0, 6),
	Parent = toastLayer,
})

local function spawnToast(text: string, color: Color3)
	local toast = new("Frame", {
		Size = UDim2.new(0, 0, 0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		ZIndex = 51,
		Parent = toastLayer,
	})
	corner(toast, 10)
	stroke(toast, color, 2, 0.2)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		Parent = toast,
	})
	local label = new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextTransparency = 1,
		TextScaled = true,
		Font = FONT,
		TextColor3 = color,
		ZIndex = 52,
		Parent = toast,
	})
	new("UITextSizeConstraint", { MaxTextSize = 20, Parent = label })
	TweenService:Create(toast, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	task.delay(2.6, function()
		TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		local t = TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 })
		t:Play()
		t.Completed:Once(function()
			toast:Destroy()
		end)
	end)
end

-- =========================================================================
--  MISE À JOUR DU HUD
-- =========================================================================
local function applyHUD(payload: any)
	for k, v in pairs(payload) do
		State[k] = v
	end

	Refs.MoneyValue.Text = Format.Money(State.Money)
	Refs.ProdValue.Text = Format.Watts(State.Production) .. "/s"
	Refs.RebirthValue.Text = string.format("×%.2f", State.RebirthMult)

	-- Jauge de batterie (animée)
	local ratio = (State.MaxWatts > 0) and math.clamp(State.Watts / State.MaxWatts, 0, 1) or 0
	TweenService:Create(Refs.BarFill, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()
	Refs.BarText.Text = Format.Watts(math.floor(State.Watts)) .. " / " .. Format.Watts(State.MaxWatts)

	-- Marché
	Refs.MarketValue.Text = string.format("$%.3f", State.Price)

	-- Auto-Sell
	local auto = State.AutoSell
	Refs.AutoBtn.Text = "AUTO\n" .. (auto and "ON" or "OFF")
	Refs.AutoBtn.TextColor3 = auto and Theme.Money or Theme.Sub

	if openPanel == shopPanel then
		refreshShop()
	elseif openPanel == statsPanel then
		refreshStats()
	elseif openPanel == rebirthPanel then
		refreshRebirth()
	end
end

-- =========================================================================
--  CONNEXIONS DES REMOTES
-- =========================================================================
Remotes.Event("UpdateHUD").OnClientEvent:Connect(applyHUD)

Remotes.Event("MarketUpdate").OnClientEvent:Connect(function(data)
	State.Price = data.Price
	Refs.MarketValue.Text = string.format("$%.3f", data.Price)
	local arrow = (data.Trend > 0) and " ▲" or (data.Trend < 0) and " ▼" or ""
	Refs.MarketValue.Text = string.format("$%.3f%s", data.Price, arrow)
	Refs.MarketValue.TextColor3 = (data.Trend > 0) and Theme.Money or (data.Trend < 0) and Theme.Danger or Theme.Text
	if data.Trend > 0 then
		spawnToast("📈 Le prix de l'énergie monte !", Theme.Money)
		playSound("Market")
	elseif data.Trend < 0 then
		spawnToast("📉 Le prix de l'énergie baisse…", Theme.Danger)
		playSound("Market")
	end
end)

Remotes.Event("Notify").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.Kind == "cash" then
		spawnCashPopup(payload.Amount or 0)
		playSound("Cash")
	elseif payload.Kind == "error" then
		spawnToast("⚠️ " .. tostring(payload.Text), Theme.Danger)
		playSound("Error")
	elseif payload.Kind == "build" then
		spawnToast("🏗️ " .. tostring(payload.Text), Theme.Accent)
		playSound(string.find(tostring(payload.Text), "REBIRTH") and "Rebirth" or "Build")
	else
		spawnToast(tostring(payload.Text), Theme.Energy)
	end
end)

-- =========================================================================
--  CONNEXIONS DES BOUTONS
-- =========================================================================
sellBtn.MouseButton1Click:Connect(function()
	Remotes.Event("RequestSell"):FireServer()
end)
autoBtn.MouseButton1Click:Connect(function()
	Remotes.Event("ToggleAutoSell"):FireServer()
end)
shopBtn.MouseButton1Click:Connect(function()
	openPanelFn(shopPanel)
	refreshShop()
end)
statsBtn.MouseButton1Click:Connect(function()
	openPanelFn(statsPanel)
	refreshStats()
end)
local function openRebirth()
	openPanelFn(rebirthPanel)
	refreshRebirth()
end
rebirthBtn.MouseButton1Click:Connect(openRebirth)
rebirthPill.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		openRebirth()
	end
end)

-- =========================================================================
--  EFFETS 3D : ROTATION DES PALES D'ÉOLIENNE (client = 0 coût réseau)
-- =========================================================================
local rotors: { [Instance]: boolean } = {}
local function trackRotor(rotor: Instance)
	if rotor:IsA("Model") then
		rotors[rotor] = true
	end
end
for _, m in ipairs(CollectionService:GetTagged("PT_WindRotor")) do
	trackRotor(m)
end
CollectionService:GetInstanceAddedSignal("PT_WindRotor"):Connect(trackRotor)
CollectionService:GetInstanceRemovedSignal("PT_WindRotor"):Connect(function(m)
	rotors[m] = nil
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for rotor in pairs(rotors) do
		local building = rotor.Parent
		if building and building:IsA("Model") and building.PrimaryPart then
			local restOffset = rotor:GetAttribute("RestOffset")
			local speed = rotor:GetAttribute("SpinSpeed") or 2
			if typeof(restOffset) == "CFrame" then
				-- Axe reconstruit depuis la tour (qui ne tourne jamais) -> robuste
				local axisCF = building.PrimaryPart.CFrame * restOffset
				rotor:PivotTo(axisCF * CFrame.Angles(0, 0, t * speed))
			end
		else
			rotors[rotor] = nil
		end
	end
end)

-- =========================================================================
--  EFFET DE CONSTRUCTION (flash lumineux)
-- =========================================================================
Remotes.Event("BuildFX").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or typeof(payload.Pos) ~= "Vector3" then
		return
	end
	local flash = new("Part", {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 255, 255),
		Size = Vector3.new(4, 4, 4),
		Position = payload.Pos + Vector3.new(0, 3, 0),
		Parent = Workspace,
	})
	local t = TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
		Size = Vector3.new(34, 34, 34),
		Transparency = 1,
	})
	t:Play()
	t.Completed:Once(function()
		flash:Destroy()
	end)
end)

-- =========================================================================
--  DÉMARRAGE : récupère config + données, puis construit la boutique
-- =========================================================================
task.spawn(function()
	local ok, result = pcall(function()
		return Remotes.Func("GetData"):InvokeServer()
	end)
	if ok and result and result.Config then
		Cfg = result.Config
		buildShopContent()
		if result.Data then
			for k, v in pairs(result.Data) do
				State[k] = v
			end
		end
		refreshShop()
		refreshStats()
		refreshRebirth()
		spawnToast("⚡ Bienvenue dans " .. Cfg.GameName .. " !", Theme.Accent)
	else
		warn("[ClientMain] GetData a échoué : " .. tostring(result))
	end
end)
