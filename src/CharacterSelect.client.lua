--!strict
-- CharacterSelect.client.lua
-- Example UI for tracking step timers and allowing players to lock in characters.
-- Place this LocalScript inside StarterPlayerScripts (or nested in a ScreenGui
-- under StarterGui) to provide the selection HUD to each player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local remotes = {
	RoundStateChanged = ReplicatedStorage:WaitForChild("RoundStateChanged"),
	RequestCharacter = ReplicatedStorage:WaitForChild("RequestCharacter"),
	CharacterAssignment = ReplicatedStorage:WaitForChild("CharacterAssignment"),
}

local getRoundStateRemote = ReplicatedStorage:FindFirstChild("GetRoundState")

local rawBossRoster = require(ReplicatedStorage:WaitForChild("BossRoster"))
local rawFighterRoster = require(ReplicatedStorage:WaitForChild("FighterRoster"))

type CharacterStats = {
	hp: number,
	speed: number,
	attack: number,
	jump: number,
}

type CharacterInfo = {
	name: string,
	stats: CharacterStats,
	abilities: {string},
	images: {[string]: any},
}

local function toAssetId(value: any): string
	if typeof(value) == "number" then
		value = tostring(value)
	end

	if typeof(value) ~= "string" then
		return ""
	end

	if value == "" then
		return ""
	end

	if string.find(value, "rbxassetid://", 1, true) == 1 then
		return value
	end

	return "rbxassetid://" .. value
end

local function clamp01(value: number): number
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

local function lighten(color: Color3, amount: number): Color3
	amount = clamp01(amount)
	return Color3.new(
		color.R + (1 - color.R) * amount,
		color.G + (1 - color.G) * amount,
		color.B + (1 - color.B) * amount
	)
end

local function darken(color: Color3, amount: number): Color3
	amount = clamp01(amount)
	return Color3.new(
		color.R * (1 - amount),
		color.G * (1 - amount),
		color.B * (1 - amount)
	)
end

local function roundHealth(value: number): number
	return math.floor(value + 0.5)
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, subValue in pairs(value) do
		copy[key] = deepCopy(subValue)
	end
	return copy
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BossRoundHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.DisplayOrder = 100
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.new(0.5, 0, 0, 20)
topBar.Size = UDim2.new(0, 600, 0, 140)
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 32)
topBar.BackgroundTransparency = 0.15
topBar.BorderSizePixel = 0
topBar.Parent = screenGui

local topBarCorner = Instance.new("UICorner")
topBarCorner.CornerRadius = UDim.new(0, 20)
topBarCorner.Parent = topBar

local topBarStroke = Instance.new("UIStroke")
topBarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
topBarStroke.Thickness = 2
topBarStroke.Color = Color3.fromRGB(120, 140, 220)
topBarStroke.Parent = topBar

local topBarPadding = Instance.new("UIPadding")
topBarPadding.PaddingTop = UDim.new(0, 12)
topBarPadding.PaddingBottom = UDim.new(0, 12)
topBarPadding.PaddingLeft = UDim.new(0, 20)
topBarPadding.PaddingRight = UDim.new(0, 20)
topBarPadding.Parent = topBar

local topBarLayout = Instance.new("UIListLayout")
topBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
topBarLayout.Padding = UDim.new(0, 6)
topBarLayout.VerticalAlignment = Enum.VerticalAlignment.Top
topBarLayout.Parent = topBar

local headerLabel = Instance.new("TextLabel")
headerLabel.Name = "HeaderLabel"
headerLabel.Size = UDim2.new(1, 0, 0, 32)
headerLabel.BackgroundTransparency = 1
headerLabel.Font = Enum.Font.GothamBlack
headerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
headerLabel.TextScaled = true
headerLabel.TextXAlignment = Enum.TextXAlignment.Left
headerLabel.Text = "Step: Waiting"
headerLabel.LayoutOrder = 1
headerLabel.Parent = topBar

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(1, 0, 0, 54)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.GothamBlack
timerLabel.TextColor3 = Color3.fromRGB(255, 235, 120)
timerLabel.TextScaled = true
timerLabel.TextXAlignment = Enum.TextXAlignment.Left
timerLabel.Text = "Time Left: --"
timerLabel.LayoutOrder = 2
timerLabel.Parent = topBar

local timerSizeConstraint = Instance.new("UITextSizeConstraint")
timerSizeConstraint.MaxTextSize = 56
timerSizeConstraint.Parent = timerLabel

local countdownSeconds: number? = nil
local lastTimerText = timerLabel.Text

local function formatCountdown(seconds: number): string
	local totalSeconds = math.max(0, math.floor(seconds + 0.5))
	local minutes = math.floor(totalSeconds / 60)
	local secs = totalSeconds % 60
	return string.format("%d:%02d", minutes, secs)
end

local function refreshTimerLabel(force: boolean?)
	local newText
	if countdownSeconds ~= nil then
		newText = string.format("Time Left: %s", formatCountdown(countdownSeconds))
	else
		newText = "Time Left: --"
	end

	if force or newText ~= lastTimerText then
		lastTimerText = newText
		timerLabel.Text = newText
	end
end

local bossStatusContainer = Instance.new("Frame")
bossStatusContainer.Name = "BossStatus"
bossStatusContainer.AnchorPoint = Vector2.new(0.5, 0)
bossStatusContainer.Position = UDim2.new(0.5, 0, 0, 176)
bossStatusContainer.Size = UDim2.new(0, 640, 0, 0)
bossStatusContainer.AutomaticSize = Enum.AutomaticSize.Y
bossStatusContainer.BackgroundTransparency = 1
bossStatusContainer.Visible = false
bossStatusContainer.ZIndex = 2
bossStatusContainer.Parent = screenGui

local bossStatusPadding = Instance.new("UIPadding")
bossStatusPadding.PaddingTop = UDim.new(0, 6)
bossStatusPadding.PaddingBottom = UDim.new(0, 6)
bossStatusPadding.PaddingLeft = UDim.new(0, 12)
bossStatusPadding.PaddingRight = UDim.new(0, 12)
bossStatusPadding.Parent = bossStatusContainer

local bossStatusLayout = Instance.new("UIListLayout")
bossStatusLayout.FillDirection = Enum.FillDirection.Vertical
bossStatusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bossStatusLayout.VerticalAlignment = Enum.VerticalAlignment.Top
bossStatusLayout.Padding = UDim.new(0, 10)
bossStatusLayout.Parent = bossStatusContainer

local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "InfoLabel"
infoLabel.Size = UDim2.new(1, 0, 0, 32)
infoLabel.BackgroundTransparency = 1
infoLabel.Font = Enum.Font.GothamMedium
infoLabel.TextColor3 = Color3.fromRGB(200, 205, 235)
infoLabel.TextScaled = true
infoLabel.TextWrapped = true
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.TextYAlignment = Enum.TextYAlignment.Top
infoLabel.Text = "Waiting for the game to begin"
infoLabel.LayoutOrder = 4
infoLabel.Parent = topBar

local infoSizeConstraint = Instance.new("UITextSizeConstraint")
infoSizeConstraint.MaxTextSize = 26
infoSizeConstraint.Parent = infoLabel

local resultFrame = Instance.new("Frame")
resultFrame.Name = "RoundResult"
resultFrame.AnchorPoint = Vector2.new(0.5, 0.5)
resultFrame.Position = UDim2.new(0.5, 0, 0.28, 0)
resultFrame.Size = UDim2.new(0, 420, 0, 180)
resultFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
resultFrame.BackgroundTransparency = 0.2
resultFrame.BorderSizePixel = 0
resultFrame.Visible = false
resultFrame.ZIndex = 10
resultFrame.Parent = screenGui

local resultCorner = Instance.new("UICorner")
resultCorner.CornerRadius = UDim.new(0, 26)
resultCorner.Parent = resultFrame

local resultStroke = Instance.new("UIStroke")
resultStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
resultStroke.Thickness = 3
resultStroke.Color = Color3.fromRGB(160, 170, 255)
resultStroke.Parent = resultFrame

local resultLayout = Instance.new("UIListLayout")
resultLayout.VerticalAlignment = Enum.VerticalAlignment.Center
resultLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
resultLayout.Padding = UDim.new(0, 8)
resultLayout.Parent = resultFrame

