# Staggered Introductions

SuperBLT mod for PAYDAY 2. Host-side fix for players who can't connect to each other when someone joins: a drop-in that stays on the loading screen, or a teammate who never appears for one player.

Only the host needs the mod. The other players need nothing, not even SuperBLT. An experimental client side, off by default, covers your own connections in lobbies hosted without the mod.

## Requirements

- [SuperBLT](https://superblt.znix.xyz/)

## Installation

Extract to `PAYDAY 2/mods/`. The folder name does not matter.

## The problem

Every player connects directly to every other player, not only to the host. The game uses Epic Online Services (EOS) P2P for these connections, Steam copy included.

When a player joins, the host introduces them to the players already in the lobby and introduces the others to them in the same frame (`HostStateBase:_introduce_old_peers_to_new_peer` and `:_introduce_new_peer_to_old_peers`). Both games then open their connection to each other at the same moment.

EOS handles two simultaneous connection requests by renegotiating the session. Most of the time that works. Sometimes EOS applies the answer to an offer it has already replaced, and the connection stays in "checking" forever. The EOS log shows it:

```
Received invitation for new Session ID for Socket ID we already know about.
Swapping to new Session ID.
...
CreateSessionDescription was successful, but our state is no-longer signaling.
...
Failed to establish connection with peer after 45 seconds.
```

EOS gives up after 45 s, but the game drops a player it hears nothing from after 15-20 s. By the time EOS would retry, the game has already given up on that player. The host's drop-in check waits for every pair to be connected and has no timeout, so the newcomer hangs on the loading screen.

The connection to the host is not affected: only the joiner opens it, so there is no collision. That is why one player can reach the host but not another teammate.

## What it does

It delays the second introduction. The newcomer is told about the other players immediately and opens the connections. The others are told about the newcomer 1.5 s later (`DELAY`), find the newcomer's request already waiting, and accept it. Only one side opens each connection.

The delayed introduction is skipped if the newcomer left (or another player took the slot) in the meantime. Nothing else changes: same messages, same order of events, sent a moment apart.

Side effect: each new connection between guests comes up about 1 s later than before (2-3 s instead of 1-2 s). If the host starts the heist during that window, the game waits until the connections are made, as it does in vanilla.

## Client side (experimental, off by default)

For lobbies hosted without the mod. When the host introduces another player to you (`peer_handshake`), the whole introduction is taken a moment later, so that player's connection request is already waiting and only one side opens the connection. Two players with the mod wait different times (1.0 s or 2.5 s, by comparing their user ids), and either way it fits with a host that staggers.

The whole introduction is delayed, not only the connection. A player without a connection makes the game refuse to load or leave (`BaseNetworkSession:is_ready_to_close`), and HUD mods that read that player's ping crash the engine. Vanilla ignores messages about a player it doesn't know yet. None that matter can arrive before you answer: the host only goes on with the pair after your `connection_established`. If the host removes that player during the wait (`kick_peer`), the pending introduction is dropped.

Turn it on with `CLIENT_ENABLED = true` (see Settings). It has not been tested in game yet.

## Evidence

Measured with Network Diagnostics (game side) and an EOS log hook.

- Before, in lobbies hosted by the author (2026-11-18 to 11-22): 40 of 121 guest-to-guest connections never came up. EOS logs of failed links showed the simultaneous-request renegotiation above. A retry with only one side requesting connected in about 1 s.
- With this mod, in one hosted session (2026-11-25): 6 of 6 guest pairs connected in 2-3 s, including pairs that had failed every time before.

That is one session so far. More data is welcome.

## Settings

In `lua/settings.lua`, or in a `local_settings.lua` next to `mod.txt` (read after the defaults, e.g. `StaggeredIntroductions.CLIENT_ENABLED = true`):

- `ENABLED` (true): host side. false restores vanilla behavior.
- `DELAY` (1.5): host side, seconds between the two introductions.
- `CLIENT_ENABLED` (false): client side.
- `CLIENT_DELAY_LOW` (1.0), `CLIENT_DELAY_HIGH` (2.5): client side wait, by user id order.

## Compatibility

- Wraps `HostStateBase:_introduce_new_peer_to_old_peers` and calls the original. Other mods that wrap it still run.
- If the author's Peer Relink mod is installed with its own staggering on, this mod does nothing, so the delay is not applied twice.
- Nothing is sent to other players beyond what vanilla sends.

## Limitations

- The host side only works when you host. In lobbies hosted by others, only the experimental client side helps, and only for your own connections.
- It prevents the collision. It does not fix connections that fail for other reasons, such as a network that can't be reached at all.
