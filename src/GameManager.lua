--!strict
-- GameManager.lua
-- Core server-side game loop management for the boss-vs-survivor experience.
-- Place this ModuleScript in ServerScriptService and require it from a Script to boot the loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossRoster = require(ReplicatedStorage:WaitForChild("BossRoster"))
local FighterRoster = require(ReplicatedStorage:WaitForChild("FighterRoster"))

local GameManager = {}
GameManager.__index = GameManager

-- Configuration tables -----------------------------------------------------

GameManager.IntermissionLength = 45 -- seconds
GameManager.BaseRoundLength = 150 -- 2 minutes 30 seconds
GameManager.RoundIncrementPerFighter = 45
GameManager.MinimumPlayersToStart = 3
GameManager.MaxBosses = 2
GameManager.CharacterSelectLength = 30
GameManager.SelectionLockLength = 2

GameManager.SurvivorCharacters = FighterRoster
GameManager.BossCharacters = BossRoster

local roundWinners = {
    BossVictory = "Boss",
    FighterVictory = "Fighter",
    BossLeft = "Fighter",
    AllFightersLeft = "Boss",
    NoBosses = "Fighter",
    NoFighters = "Boss",
}

local function findCharacterInfo(roster: {{name: string}}, characterName: string)
    for _, info in ipairs(roster) do
        if info.name == characterName then
            return info
        end
    end
    return nil
end

local function rosterContains(roster: {{name: string}}, characterName: string): boolean
    return findCharacterInfo(roster, characterName) ~= nil
end

local function countDictionaryKeys(dictionary: {[any]: any}): number
    local count = 0
    for _ in pairs(dictionary) do
        count += 1
    end
    return count
end

-- Utility functions --------------------------------------------------------

local function shuffle(array: {any})
    local n = #array
    for i = n, 2, -1 do
        local j = math.random(i)
        array[i], array[j] = array[j], array[i]
    end
    return array
end

local function findHighestChancePlayers(bossChances: {[Player]: number}, amount: number): {Player}
    local sortable = {}
    for player, value in pairs(bossChances) do
        table.insert(sortable, {player = player, chance = value})
    end
    table.sort(sortable, function(a, b)
        if a.chance == b.chance then
            return a.player.Name < b.player.Name
        end
        return a.chance > b.chance
    end)

    local selected = {}
    for index = 1, amount do
        local entry = sortable[index]
        if entry and entry.player then
            table.insert(selected, entry.player)
        end
    end
    return selected
end

local function createRemoteEvent(name: string)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        return existing
    end

    local event = Instance.new("RemoteEvent")
    event.Name = name
    event.Parent = ReplicatedStorage
    return event
end

-- Lifecycle ----------------------------------------------------------------

function GameManager.new()
    local self = setmetatable({}, GameManager)

    self.State = "Waiting"
    self.BossChances = {}
    self.RoundPlayers = {
        Bosses = {},
        Fighters = {},
        RoleLookup = {},
    }
    self.ReservedCharacters = {
        Survivors = {},
        Bosses = {},
    }

    self.RoundConnections = {
        Players = {},
    }

    self.Remotes = {
        RoundStateChanged = createRemoteEvent("RoundStateChanged"),
        RequestCharacter = createRemoteEvent("RequestCharacter"),
        CharacterAssignment = createRemoteEvent("CharacterAssignment"),
    }

    self.ActiveRoundLength = 0
    self.IntermissionTimeLeft = 0
    self.RoundCountdown = 0
    self.CharacterSelectTimeLeft = 0
    self.SelectionLockTimeLeft = 0

    self._lastPrintedTimes = {}
    self._lastBroadcastTimes = {}
    self._announcedWaiting = false

    self:_setupPlayerListeners()

    return self
end

function GameManager:_rebuildRoleLookup()
    self.RoundPlayers.RoleLookup = {}

    for _, boss in ipairs(self.RoundPlayers.Bosses) do
        self.RoundPlayers.RoleLookup[boss] = "Boss"
    end

    for _, fighter in ipairs(self.RoundPlayers.Fighters) do
        self.RoundPlayers.RoleLookup[fighter] = "Fighter"
    end
