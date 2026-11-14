# Note: All comments are to explain the code below the comment like this one.
# Note: why the hell did i make a comment for basic logic
# Note: idk man i just work here
# Note: realized i shouldnt spam comments to learn.

## Main vehicle controller that ties all the car simulation scripts together.
##
## Attach this script to the car's [RigidBody3D]. It creates the shared runtime
## data objects and one instance of each simulation script (steering,
## transmission, suspension, tire model, motor, brake, assists), and runs them in
## the right order every physics frame. It also sets up and updates the optional
## debug force arrows. The simulation itself lives in those scripts; this script
## only creates them, connects them and decides the order.
##
## [b]Minimum working scene structure:[/b]
## [codeblock]
## Car (RigidBody3D)              <- this script is attached here
## ├── CollisionShape3D
## ├── FrontLeftRay (RayCast3D)
## │   └── Node3D                 <- wheel mesh holder
## ├── FrontRightRay (RayCast3D)
## │   └── Node3D
## ├── RearRightRay (RayCast3D)
## │   └── Node3D
## └── RearLeftRay (RayCast3D)
##     └── Node3D
## [/codeblock]
## The root must be a [RigidBody3D] with this script, and it needs a
## [CollisionShape3D] child for the body. Each of the four wheels is a
## [RayCast3D] child of the body, with a [Node3D] as its first (and only
## required) child. The [Node3D] is the wheel mesh node: the suspension script
## moves it to the ground contact point, so put a [MeshInstance3D] under it if you
## want a visible wheel. The debug arrows are also attached to it.
##
## [b]Setup in the editor:[/b][br]
## - Assign the car tuning resource ([CarValues]) to [member VehicleValues].[br]
## - Fill [member wheels] with the four wheel [RayCast3D] nodes [b]in this
## order: front left, front right, rear right, rear left[/b]. Each ray must have
## its wheel mesh as its first child.[br]
## - Point each ray down. The length of its [code]target_position[/code] is the
## suspension's fully extended length, and the tire code treats the ray's local
## -Z direction as the wheel's forward direction.
##
## [b]Wheel indices:[/b] after [method _ready], the rays carry a
## [code]"wheel_index"[/code] meta value that every other script uses: 0 = front
## left, 1 = front right, 2 = rear left, 3 = rear right. This is not the same
## order as the [member wheels] array (see the note on [member wheels]).
##
## [b]Order of one physics frame (see [method _physics_process]):[/b][br]
## transmission, surface lookup, suspension, steering, brakes, motor input, then in substeps
## (tire forces, motor, wheel spin), averaged tire forces applied, assists (ABS
## and traction control), tire marks and smoke, debug arrows.
##
## [b]Physics rate:[/b] the car works at any physics tick rate. The stiff parts
## (wheel spin, tire slip, engine and clutch) run in substeps at
## [member substep_rate]; the body forces are averaged over them. The input
## actions are listed in [ShiftInput]; missing ones are added on [method _ready].
##
## [b]NPC cars:[/b] turn off [member player_controlled] and set
## [member controls] from your own script, for example
## [code]car.controls.gas = 0.6[/code] or [code]car.controls.shift_up = true[/code].
class_name ShiftCar
extends RigidBody3D

## The car tuning resource that holds all settings: suspension, steering,
## brakes, engine, transmission, wheels, tires and debug options. It must be
## assigned in the editor.
@export var VehicleValues: CarValues
## Internal rate of the wheel, tire and drivetrain simulation, in steps per
## second. Each physics frame is split into as many substeps as needed to reach
## it, so the car stays stable when the physics tick rate is low (for example a
## VR headset's 72 or 90 Hz). With a physics tick rate at or above this value
## there is one substep per frame. Higher is more accurate but costs more CPU.
@export var substep_rate := 300.0
## If true, the car is driven by the player through the input actions (see
## [ShiftInput]). If false, it ignores the input actions and drives only from
## [member controls], which your own code (an NPC or AI driver, a replay, a
## network peer) writes. Can be switched at runtime, for example when the player
## gets in or out.
@export var player_controlled := true
## A reference to this node, passed to the simulation scripts as the car body.
var car = self

