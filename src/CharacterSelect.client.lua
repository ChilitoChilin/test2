--!strict
-- CharacterSelect.client.lua
-- Example UI for tracking step timers and allowing players to lock in characters.
-- Place this LocalScript inside StarterPlayerScripts (or nested in a ScreenGui
-- under StarterGui) to provide the selection HUD to each player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local remotes = {
    RoundStateChanged = ReplicatedStorage:WaitForChild("RoundStateChanged"),
    RequestCharacter = ReplicatedStorage:WaitForChild("RequestCharacter"),
    CharacterAssignment = ReplicatedStorage:WaitForChild("CharacterAssignment"),
}

local rawBossRoster = require(ReplicatedStorage:WaitForChild("BossRoster"))
local rawFighterRoster = require(ReplicatedStorage:WaitForChild("FighterRoster"))

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

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BossRoundHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
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

local bossStatusContainer = Instance.new("Frame")
bossStatusContainer.Name = "BossStatus"
bossStatusContainer.AnchorPoint = Vector2.new(0, 0)
bossStatusContainer.Position = UDim2.new(0, 24, 0, 176)
bossStatusContainer.Size = UDim2.new(0, 360, 0, 0)
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
bossStatusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
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
selectionFrame.Position = UDim2.new(0.5, 0, 0.6, 0)
selectionFrame.Size = UDim2.new(0.96, 0, 0, 520)
selectionFrame.BackgroundTransparency = 1
selectionFrame.Visible = false
selectionFrame.Parent = screenGui

local selectionList = Instance.new("UIListLayout")
selectionList.FillDirection = Enum.FillDirection.Horizontal
selectionList.HorizontalAlignment = Enum.HorizontalAlignment.Center
selectionList.VerticalAlignment = Enum.VerticalAlignment.Center
selectionList.Padding = UDim.new(0, 24)
selectionList.Parent = selectionFrame

local function createRosterPanel(title: string, accentColor: Color3)
    local panel = Instance.new("Frame")
    panel.Name = title:gsub("%s", "") .. "Panel"
    panel.Size = UDim2.new(0.48, 0, 1, 0)
    panel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
    panel.BackgroundTransparency = 0.05
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
    panelPadding.PaddingTop = UDim.new(0, 18)
    panelPadding.PaddingBottom = UDim.new(0, 18)
    panelPadding.PaddingLeft = UDim.new(0, 18)
    panelPadding.PaddingRight = UDim.new(0, 18)
    panelPadding.Parent = panel

    local header = Instance.new("TextLabel")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.TextColor3 = accentColor
    header.TextScaled = true
    header.Text = title
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = panel

    local headerConstraint = Instance.new("UITextSizeConstraint")
    headerConstraint.MaxTextSize = 40
    headerConstraint.Parent = header

    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.Size = UDim2.new(1, 0, 0, 3)
    divider.Position = UDim2.new(0, 0, 0, 46)
    divider.BackgroundColor3 = accentColor
    divider.BackgroundTransparency = 0.25
    divider.BorderSizePixel = 0
    divider.Parent = panel

    local scrollingFrame = Instance.new("ScrollingFrame")
    scrollingFrame.Name = "RosterContainer"
    scrollingFrame.Position = UDim2.new(0, 0, 0, 58)
    scrollingFrame.Size = UDim2.new(1, 0, 1, -70)
    scrollingFrame.BackgroundTransparency = 1
    scrollingFrame.BorderSizePixel = 0
    scrollingFrame.ScrollBarImageColor3 = accentColor
    scrollingFrame.ScrollBarThickness = 6
    scrollingFrame.CanvasSize = UDim2.new()
    scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollingFrame.Parent = panel

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0, 210, 0, 240)
    grid.CellPadding = UDim2.new(0, 18, 0, 18)
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.VerticalAlignment = Enum.VerticalAlignment.Top
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.FillDirectionMaxCells = 4
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

local roundColumn = Instance.new("Frame")
roundColumn.Name = "RoundColumn"
roundColumn.AnchorPoint = Vector2.new(0, 1)
roundColumn.Position = UDim2.new(0, 24, 1, -32)
roundColumn.Size = UDim2.new(0, 360, 0, 540)
roundColumn.BackgroundTransparency = 1
roundColumn.Visible = false
roundColumn.Parent = screenGui

local roundColumnLayout = Instance.new("UIListLayout")
roundColumnLayout.FillDirection = Enum.FillDirection.Vertical
roundColumnLayout.SortOrder = Enum.SortOrder.LayoutOrder
roundColumnLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
roundColumnLayout.Padding = UDim.new(0, 24)
roundColumnLayout.Parent = roundColumn

local hpFrame = Instance.new("Frame")
hpFrame.Name = "HealthDisplay"
hpFrame.Size = UDim2.new(1, 0, 0, 140)
hpFrame.BackgroundTransparency = 1
hpFrame.Visible = false
hpFrame.LayoutOrder = 2
hpFrame.Parent = roundColumn

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

