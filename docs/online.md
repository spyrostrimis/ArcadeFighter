# Online play (room codes + rollback)

Two players on different PCs play over the internet with a short room code.
They don't need an IP address, port forwarding, a VPN, or a server of our own.
The design follows the SFAZ (Ikemen GO) netroom. The differences are that the
Godot build uses rollback, and every message to the brokers is encrypted.

## How to play

1. **Title → ONLINE → HOST ROOM.** A 6-character code appears, for example
   `K7QF2M`, and is also copied to the clipboard. Send it to your opponent.
2. The opponent picks **ONLINE → JOIN ROOM**, then types the code or pastes it
   with Ctrl+V and presses Enter.
3. While connecting, the screen shows the current step: *contacting signalling
   service → waiting for opponent / looking for the host → connecting → checking
   game version*. ESC cancels at any point.
4. Each player picks a fighter with their own controls (arrows + A/S/D/Z/X/C).
   Both cursors show on both screens. When both have confirmed, the VS screen
   plays and the fight starts. The host is always 1P (left), the guest 2P.
5. After the match, each player chooses **REMATCH**, **CHANGE FIGHTER** or
   **LEAVE ROOM**.
6. During a fight there is no pause. Press ESC twice to leave. The bottom-left
   corner shows ping, the depth of the last rollback, and the input delay.

**INPUT DELAY** in the online menu (default 2 frames) sets how far ahead local
input is scheduled. A higher value means fewer rollbacks but a less snappy
feel. The host's value is used for the match.

## How it works

```
 host                     public MQTT brokers                     guest
  |  subscribe(topic)  -->  [emqx, hivemq, mosquitto]  <--  subscribe(topic)
  |                                                     <--  join (every 1.5s)
  |  offer (SDP)       -->                              -->
  |                                                     <--  answer (SDP)
  |  ICE candidates   <------------------------------------> ICE candidates
  |=============== WebRTC (UDP, hole-punched via STUN) ===============|
  |  "game": unordered, no retransmits   (rollback inputs, pings)     |
  |  "ctl" : reliable, ordered           (hello/version, select, rematch, bye)
```

| File | Role |
|---|---|
| `scripts/net/mqtt_ws.gd` | Minimal MQTT 3.1.1 client (QoS 0) over secure WebSocket. Falls back to IPv4 when IPv6 hangs. |
| `scripts/net/room_signal.gd` | One mailbox on all brokers at once, with de-duplication and encryption. |
| `scripts/net/net_room.gd` | Room flow, WebRTC peer, data channels, timeouts and error messages. |
| `scripts/net/rollback.gd` | GGPO-style rollback session. It knows nothing about the transport. |
| `scripts/net/net.gd` | Autoload `Net`. Keeps the room alive across screens, routes packets, emits `lost`. |
| `scripts/screens/online_screen.gd` | HOST / JOIN / code entry / status / error UI. |

### Signalling

- **Brokers.** Messages go to `broker.emqx.io`, `broker.hivemq.com` and
  `test.mosquitto.org`. These are free public MQTT brokers, reached over
  `wss://`. Every message is published on every broker that is connected, and
  the receiver ignores duplicates. The players therefore meet as long as at
  least one broker works for both of them.
- **Topic and encryption.** The topic is
  `arcadefighter/v1/<sha256("AF-ROOM-TOPIC-v1:"+code)>`. Each payload is
  AES-256-CBC encrypted with `sha256("AF-ROOM-KEY-v1:"+code)`. People watching
  a public broker see neither the room code nor the players' IP addresses,
  which are in the SDP.
- **STUN.** The STUN servers are `stun.l.google.com:19302`,
  `stun1.l.google.com:19302` and `stun.cloudflare.com:3478`.
- **After connecting.** Once both data channels are open and the version
  handshake succeeds, the brokers are disconnected. All further traffic is
  peer to peer.
- **Lost messages.** Brokers may drop messages (QoS 0), so the guest repeats
  `join`, the host repeats its offer until it gets an answer, and the full list
  of ICE candidates is re-sent every 2 seconds.
- **Version check.** Both sides compare a hash of the protocol version and all
  character data. If they differ, the connection is refused.

### Failure messages

The wording matches the SFAZ netroom.

| When | Message |
|---|---|
| No broker reachable within 13 s | NO SIGNALLING SERVICE REACHABLE - CHECK YOUR INTERNET CONNECTION |
| Guest gets no offer within 15 s | NO HOST ANSWERED - CHECK THE CODE, AND THAT THE HOST HAS HOST ROOM OPEN |
| ICE fails, or no data channel within 20 s | CANNOT CONNECT TO THE OTHER PLAYER - A STRICT NAT OR FIREWALL BLOCKED THE DIRECT LINK |
| Version or data hash differs | BOTH PLAYERS NEED THE SAME GAME VERSION |
| A third player tries the code | THAT ROOM ALREADY HAS TWO PLAYERS |
| The opponent leaves | THE OTHER PLAYER LEFT |
| The connection drops | THE OTHER PLAYER LEFT OR THE CONNECTION WAS LOST |
| Nothing received for 10 s | THE OTHER PLAYER STOPPED RESPONDING |

