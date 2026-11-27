# Staggered Introductions

SuperBLT mod for PAYDAY 2. Fix for players who can't connect to each other when someone joins: a drop-in that stays on the loading screen, or a teammate who never appears for one player.

When you host, only you need the mod: the other players need nothing, not even SuperBLT. When you join a lobby hosted without the mod, the client side covers your own connections.

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

## Client side

For lobbies hosted without the mod. When the host introduces another player to you (`peer_handshake`), the whole introduction is taken a moment later, so that player's connection request is already waiting and only one side opens the connection. Two players with the mod wait different times (1.0 s or 2.5 s, by comparing their user ids), and either way it fits with a host that staggers.

The whole introduction is delayed, not only the connection. A player without a connection makes the game refuse to load or leave (`BaseNetworkSession:is_ready_to_close`), and HUD mods that read that player's ping crash the engine. Vanilla ignores messages about a player it doesn't know yet. None that matter can arrive before you answer: the host only goes on with the pair after your `connection_established`. If the host removes that player during the wait (`kick_peer`), the pending introduction is dropped. If a level or lobby load starts during the wait, the pending introduction runs at once, before the load (1.2.1: before that, a load rebuilt the Lua state and lost it, so the host waited forever for that player).

On by default since 1.2.0. It only changes when your own game acts on an introduction: nothing extra is sent, and the other players' games behave as in vanilla. Turn it off with `CLIENT_ENABLED = false` (see Settings).

## Evidence

Measured with Network Diagnostics (a game-side logging mod) and a hook that records Epic's own P2P log (EOS log level VeryVerbose, plus per-peer counts of packets sent and delivered).

### Before

- In public lobbies joined by the author (2026-10-21 to 10-30): about 7.5% of guest-to-guest connections never came up (23 of ~305). The connection to the host was fine (241 of 243). Working links came up in under 2 s, almost never later, so nothing rescued a stuck one.
- In lobbies hosted by the author (2026-11-18 to 11-22): 40 of 121 guest pairs never connected (33%). Failures were per pair and per attempt: the same two players could fail as guests and connect fine as host and joiner.
- Retrying the same pair soon after rarely helped: a rejoin within ~20 s worked 0 of 7 times, and a host re-introduction ~10 s later 0 of 4.

### Cause

- The EOS log showed the collision on about a third of all new guest connections (both requests sent 5-50 ms apart). Most survived it. The ones that didn't all logged the stale answer quoted above, and the packet counts showed the game sending while EOS delivered nothing until its 45 s timeout.
- When only one side opened the connection, it came up in under 1 s every time (median 0.24 s for the connectivity checks).
- One player failed to connect to the author three times in a row with that exact signature, then connected on the first try once only one side was allowed to open the connection.

### With the mod

- Host side, two hosted sessions (2026-11-25, 11-27): 8 of 8 guest pairs connected, in 2-3 s, including pairs that had failed every time before. The players joining did not have the mod.
- Client side, one session joining four lobbies hosted without the mod (2026-11-27): 7 of 7 connections to other guests were opened by the other side only (their request arrived 1.0-2.3 s before the game sent anything). No collision, all connected in under 1.5 s. (The author's EOS hook, which can also hold packets back, was running but never had to act.)
- Across every session run with this mod or an earlier native version of the same idea (2026-11-23 to 11-27): about 40 guest connections, none dead, against roughly one in three before in the author's lobbies.

Still a small sample. More data is welcome.

## Settings

In `lua/settings.lua`, or in a `local_settings.lua` next to `mod.txt` (read after the defaults, e.g. `StaggeredIntroductions.CLIENT_ENABLED = false`):

- `ENABLED` (true): host side. false restores vanilla behavior.
- `DELAY` (1.5): host side, seconds between the two introductions.
- `CLIENT_ENABLED` (true): client side. false restores vanilla behavior.
- `CLIENT_DELAY_LOW` (1.0), `CLIENT_DELAY_HIGH` (2.5): client side wait, by user id order.

## Compatibility

- Wraps `HostStateBase:_introduce_new_peer_to_old_peers` and calls the original. Other mods that wrap it still run.
- If the author's Peer Relink mod is installed with its own staggering on, this mod does nothing, so the delay is not applied twice.
- Nothing is sent to other players beyond what vanilla sends.

## Limitations

- The host side only works when you host. In lobbies hosted by others, only the client side helps, and only for your own connections.
- It prevents the collision. It does not fix connections that fail for other reasons, such as a network that can't be reached at all.
- It does not help when a player's own game drops out, for example after an error while a heist restarts: their game closes the connection and ignores new requests, and vanilla keeps their slot (holding up the start and other drop-ins) until it removes them about 80 s later.