local resultLabel = Instance.new("TextLabel")
resultLabel.Name = "ResultLabel"
resultLabel.Size = UDim2.new(1, -40, 0, 72)
resultLabel.BackgroundTransparency = 1
resultLabel.Font = Enum.Font.GothamBlack
resultLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
resultLabel.TextScaled = true
resultLabel.Text = "Victory"
resultLabel.LayoutOrder = 1
resultLabel.Parent = resultFrame

local resultLabelConstraint = Instance.new("UITextSizeConstraint")
resultLabelConstraint.MaxTextSize = 60
resultLabelConstraint.Parent = resultLabel

local resultDetailLabel = Instance.new("TextLabel")
resultDetailLabel.Name = "DetailLabel"
resultDetailLabel.Size = UDim2.new(1, -48, 0, 64)
resultDetailLabel.BackgroundTransparency = 1
resultDetailLabel.Font = Enum.Font.GothamSemibold
resultDetailLabel.TextColor3 = Color3.fromRGB(215, 220, 245)
resultDetailLabel.TextScaled = true
resultDetailLabel.TextWrapped = true
resultDetailLabel.Text = ""
resultDetailLabel.LayoutOrder = 2
resultDetailLabel.Parent = resultFrame

local resultDetailConstraint = Instance.new("UITextSizeConstraint")
resultDetailConstraint.MaxTextSize = 32
resultDetailConstraint.Parent = resultDetailLabel

local selectionFrame = Instance.new("Frame")
selectionFrame.Name = "SelectionFrame"
selectionFrame.AnchorPoint = Vector2.new(0.5, 0.5)
selectionFrame.Position = UDim2.new(0.5, 0, 0.58, 0)
selectionFrame.Size = UDim2.new(0.98, 0, 0, 540)
selectionFrame.BackgroundTransparency = 1
selectionFrame.Visible = false
selectionFrame.Parent = screenGui

local selectionList = Instance.new("UIListLayout")
selectionList.FillDirection = Enum.FillDirection.Vertical
selectionList.HorizontalAlignment = Enum.HorizontalAlignment.Center
selectionList.VerticalAlignment = Enum.VerticalAlignment.Top
selectionList.Padding = UDim.new(0, 0)
selectionList.Parent = selectionFrame
local function createRosterPanel(title: string, accentColor: Color3)
	local panel = Instance.new("Frame")
	panel.Name = title:gsub("%s", "") .. "Panel"
	panel.Size = UDim2.new(0.95, 0, 1, 0)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 26)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = accentColor
	stroke.Parent = panel

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighten(accentColor, 0.45)),
		ColorSequenceKeypoint.new(0.35, lighten(accentColor, 0.2)),
		ColorSequenceKeypoint.new(1, darken(accentColor, 0.7)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	gradient.Parent = panel

	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingTop = UDim.new(0, 24)
	panelPadding.PaddingBottom = UDim.new(0, 24)
	panelPadding.PaddingLeft = UDim.new(0, 24)
	panelPadding.PaddingRight = UDim.new(0, 24)
	panelPadding.Parent = panel

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 48)
	header.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	header.BackgroundTransparency = 0.05
	header.Font = Enum.Font.GothamBlack
	header.TextColor3 = accentColor
	header.TextScaled = true
	header.Text = title
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextYAlignment = Enum.TextYAlignment.Center
	header.Parent = panel

	local headerPadding = Instance.new("UIPadding")
	headerPadding.PaddingLeft = UDim.new(0, 18)
	headerPadding.Parent = header

	local headerConstraint = Instance.new("UITextSizeConstraint")
	headerConstraint.MaxTextSize = 42
	headerConstraint.Parent = header

	local scrollingFrame = Instance.new("ScrollingFrame")
	scrollingFrame.Name = "RosterContainer"
	scrollingFrame.Position = UDim2.new(0, 0, 0, 60)
	scrollingFrame.Size = UDim2.new(1, 0, 1, -72)
	scrollingFrame.BackgroundTransparency = 1
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.ScrollBarImageColor3 = accentColor
	scrollingFrame.ScrollBarThickness = 6
	scrollingFrame.CanvasSize = UDim2.new()
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollingFrame.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 156, 0, 176)
	grid.CellPadding = UDim2.new(0, 12, 0, 12)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.VerticalAlignment = Enum.VerticalAlignment.Top
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = 8
	grid.Parent = scrollingFrame

	return panel, scrollingFrame, accentColor
end

local bossAccent = Color3.fromRGB(200, 80, 90)
local survivorAccent = Color3.fromRGB(80, 150, 245)

local characterAccentColors: {[string]: Color3} = {
	["Mario"] = Color3.fromRGB(220, 60, 60),
	["Donkey Kong"] = Color3.fromRGB(160, 110, 60),
	["Link"] = Color3.fromRGB(90, 175, 110),
	["Samus"] = Color3.fromRGB(255, 140, 60),
	["Kirby"] = Color3.fromRGB(255, 150, 210),
	["Fox"] = Color3.fromRGB(230, 155, 90),
	["Pikachu"] = Color3.fromRGB(255, 225, 90),
	["Luigi"] = Color3.fromRGB(70, 190, 110),
	["Yoshi"] = Color3.fromRGB(120, 200, 90),
	["Jigglypuff"] = Color3.fromRGB(255, 175, 220),
	["Captain Falcon"] = Color3.fromRGB(90, 110, 230),
	["Ness"] = Color3.fromRGB(220, 90, 150),
	["Master Hand"] = Color3.fromRGB(180, 210, 255),
	["Crazy Hand"] = Color3.fromRGB(200, 180, 255),
	["Giga Bowser"] = Color3.fromRGB(70, 150, 90),
}

local defaultAccentColor = Color3.fromRGB(200, 205, 230)

local function getAccentColor(role: string, characterName: string): Color3
	if typeof(characterName) == "string" then
		local accent = characterAccentColors[characterName]
		if accent then
			return accent
		end
	end

	if role == "Boss" then
		return bossAccent
	elseif role == "Fighter" then
		return survivorAccent
	end

	return defaultAccentColor
end

local bossPanel, bossContainer = createRosterPanel("Boss Lineup", bossAccent)
bossPanel.LayoutOrder = 1
bossPanel.Parent = selectionFrame

local survivorPanel, survivorContainer = createRosterPanel("Fighter Lineup", survivorAccent)
survivorPanel.LayoutOrder = 2
survivorPanel.Parent = selectionFrame

local hpFrame = Instance.new("Frame")
hpFrame.Name = "HealthDisplay"
hpFrame.AnchorPoint = Vector2.new(0, 1)
hpFrame.Position = UDim2.new(0, 24, 1, -40)
hpFrame.Size = UDim2.new(0, 360, 0, 140)
hpFrame.BackgroundTransparency = 1
hpFrame.Visible = false
hpFrame.Parent = screenGui

local hpCard = Instance.new("Frame")
hpCard.Name = "Card"
hpCard.AnchorPoint = Vector2.new(0, 1)
hpCard.Position = UDim2.new(0, 0, 1, 0)
hpCard.Size = UDim2.new(1, 0, 1, 0)
hpCard.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
hpCard.BorderSizePixel = 0
hpCard.Parent = hpFrame

local hpCorner = Instance.new("UICorner")
hpCorner.CornerRadius = UDim.new(0, 18)
hpCorner.Parent = hpCard

local hpStroke = Instance.new("UIStroke")
hpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
hpStroke.Thickness = 3
hpStroke.Color = Color3.fromRGB(255, 255, 255)
hpStroke.Transparency = 0.15
hpStroke.Parent = hpCard

local hpAccentLine = Instance.new("Frame")
hpAccentLine.Name = "AccentLine"
hpAccentLine.AnchorPoint = Vector2.new(0, 1)
hpAccentLine.Position = UDim2.new(0, 18, 1, -14)
hpAccentLine.Size = UDim2.new(1, -36, 0, 6)
hpAccentLine.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
hpAccentLine.BorderSizePixel = 0
hpAccentLine.Parent = hpCard

local hpValueLabel = Instance.new("TextLabel")
hpValueLabel.Name = "ValueLabel"
hpValueLabel.AnchorPoint = Vector2.new(1, 0.5)
hpValueLabel.Position = UDim2.new(1, -24, 0.5, 0)
hpValueLabel.Size = UDim2.new(0, 200, 0, 80)
hpValueLabel.BackgroundTransparency = 1
hpValueLabel.Font = Enum.Font.GothamBlack
hpValueLabel.Text = "--"
hpValueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hpValueLabel.TextScaled = true
hpValueLabel.TextXAlignment = Enum.TextXAlignment.Right
hpValueLabel.Parent = hpCard

