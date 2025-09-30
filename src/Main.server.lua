-- Main.server.lua
-- Place this Script inside ServerScriptService. It wires up the GameManager module
-- and starts the round lifecycle loop.

local GameManager = require(script.Parent:WaitForChild("GameManager"))

local manager = GameManager.new()
manager:Start()