@export_group("Engine Sounds")

## Played once when the ignition is turned on (starter cranking and the engine
## catching).
@export var sound_ignition: AudioStream
## Played once when the engine is switched off or stalls.
@export var sound_shutdown: AudioStream
## Idle loop of a cold engine.
@export var sound_idle_cold: AudioStream
## Engine RPM the cold idle loop was recorded at. Used for pitching.
@export var idle_cold_sample_rpm = 1200.0
## Idle loop of a warm engine.
@export var sound_idle_warm: AudioStream
## Engine RPM the warm idle loop was recorded at.
@export var idle_warm_sample_rpm = 800.0
## Loops of the engine revving freely in neutral or with the clutch pressed,
## one per recorded RPM. Add as many as you like, in any order; the two closest
## to the current RPM are crossfaded.
@export var sounds_free_rev: Array[EngineSoundSample] = []
## Loops of engine braking (in gear, clutch engaged, throttle closed), one per
## recorded RPM.
@export var sounds_engine_brake: Array[EngineSoundSample] = []
## Loops of the engine under partial load (in gear, part throttle, e.g. cruising
## at constant RPM), one per recorded RPM.
@export var sounds_partial_load: Array[EngineSoundSample] = []
## Loops of the engine under high load (in gear, full throttle, accelerating),
## one per recorded RPM.
@export var sounds_high_load: Array[EngineSoundSample] = []
## Volume of all engine sounds, in dB.
@export var engine_sound_volume_db = 0.0
## Audio bus the engine sounds play on.
@export var engine_sound_bus: StringName = &"Master"
## RPM range above the idle target over which the idle loops fade into the load
## loops.
@export var sound_idle_blend_range = 600.0
## How fast the loops fade in after starting and out after stopping, in full
## volume per second.
@export var sound_fade_speed = 8.0
## How fast the load crossfade follows the throttle and the clutch. Higher is
## snappier.
@export var sound_load_smoothing = 6.0

	################
	# Runtime Data #
	################

## Runtime state of the engine and clutch.
var engine := RuntimeData.engine.new()
## Runtime state of the gearbox.
var transmission := RuntimeData.transmission.new()
## Runtime state of the wheels and tires.
var wheeldata := RuntimeData.wheels.new()
## Runtime state of the suspension.
var suspension := RuntimeData.suspension.new()
## Runtime state of the brakes.
var brake := RuntimeData.brake.new()
## Runtime state of the steering.
var steering := RuntimeData.steering.new()
## Runtime state of assists.
var assists := RuntimeData.assists.new()
## The driver's pedals, steering and buttons. Filled from the input actions every
## physics frame while [member player_controlled] is true; otherwise write it from
## your own code. The one-shot requests ([code]shift_up[/code],
## [code]shift_down[/code], [code]ignition[/code]) are reset after each physics
## frame.
var controls := RuntimeData.controls.new()

	###########
	# SCRIPTS #
	###########

## Script resource of the steering logic.
var SteeringScript = preload("steering.gd")
## Script resource of the transmission logic.
var TransmissionScript = preload("transmission.gd")
## Script resource of the suspension logic.
var SuspensionScript = preload("suspension.gd")
## Script resource of the brush tire model.
var BrushModel_Script = preload("tire_models/brushtire.gd")
## Script resource of the engine and drivetrain logic.
var MotorScript = preload("motor.gd")
## Script resource of the brake logic.
var BrakeScript = preload("brake.gd")
## Script resource of the input feedback logic. It is loaded and instantiated
## here but not used in this script yet.
var InputFeedbackScript = preload("input_feedback.gd")
## Script resource of the driver assists (ABS and traction control).
var AssistsScript = preload("assists.gd")
## Script resource of the engine sound mixer.
var EngineSoundScript = preload("engine_sound.gd")
## Script of the tire marks and tire smoke.
var TireEffectsScript = preload("tire_effects.gd")
## Script of the ground surface lookup.
var SurfaceLookupScript = preload("surface_lookup.gd")