local hpValueConstraint = Instance.new("UITextSizeConstraint")
hpValueConstraint.MaxTextSize = 66
hpValueConstraint.Parent = hpValueLabel

local hpDetailLabel = Instance.new("TextLabel")
hpDetailLabel.Name = "DetailLabel"
hpDetailLabel.AnchorPoint = Vector2.new(1, 1)
hpDetailLabel.Position = UDim2.new(1, -24, 1, -18)
hpDetailLabel.Size = UDim2.new(0, 200, 0, 26)
hpDetailLabel.BackgroundTransparency = 1
hpDetailLabel.Font = Enum.Font.GothamBold
hpDetailLabel.Text = ""
hpDetailLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
hpDetailLabel.TextScaled = true
hpDetailLabel.TextXAlignment = Enum.TextXAlignment.Right
hpDetailLabel.Visible = false
hpDetailLabel.Parent = hpCard

local hpDetailConstraint = Instance.new("UITextSizeConstraint")
hpDetailConstraint.MaxTextSize = 26
hpDetailConstraint.Parent = hpDetailLabel

local hpNameLabel = Instance.new("TextLabel")
hpNameLabel.Name = "NameLabel"
hpNameLabel.AnchorPoint = Vector2.new(0, 0)
hpNameLabel.Position = UDim2.new(0, 110, 0, 20)
hpNameLabel.Size = UDim2.new(1, -200, 0, 34)
hpNameLabel.BackgroundTransparency = 1
hpNameLabel.Font = Enum.Font.GothamBlack
hpNameLabel.Text = ""
hpNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hpNameLabel.TextScaled = true
hpNameLabel.TextXAlignment = Enum.TextXAlignment.Left
hpNameLabel.Parent = hpCard

local hpNameConstraint = Instance.new("UITextSizeConstraint")
hpNameConstraint.MaxTextSize = 32
hpNameConstraint.Parent = hpNameLabel

local hpPortrait = Instance.new("ImageLabel")
hpPortrait.Name = "ProfileImage"
hpPortrait.AnchorPoint = Vector2.new(0, 1)
hpPortrait.Position = UDim2.new(0, -20, 1, -20)
hpPortrait.Size = UDim2.new(0, 130, 0, 130)
hpPortrait.BackgroundTransparency = 1
hpPortrait.ImageTransparency = 1
hpPortrait.Visible = false
hpPortrait.Rotation = -12
hpPortrait.ZIndex = 2
hpPortrait.Parent = hpCard

local hpPortraitCorner = Instance.new("UICorner")
hpPortraitCorner.CornerRadius = UDim.new(0, 12)
hpPortraitCorner.Parent = hpPortrait

local hpPortraitStroke = Instance.new("UIStroke")
hpPortraitStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
hpPortraitStroke.Thickness = 3
hpPortraitStroke.Color = Color3.fromRGB(255, 255, 255)
hpPortraitStroke.Transparency = 0.1
hpPortraitStroke.Parent = hpPortrait

local hpStockIcon = Instance.new("ImageLabel")
hpStockIcon.Name = "StockIcon"
hpStockIcon.AnchorPoint = Vector2.new(0, 1)
hpStockIcon.Position = UDim2.new(0, 24, 1, 12)
hpStockIcon.Size = UDim2.new(0, 42, 0, 42)
hpStockIcon.BackgroundTransparency = 1
hpStockIcon.ImageTransparency = 1
hpStockIcon.Visible = false
hpStockIcon.ZIndex = 3
hpStockIcon.Parent = hpCard

local hpStockCorner = Instance.new("UICorner")
hpStockCorner.CornerRadius = UDim.new(1, 0)
hpStockCorner.Parent = hpStockIcon

local hpStockStroke = Instance.new("UIStroke")
hpStockStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
hpStockStroke.Thickness = 2
hpStockStroke.Color = Color3.fromRGB(255, 255, 255)
hpStockStroke.Transparency = 0.15
hpStockStroke.Parent = hpStockIcon

local abilityPanel = Instance.new("Frame")
abilityPanel.Name = "AbilityPanel"
abilityPanel.AnchorPoint = Vector2.new(1, 1)
abilityPanel.Position = UDim2.new(1, -32, 1, -32)
abilityPanel.Size = UDim2.new(0, 480, 0, 132)
abilityPanel.BackgroundTransparency = 1
abilityPanel.Visible = false
abilityPanel.Parent = screenGui

local abilityListLayout = Instance.new("UIListLayout")
abilityListLayout.FillDirection = Enum.FillDirection.Horizontal
abilityListLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
abilityListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
abilityListLayout.Padding = UDim.new(0, 12)
abilityListLayout.SortOrder = Enum.SortOrder.LayoutOrder
abilityListLayout.Parent = abilityPanel

local abilityPadding = Instance.new("UIPadding")
abilityPadding.PaddingBottom = UDim.new(0, 12)
abilityPadding.PaddingLeft = UDim.new(0, 12)
abilityPadding.PaddingRight = UDim.new(0, 12)
abilityPadding.Parent = abilityPanel

local fighterListTopOffset = topBar.Position.Y.Offset + topBar.Size.Y.Offset + 16
local fighterListBottomPadding = hpFrame.Size.Y.Offset + 80

local fighterListFrame = Instance.new("Frame")
fighterListFrame.Name = "FighterList"
fighterListFrame.AnchorPoint = Vector2.new(0, 0)
fighterListFrame.Position = UDim2.new(0, 24, 0, fighterListTopOffset)
fighterListFrame.Size = UDim2.new(0, 320, 1, -fighterListBottomPadding)
fighterListFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
fighterListFrame.BackgroundTransparency = 1
fighterListFrame.BorderSizePixel = 0
fighterListFrame.Visible = false
fighterListFrame.Parent = screenGui

local fighterCorner = Instance.new("UICorner")
fighterCorner.CornerRadius = UDim.new(0, 22)
fighterCorner.Parent = fighterListFrame

local fighterStroke = Instance.new("UIStroke")
fighterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
fighterStroke.Thickness = 2
fighterStroke.Color = Color3.fromRGB(255, 255, 255)
fighterStroke.Transparency = 1
fighterStroke.Parent = fighterListFrame

local fighterPadding = Instance.new("UIPadding")
fighterPadding.PaddingTop = UDim.new(0, 18)
fighterPadding.PaddingBottom = UDim.new(0, 18)
fighterPadding.PaddingLeft = UDim.new(0, 18)
fighterPadding.PaddingRight = UDim.new(0, 18)
fighterPadding.Parent = fighterListFrame

local fighterTitle = Instance.new("TextLabel")
fighterTitle.Name = "Title"
fighterTitle.Size = UDim2.new(1, 0, 0, 0)
fighterTitle.BackgroundTransparency = 1
fighterTitle.Font = Enum.Font.GothamBold
fighterTitle.Text = ""
fighterTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
fighterTitle.TextScaled = true
fighterTitle.TextXAlignment = Enum.TextXAlignment.Left
fighterTitle.Visible = false
fighterTitle.Parent = fighterListFrame

local fighterTitleConstraint = Instance.new("UITextSizeConstraint")
fighterTitleConstraint.MaxTextSize = 22
fighterTitleConstraint.Parent = fighterTitle

local fighterListContainer = Instance.new("ScrollingFrame")
fighterListContainer.Name = "ListContainer"
fighterListContainer.Position = UDim2.new(0, 0, 0, 0)
fighterListContainer.Size = UDim2.new(1, 0, 1, 0)
fighterListContainer.BackgroundTransparency = 1
fighterListContainer.BorderSizePixel = 0
fighterListContainer.ScrollBarThickness = 4
fighterListContainer.ScrollBarImageColor3 = Color3.fromRGB(90, 110, 150)
fighterListContainer.ScrollBarImageTransparency = 0.1
fighterListContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
fighterListContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
fighterListContainer.ScrollingDirection = Enum.ScrollingDirection.Y
fighterListContainer.Parent = fighterListFrame

local fighterListLayout = Instance.new("UIListLayout")
fighterListLayout.SortOrder = Enum.SortOrder.LayoutOrder
fighterListLayout.Padding = UDim.new(0, 12)
fighterListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
fighterListLayout.Parent = fighterListContainer

