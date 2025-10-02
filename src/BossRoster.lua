--!strict
-- BossRoster.lua
-- Centralized list of available boss characters with stats and abilities.
-- Place this ModuleScript inside ReplicatedStorage so both server and client
-- scripts can require the shared roster.

export type CharacterStats = {
	hp: number,
	speed: number,
	attack: number,
	jump: number,
}

export type CharacterImages = {
	profile: string,
}

export type CharacterInfo = {
	name: string,
	stats: CharacterStats,
	abilities: {string},
	images: CharacterImages,
}

-- Each boss exposes a profile image id for selection tiles and HUD displays.
local bosses: {CharacterInfo} = {
	{
		name = "Master Hand",
		stats = {hp = 800, speed = 20, attack = 40, jump = 10},
		abilities = {"Finger Lasers", "Rocket Punch", "Slap Storm"},
		images = {profile = "130120425105163"},
	},
	{
		name = "Crazy Hand",
		stats = {hp = 650, speed = 22, attack = 38, jump = 12},
		abilities = {"Chaos Bomb", "Wild Grab", "Erratic Spin"},
		images = {profile = "120558109173607"},
	},
	{
		name = "Giga Bowser",
		stats = {hp = 1000, speed = 18, attack = 45, jump = 15},
		abilities = {"Giga Flame", "Shell Slam", "Lightning Breath"},
		images = {profile = "107219913892705"},
	},
}

return bosses