## Steering logic instance. Not added to the scene tree, it is only used for
## calling its functions.
var Steering = SteeringScript.new()
## Transmission logic instance.
var Transmission = TransmissionScript.new()
## Suspension logic instance.
var Suspension = SuspensionScript.new()
## Brush tire model instance. Calculates the tire forces and the wheel spin.
var BrushModel_Process = BrushModel_Script.new()
## Engine and drivetrain logic instance.
var Motor = MotorScript.new()
## Brake logic instance.
var Brake = BrakeScript.new()
## Input feedback logic instance. Not called in this script yet.
var InputFeedback = InputFeedbackScript.new()
## Driver assist (ABS and traction control) logic instance.
var Assists = AssistsScript.new()
## Engine sound mixer instance. Creates its audio players under this node.
var EngineSound = EngineSoundScript.new()
## Tire marks and smoke instance. Creates its nodes under this node.
var TireEffects = TireEffectsScript.new()
## Surface lookup instance. Finds the [ShiftSurface] under each wheel.
var SurfaceLookup = SurfaceLookupScript.new()

	##########
	# WHEELS #
	##########
	
## The four wheel raycasts, which must be assigned in the editor in the order
## front left, front right, rear right, rear left. Each ray must have its wheel
## mesh as its first child.
##
## [b]Note:[/b] the order of this array has the rear wheels in the opposite order
## to the wheel index used by the other scripts (2 = rear left, 3 = rear right).
## The wheel indices are assigned by name in [method _ready], so the simulation
## is not affected, but the debug arrows are (see [method _ready]).
@export var wheels: Array[RayCast3D]

## Front left wheel ray ([code]wheels[0][/code]).
@onready var fl_wheel = wheels[0]
## Front right wheel ray ([code]wheels[1][/code]).
@onready var fr_wheel = wheels[1]
## Rear right wheel ray ([code]wheels[2][/code]).
@onready var rr_wheel = wheels[2]
## Rear left wheel ray ([code]wheels[3][/code]).
@onready var rl_wheel = wheels[3]

## Front left wheel mesh, the first child of its ray. The suspension script moves
## it to the ground contact point.
@onready var fl_wheel_mesh = fl_wheel.get_child(0)
## Front right wheel mesh, the first child of its ray.
@onready var fr_wheel_mesh = fr_wheel.get_child(0)
## Rear right wheel mesh, the first child of its ray.
@onready var rr_wheel_mesh = rr_wheel.get_child(0)
## Rear left wheel mesh, the first child of its ray.
@onready var rl_wheel_mesh = rl_wheel.get_child(0)

## Wheel meshes in wheel index order (front left, front right, rear left, rear
## right), used to spin them in [method wheel_spin_process].
@onready var wheel_meshes_by_index = [fl_wheel_mesh, fr_wheel_mesh, rl_wheel_mesh, rr_wheel_mesh]
## Orientation of each wheel mesh as set up in the editor. The spin is applied
## on top of it, so the mesh's own rotation and scale are kept.
@onready var wheel_mesh_rest_basis = wheel_meshes_by_index.map(func(m): return m.basis)
## Current roll angle of each wheel mesh in radians, in wheel index order.
var wheel_spin_angle = [0.0, 0.0, 0.0, 0.0]

	#########
	# DEBUG #
	#########
	
## Scene of one debug force arrow. One arrow of each kind is created per wheel.
var Force_Arrow_Scene = preload("../debug/force_debug.tscn")

