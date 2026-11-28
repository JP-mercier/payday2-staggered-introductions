-- Drop-in Desync Fix (formerly Staggered Introductions), host side.
--
-- When a player joins, the host introduces them to the players already in the lobby and the
-- players already in to them, in the same frame (HostStateBase:_introduce_old_peers_to_new_peer
-- and :_introduce_new_peer_to_old_peers). Each side then opens its peer-to-peer connection to the
-- other at the same moment. In Epic Online Services P2P, two simultaneous connection requests make
-- EOS renegotiate the session, and sometimes it applies an answer to an offer it has already
-- replaced; the connection then never comes up. EOS only gives up after 45 s, while the game drops
-- a silent player after 15-20 s, so it never recovers. A drop-in waits forever for that pair.
--
-- This delays the second introduction: the newcomer is told about the others at once and opens
-- the connections, the others are told DELAY seconds later and find the newcomer's request already
-- waiting, so only one side opens each connection. Nothing else changes, and the other players
-- need no mod.

dofile(ModPath .. "lua/settings.lua")
local SI = StaggeredIntroductions

local function say(msg)
	log("[Drop-in Desync Fix] " .. msg)
end

if HostStateBase and HostStateBase._introduce_new_peer_to_old_peers and not HostStateBase._staggered_introductions then
	if HostStateBase._peer_relink_stagger and _G.PeerRelink and PeerRelink.stagger_joins then
		say("Peer Relink already staggers introductions, not wrapping a second time")
	else
		HostStateBase._staggered_introductions = true
		local introduce = HostStateBase._introduce_new_peer_to_old_peers

		function HostStateBase:_introduce_new_peer_to_old_peers(data, new_peer, ...)
			if not SI.ENABLED or not DelayedCalls or not new_peer or not (SI.DELAY > 0) then
				return introduce(self, data, new_peer, ...)
			end

			local args, n = { ... }, select("#", ...)
			local new_id = new_peer:id()
			DelayedCalls:Add("StaggeredIntroductions_" .. tostring(new_id), SI.DELAY, function()
				-- Skipped if the newcomer left (or another player took the slot) meanwhile.
				local session = managers.network and managers.network:session()
				if not session or not session._peers or session._peers[new_id] ~= new_peer then
					return
				end
				local ok, err = pcall(introduce, self, data, new_peer, unpack(args, 1, n))
				if not ok then
					say("introducing peer " .. tostring(new_id) .. " failed: " .. tostring(err))
				end
			end)
		end
	end
end