local fighterEmptyLabel = Instance.new("TextLabel")
fighterEmptyLabel.Name = "EmptyLabel"
fighterEmptyLabel.Size = UDim2.new(1, 0, 0, 24)
fighterEmptyLabel.BackgroundTransparency = 1
fighterEmptyLabel.Font = Enum.Font.GothamSemibold
fighterEmptyLabel.Text = "No fighters"
fighterEmptyLabel.TextColor3 = Color3.fromRGB(200, 205, 235)
fighterEmptyLabel.TextScaled = true
fighterEmptyLabel.TextWrapped = true
fighterEmptyLabel.TextXAlignment = Enum.TextXAlignment.Left
fighterEmptyLabel.LayoutOrder = 0
fighterEmptyLabel.Parent = fighterListContainer

local fighterEmptyConstraint = Instance.new("UITextSizeConstraint")
fighterEmptyConstraint.MaxTextSize = 18
fighterEmptyConstraint.Parent = fighterEmptyLabel

local abilityKeyOrder = {"Q", "E", "Z", "X"}
local abilitySlots: {{Frame: Frame, NameLabel: TextLabel, KeyLabel: TextLabel}} = {}
local fighterEntries: {GuiObject} = {}
local bossStatusEntries: {Frame} = {}
local currentFighterNames: {string} = {}

local abilitySlotTemplateSize = UDim2.new(0, 110, 0, 110)

local function createAbilitySlot(index: number, key: string)
	local slotFrame = Instance.new("Frame")
	slotFrame.Name = key .. "Ability"
	slotFrame.Size = abilitySlotTemplateSize
	slotFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	slotFrame.BackgroundTransparency = 0.35
	slotFrame.BorderSizePixel = 0
	slotFrame.LayoutOrder = index
	slotFrame.Parent = abilityPanel

	local slotCorner = Instance.new("UICorner")
	slotCorner.CornerRadius = UDim.new(1, 0)
	slotCorner.Parent = slotFrame

	local slotStroke = Instance.new("UIStroke")
	slotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	slotStroke.Thickness = 3
	slotStroke.Color = Color3.fromRGB(255, 255, 255)
	slotStroke.Transparency = 0
	slotStroke.Parent = slotFrame

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.AnchorPoint = Vector2.new(0.5, 0.3)
	keyLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
	keyLabel.Size = UDim2.new(1, -20, 0, 40)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Font = Enum.Font.GothamBlack
	keyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	keyLabel.TextScaled = true
	keyLabel.Text = key
	keyLabel.Parent = slotFrame

	local keyConstraint = Instance.new("UITextSizeConstraint")
	keyConstraint.MaxTextSize = 40
	keyConstraint.Parent = keyLabel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "AbilityLabel"
	nameLabel.AnchorPoint = Vector2.new(0.5, 1)
	nameLabel.Position = UDim2.new(0.5, 0, 1, -8)
	nameLabel.Size = UDim2.new(1, -16, 0, 32)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamSemibold
	nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	nameLabel.TextScaled = false
	nameLabel.TextSize = 16
	nameLabel.TextWrapped = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	nameLabel.Text = ""
	nameLabel.Parent = slotFrame

	abilitySlots[index] = {
		Frame = slotFrame,
		NameLabel = nameLabel,
		KeyLabel = keyLabel,
	}

	return abilitySlots[index]
end

local currentState = "Waiting"

local assignmentSummaryByUserId: {[number]: {name: string, role: string, character: string?}} = {}
local currentAssignments = {
	Survivors = {} :: {[string]: string},
	Bosses = {} :: {[string]: string},
}
local playerCharacters: {[string]: string} = {}
local playerRoles: {[string]: string} = {}

local localAssignment = {
	role = "",
	character = "",
}

local function cloneRoster(source: {CharacterInfo}): {CharacterInfo}
	local cloned = {}
	for index, info in ipairs(source) do
		cloned[index] = deepCopy(info)
	end
	return cloned
end

local BossRoster = cloneRoster(rawBossRoster)
local FighterRoster = cloneRoster(rawFighterRoster)

local function applyRosterPayload(rosterPayload: {[string]: any}?): boolean
	if typeof(rosterPayload) ~= "table" then
		return false
	end

	local updated = false

	local bosses = rosterPayload.bosses
	if typeof(bosses) == "table" then
		local newBosses = {}
		for index, info in ipairs(bosses) do
			if typeof(info) == "table" then
				newBosses[index] = deepCopy(info)
			end
		end
		if #newBosses == 0 then
			newBosses = cloneRoster(rawBossRoster)
		end

		BossRoster = newBosses :: {CharacterInfo}
		updated = true
	end

	local fighters = rosterPayload.fighters
	if typeof(fighters) == "table" then
		local newFighters = {}
		for index, info in ipairs(fighters) do
			if typeof(info) == "table" then
				newFighters[index] = deepCopy(info)
			end
		end
		if #newFighters == 0 then
			newFighters = cloneRoster(rawFighterRoster)
		end

		FighterRoster = newFighters :: {CharacterInfo}
		updated = true
	end

	return updated
end

local function formatStats(stats: CharacterStats?): string
	if typeof(stats) ~= "table" then
		return "HP --  SPD --  ATK --  JMP --"
	end

	local hp = tonumber((stats :: any).hp) or 0
	local speed = tonumber((stats :: any).speed) or 0
	local attack = tonumber((stats :: any).attack) or 0
	local jump = tonumber((stats :: any).jump) or 0

	return string.format("HP %d  SPD %d  ATK %d  JMP %d", hp, speed, attack, jump)
end

local function getCharacterInfoForRole(role: string, characterName: string): CharacterInfo?
	if characterName == "" then
		return nil
	end

	local roster = role == "Boss" and BossRoster or FighterRoster
	for _, info in ipairs(roster) do
		if info.name == characterName then
			return info
		end
	end

	return nil
end

local function getProfileAssetForRole(role: string, characterName: string): string
	local info = getCharacterInfoForRole(role, characterName)
	if info and info.images and info.images.profile then
		return toAssetId(info.images.profile)
	end
	return ""
end

local function getStockAssetForRole(role: string, characterName: string): string
	local info = getCharacterInfoForRole(role, characterName)
	if info and info.images and info.images.stock then
		return toAssetId(info.images.stock)
	end
	return ""
end

local function clearFighterEntries()
	for _, entry in ipairs(fighterEntries) do
		entry:Destroy()
	end
	table.clear(fighterEntries)
end

local function clearBossStatusEntries()
	for _, entry in ipairs(bossStatusEntries) do
		entry:Destroy()
	end
	table.clear(bossStatusEntries)
end

local function applyAssignmentSummary(summary: {[number]: {name: string, role: string, character: string?}}?)
	assignmentSummaryByUserId = summary or {}
	currentAssignments = {
		Survivors = {},
		Bosses = {},
	}
	playerCharacters = {}
	playerRoles = {}

	local previousRole = localAssignment.role
	local previousCharacter = localAssignment.character

	localAssignment.role = ""
	localAssignment.character = ""

	for _, entry in pairs(assignmentSummaryByUserId) do
		if typeof(entry) == "table" then
			local nameValue = entry.name
			local roleValue = entry.role
			local characterValue = entry.character

			if typeof(nameValue) == "string" and nameValue ~= "" then
				local role = typeof(roleValue) == "string" and roleValue or ""
				local character = typeof(characterValue) == "string" and characterValue or ""

				playerRoles[nameValue] = role
				playerCharacters[nameValue] = character

				if role == "Boss" and character ~= "" then
					currentAssignments.Bosses[character] = nameValue
				elseif role == "Fighter" and character ~= "" then
					currentAssignments.Survivors[character] = nameValue
				end

				if nameValue == localPlayer.Name then
					localAssignment.role = role
					localAssignment.character = character
				end
			end
		end
	end

	if localAssignment.role ~= previousRole or localAssignment.character ~= previousCharacter then
		updateAbilityIcons(currentState == "Round")
		updateHpVisuals()
	end
end

local function getAssignedCharacterForPlayer(playerName: string, bucket: "Survivors" | "Bosses"): string
	local character = playerCharacters[playerName]
	if typeof(character) ~= "string" then
		return ""
	end

	if bucket == "Bosses" then
		return playerRoles[playerName] == "Boss" and character or ""
	end

	return playerRoles[playerName] == "Fighter" and character or ""
end