local fighterListFrame = Instance.new("Frame")
fighterListFrame.Name = "FighterList"
fighterListFrame.Size = UDim2.new(1, 0, 0, 340)
fighterListFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
fighterListFrame.BackgroundTransparency = 0.08
fighterListFrame.BorderSizePixel = 0
fighterListFrame.Visible = false
fighterListFrame.LayoutOrder = 1
fighterListFrame.Parent = roundColumn

local fighterCorner = Instance.new("UICorner")
fighterCorner.CornerRadius = UDim.new(0, 22)
fighterCorner.Parent = fighterListFrame

local fighterStroke = Instance.new("UIStroke")
fighterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
fighterStroke.Thickness = 2
fighterStroke.Color = Color3.fromRGB(255, 255, 255)
fighterStroke.Transparency = 0.12
fighterStroke.Parent = fighterListFrame

local fighterPadding = Instance.new("UIPadding")
fighterPadding.PaddingTop = UDim.new(0, 18)
fighterPadding.PaddingBottom = UDim.new(0, 18)
fighterPadding.PaddingLeft = UDim.new(0, 18)
fighterPadding.PaddingRight = UDim.new(0, 18)
fighterPadding.Parent = fighterListFrame

local fighterTitle = Instance.new("TextLabel")
fighterTitle.Name = "Title"
fighterTitle.Size = UDim2.new(1, 0, 0, 28)
fighterTitle.BackgroundTransparency = 1
fighterTitle.Font = Enum.Font.GothamBold
fighterTitle.Text = "Fighters"
fighterTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
fighterTitle.TextScaled = true
fighterTitle.TextXAlignment = Enum.TextXAlignment.Left
fighterTitle.Parent = fighterListFrame

local fighterTitleConstraint = Instance.new("UITextSizeConstraint")
fighterTitleConstraint.MaxTextSize = 22
fighterTitleConstraint.Parent = fighterTitle

local fighterListContainer = Instance.new("ScrollingFrame")
fighterListContainer.Name = "ListContainer"
fighterListContainer.Position = UDim2.new(0, 0, 0, 36)
fighterListContainer.Size = UDim2.new(1, 0, 1, -36)
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
local currentFighterNames: {string} = {}
local currentBossStatuses: {any} = {}
local bossStatusEntries: {Frame} = {}

local function createAbilitySlot(index: number, key: string)
    local slotFrame = Instance.new("Frame")
    slotFrame.Name = key .. "Ability"
    slotFrame.Size = UDim2.new(0, 110, 0, 110)
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

local function clearFighterEntries()
    for _, entry in ipairs(fighterEntries) do
        entry:Destroy()
    end
    fighterEntries = {}
end

local function clearBossStatusEntries()
    for _, entry in ipairs(bossStatusEntries) do
        entry:Destroy()
    end
    bossStatusEntries = {}
end

local function copyStringList(list: {string}): {string}
    local cloned: {string} = {}
    for index, value in ipairs(list) do
        cloned[index] = value
    end
    return cloned
end

local function sanitizeBossStatusList(statusList: {any}?): {any}
    local sanitized = {}

    if typeof(statusList) ~= "table" then
        return sanitized
    end

    for _, status in ipairs(statusList) do
        if typeof(status) == "table" then
            local entry = {
                playerName = typeof(status.playerName) == "string" and status.playerName or "",
                characterName = typeof(status.characterName) == "string" and status.characterName or "",
                health = typeof(status.health) == "number" and status.health or nil,
                maxHealth = typeof(status.maxHealth) == "number" and status.maxHealth or nil,
                profileAsset = "",
            }

            if status.profileId ~= nil then
                entry.profileAsset = toAssetId(status.profileId)
            end

            table.insert(sanitized, entry)
        end
    end

    return sanitized
end