## Debug arrows that show the suspension force of each wheel. Filled in
## [method _ready] when debugging is enabled.
@onready var Debug_Suspension = []
## Debug arrows that show the longitudinal tire force of each wheel.
@onready var Debug_Longtiude = []
## Debug arrows that show the lateral tire force of each wheel.
@onready var Debug_Lateral = []

## Prepares the car when it enters the scene tree.
##
## It does three things:[br]
## 1. Gives each wheel ray its [code]"wheel_index"[/code] meta value (front left
## 0, front right 1, rear left 2, rear right 3), which the other scripts use to
## find their data.[br]
## 2. If [code]VehicleValues.DEBUG[/code] is true, creates three force arrows
## (suspension, longitudinal, lateral) for each wheel and attaches them to the
## wheel meshes. The arrows get their color, offset and "show force magnitude"
## setting from the tuning resource. Wheels on the left side are given the
## negative of [code]Position_Offset[/code] and wheels on the right side the
## positive one.[br]
## 3. Sets the starting gear ratio from the starting gear (neutral, so 0.0).[br]
## 4. Sets the starting engine state (off or already running) and warmth.[br]
## 5. Creates the engine sound players from the sound slots.[br]
## 6. Creates the tire mark and tire smoke nodes.
##
## [b]Note:[/b] the debug arrows are created and later updated by their position
## in the [member wheels] array, while the data arrays use the wheel index. These
## orders differ for the rear wheels (the array has rear right before rear left),
## so the two rear arrow sets show each other's forces. The fix is to build the
## debug arrays in wheel index order, or to swap the last two entries of
## [code]mesh_wheels[/code] and the debug update.
func _ready() -> void:
	
	ShiftInput.ensure_actions()

	# Godot's default linear damping (0.1) acts like a drag force growing with
	# m * v, far stronger than real air drag; air drag is applied in
	# _physics_process instead
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0

	var Wheels = [fl_wheel, fr_wheel, rl_wheel, rr_wheel]
		
	for i in range(Wheels.size()):
		Wheels[i].set_meta("wheel_index", i) # wheel identification
	
	if VehicleValues.DEBUG == true:
		var mesh_wheels = [fl_wheel_mesh, fr_wheel_mesh, rr_wheel_mesh, rl_wheel_mesh]

		for i in range(wheels.size()):
			var offset = -VehicleValues.Position_Offset if (i == 0 or i == 3) else VehicleValues.Position_Offset

			var Suspension_Arrow = Force_Arrow_Scene.instantiate()
			mesh_wheels[i].add_child(Suspension_Arrow)
			Suspension_Arrow.color = VehicleValues.Suspension_Arrow_Color
			Suspension_Arrow.Position_Offset = offset
			Suspension_Arrow.Display_Force_Magntiude = VehicleValues.Display_Force_Magntiude
			Debug_Suspension.append(Suspension_Arrow)

			var Longitude_Arrow = Force_Arrow_Scene.instantiate()
			mesh_wheels[i].add_child(Longitude_Arrow)
			Longitude_Arrow.color = VehicleValues.Longtiude_Arrow_Color
			Longitude_Arrow.Position_Offset = offset
			Longitude_Arrow.Display_Force_Magntiude = VehicleValues.Display_Force_Magntiude
			Debug_Longtiude.append(Longitude_Arrow)

			var Lateral_Arrow = Force_Arrow_Scene.instantiate()
			mesh_wheels[i].add_child(Lateral_Arrow)
			Lateral_Arrow.color = VehicleValues.Lateral_Arrow_Color
			Lateral_Arrow.Position_Offset = offset
			Lateral_Arrow.Display_Force_Magntiude = VehicleValues.Display_Force_Magntiude
			Debug_Lateral.append(Lateral_Arrow)
			
	transmission.current_gear_ratio = VehicleValues.gear_ratio[transmission.current_gear]
	
	if VehicleValues.start_engine_running:
		engine.engine_running = true
		engine.engine_warmth = 1.0
		engine.engine_angular_velocity = VehicleValues.idle_rpm * TAU / 60.0
		engine.engine_rpm = VehicleValues.idle_rpm
	else:
		engine.engine_warmth = VehicleValues.initial_engine_warmth
	engine.idle_target_rpm = lerpf(VehicleValues.cold_idle_rpm, VehicleValues.idle_rpm, engine.engine_warmth)
	assists.tc_on = VehicleValues.TC
	
	EngineSound.setup(self)
	TireEffects.setup(self, VehicleValues)
	