end

function GameManager:_setupPlayerListeners()
    Players.PlayerAdded:Connect(function(player)
        self.BossChances[player] = self.BossChances[player] or 0
        player:SetAttribute("BossChance", self.BossChances[player])
        player:SetAttribute("AssignedRole", "")
        player:SetAttribute("AssignedCharacter", "")

        player.CharacterRemoving:Connect(function()
            -- Clear assigned character when the character despawns to avoid confusion.
            player:SetAttribute("AssignedCharacter", "")
        end)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:OnPlayerLeft(player)
    end)

    self.Remotes.RequestCharacter.OnServerEvent:Connect(function(player, role, characterName)
        self:AssignCharacter(player, role, characterName)
    end)
end

-- Intermission -------------------------------------------------------------

function GameManager:Start()
    -- Call this once from a Script to start the game loop.
    task.spawn(function()
        while true do
            local deltaTime = RunService.Heartbeat:Wait()
            if self.State == "Waiting" then
                self:TryStartIntermission()
            elseif self.State == "Intermission" then
                self:UpdateIntermission(deltaTime)
            elseif self.State == "CharacterSelect" then
                self:UpdateCharacterSelection(deltaTime)
            elseif self.State == "SelectionLock" then
                self:UpdateSelectionLock(deltaTime)
            elseif self.State == "Round" then
                self:UpdateRound(deltaTime)
            end
        end
    end)
end

function GameManager:_log(message: string)
    print(string.format("[GameManager] %s", message))
end

function GameManager:_broadcastState(state: string, payload: {[string]: any}?)
    self.Remotes.RoundStateChanged:FireAllClients(state, payload)
end

function GameManager:_broadcastTimedState(state: string, timeValue: number, extraPayload: {[string]: any}?, force: boolean?)
    local rounded = math.max(0, math.ceil(timeValue))
    local key = state .. "_broadcast"
    if not force and self._lastBroadcastTimes[key] == rounded then
        return
    end
    self._lastBroadcastTimes[key] = rounded

    local payload = extraPayload or {}
    payload.timeLeft = rounded
    self:_broadcastState(state, payload)
end

function GameManager:_collectAliveFighterNames(): {string}
    local names = {}

    if not self.RoundPlayers then
        return names
    end

    local fighters = self.RoundPlayers.Fighters or {}
    local aliveBucket = self.RoundPlayers.Alive and self.RoundPlayers.Alive.Fighters or nil
    local added = {}

    if fighters then
        for _, fighter in ipairs(fighters) do
            if fighter then
                local aliveStatus = aliveBucket and aliveBucket[fighter]
                if aliveStatus ~= false then
                    table.insert(names, fighter.Name)
                    added[fighter] = true
                end
            end
        end
    end

    if aliveBucket then
        for player, alive in pairs(aliveBucket) do
            if alive and player and not added[player] then
                table.insert(names, player.Name)
            end
        end
    end

    return names
end

function GameManager:_collectBossStatus(): {{[string]: any}}
    local statuses = {}

    if not self.RoundPlayers or not self.RoundPlayers.Bosses then
        return statuses
    end

    for _, bossPlayer in ipairs(self.RoundPlayers.Bosses) do
        if bossPlayer then
            local assignedCharacter = bossPlayer:GetAttribute("AssignedCharacter")
            assignedCharacter = typeof(assignedCharacter) == "string" and assignedCharacter or ""

            local info = assignedCharacter ~= "" and findCharacterInfo(GameManager.BossCharacters, assignedCharacter) or nil
            local profileId = ""
            local expectedHp = 0

            if info then
                if info.images and info.images.profile then
                    profileId = tostring(info.images.profile)
                end
                if info.stats and info.stats.hp then
                    expectedHp = info.stats.hp
                end
            end

            local humanoid = bossPlayer.Character and bossPlayer.Character:FindFirstChildOfClass("Humanoid")
            local health = expectedHp
            local maxHealth = expectedHp

            if humanoid then
                health = math.max(0, math.floor(humanoid.Health + 0.5))
                maxHealth = math.max(0, math.floor(humanoid.MaxHealth + 0.5))
            end

            table.insert(statuses, {
                playerName = bossPlayer.Name,
                characterName = assignedCharacter,
                health = health,
                maxHealth = maxHealth,
                profileId = profileId,
            })
        end
    end

    table.sort(statuses, function(left, right)
        if left.playerName == right.playerName then
            return left.characterName < right.characterName
        end
        return left.playerName < right.playerName
    end)

    return statuses