local function renderBossStatusEntries(statusList: {any})
    clearBossStatusEntries()

    if currentState ~= "Round" then
        bossStatusContainer.Visible = false
        return
    end

    if #statusList == 0 then
        bossStatusContainer.Visible = false
        return
    end

    bossStatusContainer.Visible = true

    for index, status in ipairs(statusList) do
        local characterName = typeof(status.characterName) == "string" and status.characterName or ""
        local playerName = typeof(status.playerName) == "string" and status.playerName or ""
        local displayName = characterName ~= "" and characterName or (playerName ~= "" and playerName or "Boss")
        local healthValue = typeof(status.health) == "number" and status.health or nil
        local maxHealthValue = typeof(status.maxHealth) == "number" and status.maxHealth or nil
        local profileAsset = typeof(status.profileAsset) == "string" and status.profileAsset or ""
        local accent = bossAccent
        local isLocalBoss = playerName == localPlayer.Name

        local health = 0
        local maxHealth = 0
        local fillPercent = 0
        local healthLabelText = "HP --/--"

        if healthValue ~= nil and maxHealthValue ~= nil then
            maxHealth = math.max(0, math.floor(maxHealthValue + 0.5))
            health = math.max(0, math.floor(healthValue + 0.5))
            if maxHealth > 0 then
                health = math.clamp(health, 0, maxHealth)
                fillPercent = clamp01(health / maxHealth)
            end
            healthLabelText = string.format("HP %d/%d", health, maxHealth)
        end

        local entry = Instance.new("Frame")
        entry.Name = string.format("BossStatus%d", index)
        entry.BackgroundTransparency = 1
        entry.Size = UDim2.new(1, 0, 0, 96)
        entry.LayoutOrder = index
        entry.Parent = bossStatusContainer

        local card = Instance.new("Frame")
        card.Name = "Card"
        card.BackgroundColor3 = darken(accent, 0.5)
        card.BackgroundTransparency = 0
        card.BorderSizePixel = 0
        card.Size = UDim2.new(1, 0, 1, 0)
        card.Parent = entry

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
        portrait.Image = profileAsset
        portrait.ImageTransparency = profileAsset ~= "" and 0 or 1
        portrait.Visible = profileAsset ~= ""
        portrait.Parent = card

        local portraitCorner = Instance.new("UICorner")
        portraitCorner.CornerRadius = UDim.new(0, 12)
        portraitCorner.Parent = portrait

        local portraitStroke = Instance.new("UIStroke")
        portraitStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        portraitStroke.Thickness = 2
        portraitStroke.Color = Color3.fromRGB(255, 255, 255)
        portraitStroke.Transparency = profileAsset ~= "" and 0.15 or 1
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

        local healthBar = Instance.new("Frame")
        healthBar.Name = "HealthBar"
        healthBar.BackgroundColor3 = darken(accent, 0.65)
        healthBar.BackgroundTransparency = 0.2
        healthBar.BorderSizePixel = 0
        healthBar.LayoutOrder = 2
        healthBar.Size = UDim2.new(1, 0, 0, 24)
        healthBar.Parent = content

        local healthCorner = Instance.new("UICorner")
        healthCorner.CornerRadius = UDim.new(1, 0)
        healthCorner.Parent = healthBar

        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.AnchorPoint = Vector2.new(0, 0.5)
        fill.BackgroundColor3 = lighten(accent, 0.3)
        fill.BorderSizePixel = 0
        fill.Position = UDim2.new(0, 0, 0.5, 0)
        fill.Size = UDim2.new(fillPercent, 0, 1, 0)
        fill.Parent = healthBar

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(1, 0)
        fillCorner.Parent = fill

        local fillGradient = Instance.new("UIGradient")
        fillGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, lighten(accent, 0.5)),
            ColorSequenceKeypoint.new(1, accent),
        })
        fillGradient.Parent = fill

        local healthLabel = Instance.new("TextLabel")
        healthLabel.Name = "HealthLabel"
        healthLabel.BackgroundTransparency = 1
        healthLabel.Size = UDim2.new(1, -12, 1, 0)
        healthLabel.Font = Enum.Font.GothamSemibold
        healthLabel.Text = healthLabelText
        healthLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        healthLabel.TextScaled = true
        healthLabel.TextXAlignment = Enum.TextXAlignment.Center
        healthLabel.Parent = healthBar

        local healthConstraint = Instance.new("UITextSizeConstraint")
        healthConstraint.MaxTextSize = 18
        healthConstraint.Parent = healthLabel

        table.insert(bossStatusEntries, entry)
    end
end

local function getFighterDisplayData(playerName: string)
    local characterName = getAssignedCharacterForPlayer(playerName, "Survivors")
    local accent = getAccentColor("Fighter", characterName)
    local profileAsset = characterName ~= "" and getProfileAssetForRole("Fighter", characterName) or ""
    local stockAsset = characterName ~= "" and getStockAssetForRole("Fighter", characterName) or ""
    return characterName, accent, profileAsset, stockAsset
end