local function updateHealthDisplay()
	local display = "--"

	if currentHumanoid then
		local maxHealth = math.max(0, roundHealth(currentHumanoid.MaxHealth))
		local health = math.max(0, roundHealth(currentHumanoid.Health))
		if maxHealth > 0 then
			health = math.clamp(health, 0, maxHealth)
		end
		display = string.format("%d%%", health)
	else
		local role = localAssignment.role
		local characterName = localAssignment.character
		if role ~= "" and characterName ~= "" then
			local info = getCharacterInfoForRole(role, characterName)
			local stats = info and info.stats or nil
			local configuredHp = stats and stats.hp or nil
			if typeof(configuredHp) == "number" then
				display = string.format("%d%%", roundHealth(configuredHp))
			end
		end
	end

	hpValueLabel.Text = display
end

local function updateAbilityIcons(isRound: boolean?)
	local role = localAssignment.role
	local characterName = localAssignment.character

	local abilityList: {string}? = nil
	if role ~= "" and characterName ~= "" then
		local info = getCharacterInfoForRole(role, characterName)
		abilityList = info and info.abilities or nil
	end

	local abilityCount = abilityList and #abilityList or 0

	for index = #abilitySlots, abilityCount + 1, -1 do
		local slot = abilitySlots[index]
		if slot then
			slot.Frame:Destroy()
		end
		table.remove(abilitySlots, index)
	end

	for index = 1, abilityCount do
		local key = abilityKeyOrder[index] or tostring(index)
		local slot = abilitySlots[index]
		if not slot then
			slot = createAbilitySlot(index, key)
		else
			slot.Frame.Name = key .. "Ability"
			slot.Frame.LayoutOrder = index
			slot.KeyLabel.Text = key
		end

		local abilityName = abilityList and abilityList[index] or ""
		slot.NameLabel.Text = abilityName ~= "" and abilityName or "Ability"
	end

	abilityPanel.Visible = isRound == true and abilityCount > 0
end

local function updateHpVisuals()
	local role = localAssignment.role
	local characterName = localAssignment.character

	local accent = getAccentColor(role, characterName)
	hpCard.BackgroundColor3 = darken(accent, 0.75)
	hpStroke.Color = lighten(accent, 0.45)
	hpStroke.Transparency = 0.08
	hpAccentLine.BackgroundColor3 = accent
	hpValueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpPortraitStroke.Color = lighten(accent, 0.35)
	hpStockStroke.Color = lighten(accent, 0.4)

	local displayName = localPlayer.DisplayName or localPlayer.Name
	if characterName ~= "" then
		displayName = string.upper(characterName)
	else
		displayName = string.upper(displayName)
	end
	hpNameLabel.Text = displayName

	local profileAsset = ""
	local stockAsset = ""

	if role ~= "" and characterName ~= "" then
		profileAsset = getProfileAssetForRole(role, characterName)
		stockAsset = getStockAssetForRole(role, characterName)
	end

	if profileAsset ~= "" then
		hpPortrait.Image = profileAsset
		hpPortrait.ImageTransparency = 0
		hpPortrait.Visible = true
		hpPortraitStroke.Transparency = 0.05
	else
		hpPortrait.Image = ""
		hpPortrait.ImageTransparency = 1
		hpPortrait.Visible = false
		hpPortraitStroke.Transparency = 1
	end

	if stockAsset ~= "" then
		hpStockIcon.Image = stockAsset
		hpStockIcon.ImageTransparency = 0
		hpStockIcon.Visible = true
		hpStockStroke.Transparency = 0.1
	else
		hpStockIcon.Image = ""
		hpStockIcon.ImageTransparency = 1
		hpStockIcon.Visible = false
		hpStockStroke.Transparency = 1
	end
end

local function updateFighterDisplay(roundData: any)
	local names: {string} = {}
	local aliveLookup: {[string]: boolean} = {}

	if typeof(roundData) == "table" then
		if roundData.fighters then
			for _, entry in ipairs(roundData.fighters) do
				if typeof(entry) == "table" then
					local nameValue = entry.name or entry.playerName
					if typeof(nameValue) == "string" and nameValue ~= "" then
						table.insert(names, nameValue)
						aliveLookup[nameValue] = entry.alive ~= false
					end
				end
			end
		else
			for _, value in ipairs(roundData) do
				if typeof(value) == "string" and value ~= "" then
					table.insert(names, value)
				end
			end
		end
	end

	clearFighterEntries()
	currentFighterNames = names

	fighterListContainer.CanvasPosition = Vector2.new(0, 0)

	if #names == 0 then
		fighterEmptyLabel.Visible = true
		return
	end

	fighterEmptyLabel.Visible = false

	for index, fighterName in ipairs(names) do
		local characterName = getAssignedCharacterForPlayer(fighterName, "Survivors")
		local accent = getAccentColor("Fighter", characterName)
		local stockAsset = characterName ~= "" and getStockAssetForRole("Fighter", characterName) or ""
		local isLocal = fighterName == localPlayer.Name
		local isAlive = aliveLookup[fighterName] ~= false

		local info = characterName ~= "" and getCharacterInfoForRole("Fighter", characterName)
		local maxHp = info and info.stats and info.stats.hp or 0
		local currentHp = maxHp

		local fighterPlayer = Players:FindFirstChild(fighterName)
		if fighterPlayer then
			local character = fighterPlayer.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					currentHp = math.floor(math.max(0, humanoid.Health + 0.5))
				end
			end
		end

		if not isAlive then
			currentHp = 0
		elseif currentHp == 0 and maxHp > 0 then
			currentHp = maxHp
		end

		local hpDisplayText = string.format("%d%%", currentHp)

		local entry = Instance.new("Frame")
		entry.Name = string.format("Fighter%d", index)
		entry.BackgroundColor3 = darken(accent, isLocal and 0.6 or 0.75)
		entry.BackgroundTransparency = 1
		entry.BorderSizePixel = 0
		entry.ClipsDescendants = false
		entry.LayoutOrder = index
		entry.Size = UDim2.new(1, -8, 0, 68)
		entry.Parent = fighterListContainer
		table.insert(fighterEntries, entry)

		local entryLayout = Instance.new("UIListLayout")
		entryLayout.FillDirection = Enum.FillDirection.Horizontal
		entryLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		entryLayout.SortOrder = Enum.SortOrder.LayoutOrder
		entryLayout.Padding = UDim.new(0, 14)
		entryLayout.Parent = entry

		local content = Instance.new("Frame")
		content.Name = "Content"
		content.BackgroundTransparency = 1
		content.LayoutOrder = 1
		content.Size = UDim2.new(1, -12, 1, -8)
		content.Parent = entry

		local contentLayout = Instance.new("UIListLayout")
		contentLayout.FillDirection = Enum.FillDirection.Vertical
		contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
		contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		contentLayout.Padding = UDim.new(0, 6)
		contentLayout.Parent = content

		local characterLabel = Instance.new("TextLabel")
		characterLabel.Name = "CharacterLabel"
		characterLabel.BackgroundTransparency = 1
		characterLabel.LayoutOrder = 1
		characterLabel.Size = UDim2.new(1, 0, 0, 30)
		characterLabel.Font = Enum.Font.GothamBlack
		characterLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		characterLabel.TextScaled = true
		characterLabel.TextXAlignment = Enum.TextXAlignment.Left
		characterLabel.Text = string.upper(characterName ~= "" and characterName or fighterName)
		characterLabel.Parent = content

		local characterConstraint = Instance.new("UITextSizeConstraint")
		characterConstraint.MaxTextSize = 36
		characterConstraint.Parent = characterLabel

		local row = Instance.new("Frame")
		row.Name = "PlayerRow"
		row.BackgroundTransparency = 1
		row.LayoutOrder = 2
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Parent = content

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 10)
		rowLayout.Parent = row

		local stockImage = Instance.new("ImageLabel")
		stockImage.Name = "Stock"
		stockImage.Size = UDim2.new(0, 32, 0, 32)
		stockImage.BackgroundTransparency = 1
		stockImage.LayoutOrder = 1
		stockImage.Image = stockAsset
		stockImage.ImageTransparency = stockAsset ~= "" and 0 or 1
		stockImage.Visible = stockAsset ~= ""
		stockImage.Parent = row

		local stockCorner = Instance.new("UICorner")
		stockCorner.CornerRadius = UDim.new(1, 0)
		stockCorner.Parent = stockImage

		local stockStroke = Instance.new("UIStroke")
		stockStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stockStroke.Thickness = 1.5
		stockStroke.Color = Color3.fromRGB(255, 255, 255)
		stockStroke.Transparency = stockAsset ~= "" and 0.25 or 1
		stockStroke.Parent = stockImage

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlayerLabel"
		nameLabel.BackgroundTransparency = 1
		nameLabel.LayoutOrder = 2
		nameLabel.Size = UDim2.new(1, -40, 1, 0)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = string.format("%s  %s", fighterName, hpDisplayText)
		nameLabel.TextColor3 = isLocal and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 225, 245)
		if not isAlive then
			nameLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
		end
		nameLabel.TextScaled = true
		nameLabel.TextWrapped = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local nameConstraint = Instance.new("UITextSizeConstraint")
		nameConstraint.MaxTextSize = 28
		nameConstraint.Parent = nameLabel

		local accentLine = Instance.new("Frame")
		accentLine.Name = "Accent"
		accentLine.BackgroundColor3 = lighten(accent, isLocal and 0.55 or 0.25)
		accentLine.BorderSizePixel = 0
		accentLine.LayoutOrder = 3
		accentLine.Size = UDim2.new(1, 0, 0, 4)
		if not isAlive then
			accentLine.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		end
		accentLine.Parent = content
	end
