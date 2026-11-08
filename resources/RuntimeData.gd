## Shared runtime state for the vehicle simulation.
##
## This script only holds data and has no logic. Each inner class is a bundle of
## the values that one part of the car produces and others read, such as
## suspension compression, brake torque or engine RPM. The simulation scripts
## (engine, transmission, brake, steering, suspension and wheel) receive an
## instance of the class they need as a parameter, so they can share results
## without referencing each other. These classes are used as type hints, for
## example [code]RuntimeData.engine[/code].
##
## Create one instance of each class and pass it to the scripts that need it,
## for example [code]var engine_data = RuntimeData.engine.new()[/code]. The
## tuning values that do not change at runtime live in the separate car tuning
## resource.
##
## [b]Wheel index order[/b] used by every per-wheel array: 0 = front left, 1 =
## front right, 2 = rear left, 3 = rear right.
##
## [b]Units:[/b] SI (meters, kilograms, seconds, newtons, N·m, rad/s), except
## [code]engine_rpm[/code], which is in revolutions per minute. Angles are in
## radians.
class_name RuntimeData
extends Resource


## State of the four suspension corners. Written by the suspension script and
## read by the wheel (tire) script.
class suspension:
	## Spring, damper and anti-roll force of each wheel as a world-space vector, in
	## N. It points along the spring's up direction. The tire script uses its length
	## as the tire's normal load.
	var wheel_spring_force = [Vector3(), Vector3(), Vector3(), Vector3()]
	## Compression of each spring in meters, from 0 (fully extended) up to the
	## maximum compression.
	var compression = [0.0, 0.0, 0.0, 0.0]
	

## State of the brake system. Written by the brake script (and by the ABS logic
## for [code]abs_active[/code]) and read by the wheel script.
class brake:
	## Brake torque applied to each wheel, in N·m.
	var wheel_brake_torque = [0.0, 0.0, 0.0, 0.0]
	## Number of wheels that have brakes. Not initialized here (it starts at 0),
	## and set every frame by the brake script.
	var active_wheels_brake: int
	## Brake torque of a single braked wheel, in N·m. This is the total brake torque
	## divided evenly among the braked wheels.
	var brake_torque: float
	## Smoothed brake pedal position, from 0.0 (released) to 1.0 (fully pressed).
	var input_brake := 0.0
	## ABS Brake inputs, the after result of input_brake with ABS effects.
	var abs_input_brake = [0.0, 0.0, 0.0, 0.0]
	## Smoothed handbrake lever position, from 0.0 (released) to 1.0 (pulled).
	var input_handbrake := 0.0


## State of the engine and the clutch. Written by the engine script and read by
## the wheel script.
class engine:
	## Torque the engine sends to each wheel after the clutch, gearing and
	## differential, in N·m.
	var wheel_engine_torque = [0.0, 0.0, 0.0, 0.0]
	## Torque the engine produces (throttle and torque curve), in N·m, before
	## friction and clutch.
	var engine_torque: float
	## Engine speed in revolutions per minute.
	var engine_rpm: float
	## Engine speed in rad/s. This is the value that is integrated each frame;
	## [code]engine_rpm[/code] is derived from it.
	var engine_angular_velocity: float
	## Torque the clutch exerts on the engine, in N·m. Positive when the clutch is
	## slowing the engine down.
	var clutch_torque_on_engine: float
	## True when the engine stalled (dropped below [code]stall_rpm[/code] under
	## load). Cleared on the next start.
	var engine_stalled: bool
	## Number of wheels that receive engine torque. Set every frame by the engine
	## script.
	var engine_driven_count = 0
	## True while the engine is running (combustion on). Toggled with the
	## [code]"Ignition"[/code] input action.
	var engine_running := false
	## True while the starter is cranking the engine.
	var engine_starting := false
	## Time left until the starter finishes cranking, in seconds.
	var starter_timer := 0.0
	## Engine temperature as a fraction, from 0.0 (cold) to 1.0 (fully warm).
	var engine_warmth := 0.0
	## Idle speed the idle control is aiming for, in RPM. Higher when the engine is
	## cold.
	var idle_target_rpm := 0.0
	## Effective throttle, from 0.0 to 1.0: the gas pedal plus the idle control.
	## 0.0 when the engine is off.
	var throttle := 0.0
	## Effective clutch pedal, from 0.0 (engaged) to 1.0 (fully pressed). In
	## manual mode this is the clutch input; in the clutchless and automatic modes
	## the automatic clutch can press it further. Written by the transmission
	## script.
	var clutch_input := 0.0


