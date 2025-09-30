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
        stats = {hp = 130, speed = 32, attack = 20, jump = 35},
        abilities = {"Egg Throw", "Flutter Jump"},
        images = {profile = "108623656266722", stock = "87299674913300"},
    },
    {
        name = "Donkey Kong",
        stats = {hp = 150, speed = 25, attack = 35, jump = 20},
        abilities = {"Giant Punch", "Barrel Roll"},
        images = {profile = "91622035238858", stock = "84563648425646"},
    },
    {
        name = "Link",
        stats = {hp = 125, speed = 28, attack = 30, jump = 25},
        abilities = {"Spin Attack", "Arrow Shot"},
        images = {profile = "128534457531943", stock = "112375717539915"},
    },
    {
        name = "Samus",
        stats = {hp = 140, speed = 27, attack = 30, jump = 22},
        abilities = {"Charge Beam", "Missile Barrage"},
        images = {profile = "135729021815388", stock = "118216649800226"},
    },
    {
        name = "Kirby",
        stats = {hp = 110, speed = 26, attack = 22, jump = 34},
        abilities = {"Inhale", "Final Cutter"},
        images = {profile = "132183655083652", stock = "131103346840705"},
    },
    {
        name = "Fox",
        stats = {hp = 105, speed = 35, attack = 24, jump = 27},
        abilities = {"Blaster", "Fox Illusion"},
        images = {profile = "80193823955751", stock = "122757908781248"},
    },
    {
        name = "Pikachu",
        stats = {hp = 95, speed = 38, attack = 20, jump = 30},
        abilities = {"Thunder Jolt", "Quick Attack"},
        images = {profile = "130808578016781", stock = "90281746124749"},
    },
    {
        name = "Luigi",
        stats = {hp = 115, speed = 29, attack = 23, jump = 32},
        abilities = {"Green Missile", "Super Jump Punch"},
        images = {profile = "93302006478656", stock = "91911649081195"},
    },
    {
        name = "Jigglypuff",
        stats = {hp = 90, speed = 24, attack = 18, jump = 40},
        abilities = {"Sing", "Rest"},
        images = {profile = "120522660172727", stock = "80309034901541"},
    },
    {
        name = "Captain Falcon",
        stats = {hp = 125, speed = 33, attack = 32, jump = 26},
        abilities = {"Falcon Punch", "Raptor Boost"},
        images = {profile = "129438683632303", stock = "87032683437147"},
    },
    {
        name = "Ness",
        stats = {hp = 115, speed = 27, attack = 21, jump = 28},
        abilities = {"PK Flash", "PK Fire"},
        images = {profile = "114800090331877", stock = "90652532619219"},
    },
}

return fighters