local function updateFighterDisplay(names: {any}?)
    local sanitized: {string} = {}
    local seen: {[string]: boolean} = {}
    if typeof(names) == "table" then
        for _, value in ipairs(names) do
            if typeof(value) == "string" and value ~= "" and not seen[value] then
                table.insert(sanitized, value)
                seen[value] = true
            end
        end
    end

    if currentState == "Round" then
        for _, player in ipairs(Players:GetPlayers()) do
            local roleValue = player:GetAttribute("AssignedRole")
            local characterValue = player:GetAttribute("AssignedCharacter")
            if roleValue == "Fighter" and typeof(characterValue) == "string" and characterValue ~= "" then
                if not seen[player.Name] then
                    table.insert(sanitized, player.Name)
                    seen[player.Name] = true
                end
            end
        end
    end

    clearFighterEntries()
    currentFighterNames = copyStringList(sanitized)
    fighterListContainer.CanvasPosition = Vector2.new(0, 0)

    if #sanitized == 0 then
        fighterEmptyLabel.Visible = true
        return
    end

    fighterEmptyLabel.Visible = false

    for index, fighterName in ipairs(sanitized) do
        local characterName, accent, profileAsset, stockAsset = getFighterDisplayData(fighterName)
        local isLocal = fighterName == localPlayer.Name

        local entry = Instance.new("Frame")
        entry.Name = string.format("Fighter%d", index)
        entry.BackgroundColor3 = darken(accent, isLocal and 0.6 or 0.75)
        entry.BackgroundTransparency = 0
        entry.BorderSizePixel = 0
        entry.ClipsDescendants = false
        entry.LayoutOrder = index
        entry.Size = UDim2.new(1, -8, 0, 92)
        entry.Parent = fighterListContainer
        table.insert(fighterEntries, entry)

        local entryCorner = Instance.new("UICorner")
        entryCorner.CornerRadius = UDim.new(0, 20)
        entryCorner.Parent = entry

        local entryStroke = Instance.new("UIStroke")
        entryStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        entryStroke.Thickness = isLocal and 3.5 or 2
        entryStroke.Color = lighten(accent, isLocal and 0.55 or 0.3)
        entryStroke.Transparency = isLocal and 0 or 0.15
        entryStroke.Parent = entry

        local entryLayout = Instance.new("UIListLayout")
        entryLayout.FillDirection = Enum.FillDirection.Horizontal
        entryLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        entryLayout.SortOrder = Enum.SortOrder.LayoutOrder
        entryLayout.Padding = UDim.new(0, 14)
        entryLayout.Parent = entry

        local portrait = Instance.new("ImageLabel")
        portrait.Name = "Portrait"
        portrait.Size = UDim2.new(0, 96, 0, 96)
        portrait.BackgroundTransparency = 1
        portrait.LayoutOrder = 1
        portrait.Rotation = -12
        portrait.ZIndex = 2
        portrait.Image = profileAsset
        portrait.ImageTransparency = profileAsset ~= "" and 0 or 1
        portrait.Visible = profileAsset ~= ""
        portrait.Parent = entry

        local portraitCorner = Instance.new("UICorner")
        portraitCorner.CornerRadius = UDim.new(0, 12)
        portraitCorner.Parent = portrait

        local portraitStroke = Instance.new("UIStroke")
        portraitStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        portraitStroke.Thickness = 2
        portraitStroke.Color = Color3.fromRGB(255, 255, 255)
        portraitStroke.Transparency = profileAsset ~= "" and 0.1 or 1
        portraitStroke.Parent = portrait

        local content = Instance.new("Frame")
        content.Name = "Content"
        content.BackgroundTransparency = 1
        content.LayoutOrder = 2
        content.Size = UDim2.new(1, -110, 1, -24)
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
        characterLabel.Size = UDim2.new(1, 0, 0, 36)
        characterLabel.Font = Enum.Font.GothamBlack
        characterLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        characterLabel.TextScaled = true
        characterLabel.TextXAlignment = Enum.TextXAlignment.Left
        characterLabel.Text = string.upper(characterName ~= "" and characterName or fighterName)
        characterLabel.Parent = content

        local characterConstraint = Instance.new("UITextSizeConstraint")
        characterConstraint.MaxTextSize = 32
        characterConstraint.Parent = characterLabel

        local row = Instance.new("Frame")
        row.Name = "PlayerRow"
        row.BackgroundTransparency = 1
        row.LayoutOrder = 2
        row.Size = UDim2.new(1, 0, 0, 28)
        row.Parent = content

        local rowLayout = Instance.new("UIListLayout")
        rowLayout.FillDirection = Enum.FillDirection.Horizontal
        rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
        rowLayout.Padding = UDim.new(0, 10)
        rowLayout.Parent = row

        local stockImage = Instance.new("ImageLabel")
        stockImage.Name = "Stock"
        stockImage.Size = UDim2.new(0, 34, 0, 34)
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
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.Text = string.format("%d. %s", index, fighterName)
        nameLabel.TextColor3 = isLocal and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 225, 245)
        nameLabel.TextScaled = true
        nameLabel.TextWrapped = true
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row

        local nameConstraint = Instance.new("UITextSizeConstraint")
        nameConstraint.MaxTextSize = 20
        nameConstraint.Parent = nameLabel

        local accentLine = Instance.new("Frame")
        accentLine.Name = "Accent"
        accentLine.BackgroundColor3 = lighten(accent, isLocal and 0.55 or 0.25)
        accentLine.BorderSizePixel = 0
        accentLine.LayoutOrder = 3
        accentLine.Size = UDim2.new(1, 0, 0, 5)
        accentLine.Parent = content

        table.insert(fighterEntries, entry)
    end
end

type CharacterStats = {
    hp: number,
    speed: number,
    attack: number,
    jump: number,
}

