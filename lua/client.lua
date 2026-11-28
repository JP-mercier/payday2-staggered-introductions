-- Client side (StaggeredIntroductions.CLIENT_ENABLED, on by default).
--
-- When the host introduces another player to us (peer_handshake), vanilla adds the player and
-- opens the connection to them at once, while that player does the same towards us: the
-- simultaneous opening that sometimes leaves Epic's P2P connection stuck. Here the whole
-- introduction is taken a moment later, so the other player's connection request is already
-- waiting and only one side opens the connection.
--
-- The whole call is delayed, not just the connection: a player without a connection makes the
-- game refuse to load or leave (BaseNetworkSession:is_ready_to_close) and crashes HUD mods that
-- ask the engine for that player's ping. Messages about a player we don't know yet are ignored by
-- vanilla, and none that matter can come before we answer: the host only goes on with this pair
-- after we report the connection (connection_established, sent by peer_handshake). If the host
-- removes the player meanwhile (kick_peer), the pending introduction is dropped.
--
-- A level or lobby load rebuilds the Lua state, which would silently drop a pending
-- introduction: the game would never add that player, and the host would wait forever for us to
-- load their outfit (seen 2026-11-27: introduction 1 s before a heist restart). So when a load
-- starts, pending introductions run at once, as vanilla would have run them.

dofile(ModPath .. "lua/settings.lua")
local SI = StaggeredIntroductions

local function say(msg)
	log("[Drop-in Desync Fix] " .. msg)
end

function SI:client_delay(peer_user_id)
	local ok, own = pcall(function()
		return DistributionMatchmaking:user_id()
	end)
	if ok and own and tostring(own) < tostring(peer_user_id) then
		return self.CLIENT_DELAY_LOW
	end
	return self.CLIENT_DELAY_HIGH
end

function SI:cancel_client_intro(peer_id)
	local key = "StaggeredIntroductions_client_" .. tostring(peer_id)
	if self._pending_client[key] then
		self._pending_client[key] = nil
		if DelayedCalls and DelayedCalls.Remove then
			DelayedCalls:Remove(key)
		end
	end
end

-- Runs a pending introduction now (or drops it if it no longer applies).
function SI:run_client_intro(key)
	local pending = self._pending_client[key]
	if not pending then
		return
	end
	self._pending_client[key] = nil
	if DelayedCalls and DelayedCalls.Remove then
		DelayedCalls:Remove(key)
	end
	local session = pending.session
	local current = managers.network and managers.network:session()
	if current ~= session or session._closing or (session._peers and session._peers[pending.peer_id]) then
		return
	end
	pending.fn(session, unpack(pending.args, 1, pending.n))
end

function SI:flush_client_intros()
	local keys = {}
	for key in pairs(self._pending_client) do
		keys[#keys + 1] = key
	end
	for _, key in ipairs(keys) do
		local ok, err = pcall(self.run_client_intro, self, key)
		if not ok then
			say("flush failed: " .. tostring(err))
		end
	end
	if #keys > 0 then
		say("load started: ran " .. #keys .. " pending introduction(s) at once")
	end
end

if RequiredScript == "lib/network/base/clientnetworksession" and ClientNetworkSession
	and ClientNetworkSession.peer_handshake and not ClientNetworkSession._staggered_introductions then
	ClientNetworkSession._staggered_introductions = true
	local peer_handshake = ClientNetworkSession.peer_handshake

	function ClientNetworkSession:peer_handshake(name, peer_id, peer_user_id, ...)
		local delay = SI.CLIENT_ENABLED and DelayedCalls and peer_id ~= 1 and self._peers and not self._peers[peer_id]
			and peer_user_id and self._server_protocol == SystemInfo:matchmaking_protocol() and SI:client_delay(peer_user_id)
		if not delay or not (delay > 0) then
			return peer_handshake(self, name, peer_id, peer_user_id, ...)
		end

		local key = "StaggeredIntroductions_client_" .. tostring(peer_id)
		SI._pending_client[key] = {
			session = self,
			peer_id = peer_id,
			fn = peer_handshake,
			args = { name, peer_id, peer_user_id, ... },
			n = select("#", ...) + 3,
		}
		DelayedCalls:Add(key, delay, function()
			SI:run_client_intro(key)
		end)
	end

	-- Both go through Setup:exec, which rebuilds the Lua state; run pending introductions first.
	for _, fname in ipairs({ "load_level", "load_lobby" }) do
		local orig = ClientNetworkSession[fname]
		if orig then
			ClientNetworkSession[fname] = function(self, ...)
				SI:flush_client_intros()
				return orig(self, ...)
			end
		end
	end
end

if RequiredScript == "lib/network/base/handlers/connectionnetworkhandler" and ConnectionNetworkHandler
	and ConnectionNetworkHandler.kick_peer and not ConnectionNetworkHandler._staggered_introductions then
	ConnectionNetworkHandler._staggered_introductions = true
	local kick_peer = ConnectionNetworkHandler.kick_peer

	function ConnectionNetworkHandler:kick_peer(peer_id, ...)
		SI:cancel_client_intro(peer_id)
		return kick_peer(self, peer_id, ...)
	end
end
