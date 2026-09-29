class_name SimConst
extends RefCounted
## Constants shared by the deterministic simulation.
##
## IMPORTANT: replays depend on these values. Changing any of them (or any
## arithmetic in src/core/*.gd) requires bumping SIM_VERSION so that old replays
## are detected as incompatible instead of silently desynchronising.

## Version of the simulation rules. Stored in every replay.
const SIM_VERSION: int = 1

## Fixed simulation rate (ticks per second). Rendering interpolates between ticks
## so 60/90/120/144 Hz displays all run the exact same physics.
const TICK_RATE: int = 120
const DT: float = 1.0 / 120.0

## Platform kinds
const KIND_NORMAL: int = 0
const KIND_LANDMARK: int = 1
const KIND_GROUND: int = 2

## Generator patterns
const PATTERN_FREE: int = 0
const PATTERN_STAIRS: int = 1
const PATTERN_ZIGZAG: int = 2

## Reasons a combo can end
const COMBO_END_NONE: int = 0
const COMBO_END_LOWER: int = 1     # landed on the same / one higher / a lower floor
const COMBO_END_TIMEOUT: int = 2
const COMBO_END_DEATH: int = 3

## Player events (first element of the small arrays in PlayerController.events)
const EV_JUMP: int = 0
const EV_LAND: int = 1
const EV_WALL: int = 2
const EV_LEFT_GROUND: int = 3

## Input axis quantisation used when recording replays: axis = q / AXIS_STEPS
const AXIS_STEPS: int = 127
