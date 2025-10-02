--!strict
-- GameManager.lua
-- Place this ModuleScript in ServerScriptService and require it from a Script to boot the loop.
-- Rewritten round system that manages intermissions, character selection, and boss versus fighter rounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BossRoster = require(ReplicatedStorage:WaitForChild("BossRoster"))
local FighterRoster = require(ReplicatedStorage:WaitForChild("FighterRoster"))

type Player = Players.Player

export type StepName = "Waiting" | "Intermission" | "CharacterSelect" | "SelectionLock" | "Round" | "RoundResults"

local GameManager = {}
GameManager.__index = GameManager

GameManager.MinimumPlayersToStart = 3
GameManager.IntermissionLength = 45
GameManager.CharacterSelectLength = 30
GameManager.SelectionLockLength = 3
GameManager.ResultsLength = 8
GameManager.BaseRoundLength = 150 -- 2:30 minutes
GameManager.RoundIncrementPerFighter = 45
GameManager.MaxBosses = 2

GameManager.RoundLengthOverride = 0 -- Optional override for a fixed round length.

local ROLE_FIGHTER = "Fighter"
local ROLE_BOSS = "Boss"

local TEST_MODEL_PATH = {"Folder", "test models"}

local function findTestModelFolder(): Instance?
	local current: Instance? = Workspace
	for _, segment in ipairs(TEST_MODEL_PATH) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
	end
	return current
end

