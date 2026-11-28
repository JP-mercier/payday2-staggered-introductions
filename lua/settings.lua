-- Settings, read once per Lua state by every script of the mod. To change them without editing
-- this file, create local_settings.lua next to mod.txt and set the fields there, e.g.
--   StaggeredIntroductions.CLIENT_ENABLED = false

StaggeredIntroductions = StaggeredIntroductions or {}
local SI = StaggeredIntroductions

if not SI._settings_loaded then
	SI._settings_loaded = true

	-- Host side: seconds between telling the newcomer about the others and telling the others
	-- about the newcomer. ENABLED = false restores vanilla behavior.
	SI.ENABLED = true
	SI.DELAY = 1.5

	-- Client side: when the host introduces another player to us, take the introduction a
	-- moment later, so that player's connection request arrives first and only one side opens
	-- the connection. Helps in lobbies hosted without this mod. Sends nothing extra.
	-- Two players with this mod wait different times (by comparing their ids): LOW or HIGH.
	-- CLIENT_ENABLED = false restores vanilla behavior.
	SI.CLIENT_ENABLED = true
	SI.CLIENT_DELAY_LOW = 1.0
	SI.CLIENT_DELAY_HIGH = 2.5

	SI._mod_path = ModPath
	SI._pending_client = {}

	local f = io.open(ModPath .. "local_settings.lua", "r")
	if f then
		f:close()
		dofile(ModPath .. "local_settings.lua")
	end
end

-- Match Making Improvements (global FixMatchMaking) delays the same introductions, host and
-- client side. With both mods, each introduction would wait twice, so this mod steps aside.
-- Checked at call time: the two mods can load in either order and wrap each other either way.
function SI:other_mod_staggers()
	if rawget(_G, "FixMatchMaking") == nil then
		return false
	end
	if not self._yield_logged then
		self._yield_logged = true
		log("[Drop-in Desync Fix] Match Making Improvements is installed and delays the same introductions; stepping aside")
	end
	return true
end