type CharacterImages = {
    profile: string?,
    stock: string?,
}

type CharacterInfo = {
    name: string,
    stats: CharacterStats,
    abilities: {string},
    images: CharacterImages?,
}

type CharacterRoster = {
    Survivors: {CharacterInfo}?,
    Bosses: {CharacterInfo}?,
}

type CharacterAssignments = {
    Survivors: {[string]: string}?,
    Bosses: {[string]: string}?,
}

local BossRoster = rawBossRoster :: {CharacterInfo}
local FighterRoster = rawFighterRoster :: {CharacterInfo}

local currentRoster: CharacterRoster? = nil
local currentAssignments = {
    Survivors = {} :: {[string]: string},
    Bosses = {} :: {[string]: string},
}

local function cloneAssignments(assignments: CharacterAssignments?)
    currentAssignments = {
        Survivors = {},
        Bosses = {},
    }

    if assignments and assignments.Survivors then
        for name, playerName in pairs(assignments.Survivors) do
            currentAssignments.Survivors[name] = playerName
        end
    end

    if assignments and assignments.Bosses then
        for name, playerName in pairs(assignments.Bosses) do
            currentAssignments.Bosses[name] = playerName
        end
    end
end

local function formatStats(stats: CharacterStats): string
    return string.format("HP %d  SPD %d  ATK %d  JMP %d", stats.hp, stats.speed, stats.attack, stats.jump)
end

local function findCharacterInfo(roster: {CharacterInfo}, characterName: string): CharacterInfo?
    for _, info in ipairs(roster) do
        if info.name == characterName then
            return info
        end
    end
    return nil
end

local function getCharacterInfoForRole(role: string, characterName: string): CharacterInfo?
    if characterName == "" then
        return nil
    end

    if role == "Boss" then
        return findCharacterInfo(BossRoster, characterName)
    elseif role == "Fighter" then
        return findCharacterInfo(FighterRoster, characterName)
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

local function getAssignedCharacterForPlayer(playerName: string, bucket: "Survivors" | "Bosses"): string
    local assignments = currentAssignments[bucket]
    for characterName, assignedPlayer in pairs(assignments) do
        if assignedPlayer == playerName then
            return characterName
        end
    end

    local player = Players:FindFirstChild(playerName)
    if not player then
        return ""
    end

    local roleValue = player:GetAttribute("AssignedRole")
    local characterValue = player:GetAttribute("AssignedCharacter")

    if typeof(characterValue) ~= "string" or characterValue == "" then
        return ""
    end

    if bucket == "Survivors" and roleValue == "Fighter" then
        return characterValue
    elseif bucket == "Bosses" and roleValue == "Boss" then
        return characterValue
    end

    return ""
end

local function roundHealth(value: number): number
    return math.floor(value + 0.5)
end

local currentHumanoid: Humanoid? = nil
local humanoidConnections = {
    HealthChanged = nil :: RBXScriptConnection?,
    MaxHealthChanged = nil :: RBXScriptConnection?,
    Died = nil :: RBXScriptConnection?,
    Ancestry = nil :: RBXScriptConnection?,
}

local characterConnections = {
    ChildAdded = nil :: RBXScriptConnection?,
}

local function disconnectHumanoidSignals()
    for key, connection in pairs(humanoidConnections) do
        if connection then
            connection:Disconnect()
            humanoidConnections[key] = nil
        end
    end
end

local function updateHealthDisplay()
    local healthDisplay = "--"

    if currentHumanoid then
        local maxHealth = math.max(0, roundHealth(currentHumanoid.MaxHealth))
        local health = math.clamp(roundHealth(currentHumanoid.Health), 0, maxHealth)
        healthDisplay = string.format("%d%%", health)
    end

    hpValueLabel.Text = healthDisplay

    if hpDetailLabel then
        hpDetailLabel.Text = ""
        hpDetailLabel.Visible = false
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
        humanoidConnections.HealthChanged = humanoid.HealthChanged:Connect(function()
            updateHealthDisplay()
        end)
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

local function updateAbilityIcons(isRound: boolean?)
    local roleValue = localPlayer:GetAttribute("AssignedRole")
    local characterValue = localPlayer:GetAttribute("AssignedCharacter")

    local role = typeof(roleValue) == "string" and roleValue or ""
    local characterName = typeof(characterValue) == "string" and characterValue or ""

    local abilityList: {string}? = nil

    if characterName ~= "" then
        local info = getCharacterInfoForRole(role, characterName)
        abilityList = info and info.abilities or nil
    end

    local abilityCount = 0
    if abilityList then
        abilityCount = #abilityList
    end

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
        if abilityName ~= "" then
            slot.NameLabel.Text = abilityName
        else
            slot.NameLabel.Text = "Ability"
        end
    end

    abilityPanel.Visible = isRound == true and abilityCount > 0
end