## State of the gearbox. Written by the transmission script and read by the
## engine script.
class transmission:
	## True while a gear change is in progress. During a shift no torque passes
	## through the gearbox.
	var is_shifting = false
	## Ratio of the gear that is currently engaged. It is 0.0 during a shift and in
	## neutral. It starts at 0.0 (the default for a float), which matches the
	## starting gear of neutral.
	var current_gear_ratio: float
	## Time left until the current shift finishes, in seconds.
	var shift_timer = 0.0
	## Index of the selected gear in the [code]gear_ratio[/code] array of the car
	## tuning resource: 0 is reverse, 1 is neutral and 2 and up are the forward
	## gears. The car starts in neutral (1).
	var current_gear = 1
	## Time left before the automatic gearbox may shift again, in seconds. Stops
	## it from hunting between gears.
	var auto_shift_cooldown = 0.0


## State of the four wheels and tires. Written by the wheel script and read by
## the engine, brake and other scripts.
class wheels:
	## Spin speed of each wheel in rad/s.
	var wheel_angular_velocity = [0.0, 0.0, 0.0, 0.0]
	## Longitudinal (forward/back) tire force of each wheel as a world-space vector,
	## in N.
	var longitude_force_vector = [Vector3(), Vector3(), Vector3(), Vector3()]
	## Lateral (sideways) tire force of each wheel as a world-space vector, in N.
	var lateral_force_vector = [Vector3(), Vector3(), Vector3(), Vector3()]
	## Size of the longitudinal tire force of each wheel, in N. Positive pushes the
	## car forward.
	var longitude_force = [0.0, 0.0, 0.0, 0.0]
	## Size of the lateral tire force of each wheel, in N. Positive is along the
	## wheel's sideways axis.
	var lateral_force = [0.0, 0.0, 0.0, 0.0]
	## Slip ratio of each wheel: how much faster (positive) or slower (negative) the
	## tire surface moves than the car over the ground, as a fraction of the ground
	## speed. It is used by the differential, the ABS and the traction control.
	var slip_ratio = [0.0, 0.0, 0.0, 0.0]
	## Self-aligning torque of each tire. Not used yet.
	var aligning_torque = [0.0, 0.0, 0.0, 0.0]
	## Current camber angle of each wheel. Not used yet by the scripts that were
	## documented.
	var camber = [0.0, 0.0, 0.0, 0.0]
	## Slip angle of each wheel in radians: the angle between where the tire points
	## and where it moves.
	var slip_angle = [0.0, 0.0, 0.0, 0.0]
	## Speed of the car at the wheel along the wheel's forward direction, in m/s.
	## A single value shared by all wheels, so it holds the wheel processed last.
	var forward_speed = 0.0
	## Speed of the car at the wheel along the wheel's sideways direction, in m/s.
	## A single value shared by all wheels, so it holds the wheel processed last.
	var side_velocity = 0.0
	## Speed of the tire's surface, [code]angular velocity * wheel radius[/code], in
	## m/s. A single value shared by all wheels, so it holds the wheel processed
	## last.
	var wheel_surface_speed = 0.0
	## Load pressing the tire onto the ground, in N. Taken from the suspension force.
	var normal_load = [0.0, 0.0, 0.0, 0.0]      
	## Maximum force the tire can transmit, [code]friction coefficient * normal
	## load[/code], in N.
	var friction_limit = [0.0, 0.0, 0.0, 0.0]   
	## Longitudinal part of the slip force from the brush model, in N, before the
	## friction limit is applied.
	var slip_force_x = [0.0, 0.0, 0.0, 0.0]     
	## Lateral part of the slip force from the brush model, in N, before the
	## friction limit is applied.
	var slip_force_y = [0.0, 0.0, 0.0, 0.0]
	## Length of the longitudinal and lateral slip forces combined, in N.
	var s_combined = [0.0, 0.0, 0.0, 0.0]
	## Normalized slip of the brush model: the combined slip force divided by three
	## times the friction limit. At 1.0 and above the tire is fully sliding.
	var theta = [0.0, 0.0, 0.0, 0.0]
	## Size of the combined tire force after the friction limit, in N.
	var total_force = [0.0, 0.0, 0.0, 0.0]
	## Speed of the ground under each wheel along the wheel's forward direction,
	## in m/s. The wheel spins at [code]ground_speed / wheel_radius[/code] at zero
	## slip.
	var ground_speed = [0.0, 0.0, 0.0, 0.0]
	## Ground surface under each wheel ([ShiftSurface]), set by the surface
	## lookup every physics frame. A wheel in the air keeps its last surface.
	var surface: Array = [null, null, null, null]
	## How fast the longitudinal tire force grows with the wheel's angular
	## velocity, in N per rad/s. 0.0 when the tire is sliding. Used to integrate
	## the wheel spin semi-implicitly, which keeps it stable at any time step.
	var longitude_force_gradient = [0.0, 0.0, 0.0, 0.0]      
	## Sum of the longitudinal and lateral force vectors of each wheel, in N. This is
	## the force that is applied to the car.
	var combined_force_vector = [Vector3(), Vector3(), Vector3(), Vector3()]
	