end

function GameManager:_buildRoundPayload(): {[string]: any}
    local fighters = (self.RoundPlayers and self.RoundPlayers.Fighters) or {}
    local bosses = (self.RoundPlayers and self.RoundPlayers.Bosses) or {}

    return {
        roundLength = self.ActiveRoundLength,
        fighters = #fighters,
        bosses = #bosses,
        fighterNames = self:_collectAliveFighterNames(),
        bossStatus = self:_collectBossStatus(),
    }
end

function GameManager:_broadcastBossVitals(force: boolean?)
    if self.State ~= "Round" then
        return
    end

    self:_broadcastTimedState("Round", self.RoundCountdown, self:_buildRoundPayload(), force)
end

function GameManager:_reportTime(state: string, secondsRemaining: number)
    local rounded = math.max(0, math.ceil(secondsRemaining))
    local key = state .. "_time"
    if self._lastPrintedTimes[key] ~= rounded then
        self._lastPrintedTimes[key] = rounded
        self:_log(string.format("%s - %d seconds remaining", state, rounded))
    end
end

function GameManager:TryStartIntermission()
    local playerCount = #Players:GetPlayers()
    if playerCount < GameManager.MinimumPlayersToStart then
        if not self._announcedWaiting then
            self:_log("Waiting for enough players to start intermission")
            self._announcedWaiting = true
        end
        return
    end

    self._announcedWaiting = false
    self.State = "Intermission"
    self.IntermissionTimeLeft = GameManager.IntermissionLength
    self.ReservedCharacters = {
        Survivors = {},
        Bosses = {},
    }
    self.RoundPlayers = {
        Bosses = {},
        Fighters = {},
        RoleLookup = {},
        LeftCount = 0,
    }
    self:_log(string.format("Starting intermission with %d players", playerCount))
    self._lastBroadcastTimes["Intermission_broadcast"] = nil
    self._lastPrintedTimes["Intermission_time"] = nil
    self:_broadcastTimedState("Intermission", self.IntermissionTimeLeft)
end

function GameManager:UpdateIntermission(deltaTime: number)
    if self.IntermissionTimeLeft <= 0 then
        self:SelectBosses()
        self.State = "CharacterSelect"
        self.RoundCountdown = 0
        self.CharacterSelectTimeLeft = GameManager.CharacterSelectLength
        self:_log("Entering character selection")
        self._lastBroadcastTimes["CharacterSelect_broadcast"] = nil
        self._lastPrintedTimes["CharacterSelect_time"] = nil
        self:_broadcastCharacterSelectState(true)
        return
    end

    self.IntermissionTimeLeft -= deltaTime
    self:_reportTime("Intermission", self.IntermissionTimeLeft)
    self:_broadcastTimedState("Intermission", self.IntermissionTimeLeft)
end

-- Boss selection -----------------------------------------------------------