local function updateHpVisuals()
    local roleValue = localPlayer:GetAttribute("AssignedRole")
    local characterValue = localPlayer:GetAttribute("AssignedCharacter")

    local role = typeof(roleValue) == "string" and roleValue or ""
    local characterName = typeof(characterValue) == "string" and characterValue or ""

    local accent = getAccentColor(role, characterName)
    hpCard.BackgroundColor3 = darken(accent, 0.75)
    hpStroke.Color = lighten(accent, 0.45)
    hpStroke.Transparency = 0.08
    hpAccentLine.BackgroundColor3 = accent
    if hpDetailLabel then
        hpDetailLabel.TextColor3 = lighten(accent, 0.4)
        hpDetailLabel.Visible = false
    end
    hpValueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpPortraitStroke.Color = lighten(accent, 0.35)
    hpStockStroke.Color = lighten(accent, 0.4)

    local displayName
    if characterName ~= "" then
        displayName = string.upper(characterName)
    else
        displayName = string.upper(localPlayer.DisplayName or localPlayer.Name)
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
        hpPortraitStroke.Transparency = 0.05
    else
        hpPortrait.Image = ""
        hpPortrait.ImageTransparency = 1
        hpPortraitStroke.Transparency = 1
    end

    if stockAsset ~= "" then
        hpStockIcon.Image = stockAsset
        hpStockIcon.ImageTransparency = 0
        hpStockStroke.Transparency = 0.1
    else
        hpStockIcon.Image = ""
        hpStockIcon.ImageTransparency = 1
        hpStockStroke.Transparency = 1
    end

    local isRound = currentState == "Round"
    hpPortrait.Visible = isRound and profileAsset ~= ""
    hpStockIcon.Visible = isRound and stockAsset ~= ""
end

local function updateRoundHudVisibility()
    local isRound = currentState == "Round"
    roundColumn.Visible = isRound
    hpFrame.Visible = isRound
    fighterListFrame.Visible = isRound

    if isRound then
        if #fighterEntries == 0 and #currentFighterNames > 0 then
            updateFighterDisplay(currentFighterNames)
        else
            fighterEmptyLabel.Visible = #currentFighterNames == 0
        end

        if #bossStatusEntries == 0 and #currentBossStatuses > 0 then
            renderBossStatusEntries(currentBossStatuses)
        end

        bossStatusContainer.Visible = #bossStatusEntries > 0
        updateHealthDisplay()
        updateHpVisuals()
    else
        fighterEmptyLabel.Visible = false
        hpPortrait.Visible = false
        hpStockIcon.Visible = false
        clearBossStatusEntries()
        bossStatusContainer.Visible = false
    end

    updateAbilityIcons(isRound)
end

local function updateBossStatus(statusList: {any}?)
    currentBossStatuses = sanitizeBossStatusList(statusList)

    if currentState == "Round" then
        renderBossStatusEntries(currentBossStatuses)
    else
        clearBossStatusEntries()
        bossStatusContainer.Visible = false
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
        button.Active = assignedPlayer == localPlayer.Name
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
        if canSelect then
            button.AutoButtonColor = true
            button.Active = true
        else
            button.AutoButtonColor = false
            button.Active = false
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