## State of the steering. Written by the steering script.
class steering:
	## Target steering angle of the front left wheel, in radians.
	var target_fl :float
	## Target steering angle of the front right wheel, in radians.
	var target_fr :float
	## Ideal Ackermann angle of the inner wheel for the current turn, in radians
	## (always positive).
	var inner: float
	## Ideal Ackermann angle of the outer wheel for the current turn, in radians
	## (always positive).
	var outer: float
	## Steering input from -1.0 (full right) to 1.0 (full left).
	var input_turn: float = 0.0
	## Requested tire steering angle in radians, after the steering ratio and the
	## limit to [code]max_angle[/code]. Positive is a turn to the left.
	var steering_amount: float = 0.0
	## Maximum tire steering angle in radians.
	var max_angle: float = 0.0

class assists:
	## True for each wheel on which the ABS is currently releasing the brake. Such a
	## wheel gets no brake torque.
	var abs_active = [false, false, false, false]
	## True while traction control is switched on (starts as [code]TC[/code] of
	## [CarValues], toggled by [code]controls.toggle_tc[/code]).
	var tc_on := false
	## True while traction control is cutting the throttle or braking a wheel.
	var tc_active := false
	## Share of the gas pedal traction control lets through, 0.0 to 1.0.
	var tc_throttle := 1.0
	## Brake torque traction control puts on each wheel, in N·m.
	var tc_brake_torque = [0.0, 0.0, 0.0, 0.0]


## What the driver does this frame: pedals, steering and buttons. The car
## reads only this, never the [Input] singleton directly. A player-controlled
## car fills it from the input actions every physics frame; for an NPC car your
## own code writes it (see [member ShiftCar.player_controlled]).
class controls:
	## Throttle pedal, 0.0 to 1.0.
	var gas := 0.0
	## Brake pedal, 0.0 to 1.0.
	var brake := 0.0
	## Steering, from -1.0 (full right) to 1.0 (full left).
	var steer := 0.0
	## Clutch pedal, 0.0 (released) to 1.0 (fully pressed).
	var clutch := 0.0
	## Handbrake lever, 0.0 to 1.0.
	var handbrake := 0.0
	## One-shot requests. Set them to true for one frame; the car resets them to
	## false after the physics frame that used them.
	var shift_up := false
	var shift_down := false
	## Toggles the engine on (starts cranking) or off.
	var ignition := false
	## Switches traction control on or off.
	var toggle_tc := false
