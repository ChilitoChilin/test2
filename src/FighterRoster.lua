--!strict
-- FighterRoster.lua
-- Shared survivor roster with stats and abilities for character selection.
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
	stock: string,
}

export type CharacterInfo = {
	name: string,
	stats: CharacterStats,
	abilities: {string},
	images: CharacterImages,
}

-- Each entry exposes a profile image id (for round HUDs) and a stock icon id
-- (used on teammate lists).
local fighters: {CharacterInfo} = {
	{
		name = "Mario",
		stats = {hp = 120, speed = 30, attack = 25, jump = 28},
		abilities = {"Fireball", "Super Jump Punch"},
		images = {profile = "135129756499992", stock = "132128217346059"},
	},
	{
		name = "Yoshi",
		stats = {hp = 140, speed = 28, attack = 22, jump = 33},
		abilities = {"Egg Throw", "Flutter Jump"},
		images = {profile = "108623656266722", stock = "87299674913300"},
	},
	{
		name = "Donkey Kong",
		stats = {hp = 170, speed = 22, attack = 38, jump = 18},
		abilities = {"Giant Punch", "Barrel Roll"},
		images = {profile = "91622035238858", stock = "84563648425646"},
	},
	{
		name = "Link",
		stats = {hp = 115, speed = 31, attack = 33, jump = 26},
		abilities = {"Spin Attack", "Arrow Shot"},
		images = {profile = "128534457531943", stock = "112375717539915"},
	},
	{
		name = "Samus",
		stats = {hp = 155, speed = 26, attack = 32, jump = 30},
		abilities = {"Charge Beam", "Missile Barrage"},
		images = {profile = "135729021815388", stock = "118216649800226"},
	},
	{
		name = "Kirby",
		stats = {hp = 110, speed = 37, attack = 33, jump = 35},
		abilities = {"Inhale", "Final Cutter"},
		images = {profile = "132183655083652", stock = "131103346840705"},
	},
	{
		name = "Fox",
		stats = {hp = 110, speed = 39, attack = 26, jump = 29},
		abilities = {"Blaster", "Fox Illusion"},
		images = {profile = "80193823955751", stock = "122757908781248"},
	},
	{
		name = "Pikachu",
		stats = {hp = 105, speed = 41, attack = 31, jump = 32},
		abilities = {"Thunder Jolt", "Quick Attack"},
		images = {profile = "130808578016781", stock = "90281746124749"},
	},
	{
		name = "Luigi",
		stats = {hp = 120, speed = 30, attack = 22, jump = 34},
		abilities = {"Green Missile", "Super Jump Punch"},
		images = {profile = "93302006478656", stock = "91911649081195"},
	},
	{
		name = "Jigglypuff",
		stats = {hp = 120, speed = 22, attack = 18, jump = 40},
		abilities = {"Sing", "Rest"},
		images = {profile = "120522660172727", stock = "80309034901541"},
	},
	{
		name = "Captain Falcon",
		stats = {hp = 115, speed = 37, attack = 34, jump = 27},
		abilities = {"Falcon Punch", "Raptor Boost"},
		images = {profile = "129438683632303", stock = "87032683437147"},
	},
	{
		name = "Ness",
		stats = {hp = 120, speed = 30, attack = 33, jump = 28},
		abilities = {"PK Flash", "PK Fire"},
		images = {profile = "114800090331877", stock = "90652532619219"},
	},
}

return fighters
