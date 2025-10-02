# Roblox Boss Round Manager

This repository contains a server-side game management module designed for a
boss-versus-survivors Roblox experience. The scripts implement the following
features requested by the designer:

- Automatically waits until at least three players are in the server before
  starting a 45-second intermission.
- Tracks and increments a per-player boss chance, selecting the player(s) with
  the highest value every round (up to two bosses when more than seven players
  are present).
- Provides survivor and boss character selection with unique picks enforced per
  round.
- Shares fighter and boss rosters that include per-character stats and
  abilities so every survivor has two moves while bosses boast three.
- Cancels a round immediately if no bosses or no fighters are available when
  it would begin, ensuring every match features both sides.
- Dynamically lengthens the round timer: base time of 2 minutes 30 seconds plus
  45 seconds per survivor.
- Ends the round early if a boss leaves, if all fighters leave, or if three or
  more players leave mid-round.
- Awards victory automatically when every fighter is eliminated (boss win),
  when all bosses are defeated (fighter win), or when the round timer expires
  with bosses still alive.
- Broadcasts the round winner so the client HUD can flash a clear "Victory" or
  "Defeat" banner for each player at the end of a match.
- Displays an in-round HUD with a bottom-left health readout and bottom-right
  ability wheel that labels each move with its activation key (Q, E, Z, X).
- Shows fighter stock icons next to teammate names, overlays the player's
  character portrait above their health bar, and tracks boss HP with matching
  portraits directly beneath the timer.

## Usage

1. Copy the contents of the `src` folder into Roblox Studio:
   - Place `GameManager.lua` in `ServerScriptService` as a ModuleScript.
   - Place `Main.server.lua` in `ServerScriptService` as a Script and require the
     manager.
   - Place `BossRoster.lua` and `FighterRoster.lua` in `ReplicatedStorage` as
     ModuleScripts so both the server and clients can require the shared
     character data.
   - Place `CharacterSelect.client.lua` in `StarterPlayerScripts` (or a
     ScreenGui in `StarterGui`) to provide the ready-made selection interface,
     timer HUD, character stat summaries, and the in-round health/ability HUD.
2. Customize the fighter and boss character lists inside `FighterRoster.lua`
   and `BossRoster.lua` to match the characters in your experience. Each entry
   defines stats (HP, Speed, Attack, Jump), portrait/stock asset IDs, plus two
   abilities for fighters and three abilities for bosses. The manager ensures
   that only one player can use each character per round.
3. Hook up UI to the supplied RemoteEvents in `ReplicatedStorage`:
  - `RoundStateChanged` sends updates such as `"Intermission"`,
    `"CharacterSelect"`, `"SelectionLock"`, `"Round"`, and `"RoundEnd"` and
    now includes a `timeLeft` field plus contextual data for character
    selection and rounds. The `"SelectionLock"` step fires once every player has
    locked a character, giving clients a brief moment to hide the selection
    menu before the round begins. The `"RoundEnd"` payload also reports the
    winning role so clients can show player-specific victory or defeat
    messaging.
   - `RequestCharacter` is fired by clients requesting a character name.
   - `CharacterAssignment` broadcasts the confirmed character for a player.
4. Require `GameManager` from any server Script and call `:Start()` to begin the
   lifecycle loop. The manager logs each step and reports remaining time in the
   output to help with debugging.

The module exposes helper functions to handle player departures and can be
expanded with custom victory logic, damage systems, and UI feedback tailored to
your game.