## Runs one step of the whole car simulation. Called by Godot every physics frame.
##
## The order matters because each step uses results from earlier steps:[br]
## 1. [b]Transmission:[/b] handles gear changes (manual, clutchless or
## automatic), sets the active gear ratio and the effective clutch position.[br]
## 2. [b]Suspension[/b] (each wheel): recasts the wheel ray from the current
## body position, computes spring compression and applies the suspension forces
## to the body, which gives the tire load.[br]
## The ground surface ([ShiftSurface]) under each wheel is looked up right
## after the wheel rays are updated.[br]
## 3. [b]Steering:[/b] turns the front wheels.[br]
## 4. [b]Brakes:[/b] calculates the brake torque of each wheel.[br]
## Steps 5 to 7 repeat once per substep (see [member substep_rate]); the body is
## not moved between substeps.[br]
## 5. [b]Tire forces[/b] (each wheel): computes slip and the tire forces. Uses the
## wheel speed from the previous substep, and the suspension load from step 2.
## After the last substep the average force of each wheel is applied to the body
## at its contact point.[br]
## 6. [b]Motor:[/b] handles the ignition and idle control, and calculates
## engine, clutch and differential torque. Uses the
## wheel speeds and the transmission state.[br]
## 7. [b]Wheel spin[/b] (each wheel): integrates the wheel angular velocity from
## the engine, brake, tire and rolling resistance torques.[br]
## After the substeps the air drag is applied to the body's center of mass.[br]
## 8. [b]Assists:[/b] runs the ABS and traction control. Traction control
## sets the throttle share and the wheel brake torque used in the next frame.[br]
## 9. [b]Tire effects:[/b] lays tire marks and emits smoke where tires slide.[br]
## 10. [b]Debug arrows:[/b] if debugging is on, hands the current forces to the
## arrows.
##
## Steps that call the tire model only run if
## [code]VehicleValues.TireModel[/code] is the brush model, which is currently the
## only model.
##
## [param delta] is the time step in seconds.
##
## [b]Note:[/b] the assists run last, after the brake and engine torque of this
## frame were already calculated, so their effect (for example
## [code]brake.abs_active[/code]) is applied one frame later.
func _physics_process(delta: float) -> void:
	if player_controlled:
		read_player_input()
	
	Transmission.transmission_process(delta, transmission, engine, wheeldata, controls, VehicleValues) # uses engine and wheel data of the previous frame
	
	# RayCast3D only updates once per frame, from where the car was before it
	# moved; at low tick rates and speed that hit point is far behind the wheel
	# and makes the springs read too long, so cast again from where the car is now
	for wheel in wheels:
		wheel.force_raycast_update()
	
	SurfaceLookup.surface_process(self, wheeldata, VehicleValues) # grip, rolling resistance and effect colors per wheel
	
	for wheel in wheels:
		Suspension.suspension_proccess(wheel, suspension, car, VehicleValues) # independent
	
	Steering.steering_proccess(delta, steering, car, controls, VehicleValues) # independent
	Brake.brake_process(delta, brake, assists, controls, VehicleValues) # independent
	Motor.motor_input_process(delta, engine, assists, controls, VehicleValues) # ignition and throttle, once per frame
	
	# wheel spin, tire slip and drivetrain are stiff, so they run in substeps;
	# the body only moves once per frame, so its tire force is the substep average
	var substeps := maxi(1, ceili(delta * substep_rate - 0.01))
	var sub_delta := delta / substeps
	var force_sum := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	
	for step in range(substeps):
		for wheel in wheels:
			if VehicleValues.TireModel == VehicleValues.TireModelType.Brush_Model:
				BrushModel_Process._get_wheel_forces(wheel, wheeldata, suspension, car, VehicleValues) # requires wheel angular velocity, motor, suspension
		
		Motor.motor_process(sub_delta, engine, transmission, wheeldata, brake, VehicleValues) # requires wheel angular velocity, wheel forces, transmission, brakes
		
		for wheel in wheels:
			if VehicleValues.TireModel == VehicleValues.TireModelType.Brush_Model:
				BrushModel_Process._get_wheel_angular_velocity(wheel, sub_delta, wheeldata, engine, brake, suspension, VehicleValues) # requires wheel forces, suspension, motor, brakes
				if wheel.is_colliding():
					force_sum[wheel.get_meta("wheel_index")] += wheeldata.combined_force_vector[wheel.get_meta("wheel_index")] # the force the wheel actually used
	
	var braked_wheels := 0
	for wheel in wheels:
		var i = wheel.get_meta("wheel_index")
		if wheel.is_colliding() and brake.wheel_brake_torque[i] > absf(engine.wheel_engine_torque[i]):
			braked_wheels += 1
	
	for wheel in wheels:
		if wheel.is_colliding():
			var contact = wheel.get_collision_point()
			var force = limit_tire_force(force_sum[wheel.get_meta("wheel_index")] / substeps, wheel, contact, delta, braked_wheels)
			apply_force(force, contact - global_position)

	# air drag, opposing the body's velocity
	var air_drag = 0.5 * VehicleValues.air_density * VehicleValues.drag_coefficient * VehicleValues.frontal_area
	apply_central_force(-air_drag * linear_velocity.length() * linear_velocity)

	Assists.abs_proccess(delta, assists, brake, wheeldata, VehicleValues)
	Assists.tc_proccess(delta, assists, engine, wheeldata, controls, VehicleValues)
	
	TireEffects.effects_process(self, wheeldata, VehicleValues)
	
	if VehicleValues.DEBUG == true:
			
		for i in range(Debug_Suspension.size()):
			Debug_Suspension[i].force = suspension.wheel_spring_force[i]
		for i in range(Debug_Longtiude.size()):
			Debug_Longtiude[i].force = wheeldata.longitude_force_vector[i]
		for i in range(Debug_Lateral.size()):
			Debug_Lateral[i].force = wheeldata.lateral_force_vector[i]
	
	# one-shot requests last exactly one physics frame
	controls.shift_up = false
	controls.shift_down = false
	controls.ignition = false
	controls.toggle_tc = false