end

local function updateBossStatus(roundData: any)
	clearBossStatusEntries()

	if currentState ~= "Round" and currentState ~= "RoundResults" then
		bossStatusContainer.Visible = false
		return
	end

	local bosses = {}
	if typeof(roundData) == "table" and roundData.bosses then
		bosses = roundData.bosses
	end

	if #bosses == 0 then
		bossStatusContainer.Visible = false
		return
	end

	bossStatusContainer.Visible = true

	for index, entry in ipairs(bosses) do
		local nameValue = entry.playerName or entry.name
		local characterName = entry.character or ""
		local displayName = characterName ~= "" and characterName or nameValue or "Boss"
		local accent = bossAccent
		local isLocalBoss = nameValue == localPlayer.Name
		local alive = entry.alive ~= false

		local info = characterName ~= "" and getCharacterInfoForRole("Boss", characterName) or nil
		local maxHp = info and info.stats and info.stats.hp or 0
		local currentHp = maxHp

		local bossPlayerInstance: Player? = nil
		if typeof(nameValue) == "string" then
			bossPlayerInstance = Players:FindFirstChild(nameValue)
			if bossPlayerInstance and bossPlayerInstance.Character then
				local humanoid = bossPlayerInstance.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					currentHp = math.floor(math.max(0, humanoid.Health + 0.5))
					if maxHp <= 0 then
						maxHp = math.floor(math.max(0, humanoid.MaxHealth + 0.5))
					end
				end
			end
		end

		if maxHp <= 0 then
			maxHp = currentHp
		end

		if not alive then
			currentHp = 0
		end

		local ratio = 0
		if maxHp > 0 then
			ratio = math.clamp(currentHp / maxHp, 0, 1)
		end

		local cardFrame = Instance.new("Frame")
		cardFrame.Name = string.format("BossStatus%d", index)
		cardFrame.BackgroundTransparency = 1
		cardFrame.Size = UDim2.new(1, 0, 0, 96)
		cardFrame.LayoutOrder = index
		cardFrame.Parent = bossStatusContainer
		table.insert(bossStatusEntries, cardFrame)

		local card = Instance.new("Frame")
		card.Name = "Card"
		card.BackgroundColor3 = darken(accent, 0.5)
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.Size = UDim2.new(1, 0, 1, 0)
		card.Parent = cardFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 18)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Thickness = 2.5
		cardStroke.Color = lighten(accent, 0.35)
		cardStroke.Transparency = isLocalBoss and 0 or 0.12
		cardStroke.Parent = card

		local cardPadding = Instance.new("UIPadding")
		cardPadding.PaddingTop = UDim.new(0, 12)
		cardPadding.PaddingBottom = UDim.new(0, 12)
		cardPadding.PaddingLeft = UDim.new(0, 16)
		cardPadding.PaddingRight = UDim.new(0, 16)
		cardPadding.Parent = card

		local cardLayout = Instance.new("UIListLayout")
		cardLayout.FillDirection = Enum.FillDirection.Horizontal
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		cardLayout.Padding = UDim.new(0, 16)
		cardLayout.Parent = card

		local portrait = Instance.new("ImageLabel")
		portrait.Name = "Portrait"
		portrait.BackgroundTransparency = 1
		portrait.LayoutOrder = 1
		portrait.Size = UDim2.new(0, 84, 0, 84)
		portrait.Rotation = -10
		portrait.ZIndex = 2
		portrait.Image = characterName ~= "" and getProfileAssetForRole("Boss", characterName) or ""
		portrait.ImageTransparency = portrait.Image ~= "" and 0 or 1
		portrait.Visible = portrait.Image ~= ""
		portrait.Parent = card

		local portraitCorner = Instance.new("UICorner")
		portraitCorner.CornerRadius = UDim.new(0, 12)
		portraitCorner.Parent = portrait

		local portraitStroke = Instance.new("UIStroke")
		portraitStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		portraitStroke.Thickness = 2
		portraitStroke.Color = Color3.fromRGB(255, 255, 255)
		portraitStroke.Transparency = portrait.Image ~= "" and 0.15 or 1
		portraitStroke.Parent = portrait

		local content = Instance.new("Frame")
		content.Name = "Content"
		content.BackgroundTransparency = 1
		content.LayoutOrder = 2
		content.Size = UDim2.new(1, -110, 1, 0)
		content.Parent = card

		local contentLayout = Instance.new("UIListLayout")
		contentLayout.FillDirection = Enum.FillDirection.Vertical
		contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
		contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		contentLayout.Padding = UDim.new(0, 6)
		contentLayout.Parent = content

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.BackgroundTransparency = 1
		nameLabel.LayoutOrder = 1
		nameLabel.Size = UDim2.new(1, 0, 0, 32)
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.Text = string.upper(displayName)
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = content

		local nameConstraint = Instance.new("UITextSizeConstraint")
		nameConstraint.MaxTextSize = 28
		nameConstraint.Parent = nameLabel

		local playerLabel = Instance.new("TextLabel")
		playerLabel.Name = "PlayerLabel"
		playerLabel.BackgroundTransparency = 1
		playerLabel.LayoutOrder = 2
		playerLabel.Size = UDim2.new(1, 0, 0, 20)
		playerLabel.Font = Enum.Font.GothamSemibold
		local playerDisplayName = bossPlayerInstance and bossPlayerInstance.DisplayName or nameValue
		playerLabel.Text = playerDisplayName or "Unknown"
		playerLabel.TextColor3 = Color3.fromRGB(220, 225, 245)
		playerLabel.TextScaled = true
		playerLabel.TextXAlignment = Enum.TextXAlignment.Left
		playerLabel.Parent = content

		local playerConstraint = Instance.new("UITextSizeConstraint")
		playerConstraint.MaxTextSize = 20
		playerConstraint.Parent = playerLabel

		local statusBar = Instance.new("Frame")
		statusBar.Name = "StatusBar"
		statusBar.BackgroundColor3 = darken(accent, 0.65)
		statusBar.BackgroundTransparency = 0.2
		statusBar.BorderSizePixel = 0
		statusBar.LayoutOrder = 3
		statusBar.Size = UDim2.new(1, 0, 0, 24)
		statusBar.Parent = content

		local statusCorner = Instance.new("UICorner")
		statusCorner.CornerRadius = UDim.new(1, 0)
		statusCorner.Parent = statusBar

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.BackgroundColor3 = lighten(accent, 0.35)
		fill.BorderSizePixel = 0
		fill.Position = UDim2.new(0, 0, 0.5, 0)
		fill.Size = UDim2.new(alive and ratio or 0, 0, 1, 0)
		fill.Parent = statusBar

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		local bossHpDisplayText = string.format("%d%%", currentHp)

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "StatusLabel"
		statusLabel.BackgroundTransparency = 1
		statusLabel.Size = UDim2.new(1, -12, 1, 0)
		statusLabel.Font = Enum.Font.GothamSemibold
		statusLabel.Text = bossHpDisplayText
		if alive then
			statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			statusLabel.TextColor3 = Color3.fromRGB(220, 120, 120)
		end
		statusLabel.TextScaled = true
		statusLabel.TextXAlignment = Enum.TextXAlignment.Center
		statusLabel.Parent = statusBar

		local statusConstraint = Instance.new("UITextSizeConstraint")
		statusConstraint.MaxTextSize = 18
		statusConstraint.Parent = statusLabel
	end