### Rollback

These are the main points of `scripts/net/rollback.gd`:

- **Input delay.** Local input for tick *t* is used on frame *t + delay*.
  Frames below `delay` are neutral on both sides.
- **Packets.** Each tick sends one small packet. It holds the sender's current
  frame, the last remote frame it has received (its ack), and its frame
  advantage, a checksum, and all local inputs the peer has not yet
  acknowledged (up to 64). This redundancy hides packet loss.
- **Prediction and rollback.** A missing remote input is predicted by
  repeating the last confirmed one. When the real input arrives and differs,
  the sim is restored from a ring of `MatchSim.save_state()` snapshots and
  re-simulated up to the present.
- **Rollback window.** The window is 8 frames. If the remote falls further
  behind, the sim stalls instead of predicting further.
- **Time sync.** The peer that is ahead waits one frame now and then (GGPO's
  frame-advantage method, using RTT/2). Neither side keeps running ahead and
  forcing the other into rollbacks.
- **Desync detection.** Every 30 frames, each side checksums the state at a
  fully confirmed frame and sends it. A mismatch sets `desync_frame`, and the
  fight shows DESYNC DETECTED.
- **Events.** Sounds, sparks, shake and HUD events are emitted per frame and
  de-duplicated. An event already emitted for a frame is not emitted again when
  that frame is re-simulated. An event that only appears after a correction
  still plays, a few frames late.
- **Disconnects.** After 10 s without a packet the session errors out, and the
  player goes back to the online menu with the reason.

The sim itself is unchanged. It uses integer math only, and nothing in
`scripts/sim/` uses randomness or floats.

## Limits

- **Symmetric NAT.** There is no TURN relay. If both players are behind
  symmetric or strict NATs (some mobile hotspots, carrier-grade NAT, corporate
  networks), hole punching can fail and the game shows the NAT error. Adding a
  TURN server to `NetRoom.STUN` (as `{"urls": "turn:...", "username": ...,
  "credential": ...}`) would fix this, but it costs money or needs a server.
- **Public brokers.** The brokers are free services with no uptime guarantee.
  On 2026-11-13, `test.mosquitto.org` was unreachable from the dev PC, and
  HiveMQ only worked over IPv4. One working broker is enough.
- **Windows only.** Only the Windows x86_64 build of the official
  `webrtc-native` 1.2.2 extension is bundled (`addons/webrtc_native/`). For
  Linux or macOS, copy the matching libraries from
  <https://github.com/godotengine/webrtc-native/releases/tag/1.2.2-stable> and
  add them to `webrtc_native.gdextension`.
- **No spectators, no lobby browser.** A room holds exactly two players.

## Exporting

The `.gdextension` is picked up automatically. When exporting the Windows
preset, Godot copies `libwebrtc_native.windows.template_release.x86_64.dll` next
to the `.exe`. **Ship that DLL with the game.** Without it, the ONLINE mode
cannot create a WebRTC peer.

## Testing

```bash
# rollback: two peers in one process, simulated latency / jitter / loss,
# a disconnect and an injected desync (must be detected)
godot --headless --path . --script res://tests/nettest.gd

# real network: host + guest in one process through the live brokers + WebRTC
godot --headless --path . --script res://tests/roomprobe.gd

# real game: two windows on this PC host/join a room and play CPU-driven
# matches online (rematch included), then compare checksums
tests/online_pair.sh <out_dir> <matches> <lag,jitter,loss%>

# the existing sim test still has to pass
godot --headless --path . --script res://tests/simtest.gd
```

Command-line hooks are passed after `--`:

| Option | Effect |
|---|---|
| `--host [--room=CODE] [--codefile=PATH]` | Host a room immediately, optionally with a fixed code, and write the code to a file. |
| `--join=CODE` or `--join=@PATH` | Join a room. With `@PATH`, the code is read from the file once it exists. |
| `--autopick=ced` | Pick this fighter automatically in the online character select. |
| `--autoplay [--cpu=0..2]` | A CPU brain supplies this player's inputs through the normal online path. |
| `--matches=N [--reselect]` | Play N matches with rematches. `--reselect` goes through character select once. |
| `--result=PATH` | Write a JSON line per match: winner, checksums, rollbacks, RTT. |
| `--netlog=PATH` | Log the connection steps. |
| `--quit_after=SECONDS` | Safety timeout for automated runs. |
| `--netsim=LAG,JITTER,LOSS` | Delay and drop outgoing game packets, to force rollbacks on a local link. |
| `--delay=N` | Input delay. |
| `--brokers=URL\|URL` | Use these brokers instead of the defaults. |