local function makeButton(
    characterInfo: CharacterInfo,
    requestRole: string,
    takenBy: string?,
    canSelect: boolean,
    accentColor: Color3
): TextButton
    local characterName = characterInfo.name

    local button = Instance.new("TextButton")
    button.Name = characterName .. "Tile"
    button.Size = UDim2.new(0, 200, 0, 240)
    button.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = ""
    button.LayoutOrder = 1
    button.ClipsDescendants = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 18)
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
        ColorSequenceKeypoint.new(0, lighten(accentColor, 0.4)),
        ColorSequenceKeypoint.new(1, darken(accentColor, 0.6)),
    })
    gradient.Parent = button

    local portrait = Instance.new("ImageLabel")
    portrait.Name = "Portrait"
    portrait.AnchorPoint = Vector2.new(0.5, 0)
    portrait.Position = UDim2.new(0.5, 0, 0, 68)
    portrait.Size = UDim2.new(0, 104, 0, 104)
    portrait.BackgroundTransparency = 1
    portrait.ImageTransparency = 1
    portrait.Parent = button

    local portraitAsset = characterInfo.images and characterInfo.images.profile and toAssetId(characterInfo.images.profile) or ""
    if portraitAsset ~= "" then
        portrait.Image = portraitAsset
        portrait.ImageTransparency = 0
    end

    local portraitCorner = Instance.new("UICorner")
    portraitCorner.CornerRadius = UDim.new(1, 0)
    portraitCorner.Parent = portrait

    local portraitStroke = Instance.new("UIStroke")
    portraitStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    portraitStroke.Thickness = 2
    portraitStroke.Color = Color3.fromRGB(255, 255, 255)
    portraitStroke.Transparency = portraitAsset ~= "" and 0.2 or 1
    portraitStroke.Parent = portrait

    local badge = Instance.new("TextLabel")
    badge.Name = "OccupantLabel"
    badge.AnchorPoint = Vector2.new(1, 1)
    badge.Position = UDim2.new(1, -12, 1, -12)
    badge.Size = UDim2.new(0, 120, 0, 26)
    badge.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
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

    local nameBanner = Instance.new("Frame")
    nameBanner.Name = "NameBanner"
    nameBanner.AnchorPoint = Vector2.new(0.5, 0)
    nameBanner.Position = UDim2.new(0.5, 0, 0, 16)
    nameBanner.Size = UDim2.new(1, -24, 0, 38)
    nameBanner.BackgroundColor3 = darken(accentColor, 0.45)
    nameBanner.BackgroundTransparency = 0.35
    nameBanner.BorderSizePixel = 0
    nameBanner.Parent = button

    local nameBannerCorner = Instance.new("UICorner")
    nameBannerCorner.CornerRadius = UDim.new(0, 12)
    nameBannerCorner.Parent = nameBanner

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Text = characterName
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Size = UDim2.new(1, -16, 1, 0)
    nameLabel.Position = UDim2.new(0, 8, 0, 0)
    nameLabel.Parent = nameBanner

    local nameConstraint = Instance.new("UITextSizeConstraint")
    nameConstraint.MaxTextSize = 28
    nameConstraint.Parent = nameLabel

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, -24, 0, 48)
    content.Position = UDim2.new(0, 12, 0, 184)
    content.Parent = button

    local contentLayout = Instance.new("UIListLayout")
    contentLayout.FillDirection = Enum.FillDirection.Vertical
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, 4)
    contentLayout.Parent = content

    local statsLabel = Instance.new("TextLabel")
    statsLabel.Name = "StatsLabel"
    statsLabel.BackgroundTransparency = 1
    statsLabel.Font = Enum.Font.GothamSemibold
    statsLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
    statsLabel.TextScaled = true
    statsLabel.TextWrapped = true
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.Text = formatStats(characterInfo.stats)
    statsLabel.LayoutOrder = 1
    statsLabel.Parent = content

    local statsConstraint = Instance.new("UITextSizeConstraint")
    statsConstraint.MaxTextSize = 20
    statsConstraint.Parent = statsLabel

    local abilityLabel = Instance.new("TextLabel")
    abilityLabel.Name = "AbilitiesLabel"
    abilityLabel.BackgroundTransparency = 1
    abilityLabel.Font = Enum.Font.Gotham
    abilityLabel.TextColor3 = Color3.fromRGB(210, 210, 230)
    abilityLabel.TextScaled = true
    abilityLabel.TextWrapped = true
    abilityLabel.TextXAlignment = Enum.TextXAlignment.Left
    abilityLabel.TextYAlignment = Enum.TextYAlignment.Top
    abilityLabel.Text = string.format("Abilities: %s", table.concat(characterInfo.abilities, ", "))
    abilityLabel.LayoutOrder = 2
    abilityLabel.Parent = content

    local abilityConstraint = Instance.new("UITextSizeConstraint")
    abilityConstraint.MaxTextSize = 18
    abilityConstraint.Parent = abilityLabel

    applyButtonVisualState(button, accentColor, takenBy, canSelect)

    if (not takenBy or takenBy == "") and canSelect then
        button.MouseButton1Click:Connect(function()
            remotes.RequestCharacter:FireServer(requestRole, characterName)
        end)
    end

    return button
end

local function renderButtons(playerRole: string)
    if not currentRoster then
        return
    end

    local canPickBoss = playerRole == "Boss"
    local canPickSurvivor = playerRole == "Fighter"

    local assignedCharacterValue = localPlayer:GetAttribute("AssignedCharacter")
    local hasLockedChoice = typeof(assignedCharacterValue) == "string" and assignedCharacterValue ~= ""

    if hasLockedChoice then
        if canPickBoss then
            canPickBoss = false
        end
        if canPickSurvivor then
            canPickSurvivor = false
        end
    end

    if bossPanel.Visible then
        clearButtons(bossContainer)
        for index, characterInfo in ipairs(currentRoster.Bosses or {}) do
            local assigned = currentAssignments.Bosses[characterInfo.name]
            local button = makeButton(characterInfo, "Boss", assigned, canPickBoss, bossAccent)
            button.LayoutOrder = index
            button.Parent = bossContainer
        end
    end

    if survivorPanel.Visible then
        clearButtons(survivorContainer)
        for index, characterInfo in ipairs(currentRoster.Survivors or {}) do
            local assigned = currentAssignments.Survivors[characterInfo.name]
            local button = makeButton(characterInfo, "Fighter", assigned, canPickSurvivor, survivorAccent)
            button.LayoutOrder = index
            button.Parent = survivorContainer
        end
    end
end