end

local roundEndDescriptions = {
	BossVictory = "The bosses endured until the end.",
	FighterVictory = "The fighters defeated every boss.",
	BossLeft = "The boss left the round.",
	AllFightersLeft = "All fighters left the round.",
	TooManyPlayersLeft = "Too many players left to continue.",
	TimeUp = "Time expired.",
	NoBosses = "Round cancelled - no bosses were available.",
	NoFighters = "Round cancelled - no fighters were available.",
	RoundTimerExpiredBossAlive = "Time expired with bosses still standing.",
	RoundTimerExpired = "Time expired.",
	EveryoneEliminated = "Everyone was eliminated.",
	NotEnoughPlayers = "Round ended - not enough players remaining.",
}

local function describeRoundEndReason(reason: string?): string
	if typeof(reason) ~= "string" or reason == "" then
		return "Round complete."
	end
	return roundEndDescriptions[reason] or reason
end

local function clearButtons(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

local function applyButtonVisualState(button: TextButton, accentColor: Color3, assignedPlayer: string?, canSelect: boolean)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	local gradient = button:FindFirstChildOfClass("UIGradient")
	local badge = button:FindFirstChild("OccupantLabel")

	local availableColor = darken(accentColor, 0.6)
	local highlightColor = lighten(accentColor, 0.4)

	if assignedPlayer ~= nil and assignedPlayer ~= "" then
		if assignedPlayer == localPlayer.Name then
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, highlightColor),
					ColorSequenceKeypoint.new(1, darken(accentColor, 0.3)),
				})
			end
			if stroke then
				stroke.Color = accentColor
				stroke.Thickness = 3
			end
		else
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 80)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 40)),
				})
			end
			if stroke then
				stroke.Color = Color3.fromRGB(100, 100, 110)
				stroke.Thickness = 2
			end
		end
		if badge then
			badge.Visible = true
			badge.Text = assignedPlayer == localPlayer.Name and "YOU" or assignedPlayer
		end
		button.AutoButtonColor = false
		button.Active = false
	else
		if gradient then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, highlightColor),
				ColorSequenceKeypoint.new(1, availableColor),
			})
		end
		if stroke then
			stroke.Color = accentColor
			stroke.Thickness = 2
		end
		if badge then
			badge.Visible = false
		end
		button.AutoButtonColor = canSelect
		button.Active = canSelect
		if not canSelect then
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 60, 70)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 36)),
				})
			end
			if stroke then
				stroke.Color = Color3.fromRGB(90, 90, 100)
				stroke.Thickness = 2
			end
		end
	end
end

local function makeButton(characterInfo: CharacterInfo, requestRole: string, takenBy: string?, canSelect: boolean, accentColor: Color3): TextButton
	local characterName = characterInfo.name

	local button = Instance.new("TextButton")
	button.Name = characterName .. "Tile"
	button.Size = UDim2.new(0, 156, 0, 176)
	button.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = 1
	button.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = accentColor
	stroke.Thickness = 2
	stroke.Parent = button

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighten(accentColor, 0.35)),
		ColorSequenceKeypoint.new(1, darken(accentColor, 0.65)),
	})
	gradient.Parent = button

	local topStrip = Instance.new("Frame")
	topStrip.Name = "TopStrip"
	topStrip.Size = UDim2.new(1, 0, 0, 6)
	topStrip.BackgroundColor3 = lighten(accentColor, 0.25)
	topStrip.BorderSizePixel = 0
	topStrip.Parent = button

	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 20)
	portrait.Size = UDim2.new(1, -20, 0, 112)
	portrait.BackgroundTransparency = 1
	portrait.ImageTransparency = 1
	portrait.Parent = button

	local portraitAsset = characterInfo.images and characterInfo.images.profile and toAssetId(characterInfo.images.profile) or ""
	if portraitAsset ~= "" then
		portrait.Image = portraitAsset
		portrait.ImageTransparency = 0
	end

	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(0, 12)
	portraitCorner.Parent = portrait

	local portraitStroke = Instance.new("UIStroke")
	portraitStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	portraitStroke.Thickness = 2
	portraitStroke.Color = Color3.fromRGB(255, 255, 255)
	portraitStroke.Transparency = portraitAsset ~= "" and 0.15 or 1
	portraitStroke.Parent = portrait

	local badge = Instance.new("TextLabel")
	badge.Name = "OccupantLabel"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -10, 0, 10)
	badge.Size = UDim2.new(0, 96, 0, 28)
	badge.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
	badge.BackgroundTransparency = 0.2
	badge.BorderSizePixel = 0
	badge.Font = Enum.Font.GothamBold
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.TextScaled = true
	badge.Text = ""
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.Visible = false
	badge.Parent = button

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 12)
	badgeCorner.Parent = badge

	local badgeConstraint = Instance.new("UITextSizeConstraint")
	badgeConstraint.MaxTextSize = 24
	badgeConstraint.Parent = badge

	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.new(1, 0, 0, 46)
	footer.BackgroundColor3 = Color3.fromRGB(12, 14, 24)
	footer.BackgroundTransparency = 0.1
	footer.BorderSizePixel = 0
	footer.Parent = button

	local footerGradient = Instance.new("UIGradient")
	footerGradient.Rotation = 90
	footerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, darken(accentColor, 0.6)),
		ColorSequenceKeypoint.new(1, darken(accentColor, 0.2)),
	})
	footerGradient.Parent = footer

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.Text = string.upper(characterName)
	nameLabel.TextWrapped = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Size = UDim2.new(1, -12, 1, 0)
	nameLabel.Position = UDim2.new(0, 6, 0, 0)
	nameLabel.Parent = footer

	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MaxTextSize = 22
	nameConstraint.Parent = nameLabel

	applyButtonVisualState(button, accentColor, takenBy, canSelect)

	if (not takenBy or takenBy == "") and canSelect then
		button.MouseButton1Click:Connect(function()
			remotes.RequestCharacter:FireServer(requestRole, characterName)
		end)
	end

	return button
end

local function renderButtons(playerRole: string, stepOverride: string?)
	local effectiveStep = stepOverride or currentState
	if effectiveStep ~= "CharacterSelect" then
		bossPanel.Visible = false
		survivorPanel.Visible = false
		clearButtons(bossContainer)
		clearButtons(survivorContainer)
		return
	end

	local showBossPanel = false
	local showFighterPanel = false
	local canPickBoss = false
	local canPickSurvivor = false

	if playerRole == "Boss" then
		showBossPanel = true
		canPickBoss = true
	elseif playerRole == "Fighter" then
		showFighterPanel = true
		canPickSurvivor = true
	else
		-- If the local role is not assigned yet (e.g. very first frame) still show
		-- both rosters so the selection screen isn't empty while we wait for data.
		showBossPanel = true
		showFighterPanel = true
	end

	bossPanel.Visible = showBossPanel
	survivorPanel.Visible = showFighterPanel

	if showBossPanel then
		clearButtons(bossContainer)
		for index, characterInfo in ipairs(BossRoster) do
			local assigned = currentAssignments.Bosses[characterInfo.name]
			local button = makeButton(characterInfo, "Boss", assigned, canPickBoss, bossAccent)
			button.LayoutOrder = index
			button.Parent = bossContainer
		end
	else
		clearButtons(bossContainer)
	end

	if showFighterPanel then
		clearButtons(survivorContainer)
		for index, characterInfo in ipairs(FighterRoster) do
			local assigned = currentAssignments.Survivors[characterInfo.name]
			local button = makeButton(characterInfo, "Fighter", assigned, canPickSurvivor, survivorAccent)
			button.LayoutOrder = index
			button.Parent = survivorContainer
		end
	else
		clearButtons(survivorContainer)
	end
end

local function updateSelectionVisibility()
	local inSelection = currentState == "CharacterSelect"
	selectionFrame.Visible = inSelection

	renderButtons(localAssignment.role, currentState)
end

local function updateTimerDisplay(timeLeft: number?)
	if typeof(timeLeft) == "number" and timeLeft >= 0 then
		countdownSeconds = timeLeft
		refreshTimerLabel(true)
	else
		countdownSeconds = nil
		refreshTimerLabel(true)
	end
end

