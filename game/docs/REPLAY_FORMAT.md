# Replay format and determinism contract

A replay is **not a video**. It stores what is needed to re-run the simulation:

```
seed  +  tuning snapshot  +  input events (by tick)   →   the exact same run
```

Because the simulation is deterministic (see [ARCHITECTURE.md](ARCHITECTURE.md#determinism-contract)), playback
reproduces every jump, landing, combo and the final score exactly. Replays are watch-only: watching never changes
statistics, records or leaderboards, and nothing is ever uploaded — the game has no score-submission feature.

## File (JSON)

Replays are stored in `user://spire_sprint/replays/<id>.replay.json`; the profile keeps only the list metadata
(`id`, name, date, score, floor, combo, duration, character, control, versions, completeness). The same JSON
document is what *Share* sends and what *Import* accepts (as text, so it also works through a chat message).

```jsonc
{
  "format": "spire-sprint-replay",   // must match
  "format_version": 1,               // file layout version (unknown → rejected)
  "game_version": "1.0.0",          // informational
  "sim_version": 1,                 // SimConst.SIM_VERSION when recorded (different → flagged incompatible)
  "tick_rate": 120,                 // must equal SimConst.TICK_RATE
  "id": "…", "name": "", "created": 1760000000,      // unix time
  "seed": 3405691582,               // uint32 tower/RNG seed
  "character": "pip", "control": "touch",            // cosmetic / informational
  "tuning": { "gravity": 2500.0, … },                // GameTuning.to_sim_dict(): the 62 simulation values
  "tuning_hash": 123456789,                          // hash of the snapshot (detects drift)
  "score": 1234, "floor": 42, "combo": 12, "combo_jumps": 4,   // summary for lists and verification
  "duration_ticks": 5400, "duration": 45.0,
  "complete": true,                 // false = autosave of an interrupted run
  "event_count": 310,
  "raw_size": 940,                  // size of the decoded event bytes (checked before inflating)
  "events": "eJxj…"                 // base64( deflate( event bytes ) )
}
```

### Event stream

Logical form: a flat list of triples `[tick, axis_q, flags, tick, axis_q, flags, …]`

* `tick` — 1-based number of the simulation tick the input applies to (ascending).
* `axis_q` — horizontal input quantised to `−127 … 127` (`axis = axis_q / 127`; −127 = full left, +127 = full right).
  The value stays in force **until the next event**.
* `flags` — bit 0 = a jump was requested on exactly this tick.

Only *changes* of the axis and jump presses create events, so a typical run is a few hundred events.

Byte encoding (before deflate): for every event, in order

1. `delta` = `tick − previous tick` as an unsigned LEB128 varint (7 bits per byte, high bit = more),
2. one byte `axis_q + 127` (0 … 254),
3. one byte `flags`.

`decode_events` rejects anything malformed: truncated varints, out-of-range axis, a wrong `event_count`, an absurd
`raw_size` (limit 24 MB), or a stream longer than 3 000 000 events. Corrupted deflate data, invalid base64 and
wrong `format`/`format_version`/`tick_rate` are all rejected with a readable error and never crash the game.

### Playback rules

`ReplayPlayer` builds `GameTuning.from_sim_dict(tuning)` (so later re-tuning of the game never changes old replays),
creates `RunManager(tuning, seed)` and, for tick *n* = 1, 2, 3 …:

1. applies every event with `tick ≤ n` (axis persists, `jump` is true only for an event exactly on tick *n*),
2. calls `run.tick(axis_q / 127, jump)`,
3. stops when the run dies or `duration_ticks` is reached (a still-running combo is settled exactly like the live
   game did when the run was abandoned).

`matches_recording()` compares the re-simulated score and highest floor with the stored summary — used by tests and by
the crash-recovery path.

### Interrupted runs

While a run is live the recorder can produce a snapshot (`complete = false`). If the app is killed or backgrounded and never
returns, the next start finds the snapshot and re-simulates it (`simulate_all`) to reconstruct the final state; the run
then appears in *Replays* marked as incomplete, and its result is credited to the records.

## Versioning rules

| Change | What to do |
| --- | --- |
| Tuning **number** (in `game_tuning.gd` / `.tres`) | Nothing — replays carry their own snapshot. |
| Anything that changes simulation **code or arithmetic** in `src/core/*.gd` (including the order of RNG draws) | Bump `SimConst.SIM_VERSION`; old replays are then flagged *incompatible* and refuse to play instead of drifting silently. Regenerate the golden vectors. |
| New field in the JSON | Keep `format_version`; readers must ignore unknown keys and supply defaults for missing ones. |
| Layout change of the file (encoding, required keys) | Bump `ReplayData.FORMAT_VERSION`; keep a reader for the old version if you want old files to stay importable. |

## Why it stays exact on every device

* the simulation only uses `+ − * /` and `sqrt` (correctly rounded by IEEE 754) — no `sin`/`cos`/`pow` whose results can
  differ between platforms;
* the random generator is a custom xorshift128 on 32-bit integers (not Godot's `RandomNumberGenerator`);
* timers are integer tick counters; the frame rate never enters the simulation;
* the input is quantised to 255 steps *before* it reaches the simulation, in live play and in playback alike.