## Copies the player's input actions into [member controls]. Called at the start
## of every physics frame while [member player_controlled] is true.
func read_player_input() -> void:
	controls.gas = Input.get_action_strength(ShiftInput.GAS)
	controls.brake = Input.get_action_strength(ShiftInput.BRAKE)
	controls.steer = Input.get_action_strength(ShiftInput.STEER_LEFT) - Input.get_action_strength(ShiftInput.STEER_RIGHT)
	controls.clutch = Input.get_action_strength(ShiftInput.CLUTCH)
	controls.handbrake = Input.get_action_strength(ShiftInput.HANDBRAKE)
	controls.shift_up = Input.is_action_just_pressed(ShiftInput.SHIFT_UP)
	controls.shift_down = Input.is_action_just_pressed(ShiftInput.SHIFT_DOWN)
	controls.ignition = Input.is_action_just_pressed(ShiftInput.IGNITION)
	controls.toggle_tc = Input.is_action_just_pressed(ShiftInput.TOGGLE_TC)

## Below this speed (m/s) at the contact point a tire holds like static
## friction instead of using the slip model (see [method limit_tire_force]).
const STATIC_FRICTION_SPEED := 0.1

## Returns [param force] (a wheel's tire force) corrected for long physics
## frames at low speed, where the slip model alone misbehaves.
##
## The contact point's velocity includes what gravity adds this frame, so a car
## holds on a slope. Along the wheel's forward and sideways axes:[br]
## - [b]Static friction:[/b] when the contact point moves slower than
## [constant STATIC_FRICTION_SPEED] over the ground, the force is the one that
## stops the mass this wheel holds in one frame, up to the tire's friction limit.
## Sideways this always applies (mass share from the weight distribution);
## lengthways only when the brakes hold the wheel (brake torque above the drive
## torque), and then the braked wheels share the whole mass, since the free
## wheels roll. The slip model gives no force at all below 1 mm/s, which lets a
## parked car creep and a car across a slope slide.[br]
## - [b]Overshoot limit:[/b] otherwise, a force that opposes the motion is
## limited to what stops this wheel's share of the mass in one frame, so the
## sliding force cannot throw a nearly stopped car back and forth. Forces along
## the motion are never limited, and neither is a longitudinal force the engine
## is pushing in the same direction (drive, not friction).
func limit_tire_force(force: Vector3, wheel: RayCast3D, contact: Vector3, delta: float, braked_wheels: int) -> Vector3:
	var wheel_index = wheel.get_meta("wheel_index")
	var mass_share = mass * VehicleValues.weight_distribution[wheel_index]
	var friction_limit = wheeldata.friction_limit[wheel_index]
	var velocity = linear_velocity + angular_velocity.cross(contact - global_position) + get_gravity() * delta
	var forward = -wheel.global_transform.basis.z.normalized()
	var side = wheel.global_transform.basis.x.normalized()
	var brakes_hold = brake.wheel_brake_torque[wheel_index] > absf(engine.wheel_engine_torque[wheel_index])
	var nearly_stopped = Vector2(velocity.dot(forward), velocity.dot(side)).length() < STATIC_FRICTION_SPEED
	
	for axis in [forward, side]:
		var axis_force = force.dot(axis)
		var axis_velocity = velocity.dot(axis)
		var stopping_force = -mass_share * axis_velocity / delta
		var new_force = axis_force
		
		if nearly_stopped and axis == side:
			new_force = clampf(stopping_force, -friction_limit, friction_limit)
		elif nearly_stopped and brakes_hold:
			new_force = clampf(-mass / braked_wheels * axis_velocity / delta, -friction_limit, friction_limit)
		elif axis == forward and axis_force * engine.wheel_engine_torque[wheel_index] > 0.0:
			pass # drive
		elif axis_force * axis_velocity < 0.0 and absf(axis_force) > absf(stopping_force):
			new_force = stopping_force
		
		force += axis * (new_force - axis_force)
	return force


## Updates the engine sounds from the current engine state. Called by Godot every
## frame.
func _process(delta: float) -> void:
	EngineSound.sound_process(delta, self, engine, transmission)
	wheel_spin_process(delta)


## Rolls the wheel meshes with their simulated spin speed
## ([code]wheeldata.wheel_angular_velocity[/code]).
##
## The roll turns around the wheel ray's X axis (the axle; the ray's forward is
## -Z), so positive angular velocity rolls the wheel forward. The rotation is
## applied in the ray's space on top of the mesh's rest orientation, so meshes
## that are rotated or mirrored in the editor still spin around the axle.
func wheel_spin_process(delta: float) -> void:
	for i in range(4):
		wheel_spin_angle[i] = fposmod(wheel_spin_angle[i] - wheeldata.wheel_angular_velocity[i] * delta, TAU)
		wheel_meshes_by_index[i].basis = Basis(Vector3.RIGHT, wheel_spin_angle[i]) * wheel_mesh_rest_basis[i]
