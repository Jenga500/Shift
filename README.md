# Shift Vehicle (Godot 4.7 addon)

> **Deutsch:** Eine ausführliche, leicht verständliche Anleitung findest du in
> [DOKUMENTATION.md](DOKUMENTATION.md).

Realistic raycast car simulation: brush tire model, Hz-based suspension with
anti-roll bars, Ackermann steering, curve-based engine with clutch and
open/Torsen/clutch LSD, manual / clutchless / automatic gearbox, ABS, traction
control, handbrake, RWD/FWD/AWD, aerodynamic drag, sliding friction, tire marks
and tire smoke, ground surfaces (also for Terrain3D) and a layered engine sound
system.

## Installation

1. Copy the `addons/shift_vehicle` folder into your project's `addons/` folder.
2. Enable **Shift Vehicle** in *Project > Project Settings > Plugins*. This adds
   the input actions below to your Input Map (existing actions are left alone).

## Physics tick rate (VR)

The car works at any physics tick rate, including a VR headset's refresh rate
(for example 72, 90 or 120 Hz, as set by the Godot XR Tools). The stiff parts
(wheel spin, tire slip, engine and clutch) run in substeps at the ShiftCar's
**Substep Rate** (default 300 per second), and wheel spin and clutch are solved
semi-implicitly, so the result is nearly the same from 60 to 300 Hz. At low
speed the tires hold with static friction, so a braked car stays put, also on
slopes. Raise **Substep Rate** for more precision, lower it to save CPU.

## Building a car

Add a **ShiftCar** node (it is a `RigidBody3D`) with this structure:

```
ShiftCar (RigidBody3D)
├── CollisionShape3D
├── FrontLeftRay  (RayCast3D)
│   └── Node3D    <- wheel holder, put the wheel mesh under it
├── FrontRightRay (RayCast3D)
│   └── Node3D
├── RearRightRay  (RayCast3D)
│   └── Node3D
└── RearLeftRay   (RayCast3D)
    └── Node3D
```

- Build the car at real size (1 unit = 1 m) with the rays at the real wheel
  positions. A scaled-down model with real mass and tires gets a tiny
  wheelbase and turns twitchy. Scale the model under the ShiftCar, never the
  ShiftCar (a RigidBody3D) itself.
- Point each ray down. Its `target_position` length is the fully extended
  suspension length, and its local -Z is the wheel's forward direction.
- Fill **Wheels** in this order: front left, front right, rear right, rear left.
- Assign a **Vehicle Values** resource (`CarValues`). Start from one of the
  presets in `presets/` (`roadster.tres`, `e30.tres`) — duplicate it, then tune.
- Optional: instance `ui/info.tscn` and set its `car` for a speed/RPM/gear HUD.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| `Gas` / `Brake` | W / S | right / left trigger |
| `SteerLeft` / `SteerRight` | A / D | left stick |
| `Clutch` | Shift | A |
| `ShiftUp` / `ShiftDown` | E / Q | right / left shoulder |
| `Ignition` | G | B |
| `Handbrake` | Space | X |
| `ToggleTC` | T | Y |

The car starts with the engine off; press Ignition (or tick
`start_engine_running`). The action names are defined in `shift_input.gd`;
change them there if they clash with your project. Missing actions are also
created at runtime, so a car works even if the plugin is not enabled.

## Player and NPC cars

A ShiftCar with **Player Controlled** on (the default) is driven by the input
actions. Turn it off for NPC/AI cars and drive them from code through
`car.controls`:

```gdscript
car.player_controlled = false
car.controls.ignition = true   # one-shot: start the engine
car.controls.shift_up = true   # one-shot: next gear (AUTOMATIC: N -> D)
car.controls.gas = 0.6         # 0..1, kept until changed
car.controls.steer = -0.2      # -1 (right) .. 1 (left)
car.controls.brake = 0.0
```

`shift_up`, `shift_down` and `ignition` are reset after the physics frame that
used them. Each car has its own `controls`, so any number of NPCs can drive.
See `DOKUMENTATION.md` (German), section 10.3, for a complete waypoint driver.

## Main settings (in `CarValues`)

- **Transmission > transmission_mode**: `MANUAL` (clutch needed to shift),
  `CLUTCHLESS` (shift without clutch, automatic clutch for pulling away),
  `AUTOMATIC` (ShiftUp/Down select R/N/D).
- **Motor > drive_type**: `RWD`, `FWD`, `AWD` (split by `center_diff_split`) or
  `CUSTOM` (per-wheel flags).
- **Brake > max_handbrake_torque / handbrake_wheels / handbrake_opens_clutch**.
- **Assists > TC**: traction control. When a driven wheel's drive slip exceeds
  `tc_slip_threshold` it closes the throttle (`tc_cut_rate`, reopens at
  `tc_recover_rate`) and brakes the spinning wheel (up to `tc_brake_torque`).
  Starts on or off by `TC`; the player toggles it with ToggleTC, code uses
  `car.assists.tc_on` (`car.assists.tc_active` while it intervenes).
- **Motor**: idle, cold idle, starter, warm-up and stall settings.
- **Steering > speed_factor_coeff**: speed sensitive steering; the steering
  angle is divided by `1 + coeff * km/h` (default 0.05: full key ≈ 10° at
  50 km/h). 0 turns it off for steering wheels.
- **Car > drag_coefficient / frontal_area / air_density**: aerodynamic drag
  `0.5 * rho * Cd * A * v²`, which sets the top speed. The car turns off Godot's
  built-in `linear_damp` on start, since it grows with mass × speed and capped
  cars at 80–100 km/h.
- **Effects**: tire marks and tire smoke while a tire slides (drift, wheel spin,
  locked wheels). `effect_slip_start` / `effect_slip_full` set the sliding speed
  (m/s) at which they start and reach full strength; width, segment count,
  colors, smoke amount and lifetime are adjustable.

## Surfaces (asphalt, grass, gravel, ...)

A `ShiftSurface` resource sets grip, rolling resistance, mark color and
smoke/dust per ground type; presets are in `presets/surfaces/`. The surface is
looked up per wheel every physics frame:

1. Metadata `shift_surface` (a `ShiftSurface`) on the collider the wheel hits.
2. Nodes in the group `shift_surface_providers` with a method
   `get_surface(point: Vector3, collider: Object) -> ShiftSurface`.
   **Terrain3D:** add a `ShiftTerrain3DSurfaces` node, set its `terrain` and
   fill `surfaces` (index = texture ID in the Terrain3D asset dock).
3. `CarValues.default_surface`, or asphalt if empty.

Tires also lose grip while sliding: `brush_mu_slide` (share of `brush_mu` left
when sliding fast, default 0.75) and `brush_slide_speed` (m/s).

## Engine sounds (in the ShiftCar node, group "Engine Sounds")

- `sound_ignition`, `sound_shutdown`: one-shots.
- `sound_idle_cold`, `sound_idle_warm`: idle loops, blended by engine warmth.
- `sounds_free_rev`, `sounds_engine_brake`, `sounds_partial_load`,
  `sounds_high_load`: lists of `EngineSoundSample` (stream + the RPM it was
  recorded at). Add as many as you have; the two nearest the current RPM are
  crossfaded and pitched. Free rev plays while the drivetrain is decoupled
  (neutral or clutch pressed); in gear, engine brake / partial / high load are
  blended by throttle.

Set all loop sounds to loop in their import settings.

## License

MIT, see `LICENSE`.