RunService.Heartbeat:Connect(function(dt)
	if countdownSeconds ~= nil then
		if countdownSeconds > 0 then
			countdownSeconds = math.max(0, countdownSeconds - dt)
		end
		refreshTimerLabel()
	end
end)

local function updateHeader(state: string)
	headerLabel.Text = string.format("Step: %s", state)
end

local function updateInfo(text: string)
	infoLabel.Text = text
end

local function updateResultDisplay(winner: string?, reason: string?)
	if currentState ~= "RoundResults" and currentState ~= "RoundEnd" then
		resultFrame.Visible = false
		return
	end

	if winner ~= "Boss" and winner ~= "Fighter" then
		resultFrame.Visible = false
		return
	end

	local role = localAssignment.role
	if role ~= "Boss" and role ~= "Fighter" then
		resultFrame.Visible = false
		return
	end

	local playerWon = (winner == "Boss" and role == "Boss") or (winner == "Fighter" and role == "Fighter")
	resultLabel.Text = playerWon and "Victory" or "Defeat"
	resultLabel.TextColor3 = playerWon and Color3.fromRGB(130, 255, 170) or Color3.fromRGB(255, 140, 140)
	resultDetailLabel.Text = describeRoundEndReason(reason)
	resultFrame.Visible = true
end

local function updateRoundHudVisibility()
	local isRound = currentState == "Round"
	hpFrame.Visible = isRound
	fighterListFrame.Visible = isRound

	if isRound then
		ensureCurrentHumanoid()
		updateHealthDisplay()
	else
		clearBossStatusEntries()
		bossStatusContainer.Visible = false
	end

	updateAbilityIcons(isRound)
end

local function computeTimeLeft(payload: {[string]: any}?): number?
	if not payload then
		return nil
	end

	local stepEndsAt = payload.stepEndsAt
	local now = payload.now

	if typeof(stepEndsAt) == "number" then
		local currentTime = typeof(now) == "number" and now or 0
		return math.max(0, stepEndsAt - currentTime)
	end

	return nil
end

local function extractCounts(roundData: {[string]: any}?): (number, number)
	if not roundData then
		return 0, 0
	end

	local fighterCount = 0
	local bossCount = 0

	if typeof(roundData.fighters) == "table" then
		fighterCount = #roundData.fighters
	end
	if typeof(roundData.bosses) == "table" then
		bossCount = #roundData.bosses
	end

	return fighterCount, bossCount
end

local function onRoundStateChanged(payload: {[string]: any})
	if typeof(payload) ~= "table" then
		return
	end

	local step = payload.step or "Waiting"
	currentState = step
	updateHeader(step)

	local rosterUpdated = false
	local payloadRoster = payload.roster
	if payloadRoster ~= nil then
		rosterUpdated = applyRosterPayload(payloadRoster) or rosterUpdated
	elseif typeof(payload.selection) == "table" and payload.selection.roster ~= nil then
		rosterUpdated = applyRosterPayload(payload.selection.roster) or rosterUpdated
	end

	if payload.assignments then
		applyAssignmentSummary(payload.assignments)
	end

	if rosterUpdated then
		updateAbilityIcons(currentState == "Round")
		updateHpVisuals()
		if step == "CharacterSelect" then
			renderButtons(localAssignment.role, step)
		end
	end

	local timeLeft = computeTimeLeft(payload)
	updateTimerDisplay(timeLeft)

	local message = "Waiting for the game to begin"
	resultFrame.Visible = false

	if step == "CharacterSelect" then
		selectionFrame.Visible = true
		if localAssignment.role == "" then
			message = "Waiting for your assignment..."
		elseif localAssignment.role == "Boss" then
			message = "Choose your boss. Each boss can only be selected once."
		else
			message = "Choose your fighter. Each fighter can only be selected once."
		end
		renderButtons(localAssignment.role, step)
		updateFighterDisplay({})
		updateBossStatus(nil)
	elseif step == "SelectionLock" then
		message = "Selections locked - preparing the round..."
		selectionFrame.Visible = false
		renderButtons(localAssignment.role, step)
		updateFighterDisplay({})
		updateBossStatus(nil)
	elseif step == "Intermission" then
		message = "Intermission in progress"
		selectionFrame.Visible = false
		renderButtons(localAssignment.role, step)
		updateFighterDisplay({})
		updateBossStatus(nil)
	elseif step == "Round" or step == "RoundResults" then
		local roundData = payload.round or {}
		local fighters, bosses = extractCounts(roundData)
		message = string.format("Round active - %d fighter(s) vs %d boss(es)", fighters, bosses)
		selectionFrame.Visible = false
		renderButtons(localAssignment.role, step)
		updateFighterDisplay(roundData)
		updateBossStatus(roundData)
		if step == "RoundResults" then
			updateResultDisplay(roundData.winner, roundData.reason)
		else
			resultFrame.Visible = false
		end
	else
		selectionFrame.Visible = false
		renderButtons(localAssignment.role, step)
		updateFighterDisplay({})
		updateBossStatus(nil)
	end

	if step == "Waiting" then
		message = "Waiting for enough players to start"
	elseif step == "RoundResults" then
		message = describeRoundEndReason(payload.round and payload.round.reason or "")
	end

	updateInfo(message)
	updateSelectionVisibility()
	updateRoundHudVisibility()
end

local currentHumanoid: Humanoid? = nil
local humanoidConnections = {
	HealthChanged = nil :: RBXScriptConnection?,
	MaxHealthChanged = nil :: RBXScriptConnection?,
	Died = nil :: RBXScriptConnection?,
	Ancestry = nil :: RBXScriptConnection?,
}

local function disconnectHumanoidSignals()
	for key, connection in pairs(humanoidConnections) do
		if connection then
			connection:Disconnect()
			humanoidConnections[key] = nil
		end
	end
end

local function setCurrentHumanoid(humanoid: Humanoid?)
	if currentHumanoid == humanoid then
		updateHealthDisplay()
		return
	end

	disconnectHumanoidSignals()
	currentHumanoid = humanoid

	if humanoid then
		humanoidConnections.HealthChanged = humanoid.HealthChanged:Connect(updateHealthDisplay)
		humanoidConnections.MaxHealthChanged = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealthDisplay)
		humanoidConnections.Died = humanoid.Died:Connect(function()
			task.defer(updateHealthDisplay)
		end)
		humanoidConnections.Ancestry = humanoid.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				setCurrentHumanoid(nil)
			end
		end)
	end

	updateHealthDisplay()
end

local function ensureCurrentHumanoid()
	if currentHumanoid and currentHumanoid.Parent then
		return
	end

	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		setCurrentHumanoid(humanoid)
	end
end

local characterConnections = {
	ChildAdded = nil :: RBXScriptConnection?,
}

local function observeCharacter(character: Model)
	if characterConnections.ChildAdded then
		characterConnections.ChildAdded:Disconnect()
		characterConnections.ChildAdded = nil
	end

	characterConnections.ChildAdded = character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then
			setCurrentHumanoid(child)
		end
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	setCurrentHumanoid(humanoid)
end

local function clearCharacterObservation()
	if characterConnections.ChildAdded then
		characterConnections.ChildAdded:Disconnect()
		characterConnections.ChildAdded = nil
	end
	setCurrentHumanoid(nil)
end

localPlayer.CharacterAdded:Connect(observeCharacter)
localPlayer.CharacterRemoving:Connect(function()
	clearCharacterObservation()
end)

if localPlayer.Character then
	observeCharacter(localPlayer.Character)
else
	updateHealthDisplay()
end

remotes.RoundStateChanged.OnClientEvent:Connect(onRoundStateChanged)
remotes.CharacterAssignment.OnClientEvent:Connect(function(summary)
	applyAssignmentSummary(summary)
	if currentState == "CharacterSelect" then
		renderButtons(localAssignment.role, currentState)
	end
end)

local function hydrateFromServer()
	if not getRoundStateRemote or not getRoundStateRemote:IsA("RemoteFunction") then
		return
	end

	local ok, payload = pcall(function()
		return getRoundStateRemote:InvokeServer()
	end)

	if ok and typeof(payload) == "table" then
		onRoundStateChanged(payload)
	end
end

hydrateFromServer()

updateHeader(currentState)
updateTimerDisplay(nil)
updateInfo("Waiting for the game to begin")
updateResultDisplay(nil, nil)
updateSelectionVisibility()
updateAbilityIcons(currentState == "Round")
updateFighterDisplay({})
updateRoundHudVisibility()
updateHpVisuals()
