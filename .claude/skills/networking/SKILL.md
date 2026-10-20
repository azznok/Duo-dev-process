---
name: networking
description: Client/server protocol - Commands (intents with a sequence number; the player id comes from the link), Events, Snapshots, versioned serialization with frozen frames, a Transport trait (in-memory in solo, network later), stable ids, prediction and reconciliation. Use for every task with DOMAINS network and every change at the client/server boundary or to a message. Do NOT use for a purely local client system (camera, UI with no shared state).
---

# Networking and protocol

Client/server from day one, even in solo: the solo game is a client talking to an embedded server.

## The gesture

1. Every user action is a serialisable `Command` (sequence number; the player id is the one of the
   LINK, assigned by the server, never sent by the client). The client never changes world state; it
   may only predict.
2. **Events** = discrete changes; **Snapshots** = continuous state. Across the protocol: stable ids
   (player, entity, chunk/record ids), never an engine handle or memory address.
3. The protocol module does not depend on any network library; the in-memory transport implements the
   same trait as the future network transport.
4. The pump host <-> simulation is a pure function (`&mut dyn Transport`, inbox, outbox), tested without
   threads. The client NEVER pushes into the simulation's inbox directly: it sends frames, even in solo.
5. **Prediction and reconciliation**: the client applies its own commands immediately, keeps them until
   the server acknowledges their sequence number, then replays the unacknowledged ones on top of the
   server state. Other entities are interpolated between snapshots.
6. **Proofs**: a serialization round-trip test per message; frozen bytes per message; a recorded solo
   session (seed + commands) replayed on the headless server gives the same state hash.

## Versioned serialization

- A frame = `PROTOCOL_VERSION` (fixed-width integer) + the encoded message. Reordering a variant or a
  field changes the bytes: new version.
- Change a message: new variant or field at the END, version + 1, frozen bytes updated by hand for each
  message touched, a test "frame of version n-1 refused".
- Find every construction site with the COMPILER (build all targets, keep going), not with grep: the
  missing-field errors list them.
- A message that is also written to the save journal changes the SAVE format: bump the save version and
  write a tested migration, keeping the OLD structs for reading.

## Pitfalls already paid

- Grepping for the version byte (`0x07`) also matches variant indexes: grep the full header
  (`0x07, 0x00`) AND headers split over two lines by the formatter.
- Decoders that ignore trailing bytes hide a wrong frame length: assert the consumed length in tests.
- A server in a thread: build its app INSIDE the thread closure; stop with an atomic flag raised by
  `Drop`, then join (bounded). Don't install a second global logger.
- A headless link test: the other end of an in-memory pair plays the server with hand-encoded frames; a
  real server is waited for with a bounded loop (<= 2 s).
- A wall-clock measure of a server tick in a debug test measures the machine, not the game: count in
  ticks/frames in lockstep.
- A new event variant must be handled in every exhaustive client `match`, the fuzz/load action lists
  and the localisation keys: list them in the task.

## Filled by the duo

<!-- Procedure done twice or pitfall paid: one line here, in the task's commit. -->