local function markRoundSkin(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Anchored = false
		instance.CanCollide = false
		instance.Massless = true
		instance:SetAttribute("RoundSkinPart", true)
	elseif instance:IsA("Decal") or instance:IsA("ParticleEmitter") or instance:IsA("Trail") then
		instance:SetAttribute("RoundSkinPart", true)
		if instance:IsA("ParticleEmitter") or instance:IsA("Trail") then
			instance.Enabled = true
		end
	end
	for _, child in ipairs(instance:GetChildren()) do
		markRoundSkin(child)
	end
end

local function getTimeNow(): number
	if workspace and workspace.GetServerTimeNow then
		return workspace:GetServerTimeNow()
	end
	return os.clock()
end

local function findRosterEntry(roster: {{name: string}}, name: string)
	for _, info in ipairs(roster) do
		if info.name == name then
			return info
		end
	end
	return nil
end

local function rosterContains(roster: {{name: string}}, name: string): boolean
	return findRosterEntry(roster, name) ~= nil
end

local function getRosterForRole(role: string)
	if role == ROLE_BOSS then
		return BossRoster
	end
	return FighterRoster
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

local function createRemoteEvent(name: string)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local function createRemoteFunction(name: string)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

function GameManager.new()
	local self = setmetatable({}, GameManager)

	self.State = "Waiting"
	self.StateStartedAt = getTimeNow()
	self.StateEndsAt = 0

	self.Remotes = {
		RoundStateChanged = createRemoteEvent("RoundStateChanged"),
		CharacterAssignment = createRemoteEvent("CharacterAssignment"),
		RequestCharacter = createRemoteEvent("RequestCharacter"),
		GetRoundState = createRemoteFunction("GetRoundState"),
	}

	self.BossChances = {}
	self.Assignments = {} -- [Player] = {role, character}
	self.ReservedCharacters = {
		Bosses = {},
		Survivors = {},
	}

	self.RoundParticipants = {
		Bosses = {},
		Fighters = {},
	}

	self.RoundAlive = {
		Bosses = {},
		Fighters = {},
	}

	self.RoundConnections = {
		Players = {},
		Heartbeat = nil,
	}

	self.RoundEndsAt = 0
	self.RoundLength = 0
	self.RoundWinner = nil
	self.RoundEndReason = nil
	self.RoundLeavers = 0

	self._lastPayload = nil

	self.Remotes.GetRoundState.OnServerInvoke = function()
		return self:_buildStatePayload()
	end

	self.Remotes.RequestCharacter.OnServerEvent:Connect(function(player, role: string, characterName: string)
		self:_onCharacterRequested(player, role, characterName)
	end)

	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_onPlayerAdded(player)
	end

	self.RoundConnections.Heartbeat = RunService.Heartbeat:Connect(function()
		self:_onHeartbeat()
	end)

	print("[GameManager] Initialized round system.")

	return self
end

function GameManager:Destroy()
	if self.RoundConnections.Heartbeat then
		self.RoundConnections.Heartbeat:Disconnect()
		self.RoundConnections.Heartbeat = nil
	end

	for _, conn in pairs(self.RoundConnections.Players) do
		conn:Disconnect()
	end

	self.RoundConnections.Players = {}
end

function GameManager:_onPlayerAdded(player: Player)
	self.BossChances[player] = self.BossChances[player] or 0
	self.Assignments[player] = nil
	print(string.format("[GameManager] Player joined: %s", player.Name))

	local payload = self:_buildStatePayload()
	self.Remotes.RoundStateChanged:FireClient(player, payload)

	if self.State == "Waiting" and self:_enoughPlayers() then
		self:_beginIntermission()
	end
end

function GameManager:_onPlayerRemoving(player: Player)
	print(string.format("[GameManager] Player leaving: %s", player.Name))

	self.BossChances[player] = nil
	self.Assignments[player] = nil

	for role, reservations in pairs(self.ReservedCharacters) do
		for characterName, reservedPlayer in pairs(reservations) do
			if reservedPlayer == player then
				reservations[characterName] = nil
			end
		end
	end

	if self.State == "CharacterSelect" or self.State == "SelectionLock" then
		self:_checkSelectionProgress()
	elseif self.State == "Round" then
		if self.RoundAlive.Bosses[player] or self.RoundAlive.Fighters[player] then
			self.RoundLeavers += 1
			self:_markParticipantDown(player)
			if self.RoundLeavers > 2 then
				self:_endRound("TooManyPlayersLeft")
			end
		end
	end

	if not self:_enoughPlayers() then
		if self.State == "Round" then
			self:_endRound("NotEnoughPlayers")
		elseif self.State ~= "Waiting" then
			self:_switchState("Waiting")
		end
	end
end

function GameManager:_enoughPlayers(): boolean
	return #Players:GetPlayers() >= GameManager.MinimumPlayersToStart
end

function GameManager:_onHeartbeat()
	local now = getTimeNow()

	if self.State == "Waiting" then
		if self:_enoughPlayers() then
			self:_beginIntermission()
		end
		return
	end

	if not self:_enoughPlayers() then
		if self.State ~= "Waiting" then
			self:_switchState("Waiting")
		end
		return
	end

	if self.State == "Intermission" then
		if now >= self.StateEndsAt then
			self:_beginCharacterSelect()
		end
	elseif self.State == "CharacterSelect" then
		if now >= self.StateEndsAt then
			self:_lockSelections()
		end
	elseif self.State == "SelectionLock" then
		if now >= self.StateEndsAt then
			self:_beginRound()
		end
	elseif self.State == "Round" then
		self:_updateRoundHealth()
		if now >= self.RoundEndsAt then
			self:_handleRoundTimeout()
		end
	elseif self.State == "RoundResults" then
		if now >= self.StateEndsAt then
			self:_beginIntermission()
		end
	end
end

function GameManager:_switchState(newState: StepName, endsAt: number?)
	self.State = newState
	self.StateStartedAt = getTimeNow()
	if endsAt then
		self.StateEndsAt = endsAt
	else
		self.StateEndsAt = 0
	end

	if newState == "Waiting" then
		self.Assignments = {}
		self.ReservedCharacters = {Bosses = {}, Survivors = {}}
		self.RoundParticipants = {Bosses = {}, Fighters = {}}
		self.RoundAlive = {Bosses = {}, Fighters = {}}
		self.RoundWinner = nil
		self.RoundEndReason = nil
		self.RoundLength = 0
		self.RoundEndsAt = 0
		self.RoundLeavers = 0
	end

	print(string.format("[GameManager] Entering step: %s", newState))
	if newState == "Round" then
		self:_applyRoundAppearances()
	else
		self:_restoreAllAppearances()
	end
	self:_broadcastState()
end

function GameManager:_beginIntermission()
	self.Assignments = {}
	self.ReservedCharacters = {Bosses = {}, Survivors = {}}
	self.RoundParticipants = {Bosses = {}, Fighters = {}}
	self.RoundAlive = {Bosses = {}, Fighters = {}}
	self.RoundLeavers = 0
	self.RoundWinner = nil
	self.RoundEndReason = nil
	self.RoundLength = 0
	self.RoundEndsAt = 0

	for _, player in ipairs(Players:GetPlayers()) do
		self.BossChances[player] = (self.BossChances[player] or 0) + 1
	end

	local endsAt = getTimeNow() + GameManager.IntermissionLength
	self:_switchState("Intermission", endsAt)
end

function GameManager:_determineBossCount(): number
	local playerCount = #Players:GetPlayers()
	if playerCount > 7 then
		return math.max(1, math.min(GameManager.MaxBosses, 2))
	end
	return 1
end

function GameManager:_pickBossPlayers(): {Player}
	local bossCount = self:_determineBossCount()
	local sortable = {}
	for player, chance in pairs(self.BossChances) do
		table.insert(sortable, {player = player, chance = chance})
	end

	table.sort(sortable, function(a, b)
		if a.chance == b.chance then
			return a.player.Name < b.player.Name
		end
		return a.chance > b.chance
	end)

	local bosses = {}
	for i = 1, bossCount do
		local entry = sortable[i]
		if entry and entry.player then
			table.insert(bosses, entry.player)
		end
	end

	if #bosses == 0 and sortable[1] then
		table.insert(bosses, sortable[1].player)
	end

	return bosses
end

function GameManager:_beginCharacterSelect()
	local players = Players:GetPlayers()
	if #players < GameManager.MinimumPlayersToStart then
		self:_switchState("Waiting")
		return
	end

	local bosses = self:_pickBossPlayers()
	local bossLookup: {[Player]: boolean} = {}
	for _, player in ipairs(bosses) do
		bossLookup[player] = true
		self.BossChances[player] = 0
	end

	self.Assignments = {}
	for _, player in ipairs(players) do
		local role = bossLookup[player] and ROLE_BOSS or ROLE_FIGHTER
		self.Assignments[player] = {role = role, character = nil}
	end

	self.ReservedCharacters = {Bosses = {}, Survivors = {}}
	local endsAt = getTimeNow() + GameManager.CharacterSelectLength
	self:_switchState("CharacterSelect", endsAt)
	self:_broadcastAssignments()
end

function GameManager:_lockSelections()
	if self.State ~= "CharacterSelect" then
		return
	end

	self:_autoAssignMissingCharacters()
	local endsAt = getTimeNow() + GameManager.SelectionLockLength
	self:_switchState("SelectionLock", endsAt)
end

function GameManager:_autoAssignMissingCharacters()
	local availableBosses = {}
	for _, info in ipairs(BossRoster) do
		if self.ReservedCharacters.Bosses[info.name] == nil then
			table.insert(availableBosses, info.name)
		end
	end

	local availableFighters = {}
	for _, info in ipairs(FighterRoster) do
		if self.ReservedCharacters.Survivors[info.name] == nil then
			table.insert(availableFighters, info.name)
		end
	end

	for player, assignment in pairs(self.Assignments) do
		if assignment.character == nil then
			if assignment.role == ROLE_BOSS then
				local pick = table.remove(availableBosses, 1)
				if not pick then
					pick = BossRoster[1] and BossRoster[1].name or "Boss"
				end
				assignment.character = pick
				self.ReservedCharacters.Bosses[pick] = player
			else
				local pick = table.remove(availableFighters, 1)
				if not pick then
					pick = FighterRoster[1] and FighterRoster[1].name or "Fighter"
				end
				assignment.character = pick
				self.ReservedCharacters.Survivors[pick] = player
			end
		end
	end

	self:_broadcastAssignments()
end

function GameManager:_beginRound()
	if self.State ~= "SelectionLock" then
		return
	end

	local bosses = {}
	local fighters = {}

	for player, assignment in pairs(self.Assignments) do
		if assignment.role == ROLE_BOSS then
			table.insert(bosses, player)
		else
			table.insert(fighters, player)
		end
	end

	if #bosses == 0 or #fighters == 0 then
		self:_endRound("NoOpponents")
		return
	end

	self.RoundParticipants = {Bosses = bosses, Fighters = fighters}
	self.RoundAlive = {Bosses = {}, Fighters = {}}

	local fighterCount = #fighters
	if GameManager.RoundLengthOverride > 0 then
		self.RoundLength = GameManager.RoundLengthOverride
	else
		self.RoundLength = GameManager.BaseRoundLength + (fighterCount * GameManager.RoundIncrementPerFighter)
	end

	self.RoundEndsAt = getTimeNow() + self.RoundLength

	for _, player in ipairs(bosses) do
		self.RoundAlive.Bosses[player] = true
		self:_trackParticipant(player)
	end

	for _, player in ipairs(fighters) do
		self.RoundAlive.Fighters[player] = true
		self:_trackParticipant(player)
	end

	self.RoundWinner = nil
	self.RoundEndReason = nil
	self.RoundLeavers = 0

	self:_switchState("Round", self.RoundEndsAt)
end

function GameManager:_updateRoundHealth()
	for role, aliveMap in pairs(self.RoundAlive) do
		for player in pairs(aliveMap) do
			local character = player.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					if humanoid.Health <= 0 then
						self:_markParticipantDown(player)
					end
				end
			end
		end
	end
end

function GameManager:_markParticipantDown(player: Player)
	if self.RoundAlive.Bosses[player] then
		self.RoundAlive.Bosses[player] = nil
	end

	if self.RoundAlive.Fighters[player] then
		self.RoundAlive.Fighters[player] = nil
	end

	self:_checkRoundWinConditions()
end

function GameManager:_handleRoundTimeout()
	if self.State ~= "Round" then
		return
	end

	local bossAlive = next(self.RoundAlive.Bosses) ~= nil
	local fighterAlive = next(self.RoundAlive.Fighters) ~= nil

	if bossAlive and not fighterAlive then
		self:_endRound("BossVictory")
	elseif fighterAlive and not bossAlive then
		self:_endRound("FighterVictory")
	elseif bossAlive then
		self:_endRound("RoundTimerExpiredBossAlive")
	else
		self:_endRound("RoundTimerExpired")
	end
end

function GameManager:_checkRoundWinConditions()
	if next(self.RoundAlive.Bosses) == nil and next(self.RoundAlive.Fighters) == nil then
		self:_endRound("EveryoneEliminated")
	elseif next(self.RoundAlive.Bosses) == nil then
		self:_endRound("FighterVictory")
	elseif next(self.RoundAlive.Fighters) == nil then
		self:_endRound("BossVictory")
	end
end

function GameManager:_getAssignedCharacterInfo(player: Player)
	local assignment = self.Assignments[player]
	if not assignment or not assignment.character then
		return nil, assignment
	end

	local roster = getRosterForRole(assignment.role)
	if not roster then
		return nil, assignment
	end

	local info = findRosterEntry(roster, assignment.character)
	return info, assignment
end

function GameManager:_getRoundSkinTemplate(characterName: string): Instance?
	local folder = findTestModelFolder()
	if not folder then
		return nil
	end
	return folder:FindFirstChild(characterName)
end

function GameManager:_hideCharacterParts(character: Model, hide: boolean)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:GetAttribute("RoundSkinPart") then
			continue
		end

		if descendant:IsA("BasePart") then
			if hide then
				if descendant:GetAttribute("RoundHidden") == nil then
					descendant:SetAttribute("OriginalTransparency", descendant.Transparency)
					descendant:SetAttribute("OriginalCanCollide", descendant.CanCollide)
				end
				descendant.Transparency = 1
				descendant.CanCollide = false
				descendant:SetAttribute("RoundHidden", true)
			elseif descendant:GetAttribute("RoundHidden") then
				local originalTransparency = descendant:GetAttribute("OriginalTransparency")
				if originalTransparency ~= nil then
					descendant.Transparency = originalTransparency
				else
					descendant.Transparency = 0
				end

				local originalCollide = descendant:GetAttribute("OriginalCanCollide")
				if originalCollide ~= nil then
					descendant.CanCollide = originalCollide
				end

				descendant:SetAttribute("RoundHidden", nil)
				descendant:SetAttribute("OriginalTransparency", nil)
				descendant:SetAttribute("OriginalCanCollide", nil)
			end
		elseif descendant:IsA("Decal") then
			if hide then
				if descendant:GetAttribute("RoundHidden") == nil then
					descendant:SetAttribute("OriginalTransparency", descendant.Transparency)
				end
				descendant.Transparency = 1
				descendant:SetAttribute("RoundHidden", true)
			elseif descendant:GetAttribute("RoundHidden") then
				local original = descendant:GetAttribute("OriginalTransparency")
				if original ~= nil then
					descendant.Transparency = original
				else
					descendant.Transparency = 0
				end
				descendant:SetAttribute("RoundHidden", nil)
				descendant:SetAttribute("OriginalTransparency", nil)
			end
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			if hide then
				if descendant:GetAttribute("RoundHidden") == nil then
					descendant:SetAttribute("OriginalEnabled", descendant.Enabled)
				end
				descendant.Enabled = false
				descendant:SetAttribute("RoundHidden", true)
			elseif descendant:GetAttribute("RoundHidden") then
				local originalEnabled = descendant:GetAttribute("OriginalEnabled")
				if originalEnabled ~= nil then
					descendant.Enabled = originalEnabled
				else
					descendant.Enabled = true
				end
				descendant:SetAttribute("RoundHidden", nil)
				descendant:SetAttribute("OriginalEnabled", nil)
			end
		end
	end
end

function GameManager:_clearRoundSkin(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("RoundSkinModel") then
			child:Destroy()
		end
	end
end

function GameManager:_restoreCharacterAppearance(character: Model)
	if not character then
		return
	end
	self:_clearRoundSkin(character)
	self:_hideCharacterParts(character, false)
end

function GameManager:_applyRoundAppearance(player: Player, character: Model)
	if self.State ~= "Round" then
		return
	end

	local info = self:_getAssignedCharacterInfo(player)
	if not info then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	self:_restoreCharacterAppearance(character)

	local template = self:_getRoundSkinTemplate(info.name)
	if not template then
		warn(string.format("[GameManager] Missing round skin template for %s", info.name))
		return
	end

	self:_hideCharacterParts(character, true)

	local skin = template:Clone()
	local hasBasePart = false
	if skin:IsA("BasePart") then
		hasBasePart = true
	elseif skin:IsA("Model") then
		hasBasePart = skin:FindFirstChildWhichIsA("BasePart", true) ~= nil
	else
		hasBasePart = skin:FindFirstChildWhichIsA("BasePart", true) ~= nil
	end

	if not hasBasePart then
		skin:Destroy()
		warn(string.format("[GameManager] Round skin template for %s has no parts to display", info.name))
		self:_hideCharacterParts(character, false)
		return
	end

	skin.Name = "RoundSkinModel"
	skin:SetAttribute("RoundSkinModel", true)
	markRoundSkin(skin)
	skin.Parent = character

	local function weldToRoot(part: BasePart)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = rootPart
		weld.Parent = part
	end

	if skin:IsA("Model") then
		if not skin.PrimaryPart then
			local primary = skin:FindFirstChildWhichIsA("BasePart", true)
			if primary then
				skin.PrimaryPart = primary
			end
		end

		if skin.PrimaryPart then
			skin:PivotTo(rootPart.CFrame)
		end

		for _, descendant in ipairs(skin:GetDescendants()) do
			if descendant:IsA("BasePart") then
				weldToRoot(descendant)
			end
		end
	elseif skin:IsA("BasePart") then
		skin.CFrame = rootPart.CFrame
		weldToRoot(skin)
	else
		-- Non-model, non-part templates are simply parented without welding.
	end
end

function GameManager:_applyRoundAppearances()
	for _, player in ipairs(self.RoundParticipants.Bosses or {}) do
		local character = player.Character
		if character then
			self:_applyRoundAppearance(player, character)
		end
	end

	for _, player in ipairs(self.RoundParticipants.Fighters or {}) do
		local character = player.Character
		if character then
			self:_applyRoundAppearance(player, character)
		end
	end
end

function GameManager:_restoreAllAppearances()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			self:_restoreCharacterAppearance(character)
		end
	end
end

function GameManager:_applyCharacterStats(player: Player, humanoid: Humanoid)
	local info, assignment = self:_getAssignedCharacterInfo(player)
	if not info or not info.stats then
		return
	end

	local stats = info.stats

	local maxHealth = tonumber(stats.hp)
	if maxHealth and maxHealth > 0 then
		maxHealth = math.max(1, math.floor(maxHealth + 0.5))
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
		humanoid:SetAttribute("MaxHealthBase", maxHealth)
	end

	local walkSpeed = tonumber(stats.speed)
	if walkSpeed and walkSpeed > 0 then
		humanoid.WalkSpeed = walkSpeed
		humanoid:SetAttribute("Speed", walkSpeed)
	end

	local jumpValue = tonumber(stats.jump)
	if jumpValue and jumpValue > 0 then
		if humanoid.UseJumpPower == nil or humanoid.UseJumpPower then
			humanoid.JumpPower = jumpValue
		else
			humanoid.JumpHeight = jumpValue
		end
		humanoid:SetAttribute("Jump", jumpValue)
	end

	local attack = tonumber(stats.attack)
	if attack then
		humanoid:SetAttribute("Attack", attack)
	end

	if assignment then
		humanoid:SetAttribute("AssignedRole", assignment.role)
		humanoid:SetAttribute("AssignedCharacter", assignment.character)
	end
end

function GameManager:_trackParticipant(player: Player)
	local function hookCharacter(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			self:_applyCharacterStats(player, humanoid)
			humanoid.Died:Connect(function()
				self:_markParticipantDown(player)
			end)
		else
			local connection: RBXScriptConnection?
			connection = character.ChildAdded:Connect(function(child)
				if child:IsA("Humanoid") then
					if connection then
						connection:Disconnect()
						connection = nil
					end
					self:_applyCharacterStats(player, child)
					child.Died:Connect(function()
						self:_markParticipantDown(player)
					end)
				end
			end)
		end

		if self.State == "Round" then
			self:_applyRoundAppearance(player, character)
		else
			self:_restoreCharacterAppearance(character)
		end
	end

	local character = player.Character
	if character then
		hookCharacter(character)
	end

	local connections = self.RoundConnections.Players
	if connections[player] then
		connections[player]:Disconnect()
	end

	connections[player] = player.CharacterAdded:Connect(function(newCharacter)
		hookCharacter(newCharacter)
	end)
end

function GameManager:_endRound(reason: string)
	if self.State ~= "Round" and reason ~= "NoOpponents" then
		return
	end

	self.RoundEndReason = reason

	local bossAlive = next(self.RoundAlive.Bosses) ~= nil
	local fighterAlive = next(self.RoundAlive.Fighters) ~= nil

	if reason == "FighterVictory" or (not bossAlive and fighterAlive) then
		self.RoundWinner = ROLE_FIGHTER
	elseif reason == "BossVictory" or (bossAlive and not fighterAlive) or reason == "RoundTimerExpiredBossAlive" then
		self.RoundWinner = ROLE_BOSS
	else
		self.RoundWinner = nil
	end

	local endsAt = getTimeNow() + GameManager.ResultsLength
	self:_switchState("RoundResults", endsAt)

	for player, conn in pairs(self.RoundConnections.Players) do
		conn:Disconnect()
		self.RoundConnections.Players[player] = nil
	end
end

function GameManager:_checkSelectionProgress()
	if self.State ~= "CharacterSelect" then
		return
	end

	local bossesMissing = false
	local fightersMissing = false

	for player, assignment in pairs(self.Assignments) do
		if assignment.role == ROLE_BOSS and assignment.character == nil then
			bossesMissing = true
		elseif assignment.role == ROLE_FIGHTER and assignment.character == nil then
			fightersMissing = true
		end
	end

	if not bossesMissing and not fightersMissing then
		self:_lockSelections()
	end
end

function GameManager:_onCharacterRequested(player: Player, role: string, characterName: string)
	if self.State ~= "CharacterSelect" then
		return
	end

	local assignment = self.Assignments[player]
	if not assignment or assignment.role ~= role then
		return
	end

	local roster
	local reservations

	if role == ROLE_BOSS then
		roster = BossRoster
		reservations = self.ReservedCharacters.Bosses
	else
		roster = FighterRoster
		reservations = self.ReservedCharacters.Survivors
	end

	if not rosterContains(roster, characterName) then
		return
	end

	local reservedPlayer = reservations[characterName]
	if reservedPlayer and reservedPlayer ~= player then
		return
	end

	if assignment.character then
		reservations[assignment.character] = nil
	end

	assignment.character = characterName
	reservations[characterName] = player

	self:_broadcastAssignments()
	self:_checkSelectionProgress()
end

function GameManager:_broadcastAssignments()
	local summary = {}
	for player, assignment in pairs(self.Assignments) do
		summary[player.UserId] = {
			name = player.Name,
			role = assignment.role,
			character = assignment.character,
		}
	end
	self.Remotes.CharacterAssignment:FireAllClients(summary)
	self:_broadcastState()
end

function GameManager:_broadcastState()
	local payload = self:_buildStatePayload()
	self._lastPayload = deepCopy(payload)
	self.Remotes.RoundStateChanged:FireAllClients(payload)
end

function GameManager:_buildStatePayload()
	local now = getTimeNow()
	local payload: {[string]: any} = {
		step = self.State,
		stepEndsAt = self.StateEndsAt,
		now = now,
		intermissionLength = GameManager.IntermissionLength,
		characterSelectLength = GameManager.CharacterSelectLength,
		selectionLockLength = GameManager.SelectionLockLength,
		roundLength = self.RoundLength,
		assignments = {},
	}

	for player, assignment in pairs(self.Assignments) do
		payload.assignments[player.UserId] = {
			name = player.Name,
			role = assignment.role,
			character = assignment.character,
		}
	end

	if self.State == "Intermission" then
		payload.intermissionEndsAt = self.StateEndsAt
	elseif self.State == "CharacterSelect" or self.State == "SelectionLock" then
		local bosses = {}
		local fighters = {}
		for player, assignment in pairs(self.Assignments) do
			if assignment.role == ROLE_BOSS then
				table.insert(bosses, player.UserId)
			else
				table.insert(fighters, player.UserId)
			end
		end

		payload.selection = {
			bosses = bosses,
			fighters = fighters,
		}

		payload.roster = {
			bosses = deepCopy(BossRoster),
			fighters = deepCopy(FighterRoster),
		}
	elseif self.State == "Round" or self.State == "RoundResults" then
		local bossEntries = {}
		for _, player in ipairs(self.RoundParticipants.Bosses) do
			local assignment = self.Assignments[player]
			table.insert(bossEntries, {
				userId = player.UserId,
				name = player.Name,
				character = assignment and assignment.character or nil,
				playerName = player.Name,
				alive = self.RoundAlive.Bosses[player] == true,
			})
		end

		local fighterEntries = {}
		for _, player in ipairs(self.RoundParticipants.Fighters) do
			local assignment = self.Assignments[player]
			table.insert(fighterEntries, {
				userId = player.UserId,
				name = player.Name,
				character = assignment and assignment.character or nil,
				playerName = player.Name,
				alive = self.RoundAlive.Fighters[player] == true,
			})
		end

		payload.round = {
			bosses = bossEntries,
			fighters = fighterEntries,
			roundEndsAt = self.RoundEndsAt,
			winner = self.RoundWinner,
			reason = self.RoundEndReason,
		}
	end

	return payload
end

return GameManager