function GameManager:SelectBosses()
    local players = Players:GetPlayers()
    if #players == 0 then
        return
    end

    for _, player in ipairs(players) do
        self.BossChances[player] = (self.BossChances[player] or 0) + 1
        player:SetAttribute("BossChance", self.BossChances[player])
    end

    local bossCount = math.clamp(#players > 7 and 2 or 1, 1, GameManager.MaxBosses)
    local selectedBosses = findHighestChancePlayers(self.BossChances, bossCount)

    -- Reset chances for selected boss(es)
    for _, boss in ipairs(selectedBosses) do
        self.BossChances[boss] = 0
        boss:SetAttribute("BossChance", 0)
    end

    self.RoundPlayers.Bosses = selectedBosses
    self.RoundPlayers.Fighters = {}

    for _, player in ipairs(players) do
        if not table.find(selectedBosses, player) then
            table.insert(self.RoundPlayers.Fighters, player)
        end
    end

    self:_rebuildRoleLookup()
    self.RoundPlayers.LeftCount = 0

    local bossNames = {}
    for _, boss in ipairs(selectedBosses) do
        table.insert(bossNames, boss.Name)
    end
    local bossRosterText = #bossNames > 0 and table.concat(bossNames, ", ") or "None"
    self:_log(string.format("Selected boss roster: %s", bossRosterText))
    self:_log(string.format("Fighters queued: %d", #self.RoundPlayers.Fighters))

    for _, player in ipairs(players) do
        local role = table.find(selectedBosses, player) and "Boss" or "Fighter"
        player:SetAttribute("AssignedRole", role)
        player:SetAttribute("AssignedCharacter", "")
    end
end

-- Character selection ------------------------------------------------------

function GameManager:_clearPlayerReservation(player: Player)
    local roleValue = player:GetAttribute("AssignedRole")
    local assignedCharacter = player:GetAttribute("AssignedCharacter")
    if typeof(roleValue) ~= "string" or roleValue == "" then
        return
    end

    if typeof(assignedCharacter) ~= "string" or assignedCharacter == "" then
        return
    end

    local roleKey = roleValue == "Boss" and "Bosses" or "Survivors"
    local pool = self.ReservedCharacters[roleKey]
    if pool[assignedCharacter] == player then
        pool[assignedCharacter] = nil
        player:SetAttribute("AssignedCharacter", "")
        local remoteRole = roleValue == "Boss" and "Boss" or "Fighter"
        self.Remotes.CharacterAssignment:FireAllClients(nil, remoteRole, assignedCharacter)
    end
end

function GameManager:_removeFromRound(player: Player)
    for index, boss in ipairs(self.RoundPlayers.Bosses) do
        if boss == player then
            table.remove(self.RoundPlayers.Bosses, index)
            break
        end
    end

    for index, fighter in ipairs(self.RoundPlayers.Fighters) do
        if fighter == player then
            table.remove(self.RoundPlayers.Fighters, index)
            break
        end
    end

    if self.RoundPlayers.RoleLookup then
        self.RoundPlayers.RoleLookup[player] = nil
    end

    if self.RoundPlayers.Alive then
        if self.RoundPlayers.Alive.Bosses then
            self.RoundPlayers.Alive.Bosses[player] = nil
        end
        if self.RoundPlayers.Alive.Fighters then
            self.RoundPlayers.Alive.Fighters[player] = nil
        end
    end

    self:_disconnectPlayerConnections(player)
    self:_rebuildRoleLookup()
end

function GameManager:AssignCharacter(player: Player, role: string, characterName: string)
    if self.State ~= "CharacterSelect" then
        return
    end

    local roleKey = role == "Boss" and "Bosses" or "Survivors"
    local roster = role == "Boss" and self.RoundPlayers.Bosses or self.RoundPlayers.Fighters

    if not roster or not table.find(roster, player) then
        return
    end

    local currentCharacter = player:GetAttribute("AssignedCharacter")
    if typeof(currentCharacter) == "string" and currentCharacter ~= "" then
        return
    end

    local pool = role == "Boss" and GameManager.BossCharacters or GameManager.SurvivorCharacters
    if not rosterContains(pool, characterName) then
        return
    end

    if self.ReservedCharacters[roleKey][characterName] then
        return
    end

    self.ReservedCharacters[roleKey][characterName] = player
    player:SetAttribute("AssignedCharacter", characterName)
    self.Remotes.CharacterAssignment:FireAllClients(player, role, characterName)

    if role == "Boss" then
        self:_log(string.format("%s locked in boss character %s", player.Name, characterName))
    else
        self:_log(string.format("%s locked in survivor character %s", player.Name, characterName))
    end

    self:_broadcastCharacterSelectState(true)

    self:CheckCharacterSelectionCompletion()
end

function GameManager:CheckCharacterSelectionCompletion()
    if self.State ~= "CharacterSelect" then
        return
    end

    local allAssigned = true

    for _, boss in ipairs(self.RoundPlayers.Bosses) do
        if boss:GetAttribute("AssignedCharacter") == "" then
            allAssigned = false
            break
        end
    end

    if allAssigned then
        for _, fighter in ipairs(self.RoundPlayers.Fighters) do
            if fighter:GetAttribute("AssignedCharacter") == "" then
                allAssigned = false
                break
            end
        end
    end

    if allAssigned then
        self:_transitionToSelectionLock()
    end
end

function GameManager:_autoAssignMissingCharacters()
    for _, boss in ipairs(self.RoundPlayers.Bosses) do
        if boss:GetAttribute("AssignedCharacter") == "" then
            for _, characterInfo in ipairs(GameManager.BossCharacters) do
                local characterName = characterInfo.name
                if not self.ReservedCharacters.Bosses[characterName] then
                    self.ReservedCharacters.Bosses[characterName] = boss
                    boss:SetAttribute("AssignedCharacter", characterName)
                    self.Remotes.CharacterAssignment:FireAllClients(boss, "Boss", characterName)
                    self:_log(string.format("Auto-assigned boss %s to %s", boss.Name, characterName))
                    break
                end
            end
        end
    end

    for _, fighter in ipairs(self.RoundPlayers.Fighters) do
        if fighter:GetAttribute("AssignedCharacter") == "" then
            for _, characterInfo in ipairs(GameManager.SurvivorCharacters) do
                local characterName = characterInfo.name
                if not self.ReservedCharacters.Survivors[characterName] then
                    self.ReservedCharacters.Survivors[characterName] = fighter
                    fighter:SetAttribute("AssignedCharacter", characterName)
                    self.Remotes.CharacterAssignment:FireAllClients(fighter, "Fighter", characterName)
                    self:_log(string.format("Auto-assigned survivor %s to %s", fighter.Name, characterName))
                    break
                end
            end
        end
    end
end

function GameManager:_disconnectPlayerConnections(player: Player)
    local bucket = self.RoundConnections.Players[player]
    if not bucket then
        return
    end

    for _, connection in pairs(bucket) do
        if connection and connection.Disconnect then
            connection:Disconnect()
        end
    end

    self.RoundConnections.Players[player] = nil
end

function GameManager:_cleanupRoundConnections()
    for player, connectionSet in pairs(self.RoundConnections.Players) do
        if connectionSet then
            for _, connection in pairs(connectionSet) do
                if connection and connection.Disconnect then
                    connection:Disconnect()
                end
            end
        end
        self.RoundConnections.Players[player] = nil
    end
end

function GameManager:_handleCharacterSpawn(player: Player, role: string, character: Model)
    if self.State ~= "Round" then
        return
    end

    if self.RoundPlayers.Eliminated and self.RoundPlayers.Eliminated[player] then
        return
    end

    local roleKey = role == "Boss" and "Bosses" or "Fighters"
    self.RoundPlayers.Alive[roleKey][player] = true

    local bucket = self.RoundConnections.Players[player]
    if not bucket then
        bucket = {}
        self.RoundConnections.Players[player] = bucket
    end

    if bucket.HealthChanged then
        bucket.HealthChanged:Disconnect()
        bucket.HealthChanged = nil
    end

    if bucket.MaxHealthChanged then
        bucket.MaxHealthChanged:Disconnect()
        bucket.MaxHealthChanged = nil
    end

    if bucket.HumanoidDied then
        bucket.HumanoidDied:Disconnect()
        bucket.HumanoidDied = nil
    end

    if bucket.HumanoidAdded then
        bucket.HumanoidAdded:Disconnect()
        bucket.HumanoidAdded = nil
    end

    local function attachBossVitalsListeners(humanoid: Humanoid)
        if role ~= "Boss" then
            return
        end

        if bucket.HealthChanged then
            bucket.HealthChanged:Disconnect()
            bucket.HealthChanged = nil
        end

        if bucket.MaxHealthChanged then
            bucket.MaxHealthChanged:Disconnect()
            bucket.MaxHealthChanged = nil
        end

        bucket.HealthChanged = humanoid.HealthChanged:Connect(function()
            self:_broadcastBossVitals(true)
        end)

        bucket.MaxHealthChanged = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
            self:_broadcastBossVitals(true)
        end)
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        bucket.HumanoidDied = humanoid.Died:Connect(function()
            self:_onParticipantDied(player, role)
        end)
        attachBossVitalsListeners(humanoid)
    else
        bucket.HumanoidAdded = character.ChildAdded:Connect(function(child)
            if child:IsA("Humanoid") then
                if bucket.HumanoidAdded then
                    bucket.HumanoidAdded:Disconnect()
                    bucket.HumanoidAdded = nil
                end
                bucket.HumanoidDied = child.Died:Connect(function()
                    self:_onParticipantDied(player, role)
                end)
                attachBossVitalsListeners(child)
            end
        end)
    end

    if role == "Boss" then
        self:_broadcastBossVitals(true)
    end
end

function GameManager:_registerRoundParticipant(player: Player, role: string)
    self:_disconnectPlayerConnections(player)

    local bucket = {}
    self.RoundConnections.Players[player] = bucket

    local roleKey = role == "Boss" and "Bosses" or "Fighters"
    self.RoundPlayers.Alive[roleKey][player] = true
    self.RoundPlayers.Eliminated[player] = false

    bucket.CharacterAdded = player.CharacterAdded:Connect(function(character)
        self:_handleCharacterSpawn(player, role, character)
    end)

    if player.Character then
        self:_handleCharacterSpawn(player, role, player.Character)
    end
end

function GameManager:_evaluateEliminationOutcome()
    if not self.RoundPlayers.Alive then
        return
    end

    local bossesAlive = countDictionaryKeys(self.RoundPlayers.Alive.Bosses or {})
    local fightersAlive = countDictionaryKeys(self.RoundPlayers.Alive.Fighters or {})

    if bossesAlive == 0 then
        self:_log("All bosses have been defeated - fighters win")
        self:EndRound("FighterVictory")
    elseif fightersAlive == 0 then
        self:_log("All fighters have been defeated - bosses win")
        self:EndRound("BossVictory")
    end
end

function GameManager:_onParticipantDied(player: Player, role: string)
    if self.State ~= "Round" then
        return
    end

    if not self.RoundPlayers.Alive or not self.RoundPlayers.Eliminated then
        return
    end

    if self.RoundPlayers.Eliminated[player] then
        return
    end

    local roleKey = role == "Boss" and "Bosses" or "Fighters"
    if self.RoundPlayers.Alive[roleKey] then
        self.RoundPlayers.Alive[roleKey][player] = nil
    end

    self.RoundPlayers.Eliminated[player] = true
    self:_log(string.format("%s %s has been eliminated", role, player.Name))

    self:_disconnectPlayerConnections(player)
    self:_evaluateEliminationOutcome()

    if role == "Boss" then
        self:_broadcastBossVitals(true)
    end
end

function GameManager:_buildCharacterAssignments()
    local assignments = {
        Survivors = {},
        Bosses = {},
    }

    for characterName, player in pairs(self.ReservedCharacters.Survivors) do
        assignments.Survivors[characterName] = player and player.Name or ""
    end

    for characterName, player in pairs(self.ReservedCharacters.Bosses) do
        assignments.Bosses[characterName] = player and player.Name or ""
    end

    return assignments
end

function GameManager:_broadcastCharacterSelectState(force: boolean?)
    self:_broadcastTimedState(
        "CharacterSelect",
        self.CharacterSelectTimeLeft,
        {
            assignments = self:_buildCharacterAssignments(),
            roster = {
                Survivors = GameManager.SurvivorCharacters,
                Bosses = GameManager.BossCharacters,
            },
        },
        force
    )
    self:_reportTime("CharacterSelect", self.CharacterSelectTimeLeft)
end

function GameManager:UpdateCharacterSelection(deltaTime: number)
    if self.CharacterSelectTimeLeft <= 0 then
        self:_log("Character selection timer expired - auto assigning remaining players")
        self:_autoAssignMissingCharacters()
        self:_transitionToSelectionLock()
        return
    end

    self.CharacterSelectTimeLeft -= deltaTime
    self:_broadcastCharacterSelectState()
end

function GameManager:_transitionToSelectionLock()
    if self.State ~= "CharacterSelect" then
        return
    end

    self.State = "SelectionLock"
    self.SelectionLockTimeLeft = GameManager.SelectionLockLength
    self.CharacterSelectTimeLeft = 0

    self:_log("All characters locked - preparing to start the round")
    self._lastBroadcastTimes["SelectionLock_broadcast"] = nil
    self._lastPrintedTimes["SelectionLock_time"] = nil

    self:_broadcastTimedState(
        "SelectionLock",
        self.SelectionLockTimeLeft,
        {
            assignments = self:_buildCharacterAssignments(),
            roster = {
                Survivors = GameManager.SurvivorCharacters,
                Bosses = GameManager.BossCharacters,
            },
        },
        true
    )
end

function GameManager:UpdateSelectionLock(deltaTime: number)
    if self.SelectionLockTimeLeft <= 0 then
        self:BeginRound()
        return
    end

    self.SelectionLockTimeLeft -= deltaTime
    self:_reportTime("SelectionLock", self.SelectionLockTimeLeft)
    self:_broadcastTimedState(
        "SelectionLock",
        self.SelectionLockTimeLeft,
        {
            assignments = self:_buildCharacterAssignments(),
            roster = {
                Survivors = GameManager.SurvivorCharacters,
                Bosses = GameManager.BossCharacters,
            },
        }
    )
end

-- Round --------------------------------------------------------------------

function GameManager:BeginRound()
    local fighterCount = #self.RoundPlayers.Fighters
    local bossCount = #self.RoundPlayers.Bosses

    if bossCount == 0 then
        self:_log("Cannot begin round - no bosses were selected")
        self:EndRound("NoBosses")
        return
    elseif fighterCount == 0 then
        self:_log("Cannot begin round - no fighters were selected")
        self:EndRound("NoFighters")
        return
    end

    local roundLength = GameManager.BaseRoundLength + (fighterCount * GameManager.RoundIncrementPerFighter)

    self.ActiveRoundLength = roundLength
    self.RoundCountdown = roundLength
    self.State = "Round"
    self.CharacterSelectTimeLeft = 0
    self.SelectionLockTimeLeft = 0
    self.RoundPlayers.LeftCount = 0
    self.RoundPlayers.Alive = {
        Bosses = {},
        Fighters = {},
    }
    self.RoundPlayers.Eliminated = {}

    self:_cleanupRoundConnections()

    for _, boss in ipairs(self.RoundPlayers.Bosses) do
        self:_registerRoundParticipant(boss, "Boss")
    end

    for _, fighter in ipairs(self.RoundPlayers.Fighters) do
        self:_registerRoundParticipant(fighter, "Fighter")
    end

    self:_log(string.format("Round started with %d fighters and %d boss(es)", fighterCount, bossCount))
    self._lastBroadcastTimes["Round_broadcast"] = nil
    self._lastPrintedTimes["Round_time"] = nil
    self:_broadcastTimedState(
        "Round",
        self.RoundCountdown,
        self:_buildRoundPayload()
    )
end

function GameManager:UpdateRound(deltaTime: number)
    if self.RoundCountdown <= 0 then
        self:_resolveRoundTimeoutOutcome()
        return
    end

    self.RoundCountdown -= deltaTime
    self:_reportTime("Round", self.RoundCountdown)
    self:_broadcastTimedState(
        "Round",
        self.RoundCountdown,
        self:_buildRoundPayload()
    )
end

function GameManager:_resolveRoundTimeoutOutcome()
    if not self.RoundPlayers or not self.RoundPlayers.Alive then
        self:_log("Round timer expired - unable to determine participants")
        self:EndRound("TimeUp")
        return
    end

    local bossesAlive = countDictionaryKeys(self.RoundPlayers.Alive.Bosses or {})
    local fightersAlive = countDictionaryKeys(self.RoundPlayers.Alive.Fighters or {})

    if bossesAlive > 0 and fightersAlive > 0 then
        self:_log("Round timer expired with bosses alive - bosses win")
        self:EndRound("BossVictory")
    elseif bossesAlive == 0 and fightersAlive > 0 then
        self:_log("Round timer expired but no bosses remain - fighters win")
        self:EndRound("FighterVictory")
    elseif bossesAlive > 0 and fightersAlive == 0 then
        self:_log("Round timer expired with no fighters remaining - bosses win")
        self:EndRound("BossVictory")
    else
        self:_log("Round timer expired with no participants remaining")
        self:EndRound("TimeUp")
    end
end

function GameManager:EndRound(reason: string)
    self.State = "Waiting"
    self.RoundCountdown = 0
    self.ActiveRoundLength = 0
    self.SelectionLockTimeLeft = 0
    self.CharacterSelectTimeLeft = 0

    self:_cleanupRoundConnections()

    self.ReservedCharacters = {
        Survivors = {},
        Bosses = {},
    }
    self.RoundPlayers = {
        Bosses = {},
        Fighters = {},
        RoleLookup = {},
        LeftCount = 0,
    }

    self.RoundPlayers.Alive = nil
    self.RoundPlayers.Eliminated = nil

    self:_log(string.format("Round ended because: %s", reason))
    self:_broadcastState("RoundEnd", {
        reason = reason,
        winner = roundWinners[reason],
    })
end

-- Player departure rules ---------------------------------------------------

function GameManager:OnPlayerLeft(player: Player)
    self.BossChances[player] = nil

    if self.State == "CharacterSelect" then
        self:_clearPlayerReservation(player)
        self:_removeFromRound(player)
        self:CheckCharacterSelectionCompletion()
        self:_broadcastCharacterSelectState(true)
        return
    end

    if self.State ~= "Round" then
        return
    end

    local bossLeaving = table.find(self.RoundPlayers.Bosses, player)
    local fighterLeaving = table.find(self.RoundPlayers.Fighters, player)

    if bossLeaving then
        self:_log(string.format("Boss %s left the game", player.Name))
        self:_disconnectPlayerConnections(player)
        self:EndRound("BossLeft")
        return
    end

    if fighterLeaving then
        if self.RoundPlayers.Alive and self.RoundPlayers.Alive.Fighters then
            self.RoundPlayers.Alive.Fighters[player] = nil
        end

        if self.RoundPlayers.Eliminated then
            self.RoundPlayers.Eliminated[player] = true
        end

        self:_disconnectPlayerConnections(player)

        local fightersRemaining = {}
        for _, survivor in ipairs(self.RoundPlayers.Fighters) do
            if survivor ~= player and survivor.Parent == Players then
                table.insert(fightersRemaining, survivor)
            end
        end
        self.RoundPlayers.Fighters = fightersRemaining
        self:_rebuildRoleLookup()

        if #fightersRemaining == 0 then
            self:_log("All fighters have left the round")
            self:EndRound("AllFightersLeft")
            return
        end
    end

    -- Global rule: if more than two players leave during a round, end it.
    self.RoundPlayers.LeftCount = (self.RoundPlayers.LeftCount or 0) + 1
    if self.RoundPlayers.LeftCount > 2 then
        self:_log("Ending round because too many players left")
        self:EndRound("TooManyPlayersLeft")
    end
end

return GameManager