local function updateSelectionVisibility()
    local roleValue = localPlayer:GetAttribute("AssignedRole")
    local role = typeof(roleValue) == "string" and roleValue or ""
    local inSelectionState = currentState == "CharacterSelect"
    local showBoss = inSelectionState and role == "Boss"
    local showFighter = inSelectionState and role == "Fighter"

    selectionFrame.Visible = showBoss or showFighter
    bossPanel.Visible = showBoss
    survivorPanel.Visible = showFighter

    if not selectionFrame.Visible then
        clearButtons(bossContainer)
        clearButtons(survivorContainer)
        return
    end

    renderButtons(role)
end

local function updateTimerDisplay(timeLeft: number?)
    if timeLeft and timeLeft >= 0 then
        timerLabel.Text = string.format("Time Left: %ds", math.ceil(timeLeft))
    else
        timerLabel.Text = "Time Left: --"
    end
end

local function updateHeader(state: string)
    headerLabel.Text = string.format("Step: %s", state)
end

local function updateInfo(text: string)
    infoLabel.Text = text
end

local function updateResultDisplay(winner: string?, reason: string?)
    local roleValue = localPlayer:GetAttribute("AssignedRole")
    local role = typeof(roleValue) == "string" and roleValue or ""

    if winner ~= "Boss" and winner ~= "Fighter" then
        resultFrame.Visible = false
        return
    end

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

local function onRoundStateChanged(state: string, payload: {[string]: any}?)
    currentState = state
    updateHeader(state)

    payload = payload or {}
    updateTimerDisplay(payload.timeLeft)
    updateResultDisplay(nil, nil)

    if state == "Round" then
        updateFighterDisplay(payload.fighterNames)
        updateBossStatus(payload.bossStatus)
    else
        updateFighterDisplay({})
        updateBossStatus(nil)
    end

    if state == "CharacterSelect" then
        currentRoster = payload.roster
        cloneAssignments(payload.assignments)

        local roleValue = localPlayer:GetAttribute("AssignedRole")
        local role = typeof(roleValue) == "string" and roleValue or ""
        local message = "Select your character."
        if role == "" then
            message = "Waiting for assignment..."
        elseif role == "Boss" then
            message = "Choose your boss. Each boss can only be selected once."
        else
            message = "Choose your fighter. Each fighter can only be selected once."
        end
        updateInfo(message)
    elseif state == "SelectionLock" then
        currentRoster = nil
        updateInfo("Preparing to start the round...")
    elseif state == "Intermission" then
        currentRoster = nil
        updateInfo("Intermission in progress")
    elseif state == "Round" then
        currentRoster = nil
        local fighters = payload.fighters or 0
        local bosses = payload.bosses or 0
        updateInfo(string.format("Round active - %d fighter(s) vs %d boss(es)", fighters, bosses))
    elseif state == "RoundEnd" then
        currentRoster = nil
        updateInfo(describeRoundEndReason(payload.reason))
        updateResultDisplay(payload.winner, payload.reason)
    else
        currentRoster = nil
        updateInfo("Waiting for the game to begin")
    end

    updateSelectionVisibility()
    updateRoundHudVisibility()
end

local function onCharacterAssignment(player: Player?, role: string, characterName: string)
    if role == "Boss" then
        currentAssignments.Bosses[characterName] = player and player.Name or ""
    else
        currentAssignments.Survivors[characterName] = player and player.Name or ""
    end

    if currentState == "CharacterSelect" then
        local roleValue = localPlayer:GetAttribute("AssignedRole")
        local myRole = typeof(roleValue) == "string" and roleValue or ""
        renderButtons(myRole)
    end

    if player == localPlayer then
        if currentState == "Round" then
            updateRoundHudVisibility()
        else
            updateAbilityIcons(false)
        end
    end
end

local function onAssignedCharacterChanged()
    if currentState == "CharacterSelect" then
        updateSelectionVisibility()
    end

    if currentState == "Round" then
        updateRoundHudVisibility()
    else
        updateAbilityIcons(false)
    end

    updateHpVisuals()
end

local function onAssignedRoleChanged()
    updateSelectionVisibility()

    if currentState == "Round" then
        updateRoundHudVisibility()
    else
        updateAbilityIcons(false)
    end

    updateHpVisuals()
end

localPlayer:GetAttributeChangedSignal("AssignedRole"):Connect(onAssignedRoleChanged)
localPlayer:GetAttributeChangedSignal("AssignedCharacter"):Connect(onAssignedCharacterChanged)

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
remotes.CharacterAssignment.OnClientEvent:Connect(onCharacterAssignment)

updateHeader(currentState)
updateTimerDisplay(nil)
updateInfo("Waiting for the game to begin")
updateResultDisplay(nil, nil)
updateSelectionVisibility()
updateAbilityIcons(currentState == "Round")
updateFighterDisplay({})
updateRoundHudVisibility()
updateHpVisuals()
