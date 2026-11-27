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

dofile(ModPath .. "lua/settings.lua")
local SI = StaggeredIntroductions

local function say(msg)
	log("[Staggered Introductions] " .. msg)
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

		local args, n = { name, peer_id, peer_user_id, ... }, select("#", ...) + 3
		local key = "StaggeredIntroductions_client_" .. tostring(peer_id)
		SI._pending_client[key] = true
		DelayedCalls:Add(key, delay, function()
			if not SI._pending_client[key] then
				return
			end
			SI._pending_client[key] = nil
			local session = managers.network and managers.network:session()
			if session ~= self or self._closing or (self._peers and self._peers[peer_id]) then
				return
			end
			peer_handshake(self, unpack(args, 1, n))
		end)
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
